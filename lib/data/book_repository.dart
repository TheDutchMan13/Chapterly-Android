import 'package:flutter/foundation.dart';

import '../models/book.dart';
import '../models/shelf.dart';
import 'book_store.dart';

/// Splits "sci-fi, Favorites,, sci-fi" into ["sci-fi", "Favorites"].
/// Tags are trimmed, empty ones dropped, and duplicates (ignoring case) removed.
List<String> parseTags(String input) {
  final seen = <String>{};
  final tags = <String>[];
  for (final part in input.split(',')) {
    final tag = part.trim();
    if (tag.isEmpty) continue;
    if (seen.add(tag.toLowerCase())) tags.add(tag);
  }
  return tags;
}

String _duplicateKey(Book book) =>
    '${book.title.trim().toLowerCase()}|${book.author.trim().toLowerCase()}';

/// Keeps the library in memory for the UI and saves every change to a [BookStore].
class BookRepository extends ChangeNotifier {
  BookRepository(this._store);

  final BookStore _store;
  final List<Book> _books = [];
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  /// A read-only copy of every book, newest first.
  List<Book> get books => List.unmodifiable(_books);

  Future<void> load() async {
    final books = await _store.loadAll();
    books.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    _books.clear();
    _books.addAll(books);
    _isLoaded = true;
    notifyListeners();
  }

  /// Books on [shelf]. If [tags] is not empty, only books that have all of them.
  List<Book> booksOn(Shelf shelf, {Set<String> tags = const {}}) => _books
      .where((book) => book.shelf == shelf && tags.every(book.tags.contains))
      .toList();

  /// Every tag in use, sorted alphabetically.
  List<String> get allTags {
    final tags = <String>{};
    for (final book in _books) {
      tags.addAll(book.tags);
    }
    return tags.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Book? byId(String id) {
    for (final book in _books) {
      if (book.id == id) return book;
    }
    return null;
  }

  Future<void> add({
    required String title,
    required String author,
    required Shelf shelf,
    List<String> tags = const [],
    String? isbn,
    String? coverUrl,
    int? firstPublishYear,
    int? pages,
  }) async {
    final now = DateTime.now();
    final book = Book(
      id: now.microsecondsSinceEpoch.toString(),
      title: title,
      author: author,
      shelf: shelf,
      addedAt: now,
      tags: tags,
      isbn: isbn,
      coverUrl: coverUrl,
      firstPublishYear: firstPublishYear,
      pages: pages,
    );
    _books.insert(0, book);
    notifyListeners();
    await _store.save(book);
  }

  /// Moves a book to another shelf. Moving to "In progress" records today as
  /// the start date and moving to "Finished" records today as the finish date,
  /// unless those dates are already set.
  Future<void> moveTo(String id, Shelf shelf) => _update(id, (book) {
        final now = DateTime.now();
        return book.copyWith(
          shelf: shelf,
          startedAt: shelf == Shelf.inProgress && book.startedAt == null
              ? () => now
              : null,
          finishedAt: shelf == Shelf.finished && book.finishedAt == null
              ? () => now
              : null,
        );
      });

  Future<void> setTags(String id, List<String> tags) =>
      _update(id, (book) => book.copyWith(tags: tags));

  /// 1 to 5 stars, or null to clear the rating.
  Future<void> setRating(String id, int? rating) =>
      _update(id, (book) => book.copyWith(rating: () => rating));

  Future<void> setPages(String id, int? pages) =>
      _update(id, (book) => book.copyWith(pages: () => pages));

  Future<void> setDates(
    String id, {
    required DateTime? startedAt,
    required DateTime? finishedAt,
  }) =>
      _update(
        id,
        (book) => book.copyWith(
          startedAt: () => startedAt,
          finishedAt: () => finishedAt,
        ),
      );

  Future<void> remove(String id) async {
    _books.removeWhere((book) => book.id == id);
    notifyListeners();
    await _store.remove(id);
  }

  /// Adds [incoming] books, skipping any whose title and author match a book
  /// already in the library. Returns how many were added.
  Future<int> importBooks(List<Book> incoming) async {
    final known = {for (final book in _books) _duplicateKey(book)};
    final fresh = <Book>[];
    for (final book in incoming) {
      if (known.add(_duplicateKey(book))) fresh.add(book);
    }
    if (fresh.isEmpty) return 0;
    _books.addAll(fresh);
    _books.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    notifyListeners();
    await _store.saveAll(fresh);
    return fresh.length;
  }

  /// Replaces the whole library, for restoring a backup.
  Future<void> replaceAll(List<Book> books) async {
    final sorted = [...books]..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    _books.clear();
    _books.addAll(sorted);
    _isLoaded = true;
    notifyListeners();
    await _store.replaceAll(sorted);
  }

  Future<void> _update(String id, Book Function(Book) change) async {
    final index = _books.indexWhere((book) => book.id == id);
    if (index == -1) return;
    final updated = change(_books[index]);
    _books[index] = updated;
    notifyListeners();
    await _store.save(updated);
  }
}
