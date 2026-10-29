import 'package:flutter/foundation.dart';

import '../models/book.dart';
import '../models/book_format.dart';
import '../models/reading.dart';
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

bool _matchesQuery(Book book, String query) {
  final text = query.trim().toLowerCase();
  if (text.isEmpty) return true;
  return book.title.toLowerCase().contains(text) ||
      book.author.toLowerCase().contains(text) ||
      (book.isbn ?? '').contains(text) ||
      book.tags.any((tag) => tag.toLowerCase().contains(text));
}

/// Moves a book to another shelf. Moving to "In progress" records today as
/// the start date and moving to "Finished" records today as the finish date,
/// unless those dates are already set.
Book _withShelf(Book book, Shelf shelf) {
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
}

/// Keeps the library in memory for the UI and saves every change to a [BookStore].
/// Deleted books stay in the list with a `deletedAt` date until the trash is emptied.
class BookRepository extends ChangeNotifier {
  BookRepository(this._store);

  final BookStore _store;
  final List<Book> _books = [];
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  /// Every book that is not in the trash, newest first.
  List<Book> get books =>
      List.unmodifiable([for (final b in _books) if (b.deletedAt == null) b]);

  /// Everything, including the trash. Used for backups.
  List<Book> get allBooks => List.unmodifiable(_books);

