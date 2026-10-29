import 'package:flutter_test/flutter_test.dart';

import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/models/shelf.dart';

void main() {
  test('adds a book to a shelf and moves it', () {
    final repo = BookRepository();
    repo.add(title: 'Dune', author: 'Frank Herbert', shelf: Shelf.forLater);

    expect(repo.booksOn(Shelf.forLater).single.title, 'Dune');

    final id = repo.booksOn(Shelf.forLater).single.id;
    repo.moveTo(id, Shelf.finished);

    expect(repo.booksOn(Shelf.forLater), isEmpty);
    expect(repo.booksOn(Shelf.finished).single.title, 'Dune');
  });
}
