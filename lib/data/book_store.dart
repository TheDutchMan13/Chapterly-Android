import '../models/book.dart';

/// Where books are saved. The app uses SQLite; tests use the in-memory one.
abstract interface class BookStore {
  Future<List<Book>> loadAll();
  Future<void> save(Book book);
  Future<void> saveAll(List<Book> books);
  Future<void> replaceAll(List<Book> books);
  Future<void> remove(String id);
}

class InMemoryBookStore implements BookStore {
  final Map<String, Book> _books = {};

  @override
  Future<List<Book>> loadAll() async => _books.values.toList();

  @override
  Future<void> save(Book book) async {
    _books[book.id] = book;
  }

  @override
  Future<void> saveAll(List<Book> books) async {
    for (final book in books) {
      _books[book.id] = book;
    }
  }

  @override
  Future<void> replaceAll(List<Book> books) async {
    _books.clear();
    for (final book in books) {
      _books[book.id] = book;
    }
  }

  @override
  Future<void> remove(String id) async {
    _books.remove(id);
  }
}
