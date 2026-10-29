import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/book_sorting.dart';
import '../data/file_io.dart';
import '../data/open_library_client.dart';
import '../models/book.dart';
import '../models/shelf.dart';
import '../widgets/book_cover.dart';
import 'add_book_dialog.dart';
import 'book_detail_screen.dart';
import 'scan_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'shelf_picker.dart';
import 'statistics_screen.dart';

enum _AddChoice { search, scan, manual }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.repository,
    required this.client,
    required this.settings,
    required this.fileIo,
  });

  final BookRepository repository;
  final OpenLibraryClient client;
  final AppSettings settings;
  final FileIo fileIo;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final Set<String> _selectedTags = {};

  void _toggleTag(String tag) {
    setState(() {
      if (!_selectedTags.add(tag)) _selectedTags.remove(tag);
    });
  }

  void _openBook(Book book) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookDetailScreen(
          repository: widget.repository,
          bookId: book.id,
        ),
      ),
    );
  }

  void _openStatistics() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StatisticsScreen(
          repository: widget.repository,
          settings: widget.settings,
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          repository: widget.repository,
          fileIo: widget.fileIo,
        ),
      ),
    );
  }

  Future<void> _addBook() async {
    final choice = await showModalBottomSheet<_AddChoice>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Search Open Library'),
              onTap: () => Navigator.of(sheetContext).pop(_AddChoice.search),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Scan a barcode'),
              onTap: () => Navigator.of(sheetContext).pop(_AddChoice.scan),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Add manually'),
              onTap: () => Navigator.of(sheetContext).pop(_AddChoice.manual),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _AddChoice.search:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SearchScreen(
              repository: widget.repository,
              client: widget.client,
            ),
          ),
        );
      case _AddChoice.scan:
        final scanned = await Navigator.of(context).push<ScannedBook>(
          MaterialPageRoute<ScannedBook>(
            builder: (_) => ScanScreen(client: widget.client),
          ),
        );
        if (scanned == null || !mounted) return;
        await _addScanned(scanned);
      case _AddChoice.manual:
        await _addManually();
    }
  }

  Future<void> _addManually({String? isbn}) async {
    final data = await showAddBookDialog(context, isbn: isbn);
    if (data == null) return;
    await widget.repository.add(
      title: data.title,
      author: data.author,
      shelf: data.shelf,
      tags: data.tags,
      isbn: data.isbn,
      pages: data.pages,
    );
  }

  Future<void> _addScanned(ScannedBook scanned) async {
    final found = scanned.book;
    if (found == null) {
      final addManually = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Book not found'),
          content: Text(
            'Open Library has no match for ISBN ${scanned.isbn}. '
            'Do you want to add it yourself?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Add manually'),
            ),
          ],
        ),
      );
      if (addManually != true || !mounted) return;
      await _addManually(isbn: scanned.isbn);
      return;
    }

    final shelf = await showShelfPicker(context);
    if (shelf == null || !mounted) return;
    await widget.repository.add(
      title: found.title,
      author: found.author,
      shelf: shelf,
      isbn: scanned.isbn,
      coverUrl: found.coverUrl,
      firstPublishYear: found.firstPublishYear,
      pages: found.pages,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added "${found.title}" to ${shelf.label}')),
    );
  }

  String _sortLabel(SortField field) {
    if (field != widget.settings.sortField) return field.label;
    return '${field.label} ${widget.settings.ascending ? '↑' : '↓'}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) => DefaultTabController(
        length: Shelf.values.length,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Chapterly'),
            actions: [
              PopupMenuButton<SortField>(
                icon: const Icon(Icons.sort),
                tooltip: 'Sort',
                onSelected: widget.settings.setSort,
                itemBuilder: (_) => [
                  for (final field in SortField.values)
                    CheckedPopupMenuItem<SortField>(
                      value: field,
                      checked: field == widget.settings.sortField,
                      child: Text(_sortLabel(field)),
                    ),
                ],
              ),
              IconButton(
                tooltip: widget.settings.display == DisplayMode.grid
                    ? 'Show as list'
                    : 'Show as grid',
                icon: Icon(
                  widget.settings.display == DisplayMode.grid
                      ? Icons.view_list
                      : Icons.grid_view,
                ),
                onPressed: widget.settings.toggleDisplay,
              ),
              IconButton(
                tooltip: 'Statistics',
                icon: const Icon(Icons.bar_chart),
                onPressed: _openStatistics,
              ),
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings),
                onPressed: _openSettings,
              ),
            ],
            bottom: TabBar(
              isScrollable: true,
              tabs: [for (final shelf in Shelf.values) Tab(text: shelf.label)],
            ),
          ),
          body: ListenableBuilder(
            listenable: widget.repository,
            builder: (context, _) {
              if (!widget.repository.isLoaded) {
                return const Center(child: CircularProgressIndicator());
              }
              final allTags = widget.repository.allTags;
              // Forget filters for tags that no longer exist on any book.
              _selectedTags.retainAll(allTags);
              return Column(
                children: [
                  if (allTags.isNotEmpty)
                    _TagFilterBar(
                      tags: allTags,
                      selected: _selectedTags,
                      onToggle: _toggleTag,
                    ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        for (final shelf in Shelf.values)
                          _ShelfList(
                            books: sortBooks(
                              widget.repository
                                  .booksOn(shelf, tags: _selectedTags),
                              widget.settings.sortField,
                              ascending: widget.settings.ascending,
                            ),
                            display: widget.settings.display,
                            filtering: _selectedTags.isNotEmpty,
                            onOpen: _openBook,
                            onMove: widget.repository.moveTo,
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          floatingActionButton: FloatingActionButton(
            tooltip: 'Add book',
            onPressed: _addBook,
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );
  }
}

class _TagFilterBar extends StatelessWidget {
  const _TagFilterBar({
    required this.tags,
    required this.selected,
    required this.onToggle,
  });

  final List<String> tags;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: tags.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tag = tags[index];
          return FilterChip(
            label: Text(tag),
            selected: selected.contains(tag),
            onSelected: (_) => onToggle(tag),
          );
        },
      ),
    );
  }
}

class _ShelfList extends StatelessWidget {
  const _ShelfList({
    required this.books,
    required this.display,
    required this.filtering,
    required this.onOpen,
    required this.onMove,
  });

  final List<Book> books;
  final DisplayMode display;
  final bool filtering;
  final void Function(Book book) onOpen;
  final void Function(String id, Shelf shelf) onMove;

  List<String> _subtitleLines(Book book) {
    final first = [
      if (book.author.isNotEmpty) book.author,
      if (book.rating != null) '★ ${book.rating}',
    ].join(' · ');
    return [
      if (first.isNotEmpty) first,
      if (book.tags.isNotEmpty) book.tags.join(' · '),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            filtering
                ? 'No books on this shelf have the selected tags.'
                : 'No books on this shelf yet.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (display == DisplayMode.grid) {
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130,
          mainAxisExtent: 220,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: books.length,
        itemBuilder: (context, index) {
          final book = books[index];
          return InkWell(
            onTap: () => onOpen(book),
            child: Column(
              children: [
                BookCover(coverUrl: book.coverUrl, width: 110, height: 160),
                const SizedBox(height: 4),
                Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        },
      );
    }

    return ListView.builder(
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        final lines = _subtitleLines(book);
        return ListTile(
          leading: BookCover(coverUrl: book.coverUrl),
          title: Text(book.title),
          subtitle: lines.isEmpty ? null : Text(lines.join('\n')),
          isThreeLine: lines.length > 1,
          onTap: () => onOpen(book),
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
