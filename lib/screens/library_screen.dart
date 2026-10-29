import 'package:flutter/material.dart';

import '../data/book_repository.dart';
import '../models/book.dart';
import '../models/shelf.dart';
import 'add_book_dialog.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, required this.repository});

  final BookRepository repository;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: Shelf.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chapterly'),
          bottom: TabBar(
            isScrollable: true,
            tabs: [for (final shelf in Shelf.values) Tab(text: shelf.label)],
          ),
        ),
        body: ListenableBuilder(
          listenable: repository,
          builder: (context, _) => TabBarView(
            children: [
              for (final shelf in Shelf.values)
                _ShelfList(
                  books: repository.booksOn(shelf),
                  onMove: repository.moveTo,
                ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Add book',
          onPressed: () async {
            final result = await showAddBookDialog(context);
            if (result == null) return;
            repository.add(
              title: result['title'] as String,
              author: result['author'] as String,
              shelf: result['shelf'] as Shelf,
            );
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _ShelfList extends StatelessWidget {
  const _ShelfList({required this.books, required this.onMove});

  final List<Book> books;
  final void Function(String id, Shelf shelf) onMove;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return const Center(child: Text('No books on this shelf yet.'));
    }
    return ListView.builder(
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        return ListTile(
          title: Text(book.title),
          subtitle: Text(book.author),
          trailing: PopupMenuButton<Shelf>(
            tooltip: 'Move to shelf',
            onSelected: (shelf) => onMove(book.id, shelf),
            itemBuilder: (_) => [
              for (final shelf in Shelf.values)
                if (shelf != book.shelf)
                  PopupMenuItem(value: shelf, child: Text(shelf.label)),
            ],
          ),
        );
      },
    );
  }
}