  /// Books in the trash, most recently deleted first.
  List<Book> get trash {
    final deleted = [for (final b in _books) if (b.deletedAt != null) b];
    deleted.sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));
    return List.unmodifiable(deleted);
  }

  Future<void> load() async {
    final books = await _store.loadAll();
    books.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    _books.clear();
    _books.addAll(books);
    _isLoaded = true;
    notifyListeners();
  }

  /// Books on [shelf] that are not in the trash. Every filter given must match:
  /// [tags] (all of them), [query] (title, author, ISBN or a tag),
  /// [favoritesOnly], and [formats] (any of them, when not empty).
  List<Book> booksOn(
    Shelf shelf, {
    Set<String> tags = const {},
    String query = '',
    bool favoritesOnly = false,
    Set<BookFormat> formats = const {},
  }) =>
      [
        for (final book in _books)
          if (book.deletedAt == null &&
              book.shelf == shelf &&
              tags.every(book.tags.contains) &&
              (!favoritesOnly || book.favorite) &&
              (formats.isEmpty || formats.contains(book.format)) &&
              _matchesQuery(book, query))
            book,
      ];

  /// Every tag in use on books that are not in the trash, sorted alphabetically.
  List<String> get allTags {
    final tags = <String>{};
    for (final book in _books) {
      if (book.deletedAt == null) tags.addAll(book.tags);
    }
    return tags.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  /// Finds a book by id, including books in the trash.
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
    BookFormat? format,
  }) async {
    final now = DateTime.now();
    final book = Book(
      id: newBookId(),
      title: title,
      author: author,
      shelf: shelf,
      addedAt: now,
      tags: tags,
      isbn: isbn,
      coverUrl: coverUrl,
      firstPublishYear: firstPublishYear,
      pages: pages,
      format: format,
    );
    _books.insert(0, book);
    notifyListeners();
    await _store.save(book);
  }

  Future<void> moveTo(String id, Shelf shelf) =>
      _update(id, (book) => _withShelf(book, shelf));

  Future<void> setTags(String id, List<String> tags) =>
      _update(id, (book) => book.copyWith(tags: tags));

  /// 1 to 5 stars, or null to clear the rating.
  Future<void> setRating(String id, int? rating) =>
      _update(id, (book) => book.copyWith(rating: () => rating));

  Future<void> setPages(String id, int? pages) =>
      _update(id, (book) => book.copyWith(pages: () => pages));

  Future<void> setFormat(String id, BookFormat? format) =>
      _update(id, (book) => book.copyWith(format: () => format));

  Future<void> setFavorite(String id, {required bool favorite}) =>
      _update(id, (book) => book.copyWith(favorite: favorite));

  /// Empty or null text clears the notes.
  Future<void> setNotes(String id, String? notes) {
    final text = notes?.trim();
    final value = text == null || text.isEmpty ? null : text;
    return _update(id, (book) => book.copyWith(notes: () => value));
  }

  Future<void> setCoverPath(String id, String? path) =>
      _update(id, (book) => book.copyWith(coverPath: () => path));

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

  // ---- reading log and re-reads

  /// Records pages read and/or minutes spent reading on a day for the
  /// current reading. Does nothing if both are 0.
  Future<void> addLogEntry(
    String id,
    DateTime date,
    int pages, {
    int minutes = 0,
  }) {
    if (pages <= 0 && minutes <= 0) return Future.value();
    return _update(id, (book) {
      final entry = LogEntry(date: date, pages: pages, minutes: minutes);
      final log = [...book.readingLog, entry];
      log.sort((a, b) => a.date.compareTo(b.date));
      return book.copyWith(readingLog: log);
    });
  }

  /// Removes an entry by its position in the book's log (oldest first).
  Future<void> removeLogEntry(String id, int index) => _update(id, (book) {
        final log = [...book.readingLog];
        if (index >= 0 && index < log.length) log.removeAt(index);
        return book.copyWith(readingLog: log);
      });

  /// Saves the current reading under earlier readings and starts a new one:
  /// the book moves to In progress with [startedAt] (today if not given) as
  /// the start date, and the finish date, rating and log are cleared.
  Future<void> readAgain(String id, {DateTime? startedAt}) =>
      _update(id, (book) {
        final start = startedAt ?? DateTime.now();
        return book.copyWith(
          shelf: Shelf.inProgress,
          previousReadings: [...book.previousReadings, book.currentReading],
          startedAt: () => start,
          finishedAt: () => null,
          rating: () => null,
          readingLog: const [],
        );
      });

  /// Removes an earlier reading by its position (oldest first).
  Future<void> removePreviousReading(String id, int index) =>
      _update(id, (book) {
        final readings = [...book.previousReadings];
        if (index >= 0 && index < readings.length) readings.removeAt(index);
        return book.copyWith(previousReadings: readings);
      });

  // ---- series

  /// An empty name clears the series (and the number).
  Future<void> setSeries(String id, String? series, int? number) {
    final name = series?.trim();
    final clean = name == null || name.isEmpty ? null : name;
    return _update(
      id,
      (book) => book.copyWith(
        series: () => clean,
        seriesNumber: () => clean == null ? null : number,
      ),
    );
  }

  /// Books (not in the trash) in the same series, ordered by number.
  List<Book> booksInSeries(String series) {
    final key = series.trim().toLowerCase();
    final found = [
      for (final book in _books)
        if (book.deletedAt == null &&
            book.series?.trim().toLowerCase() == key)
          book,
    ];
    found.sort((a, b) {
      final x = a.seriesNumber, y = b.seriesNumber;
      if (x == null && y == null) return a.title.compareTo(b.title);
      if (x == null) return 1;
      if (y == null) return -1;
      return x.compareTo(y);
    });
    return found;
  }

  /// The book that comes after [book] in its series, if you have it.
  Book? nextInSeries(Book book) {
    final name = book.series;
    final number = book.seriesNumber;
    if (name == null || number == null) return null;
    for (final other in booksInSeries(name)) {
      final otherNumber = other.seriesNumber;
      if (otherNumber != null && otherNumber > number) return other;
    }
    return null;
  }

  // ---- bulk edits

  Future<void> moveAllTo(Set<String> ids, Shelf shelf) =>
      _updateMany(ids, (book) => _withShelf(book, shelf));

  /// Adds [tag] to every book in [ids] that does not have it yet.
  Future<void> addTagToAll(Set<String> ids, String tag) {
    final clean = tag.trim();
    if (clean.isEmpty) return Future.value();
    return _updateMany(ids, (book) {
      final has = book.tags.any((t) => t.toLowerCase() == clean.toLowerCase());
      return has ? book : book.copyWith(tags: [...book.tags, clean]);
    });
  }

  /// Puts earlier copies of books back, for undoing a bulk change.
  Future<void> putBack(List<Book> earlier) async {
    final byId = {for (final book in earlier) book.id: book};
    final changed = <Book>[];
    for (var i = 0; i < _books.length; i++) {
      final old = byId[_books[i].id];
      if (old != null) {
        _books[i] = old;
        changed.add(old);
      }
    }
    if (changed.isEmpty) return;
    notifyListeners();
    await _store.saveAll(changed);
  }

  // ---- trash

  Future<void> moveToTrash(String id) => trashAll({id});

  Future<void> trashAll(Set<String> ids) {
    final now = DateTime.now();
    return _updateMany(ids, (book) => book.copyWith(deletedAt: () => now));
  }

  Future<void> restore(String id) => restoreAll({id});

  Future<void> restoreAll(Set<String> ids) =>
      _updateMany(ids, (book) => book.copyWith(deletedAt: () => null));

  /// Removes a book for good.
  Future<void> deleteForever(String id) async {
    _books.removeWhere((book) => book.id == id);
    notifyListeners();
    await _store.remove(id);
  }

  Future<void> emptyTrash() async {
    final ids = [for (final b in _books) if (b.deletedAt != null) b.id];
    if (ids.isEmpty) return;
    _books.removeWhere((book) => book.deletedAt != null);
    notifyListeners();
    for (final id in ids) {
      await _store.remove(id);
    }
  }

  // ---- import and restore

  /// Adds [incoming] books, skipping any whose title and author match a book
  /// already in the library. Returns how many were added.
  Future<int> importBooks(List<Book> incoming) async {
    final known = {
      for (final book in _books)
        if (book.deletedAt == null) _duplicateKey(book),
    };
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

  Future<void> _update(String id, Book Function(Book) change) =>
      _updateMany({id}, change);

  Future<void> _updateMany(Set<String> ids, Book Function(Book) change) async {
    final changed = <Book>[];
    for (var i = 0; i < _books.length; i++) {
      if (ids.contains(_books[i].id)) {
        final updated = change(_books[i]);
        _books[i] = updated;
        changed.add(updated);
      }
    }
    if (changed.isEmpty) return;
    notifyListeners();
    await _store.saveAll(changed);
  }
}
