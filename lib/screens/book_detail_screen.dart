import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/book_repository.dart';
import '../data/date_format.dart';
import '../data/file_io.dart';
import '../models/book.dart';
import '../models/book_format.dart';
import '../models/reading.dart';
import '../models/shelf.dart';
import '../widgets/book_cover.dart';
import 'book_card_screen.dart';
import 'log_entry_dialog.dart';
import 'similar_books_screen.dart';

/// Shows one book. Change its shelf, format, rating, dates, pages, tags,
/// notes and cover, keep a reading log, read it again, or move it to the trash.
class BookDetailScreen extends StatelessWidget {
  const BookDetailScreen({
    super.key,
    required this.repository,
    required this.fileIo,
    required this.bookId,
  });

  final BookRepository repository;
  final FileIo fileIo;
  final String bookId;

  /// Shows a dialog with one text field. Returns the text, or null if cancelled.
  Future<String?> _askText(
    BuildContext context, {
    required String title,
    required String initial,
    String? label,
    String? helper,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: maxLines == 1 ? 1 : 3,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: formatters,
          decoration: InputDecoration(labelText: label, helperText: helper),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editTags(BuildContext context, Book book) async {
    final text = await _askText(
      context,
      title: 'Edit tags',
      initial: book.tags.join(', '),
      label: 'Tags',
      helper: 'Separate with commas',
    );
    if (text == null) return;
    await repository.setTags(book.id, parseTags(text));
  }

  Future<void> _editPages(BuildContext context, Book book) async {
    final text = await _askText(
      context,
      title: 'Number of pages',
      initial: book.pages?.toString() ?? '',
      label: 'Pages',
      helper: 'Leave empty to clear',
      keyboardType: TextInputType.number,
      formatters: [FilteringTextInputFormatter.digitsOnly],
    );
    if (text == null) return;
    final pages = int.tryParse(text.trim());
    await repository.setPages(book.id, pages != null && pages > 0 ? pages : null);
  }

  Future<void> _editNotes(BuildContext context, Book book) async {
    final text = await _askText(
      context,
      title: 'Notes and review',
      initial: book.notes ?? '',
      label: 'Your thoughts',
      helper: 'Leave empty to clear',
      maxLines: 8,
    );
    if (text == null) return;
    await repository.setNotes(book.id, text);
  }

  Future<void> _pickDate(
    BuildContext context,
    Book book, {
    required bool start,
  }) async {
    final current = start ? book.startedAt : book.finishedAt;
    final first = DateTime(1950);
    final last = DateTime.now().add(const Duration(days: 1));
    var initial = current ?? DateTime.now();
    if (initial.isAfter(last)) initial = last;
    if (initial.isBefore(first)) initial = first;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null || !context.mounted) return;

    final startedAt = start ? picked : book.startedAt;
    final finishedAt = start ? book.finishedAt : picked;
    if (startedAt != null &&
        finishedAt != null &&
        finishedAt.isBefore(startedAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The finish date cannot be before the start date.'),
        ),
      );
      return;
    }
    await repository.setDates(
      book.id,
      startedAt: startedAt,
      finishedAt: finishedAt,
    );
  }

  Future<void> _addLogEntry(BuildContext context, Book book) async {
    final amounts = await showLogEntryDialog(context);
    if (amounts == null) return;
    await repository.addLogEntry(
      book.id,
      DateTime.now(),
      amounts.pages,
      minutes: amounts.minutes,
    );
  }

  Future<void> _readAgain(BuildContext context, Book book) async {
    var start = DateTime.now();
    final chosen = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Read again?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This reading is saved under "Earlier readings". The book '
                'moves to In progress.',
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                icon: const Icon(Icons.event),
                label: Text('Started ${formatDate(start)}'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: start,
                    firstDate: DateTime(1950),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setDialogState(() => start = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(start),
              child: const Text('Read again'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    await repository.readAgain(book.id, startedAt: chosen);
  }

  Future<void> _editSeries(BuildContext context, Book book) async {
    final name = TextEditingController(text: book.series ?? '');
    final number =
        TextEditingController(text: book.seriesNumber?.toString() ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Series'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Series name',
                helperText: 'Leave empty to remove',
              ),
            ),
            TextField(
              controller: number,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Book number'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final nameText = name.text;
    final numberValue = int.tryParse(number.text.trim());
    name.dispose();
    number.dispose();
    if (saved != true) return;
    await repository.setSeries(
      book.id,
      nameText,
      numberValue != null && numberValue > 0 ? numberValue : null,
    );
  }

  void _openBook(BuildContext context, Book book) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookDetailScreen(
          repository: repository,
          fileIo: fileIo,
          bookId: book.id,
        ),
      ),
    );
  }

