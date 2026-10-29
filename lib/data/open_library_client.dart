import 'dart:convert';

import 'package:http/http.dart' as http;

class OpenLibraryException implements Exception {
  const OpenLibraryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One search hit from Open Library.
class OpenLibraryBook {
  const OpenLibraryBook({
    required this.title,
    required this.author,
    this.firstPublishYear,
    this.isbn,
    this.coverUrl,
    this.pages,
    this.workKey,
  });

  final String title;
  final String author;
  final int? firstPublishYear;
  final String? isbn;
  final String? coverUrl;
  final int? pages;

  /// Open Library's key for the work, such as "/works/OL45804W". Used to
  /// look up the editions of the book.
  final String? workKey;

  /// This book with the details of one [edition] (ISBN, pages, cover) instead.
  /// The title, author and first publication year stay those of the work.
  OpenLibraryBook withEdition(OpenLibraryEdition edition) => OpenLibraryBook(
        title: title,
        author: author,
        firstPublishYear: firstPublishYear,
        isbn: edition.isbn ?? isbn,
        coverUrl: edition.coverUrl ?? coverUrl,
        pages: edition.pages ?? pages,
        workKey: workKey,
      );

  String get subtitle =>
      firstPublishYear == null ? author : '$author · $firstPublishYear';

  factory OpenLibraryBook.fromJson(Map<String, dynamic> json) {
    final authors = json['author_name'];
    final isbns = json['isbn'];
    final coverId = json['cover_i'];
    final year = json['first_publish_year'];
    final pages = json['number_of_pages_median'];
    final key = json['key'];
    return OpenLibraryBook(
      workKey: key is String && key.startsWith('/works/') ? key : null,
      title: json['title'] is String ? json['title'] as String : 'Untitled',
      author: authors is List && authors.isNotEmpty
          ? authors.first.toString()
          : 'Unknown author',
      firstPublishYear: year is int ? year : null,
      isbn: isbns is List && isbns.isNotEmpty ? isbns.first.toString() : null,
      coverUrl: coverId is int
          ? 'https://covers.openlibrary.org/b/id/$coverId-M.jpg'
          : null,
      pages: pages is int && pages > 0 ? pages : null,
    );
  }
}

/// One edition (a specific printing) of a book.
class OpenLibraryEdition {
  const OpenLibraryEdition({
    required this.title,
    this.publisher,
    this.publishDate,
    this.pages,
    this.isbn,
    this.coverUrl,
  });

  final String title;
  final String? publisher;
  final String? publishDate;
  final int? pages;
  final String? isbn;
  final String? coverUrl;

  String get subtitle => [
        ?publisher,
        ?publishDate,
        if (pages != null) '$pages pages',
        if (isbn != null) 'ISBN $isbn',
      ].join(' · ');

  factory OpenLibraryEdition.fromJson(Map<String, dynamic> json) {
    String? first(Object? value) =>
        value is List && value.isNotEmpty ? value.first.toString() : null;
    final covers = json['covers'];
    int? coverId;
    if (covers is List) {
      for (final id in covers) {
        if (id is int && id > 0) {
          coverId = id;
          break;
        }
      }
    }
    final pages = json['number_of_pages'];
    final date = json['publish_date'];
    return OpenLibraryEdition(
      title: json['title'] is String ? json['title'] as String : 'Untitled',
      publisher: first(json['publishers']),
      publishDate: date is String && date.isNotEmpty ? date : null,
      pages: pages is int && pages > 0 ? pages : null,
      isbn: first(json['isbn_13']) ?? first(json['isbn_10']),
      coverUrl: coverId == null
          ? null
          : 'https://covers.openlibrary.org/b/id/$coverId-M.jpg',
    );
  }
}

/// Turns an Open Library ID (OL45804W for a work, OL7353617M for an edition,
/// OL23919A for an author) into a search query. Other text is left alone.
String openLibraryQuery(String text) {
  final trimmed = text.trim();
  if (!RegExp(r'^OL\d+[WMA]$', caseSensitive: false).hasMatch(trimmed)) {
    return trimmed;
  }
  final id = trimmed.toUpperCase();
  return switch (id[id.length - 1]) {
    'W' => 'key:/works/$id',
    'M' => 'edition_key:$id',
    _ => 'author_key:$id',
  };
}

/// Searches https://openlibrary.org. No account or API key is needed.
class OpenLibraryClient {
  OpenLibraryClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<OpenLibraryBook>> search(String query) async {
    final text = query.trim();
    if (text.isEmpty) return [];

    final uri = Uri.https('openlibrary.org', '/search.json', {
      'q': openLibraryQuery(text),
      'limit': '20',
      'fields': 'key,title,author_name,first_publish_year,isbn,cover_i,'
          'number_of_pages_median',
    });
    final data = await _getJson(uri);
    final docs = data is Map<String, dynamic> ? data['docs'] : null;
    if (docs is! List) return [];
    return docs
        .whereType<Map<String, dynamic>>()
        .map(OpenLibraryBook.fromJson)
        .toList();
  }

  Future<Object?> _getJson(Uri uri) async {
    final response = await _client.get(uri, headers: {
      'User-Agent':
          'Chapterly/1.7 (https://github.com/TheDutchMan13/Chapterly-Android)',
    }).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw OpenLibraryException(
        'Open Library returned status ${response.statusCode}',
      );
    }
    // Decode as UTF-8 ourselves so names like "Brontë" are not garbled.
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  /// The editions of a work, for choosing the right printing. [workKey] is
  /// the key from a search result, such as "/works/OL45804W".
  Future<List<OpenLibraryEdition>> editions(String workKey) async {
    final key = workKey.trim();
    if (key.isEmpty) return [];
    final path = key.startsWith('/works/') ? key : '/works/$key';
    final data = await _getJson(
      Uri.https('openlibrary.org', '$path/editions.json', {'limit': '50'}),
    );
    final entries = data is Map<String, dynamic> ? data['entries'] : null;
    if (entries is! List) return [];
    return entries
        .whereType<Map<String, dynamic>>()
        .map(OpenLibraryEdition.fromJson)
        .toList();
  }

  /// Finds the book with this ISBN, or null if there is no match.
  /// Dashes and spaces in [isbn] are ignored.
  Future<OpenLibraryBook?> lookupIsbn(String isbn) async {
    final digits = isbn.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (digits.isEmpty) return null;
    final results = await search('isbn:$digits');
    return results.isEmpty ? null : results.first;
  }
}
