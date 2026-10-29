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
  });

  final String title;
  final String author;
  final int? firstPublishYear;
  final String? isbn;
  final String? coverUrl;
  final int? pages;

  String get subtitle =>
      firstPublishYear == null ? author : '$author · $firstPublishYear';

  factory OpenLibraryBook.fromJson(Map<String, dynamic> json) {
    final authors = json['author_name'];
    final isbns = json['isbn'];
    final coverId = json['cover_i'];
    final year = json['first_publish_year'];
    final pages = json['number_of_pages_median'];
    return OpenLibraryBook(
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

/// Searches https://openlibrary.org. No account or API key is needed.
class OpenLibraryClient {
  OpenLibraryClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<OpenLibraryBook>> search(String query) async {
    final text = query.trim();
    if (text.isEmpty) return [];

    final uri = Uri.https('openlibrary.org', '/search.json', {
      'q': text,
      'limit': '20',
      'fields': 'key,title,author_name,first_publish_year,isbn,cover_i,'
          'number_of_pages_median',
    });
    final response = await _client.get(uri, headers: {
      'User-Agent':
          'Chapterly/1.0 (https://github.com/TheDutchMan13/Chapterly)',
    }).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw OpenLibraryException(
        'Open Library returned status ${response.statusCode}',
      );
    }
    // Decode as UTF-8 ourselves so names like "Brontë" are not garbled.
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final docs = data is Map<String, dynamic> ? data['docs'] : null;
    if (docs is! List) return [];
    return docs
        .whereType<Map<String, dynamic>>()
        .map(OpenLibraryBook.fromJson)
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
