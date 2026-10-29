import 'package:flutter/foundation.dart';

import '../models/book.dart';
import '../models/shelf.dart';

/// Holds books in memory. Replace with a database-backed version later.
class BookRepository extends ChangeNotifier {
  final List<Book> _books = [];

  List<Book> booksOn(Shelf shelf) =>
      _books.where((book) => book.shelf == shelf).toList();

  void add({required String title, required String author, required Shelf shelf}) {
    _books.add(Book(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      author: author,
      shelf: shelf,
    ));
    notifyListeners();
  }

  void moveTo(String id, Shelf shelf) {
    final index = _books.indexWhere((book) => book.id == id);
    if (index == -1) return;
    _books[index] = _books[index].copyWith(shelf: shelf);
    notifyListeners();
  }
}
