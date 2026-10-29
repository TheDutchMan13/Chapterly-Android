import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/book_sorting.dart';
import '../data/file_io.dart';
import '../data/open_library_client.dart';
import '../models/book.dart';
import '../models/book_format.dart';
import '../models/shelf.dart';
import '../widgets/book_cover.dart';
import 'add_book_dialog.dart';
import 'book_detail_screen.dart';
import 'scan_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'shelf_picker.dart';
import 'statistics_screen.dart';
import 'trash_screen.dart';

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
  final Set<BookFormat> _formats = {};
  final Set<String> _selected = {};
  final _searchController = TextEditingController();
  bool _searching = false;
  bool _favoritesOnly = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _filtering =>
      _selectedTags.isNotEmpty ||
      _formats.isNotEmpty ||
      _favoritesOnly ||
      _searchController.text.trim().isNotEmpty;

  void _toggleFormat(BookFormat format) {
    setState(() {
      if (!_formats.add(format)) _formats.remove(format);
    });
  }

  void _stopSearching() {
    setState(() {
      _searching = false;
      _searchController.clear();
    });
  }

  void _toggleSelected(Book book) {
    setState(() {
      if (!_selected.add(book.id)) _selected.remove(book.id);
    });
  }

  Future<void> _moveSelected() async {
    final shelf = await showShelfPicker(context);
    if (shelf == null || !mounted) return;
    final ids = {..._selected};
    final before = [
      for (final id in ids)
        ?widget.repository.byId(id),
    ];
    final messenger = ScaffoldMessenger.of(context);
    await widget.repository.moveAllTo(ids, shelf);
    if (!mounted) return;
    setState(_selected.clear);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Moved ${ids.length} book${ids.length == 1 ? '' : 's'} '
          'to ${shelf.label}',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.repository.putBack(before),
        ),
      ),
    );
  }

  Future<void> _tagSelected() async {
    final controller = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add a tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tag'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (tag == null || tag.trim().isEmpty || !mounted) return;
    await widget.repository.addTagToAll({..._selected}, tag);
    if (mounted) setState(_selected.clear);
  }

  Future<void> _trashSelected() async {
    final ids = {..._selected};
    final messenger = ScaffoldMessenger.of(context);
    await widget.repository.trashAll(ids);
    if (!mounted) return;
    setState(_selected.clear);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${ids.length} book${ids.length == 1 ? '' : 's'} moved to the trash',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.repository.restoreAll(ids),
        ),
      ),
    );
  }

  void _openTrash() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrashScreen(repository: widget.repository),
      ),
    );
  }

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
          fileIo: widget.fileIo,
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
          settings: widget.settings,
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
      format: data.format,
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

  AppBar _buildAppBar(PreferredSizeWidget tabBar) {
    if (_selected.isNotEmpty) {
      return AppBar(
        leading: IconButton(
          tooltip: 'Cancel selection',
          icon: const Icon(Icons.close),
          onPressed: () => setState(_selected.clear),
        ),
        title: Text('${_selected.length} selected'),
        actions: [
          IconButton(
            tooltip: 'Move to shelf',
            icon: const Icon(Icons.drive_file_move_outline),
            onPressed: _moveSelected,
          ),
          IconButton(
            tooltip: 'Add a tag',
            icon: const Icon(Icons.label_outline),
            onPressed: _tagSelected,
          ),
          IconButton(
            tooltip: 'Move to trash',
            icon: const Icon(Icons.delete_outline),
            onPressed: _trashSelected,
          ),
        ],
        bottom: tabBar,
      );
    }
    if (_searching) {
      return AppBar(
        leading: IconButton(
          tooltip: 'Close search',
          icon: const Icon(Icons.arrow_back),
          onPressed: _stopSearching,
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Title, author, ISBN or tag',
            border: InputBorder.none,
          ),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.clear),
              onPressed: () => setState(_searchController.clear),
            ),
        ],
        bottom: tabBar,
      );
    }
    return AppBar(
      title: const Text('Chapterly'),
      actions: [
        IconButton(
          tooltip: 'Search',
          icon: const Icon(Icons.search),
          onPressed: () => setState(() => _searching = true),
        ),
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
        PopupMenuButton<VoidCallback>(
          tooltip: 'More',
          onSelected: (action) => action(),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: _openStatistics,
              child: const Text('Statistics'),
            ),
            PopupMenuItem(value: _openTrash, child: const Text('Trash')),
            PopupMenuItem(
              value: _openSettings,
              child: const Text('Settings'),
            ),
          ],
        ),
      ],
      bottom: tabBar,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.settings, widget.repository]),
      builder: (context, _) => DefaultTabController(
        length: Shelf.values.length,
        child: PopScope(
          canPop: _selected.isEmpty && !_searching,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_selected.isNotEmpty) {
              setState(_selected.clear);
            } else {
              _stopSearching();
            }
          },
          child: Scaffold(
            appBar: _buildAppBar(
              TabBar(
                isScrollable: true,
                tabs: [
                  for (final shelf in Shelf.values)
                    Tab(
                      text: '${shelf.label} '
                          '(${widget.repository.booksOn(shelf).length})',
                    ),
                ],
              ),
            ),
            body: ListenableBuilder(
              listenable: widget.repository,
              builder: (context, _) {
                if (!widget.repository.isLoaded) {
                  return const Center(child: CircularProgressIndicator());
                }
                final allTags = widget.repository.allTags;
                // Forget filters for tags that no longer exist on any book,
                // and selections for books that are gone.
                _selectedTags.retainAll(allTags);
                _selected.retainAll({
                  for (final book in widget.repository.books) book.id,
                });
                return Column(
                  children: [
                    _FilterBar(
                      chips: [
                        FilterChip(
                          avatar: const Icon(Icons.favorite, size: 18),
                          label: const Text('Favorites'),
                          selected: _favoritesOnly,
                          onSelected: (value) =>
                              setState(() => _favoritesOnly = value),
                        ),
                        for (final format in BookFormat.values)
                          FilterChip(
                            label: Text(format.label),
                            selected: _formats.contains(format),
                            onSelected: (_) => _toggleFormat(format),
                          ),
                        for (final tag in allTags)
                          FilterChip(
                            label: Text(tag),
                            selected: _selectedTags.contains(tag),
                            onSelected: (_) => _toggleTag(tag),
                          ),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          for (final shelf in Shelf.values)
                            _ShelfList(
                              books: sortBooks(
                                widget.repository.booksOn(
                                  shelf,
                                  tags: _selectedTags,
                                  query: _searchController.text,
                                  favoritesOnly: _favoritesOnly,
                                  formats: _formats,
                                ),
                                widget.settings.sortField,
                                ascending: widget.settings.ascending,
                              ),
                              display: widget.settings.display,
                              filtering: _filtering,
                              selected: _selected,
                              onOpen: (book) => _selected.isEmpty
                                  ? _openBook(book)
                                  : _toggleSelected(book),
                              onSelect: _toggleSelected,
                              onMove: widget.repository.moveTo,
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            floatingActionButton: _selected.isEmpty
                ? FloatingActionButton(
                    tooltip: 'Add book',
                    onPressed: _addBook,
                    child: const Icon(Icons.add),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.chips});

  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: chips.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) => chips[index],
      ),
    );
  }
}

class _ShelfList extends StatelessWidget {
  const _ShelfList({
    required this.books,
    required this.display,
    required this.filtering,
    required this.selected,
    required this.onOpen,
    required this.onSelect,
    required this.onMove,
  });

  final List<Book> books;
  final DisplayMode display;
  final bool filtering;
  final Set<String> selected;
  final void Function(Book book) onOpen;
  final void Function(Book book) onSelect;
  final void Function(String id, Shelf shelf) onMove;

  List<String> _subtitleLines(Book book) {
    final first = [
      if (book.author.isNotEmpty) book.author,
      if (book.format != null) book.format!.label,
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
                ? 'No books on this shelf match your search or filters.'
                : 'No books on this shelf yet.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final selecting = selected.isNotEmpty;

    if (display == DisplayMode.grid) {
      final highlight = Theme.of(context).colorScheme.primaryContainer;
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
            onLongPress: () => onSelect(book),
            child: Container(
              color: selected.contains(book.id) ? highlight : null,
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      BookCover(
                        coverUrl: book.coverUrl,
                        coverPath: book.coverPath,
                        width: 110,
                        height: 160,
                      ),
                      if (book.favorite)
                        const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.favorite,
                            size: 18,
                            color: Colors.redAccent,
                          ),
                        ),
                    ],
                  ),
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
          selected: selected.contains(book.id),
          selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
          leading: BookCover(
            coverUrl: book.coverUrl,
            coverPath: book.coverPath,
          ),
          title: Text(book.title),
          subtitle: lines.isEmpty ? null : Text(lines.join('\n')),
          isThreeLine: lines.length > 1,
          onTap: () => onOpen(book),
          onLongPress: () => onSelect(book),
          trailing: selecting
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (book.favorite)
                      const Icon(
                        Icons.favorite,
                        size: 18,
                        color: Colors.redAccent,
                      ),
                    PopupMenuButton<Shelf>(
                      tooltip: 'Move to shelf',
                      onSelected: (shelf) => onMove(book.id, shelf),
                      itemBuilder: (_) => [
                        for (final shelf in Shelf.values)
                          if (shelf != book.shelf)
                            PopupMenuItem(
                              value: shelf,
                              child: Text(shelf.label),
                            ),
                      ],
                    ),
                  ],
                ),
        );
      },
    );
  }
}