  void _openCard(BuildContext context, Book book) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookCardScreen(book: book, fileIo: fileIo),
      ),
    );
  }

  Future<void> _editCover(BuildContext context, Book book) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose a photo'),
              onTap: () => Navigator.of(sheetContext).pop('pick'),
            ),
            if (book.coverPath != null)
              ListTile(
                leading: const Icon(Icons.hide_image_outlined),
                title: const Text('Remove my cover'),
                onTap: () => Navigator.of(sheetContext).pop('remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'remove') {
      await repository.setCoverPath(book.id, null);
      return;
    }
    try {
      final path = await fileIo.pickCoverImage(book.id);
      if (path != null) await repository.setCoverPath(book.id, path);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not use that photo.')),
      );
    }
  }

  Future<void> _trash(BuildContext context, Book book) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await repository.moveToTrash(book.id);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text('"${book.title}" moved to the trash'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => repository.restore(book.id),
        ),
      ),
    );
  }

  void _showSimilar(
    BuildContext context, {
    required String title,
    required bool Function(Book) test,
    int Function(Book, Book)? compare,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SimilarBooksScreen(
          repository: repository,
          fileIo: fileIo,
          title: title,
          test: test,
          compare: compare,
        ),
      ),
    );
  }

  Widget _dateTile(BuildContext context, Book book, {required bool start}) {
    final date = start ? book.startedAt : book.finishedAt;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        start ? Icons.play_circle_outline : Icons.check_circle_outline,
      ),
      title: Text(start ? 'Started' : 'Finished'),
      subtitle: Text(date == null ? 'Not set' : formatDate(date)),
      trailing: date == null
          ? null
          : IconButton(
              tooltip: 'Clear date',
              icon: const Icon(Icons.clear),
              onPressed: () => repository.setDates(
                book.id,
                startedAt: start ? null : book.startedAt,
                finishedAt: start ? book.finishedAt : null,
              ),
            ),
      onTap: () => _pickDate(context, book, start: start),
    );
  }

  String _logLine(LogEntry entry) {
    final amounts = [
      if (entry.pages > 0) '${entry.pages} pages',
      if (entry.minutes > 0) formatMinutes(entry.minutes),
    ].join(' · ');
    return '${formatDate(entry.date)}: $amounts';
  }

  String _readingSummary(Reading reading) {
    final started = reading.startedAt;
    final finished = reading.finishedAt;
    final dates = [
      if (started != null) formatDate(started),
      if (finished != null) formatDate(finished),
    ].join(' → ');
    return [
      if (dates.isNotEmpty) dates else 'No dates',
      if (reading.rating != null) '★ ${reading.rating}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repository,
      builder: (context, _) {
        final book = repository.byId(bookId);
        if (book == null) return const Scaffold(body: SizedBox.shrink());
        final textTheme = Theme.of(context).textTheme;
        final loggedPages =
            book.readingLog.fold<int>(0, (sum, entry) => sum + entry.pages);
        final loggedMinutes =
            book.readingLog.fold<int>(0, (sum, entry) => sum + entry.minutes);
        final author = book.author;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Book'),
            actions: [
              IconButton(
                tooltip: 'Share a book card',
                icon: const Icon(Icons.ios_share),
                onPressed: () => _openCard(context, book),
              ),
              IconButton(
                tooltip: book.favorite
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                icon: Icon(
                  book.favorite ? Icons.favorite : Icons.favorite_border,
                  color: book.favorite ? Colors.redAccent : null,
                ),
                onPressed: () =>
                    repository.setFavorite(book.id, favorite: !book.favorite),
              ),
              IconButton(
                tooltip: 'Move to trash',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _trash(context, book),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: InkWell(
                  onTap: () => _editCover(context, book),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      BookCover(
                        coverUrl: book.coverUrl,
                        coverPath: book.coverPath,
                        width: 120,
                        height: 180,
                      ),
                      const Padding(
                        padding: EdgeInsets.all(4),
                        child: CircleAvatar(
                          radius: 14,
                          child: Icon(Icons.edit, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(book.title, style: textTheme.headlineSmall),
              const SizedBox(height: 4),
              if (author.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => _showSimilar(
                      context,
                      title: 'More by $author',
                      test: (other) =>
                          other.author.toLowerCase() == author.toLowerCase(),
                    ),
                    icon: const Icon(Icons.person_outline),
                    label: Text(author),
                  ),
                ),
              if (book.firstPublishYear != null)
                Text('First published ${book.firstPublishYear}'),
              if (book.isbn != null) Text('ISBN ${book.isbn}'),
              const SizedBox(height: 24),
              DropdownButtonFormField<Shelf>(
                initialValue: book.shelf,
                decoration: const InputDecoration(labelText: 'Shelf'),
                items: [
                  for (final shelf in Shelf.values)
                    DropdownMenuItem(value: shelf, child: Text(shelf.label)),
                ],
                onChanged: (value) {
                  if (value != null) repository.moveTo(book.id, value);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<BookFormat?>(
                initialValue: book.format,
                decoration: const InputDecoration(labelText: 'Format'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Not set')),
                  for (final format in BookFormat.values)
                    DropdownMenuItem(value: format, child: Text(format.label)),
                ],
                onChanged: (value) => repository.setFormat(book.id, value),
              ),
              const SizedBox(height: 24),
              Text('Your rating', style: textTheme.titleMedium),
              Row(
                children: [
                  for (var star = 1; star <= 5; star++)
                    IconButton(
                      tooltip: '$star of 5',
                      icon: Icon(
                        star <= (book.rating ?? 0)
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.amber,
                      ),
                      onPressed: () => repository.setRating(
                        book.id,
                        book.rating == star ? null : star,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _dateTile(context, book, start: true),
              _dateTile(context, book, start: false),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('Pages'),
                subtitle: Text(book.pages?.toString() ?? 'Not set'),
                onTap: () => _editPages(context, book),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.collections_bookmark_outlined),
                title: const Text('Series'),
                subtitle: Text(
                  book.series == null
                      ? 'Not set'
                      : book.seriesNumber == null
                          ? book.series!
                          : '${book.series} #${book.seriesNumber}',
                ),
                onTap: () => _editSeries(context, book),
              ),
              if (book.series != null)
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.list, size: 18),
                      label: const Text('Show the series'),
                      onPressed: () => _showSimilar(
                        context,
                        title: book.series!,
                        test: (other) =>
                            other.series?.trim().toLowerCase() ==
                            book.series!.trim().toLowerCase(),
                        compare: (a, b) =>
                            (a.seriesNumber ?? 1 << 30)
                                .compareTo(b.seriesNumber ?? 1 << 30),
                      ),
                    ),
                    if (repository.nextInSeries(book) != null)
                      ActionChip(
                        avatar: const Icon(Icons.skip_next, size: 18),
                        label: Text(
                          'Next: ${repository.nextInSeries(book)!.title}',
                        ),
                        onPressed: () =>
                            _openBook(context, repository.nextInSeries(book)!),
                      ),
                  ],
                ),
              if (book.shelf == Shelf.finished)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _readAgain(context, book),
                    icon: const Icon(Icons.replay),
                    label: const Text('Read again'),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Notes', style: textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _editNotes(context, book),
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit'),
                  ),
                ],
              ),
              Text(book.notes ?? 'No notes yet.'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Reading log', style: textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _addLogEntry(context, book),
                    icon: const Icon(Icons.add),
                    label: const Text('Add to log'),
                  ),
                ],
              ),
              if (book.readingLog.isEmpty)
                const Text(
                  'Write down pages or minutes you read to see them in your '
                  'statistics.',
                )
              else ...[
                Text(
                  [
                    if (loggedPages > 0) '$loggedPages pages',
                    if (loggedMinutes > 0) formatMinutes(loggedMinutes),
                  ].join(' · '),
                ),
                for (var i = 0; i < book.readingLog.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(_logLine(book.readingLog[i])),
                    trailing: IconButton(
                      tooltip: 'Remove entry',
                      icon: const Icon(Icons.clear),
                      onPressed: () => repository.removeLogEntry(book.id, i),
                    ),
                  ),
              ],
              if (book.previousReadings.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Earlier readings', style: textTheme.titleMedium),
                for (var i = 0; i < book.previousReadings.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.history),
                    title: Text(_readingSummary(book.previousReadings[i])),
                    trailing: IconButton(
                      tooltip: 'Remove this reading',
                      icon: const Icon(Icons.clear),
                      onPressed: () =>
                          repository.removePreviousReading(book.id, i),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Tags', style: textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _editTags(context, book),
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit'),
                  ),
                ],
              ),
              if (book.tags.isEmpty)
                const Text('No tags yet.')
              else
                Wrap(
                  spacing: 8,
                  children: [
                    for (final tag in book.tags)
                      ActionChip(
                        label: Text(tag),
                        tooltip: 'Show books with this tag',
                        onPressed: () => _showSimilar(
                          context,
                          title: 'Tagged "$tag"',
                          test: (other) => other.tags.contains(tag),
                        ),
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
