import 'package:flutter/material.dart';

import '../audio/listening.dart';
import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/book_sorting.dart';
import '../data/collections.dart';
import '../data/details_refresh.dart';
import '../data/file_io.dart';
import '../data/forecast.dart';
import '../data/open_library_client.dart';
import '../data/phone_sync.dart';
import '../data/quote_of_day.dart';
import '../data/rating_text.dart';
import '../data/saved_filters.dart';
import '../data/stalled.dart';
import '../data/statistics.dart';
import '../ebook/ebook_reading.dart';
import '../models/book.dart';
import '../models/book_format.dart';
import '../models/shelf.dart';
import '../models/wish_priority.dart';
import '../widgets/book_cover.dart';
import 'add_book_dialog.dart';
import 'add_file_flow.dart';
import 'book_detail_screen.dart';
import 'book_insights.dart';
import 'cover_size_dialog.dart';
import 'library_health_screen.dart';
import 'scan_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'shelf_picker.dart';

enum _AddChoice { search, scan, manual, bookFile, audioFile, audioFolder }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.repository,
    required this.client,
    required this.settings,
    required this.phoneSync,
    required this.fileIo,
  });

  final BookRepository repository;
  final OpenLibraryClient client;
  final AppSettings settings;
  final PhoneSync phoneSync;
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
  int _quoteSkip = 0;
  final Set<String> _excludedTags = {};
  bool _matchAllTags = true;
  int? _finishYear;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _filtering =>
      _selectedTags.isNotEmpty ||
      _excludedTags.isNotEmpty ||
      _finishYear != null ||
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

  /// Asks which of your own shelves, from [names] or a new one. Null when
  /// the dialog is closed without a choice.
  Future<String?> _chooseShelf(String title, List<String> names) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(title),
        children: [
          for (final name in names)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(name),
              child: Text(name),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(''),
            child: const Text('New shelf...'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return null;
    var name = choice;
    if (name.isEmpty) {
      final controller = TextEditingController();
      final typed = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('New shelf'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Shelf name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Add'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (typed == null || typed.trim().isEmpty || !mounted) return null;
      name = typed.trim();
      widget.settings.addCollection(name);
    }
    return name;
  }

  Future<void> _addSelectedToShelf() async {
    final name = await _chooseShelf(
      'Add to shelf',
      allCollectionNames(widget.settings, widget.repository),
    );
    if (name == null || !mounted) return;
    await widget.repository.addToCollectionAll({..._selected}, name);
    if (mounted) setState(_selected.clear);
  }

  /// The name of the shelf of your own that is open, or null on one of the
  /// main shelves.
  String? _openOwnShelf(BuildContext context) {
    final index = DefaultTabController.maybeOf(context)?.index;
    if (index == null) return null;
    final own = index - Shelf.values.length;
    final names = _collections;
    return own >= 0 && own < names.length ? names[own] : null;
  }

  /// Moves the selected books from the open shelf of your own to another.
  Future<void> _moveSelectedToOwnShelf(String from) async {
    final names = [
      for (final name in _collections)
        if (name.toLowerCase() != from.toLowerCase()) name,
    ];
    final to = await _chooseShelf('Move to shelf', names);
    if (to == null || !mounted) return;
    final ids = {..._selected};
    final before = [for (final id in ids) ?widget.repository.byId(id)];
    final messenger = ScaffoldMessenger.of(context);
    await widget.repository.moveBetweenCollections(ids, from: from, to: to);
    if (!mounted) return;
    setState(_selected.clear);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Moved ${ids.length} book${ids.length == 1 ? '' : 's'} '
          'from $from to $to',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.repository.putBack(before),
        ),
      ),
    );
  }

  /// Takes the selected books off the open shelf of your own. The books
  /// stay in the library.
  Future<void> _removeSelectedFromOwnShelf(String shelf) async {
    final ids = {..._selected};
    final before = [for (final id in ids) ?widget.repository.byId(id)];
    final messenger = ScaffoldMessenger.of(context);
    await widget.repository.removeFromCollectionAll(ids, shelf);
    if (!mounted) return;
    setState(_selected.clear);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Took ${ids.length} book${ids.length == 1 ? '' : 's'} '
          'off $shelf',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.repository.putBack(before),
        ),
      ),
    );
  }

  /// Tapping a tag cycles it: off, shown, hidden, off.
  void _cycleTag(String tag) {
    setState(() {
      if (_selectedTags.remove(tag)) {
        _excludedTags.add(tag);
      } else if (!_excludedTags.remove(tag)) {
        _selectedTags.add(tag);
      }
    });
  }

  Future<void> _chooseFinishYear() async {
    final years = widget.repository.finishedYears;
    final choice = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Finished in'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(0),
            child: const Text('Any year'),
          ),
          for (final year in years)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(year),
              child: Text('$year'),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _finishYear = choice == 0 ? null : choice);
  }

  Future<void> _changeFormatSelected() async {
    final choice = await showDialog<List<BookFormat?>>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Change format'),
        children: [
          for (final format in BookFormat.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop([format]),
              child: Text(format.label),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop([null]),
            child: const Text('Not set'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final ids = {..._selected};
    final before = [
      for (final id in ids) ?widget.repository.byId(id),
    ];
    final messenger = ScaffoldMessenger.of(context);
    await widget.repository.setFormatAll(ids, choice.first);
    if (!mounted) return;
    setState(_selected.clear);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Changed the format of ${ids.length} '
            'book${ids.length == 1 ? '' : 's'}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.repository.putBack(before),
        ),
      ),
    );
  }

  Future<void> _setPrioritySelected() async {
    final choice = await showDialog<List<WishPriority?>>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Set priority'),
        children: [
          for (final priority in WishPriority.values.reversed)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop([priority]),
              child: Text(priority.label),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop([null]),
            child: const Text('Not set'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final ids = {..._selected};
    final before = [
      for (final id in ids) ?widget.repository.byId(id),
    ];
    final messenger = ScaffoldMessenger.of(context);
    await widget.repository.setPriorityAll(ids, choice.first);
    if (!mounted) return;
    setState(_selected.clear);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Changed the priority of ${ids.length} '
            'book${ids.length == 1 ? '' : 's'}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.repository.putBack(before),
        ),
      ),
    );
  }

  Future<void> _changeAuthorSelected() async {
    final controller = TextEditingController();
    final author = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change author'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Author'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Change'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (author == null || author.trim().isEmpty || !mounted) return;
    final ids = {..._selected};
    final before = [
      for (final id in ids) ?widget.repository.byId(id),
    ];
    final messenger = ScaffoldMessenger.of(context);
    await widget.repository.setAuthorAll(ids, author);
    if (!mounted) return;
    setState(_selected.clear);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Changed the author of ${ids.length} '
            'book${ids.length == 1 ? '' : 's'}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.repository.putBack(before),
        ),
      ),
    );
  }

  /// Opens a book by id, such as one a file was just linked to.
  void _openById(String id) {
    if (!mounted) return;
    final book = widget.repository.byId(id);
    if (book != null && book.deletedAt == null) _openBook(book);
  }

  Future<void> _addFile(AddFileKind kind) => addFileToLibrary(
        context,
        repository: widget.repository,
        kind: kind,
        onLinked: _openById,
      );

  /// Fills in blank ISBNs, years, covers and pages of the selected books
  /// from Open Library.
  Future<void> _refreshSelected() async {
    final books = [
      for (final id in _selected)
        ?widget.repository.byId(id),
    ];
    if (books.isEmpty) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final done = ValueNotifier<int>(0);
    var stopped = false;
    var shown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      // Back closes the dialog too: that stops the refresh as well.
      builder: (dialog) => PopScope(
        onPopInvokedWithResult: (didPop, _) => stopped = true,
        child: AlertDialog(
          title: const Text('Refreshing details'),
          content: SizedBox(
            width: 360,
            child: ValueListenableBuilder<int>(
              valueListenable: done,
              builder: (context, count, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: count / books.length),
                  const SizedBox(height: 12),
                  Text('$count of ${books.length} books'),
                  const SizedBox(height: 4),
                  const Text(
                    'Only blank details are filled in.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                stopped = true;
                Navigator.pop(dialog);
              },
              child: const Text('Stop'),
            ),
          ],
        ),
      ),
    ).whenComplete(() => shown = false);
    final counts = {for (final outcome in RefreshOutcome.values) outcome: 0};
    for (final book in books) {
      if (stopped) break;
      final outcome =
          await refreshBookDetails(widget.repository, widget.client, book);
      counts[outcome] = counts[outcome]! + 1;
      done.value++;
      // Offline: no point asking for the rest.
      if (outcome == RefreshOutcome.failed) break;
    }
    if (shown) navigator.pop();
    done.dispose();
    final updated = counts[RefreshOutcome.updated]!;
    final parts = [
      'Filled in details for $updated ${updated == 1 ? 'book' : 'books'}',
      if (counts[RefreshOutcome.unchanged]! > 0)
        '${counts[RefreshOutcome.unchanged]} already complete',
      if (counts[RefreshOutcome.notFound]! > 0)
        '${counts[RefreshOutcome.notFound]} not found',
      if (counts[RefreshOutcome.failed]! > 0)
        'Open Library could not be reached',
    ];
    messenger.showSnackBar(SnackBar(content: Text('${parts.join(', ')}.')));
    if (mounted) setState(_selected.clear);
  }

  void _openHealth() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LibraryHealthScreen(
          repository: widget.repository,
          settings: widget.settings,
          onOpenBook: (book) {
            if (mounted) _openBook(book);
          },
        ),
      ),
    );
  }

  /// A quote or highlight to read again, one a day.
  Widget? _quoteCard() {
    if (!widget.settings.quoteOnLibrary) return null;
    final now = DateTime.now();
    if (widget.settings.quoteHiddenToday(now)) return null;
    final quotes = allQuotes(
      widget.repository.books,
      ebooks: EbookReading.library?.links ?? const {},
    );
    final quote = quoteOfTheDay(
      quotes,
      seen: widget.settings.quoteSeen,
      now: now,
      skip: _quoteSkip,
    );
    if (quote == null) return null;
    if (_quoteSkip == 0) widget.settings.markQuoteSeen(quote.key, now);
    final textTheme = Theme.of(context).textTheme;
    // Kept to two lines so the books still have most of a phone's screen.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
      child: Row(
        children: [
          const Icon(Icons.format_quote, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () => _openBook(quote.book),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quote.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium
                        ?.copyWith(fontStyle: FontStyle.italic),
                  ),
                  Text(
                    '${quote.book.title}'
                    '${quote.book.author.isEmpty ? '' : ', ${quote.book.author}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          if (quotes.length > 1)
            IconButton(
              tooltip: 'Another quote',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: () => setState(() => _quoteSkip++),
            ),
          IconButton(
            tooltip: 'Hide for today (turn it off in Settings)',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => widget.settings.hideQuoteToday(now),
          ),
        ],
      ),
    );
  }

  /// Books on In progress that have not moved for a while.
  Widget? _stalledBanner() {
    final stalled = stalledBooks(
      widget.repository.books,
      ebooks: EbookReading.library?.links ?? const {},
      snoozed: widget.settings.stalledSnoozed,
    );
    if (stalled.isEmpty) return null;
    final count = stalled.length;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
      child: Row(
        children: [
          const Icon(Icons.hourglass_bottom, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              count == 1
                  ? '"${stalled.first.book.title}" has not moved in '
                      '${stalled.first.idleDays} days.'
                  : '$count books on In progress have not moved in a while.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium,
            ),
          ),
          TextButton(
            onPressed: () {
              final now = DateTime.now();
              for (final s in stalled) {
                widget.settings.snoozeStalled(s.book.id, now);
              }
            },
            child: const Text('Keep'),
          ),
          TextButton(onPressed: _openHealth, child: const Text('Review')),
        ],
      ),
    );
  }

  // ---- Saved filters

  void _applySavedFilter(SavedFilter filter) {
    final allTags = widget.repository.allTags.toSet();
    setState(() {
      _selectedTags
        ..clear()
        ..addAll(filter.tags.where(allTags.contains));
      _excludedTags
        ..clear()
        ..addAll(filter.excludedTags.where(allTags.contains));
      _matchAllTags = filter.matchAllTags;
      _formats
        ..clear()
        ..addAll(filter.formats);
      _favoritesOnly = filter.favoritesOnly;
      _finishYear = filter.finishYear;
      _searchController.text = filter.query;
      _searching = filter.query.isNotEmpty;
    });
  }

  void _clearFilters() {
    setState(() {
      _selectedTags.clear();
      _excludedTags.clear();
      _matchAllTags = true;
      _formats.clear();
      _favoritesOnly = false;
      _finishYear = null;
      _searchController.clear();
      _searching = false;
    });
  }

  Future<void> _saveFilters() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Save these filters'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'For example: Unread fantasy',
          ),
          onSubmitted: (value) => Navigator.pop(dialog, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final clean = name?.trim() ?? '';
    if (clean.isEmpty) return;
    final filter = SavedFilter(
      name: clean,
      tags: {..._selectedTags},
      excludedTags: {..._excludedTags},
      matchAllTags: _matchAllTags,
      formats: {..._formats},
      favoritesOnly: _favoritesOnly,
      finishYear: _finishYear,
      query: _searchController.text.trim(),
    );
    widget.settings.setSavedFilters([
      for (final f in widget.settings.savedFilters)
        if (f.name.toLowerCase() != clean.toLowerCase()) f,
      filter,
    ]);
  }

  Future<void> _manageSavedFilters() async {
    await showDialog<void>(
      context: context,
      builder: (dialog) => ListenableBuilder(
        listenable: widget.settings,
        builder: (dialog, _) {
          final filters = widget.settings.savedFilters;
          return AlertDialog(
            title: const Text('Saved filters'),
            content: SizedBox(
              width: 420,
              child: filters.isEmpty
                  ? const Text('No saved filters.')
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final filter in filters)
                          ListTile(
                            title: Text(filter.name),
                            subtitle: Text(filter.describe()),
                            trailing: IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => widget.settings.setSavedFilters([
                                for (final f in filters)
                                  if (f.name != filter.name) f,
                              ]),
                            ),
                          ),
                      ],
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _savedFiltersChip() {
    final filters = widget.settings.savedFilters;
    return MenuAnchor(
      menuChildren: [
        for (final filter in filters)
          MenuItemButton(
            leadingIcon: const Icon(Icons.filter_alt_outlined),
            onPressed: () => _applySavedFilter(filter),
            child: Text(filter.name),
          ),
        if (filters.isNotEmpty) const Divider(height: 1),
        MenuItemButton(
          leadingIcon: const Icon(Icons.bookmark_add_outlined),
          onPressed: _filtering ? _saveFilters : null,
          child: const Text('Save these filters...'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.filter_alt_off_outlined),
          onPressed: _filtering ? _clearFilters : null,
          child: const Text('Clear filters'),
        ),
        if (filters.isNotEmpty)
          MenuItemButton(
            leadingIcon: const Icon(Icons.edit_outlined),
            onPressed: _manageSavedFilters,
            child: const Text('Manage saved filters...'),
          ),
      ],
      builder: (context, controller, _) => ActionChip(
        avatar: const Icon(Icons.bookmarks_outlined, size: 18),
        label: const Text('Saved filters'),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  /// This year's reading goal, at the top of the Library.
  Widget? _goalStrip() {
    if (!widget.settings.goalOnLibrary) return null;
    final year = DateTime.now().year;
    final goal = widget.settings.goalFor(year);
    if (goal == null || goal <= 0) return null;
    final stats = computeStats(widget.repository.books, year: year);
    final status = challengeStatus(
      finished: stats.finishedCount,
      goal: goal,
      year: year,
    );
    final outlook = forecastGoal(
      widget.repository.books,
      goal: goal,
      year: year,
      finishDates: [
        for (final book in widget.repository.booksOn(Shelf.inProgress))
          if (forecastFor(book) case final forecast?) forecast.date,
      ],
    );
    final textTheme = Theme.of(context).textTheme;
    // The outlook to Dec 31 is in Statistics; here it is one line and a bar.
    final details = outlook?.describe() ?? status.describe();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
      child: Row(
        children: [
          const Icon(Icons.flag_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$year goal: ${status.finished} of $goal · $details',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: status.progress),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Hide (turn it back on in Settings)',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => widget.settings.setGoalOnLibrary(false),
          ),
        ],
      ),
    );
  }


  void _openBook(Book book) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookDetailScreen(
          repository: widget.repository,
          settings: widget.settings,
          fileIo: widget.fileIo,
          bookId: book.id,
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
          phoneSync: widget.phoneSync,
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
            if (EbookReading.library != null || Listening.controller != null)
              const Divider(height: 1),
            // A file from this phone, linked to its book in your library.
            if (EbookReading.library != null)
              ListTile(
                leading: const Icon(Icons.chrome_reader_mode_outlined),
                title: const Text('Add a book to read'),
                subtitle: const Text('EPUB or PDF file'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_AddChoice.bookFile),
              ),
            if (Listening.controller != null) ...[
              ListTile(
                leading: const Icon(Icons.headphones_outlined),
                title: const Text('Add an audiobook'),
                subtitle: const Text('One audio file, such as an M4B'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_AddChoice.audioFile),
              ),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('Add an audiobook folder'),
                subtitle: const Text('A folder of audio files'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_AddChoice.audioFolder),
              ),
            ],
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
              settings: widget.settings,
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
      case _AddChoice.bookFile:
        await _addFile(AddFileKind.book);
      case _AddChoice.audioFile:
        await _addFile(AddFileKind.audioFile);
      case _AddChoice.audioFolder:
        await _addFile(AddFileKind.audioFolder);
    }
  }

  Future<void> _addManually({String? isbn}) async {
    final data = await showAddBookDialog(
      context,
      isbn: isbn,
      initialShelf: widget.settings.defaultShelf ?? Shelf.forLater,
      initialFormat: widget.settings.defaultFormat,
      initialTags: widget.settings.defaultTags,
    );
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

    final shelf = await chooseShelfForNewBook(context, widget.settings);
    if (shelf == null || !mounted) return;
    await widget.repository.add(
      title: found.title,
      author: found.author,
      shelf: shelf,
      tags: widget.settings.defaultTags,
      format: widget.settings.defaultFormat,
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

  Widget _list(List<Book> books) => _ShelfList(
        books: sortBooks(
          books,
          widget.settings.sortField,
          ascending: widget.settings.ascending,
        ),
        display: widget.settings.display,
        filtering: _filtering,
        selected: _selected,
        onOpen: (book) =>
            _selected.isEmpty ? _openBook(book) : _toggleSelected(book),
        onSelect: _toggleSelected,
        onMove: widget.repository.moveTo,
        showFormat: widget.settings.showFormatOnCards,
        showTags: widget.settings.showTagsOnCards,
        ratingAsNumber: widget.settings.ratingAsNumber,
        coverScale: widget.settings.coverScale,
      );

  List<String> get _collections =>
      allCollectionNames(widget.settings, widget.repository);

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
            tooltip: 'Add to a shelf of your own',
            icon: const Icon(Icons.playlist_add),
            onPressed: _addSelectedToShelf,
          ),
          IconButton(
            tooltip: 'Move to trash',
            icon: const Icon(Icons.delete_outline),
            onPressed: _trashSelected,
          ),
          Builder(
            builder: (context) => PopupMenuButton<VoidCallback>(
            tooltip: 'More',
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              // On a shelf of your own: move books to another one, or take
              // them off it.
              if (_openOwnShelf(context) case final shelf?) ...[
                PopupMenuItem(
                  value: () => _moveSelectedToOwnShelf(shelf),
                  child: const Text('Move to another shelf of mine'),
                ),
                PopupMenuItem(
                  value: () => _removeSelectedFromOwnShelf(shelf),
                  child: Text('Remove from $shelf'),
                ),
              ],
              PopupMenuItem(
                value: _changeFormatSelected,
                child: const Text('Change format'),
              ),
              PopupMenuItem(
                value: _changeAuthorSelected,
                child: const Text('Change author'),
              ),
              PopupMenuItem(
                value: _setPrioritySelected,
                child: const Text('Set priority'),
              ),
              PopupMenuItem(
                value: _refreshSelected,
                child: const Text('Refresh details from Open Library'),
              ),
            ],
            ),
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
      title: const Text('Library'),
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
        PopupMenuButton<DisplayMode>(
          tooltip: 'View',
          icon: Icon(
            widget.settings.display == DisplayMode.grid
                ? Icons.grid_view
                : Icons.view_list,
          ),
          onSelected: (mode) {
            if (mode != widget.settings.display) {
              widget.settings.toggleDisplay();
            }
          },
          itemBuilder: (_) => [
            for (final (mode, label) in [
              (DisplayMode.list, 'List'),
              (DisplayMode.grid, 'Grid'),
            ])
              CheckedPopupMenuItem(
                value: mode,
                checked: widget.settings.display == mode,
                child: Text(label),
              ),
            const PopupMenuDivider(),
            PopupMenuItem<DisplayMode>(
              onTap: () => showCoverSizeDialog(context, widget.settings),
              child: const Text('Cover size...'),
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
        key: ValueKey(_collections.length),
        length: Shelf.values.length + _collections.length,
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
                  for (final shelf in widget.settings.shelfOrder)
                    Tab(
                      text: '${shelf.label} '
                          '(${widget.repository.booksOn(shelf).length})',
                    ),
                  for (final name in _collections)
                    Tab(
                      text: '$name '
                          '(${widget.repository.booksInCollection(name).length})',
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
                _excludedTags.retainAll(allTags);
                _selected.retainAll({
                  for (final book in widget.repository.books) book.id,
                });
                return Column(
                  children: [
                    if (widget.settings.backupDue(
                      bookCount: widget.repository.books.length,
                    ))
                      MaterialBanner(
                        content: const Text(
                          'It has been a while since your last backup.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                widget.settings.snoozeBackupReminder(),
                            child: const Text('Later'),
                          ),
                          TextButton(
                            onPressed: _openSettings,
                            child: const Text('Back up'),
                          ),
                        ],
                      ),
                    ?_goalStrip(),
                    // One note at a time, so the books keep the screen.
                    ?(_stalledBanner() ?? _quoteCard()),
                    _FilterBar(
                      chips: [
                        _savedFiltersChip(),
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
                        if (widget.repository.finishedYears.isNotEmpty)
                          FilterChip(
                            label: Text(
                              _finishYear == null
                                  ? 'Year finished'
                                  : 'Finished $_finishYear',
                            ),
                            selected: _finishYear != null,
                            onSelected: (_) => _chooseFinishYear(),
                          ),
                        if (_selectedTags.length > 1)
                          ActionChip(
                            label: Text(
                              _matchAllTags
                                  ? 'Match all tags'
                                  : 'Match any tag',
                            ),
                            onPressed: () =>
                                setState(() => _matchAllTags = !_matchAllTags),
                          ),
                        for (final tag in allTags)
                          FilterChip(
                            tooltip: 'Tap to show these books, '
                                'tap again to hide them',
                            avatar: _excludedTags.contains(tag)
                                ? const Icon(Icons.block, size: 18)
                                : null,
                            label: Text(
                              tag,
                              style: _excludedTags.contains(tag)
                                  ? const TextStyle(
                                      decoration: TextDecoration.lineThrough,
                                    )
                                  : null,
                            ),
                            selected: _selectedTags.contains(tag) ||
                                _excludedTags.contains(tag),
                            onSelected: (_) => _cycleTag(tag),
                          ),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          for (final shelf in widget.settings.shelfOrder)
                            _list(
                              widget.repository.booksOn(
                                shelf,
                                tags: _selectedTags,
                                matchAllTags: _matchAllTags,
                                excludedTags: _excludedTags,
                                finishYear: _finishYear,
                                query: _searchController.text,
                                favoritesOnly: _favoritesOnly,
                                formats: _formats,
                              ),
                            ),
                          for (final name in _collections)
                            _list(
                              widget.repository.booksInCollection(
                                name,
                                tags: _selectedTags,
                                matchAllTags: _matchAllTags,
                                excludedTags: _excludedTags,
                                finishYear: _finishYear,
                                query: _searchController.text,
                                favoritesOnly: _favoritesOnly,
                                formats: _formats,
                              ),
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
    required this.showFormat,
    required this.showTags,
    required this.ratingAsNumber,
    required this.coverScale,
  });

  final List<Book> books;
  final DisplayMode display;
  final bool filtering;
  final Set<String> selected;
  final void Function(Book book) onOpen;
  final void Function(Book book) onSelect;
  final void Function(String id, Shelf shelf) onMove;
  final bool showFormat;
  final bool showTags;
  final bool ratingAsNumber;

  /// How big the covers are in the grid; 1 is the normal size.
  final double coverScale;

  List<String> _subtitleLines(Book book) {
    final format = book.format;
    final rating = book.rating;
    final priority = book.priority;
    final first = [
      if (book.author.isNotEmpty) book.author,
      if (showFormat && format != null) format.label,
      if (rating != null) ratingText(rating, asNumber: ratingAsNumber),
      if (book.shelf == Shelf.forLater && priority != null)
        '${priority.label} priority',
      if (book.shelf == Shelf.inProgress && book.progress != null)
        '${(book.progress! * 100).round()}% read',
    ].join(' · ');
    return [
      if (first.isNotEmpty) first,
      if (showTags && book.tags.isNotEmpty) book.tags.join(' · '),
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
      final coverWidth = 110 * coverScale;
      final coverHeight = 160 * coverScale;
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: coverWidth + 20,
          mainAxisExtent: coverHeight + 60,
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
                        width: coverWidth,
                        height: coverHeight,
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
