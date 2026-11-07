import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/library_health.dart';
import '../data/stalled.dart';
import '../ebook/ebook_reading.dart';
import '../models/book.dart';
import '../models/shelf.dart';
import 'duplicates_screen.dart';

// The same screen is in the Windows app.

/// Everything that looks wrong or missing in the library, with a tap to
/// open each book, plus stalled books and duplicates.
class LibraryHealthScreen extends StatefulWidget {
  const LibraryHealthScreen({
    super.key,
    required this.repository,
    required this.settings,
    required this.onOpenBook,
  });

  final BookRepository repository;
  final AppSettings settings;
  final void Function(Book book) onOpenBook;

  @override
  State<LibraryHealthScreen> createState() => _LibraryHealthScreenState();
}

class _LibraryHealthScreenState extends State<LibraryHealthScreen> {
  void _open(Book book) => widget.onOpenBook(book);

  Future<void> _convertIsbns(List<Book> books) async {
    var changed = 0;
    for (final book in books) {
      final isbn13 = isbn10To13(book.isbn ?? '');
      if (isbn13 == null) continue;
      await widget.repository.setIsbn(book.id, isbn13);
      changed++;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Changed $changed ${changed == 1 ? 'ISBN' : 'ISBNs'} to ISBN-13.'),
    ));
  }

  Widget _bookTile(Book book, {String? detail}) => ListTile(
        dense: true,
        title: Text(book.title),
        subtitle: Text([
          if (book.author.isNotEmpty) book.author,
          book.shelf.label,
          ?detail,
        ].join(' · ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(book),
      );

  Widget _group({
    required IconData icon,
    required String title,
    required String hint,
    required List<Widget> children,
    int? count,
    Widget? action,
  }) {
    return Card(
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text(count == null ? title : '$title ($count)'),
        subtitle: Text(hint),
        children: [
          ?action,
          ...children,
        ],
      ),
    );
  }

  List<Widget> _stalledSection() {
    final stalled = stalledBooks(
      widget.repository.books,
      ebooks: EbookReading.library?.links ?? const {},
      snoozed: widget.settings.stalledSnoozed,
    );
    if (stalled.isEmpty) return const [];
    return [
      _group(
        icon: Icons.hourglass_bottom,
        title: 'Stalled on In progress',
        hint: 'Books you have not touched for much longer than usual.',
        count: stalled.length,
        children: [
          for (final s in stalled)
            ListTile(
              dense: true,
              title: Text(s.book.title),
              onTap: () => _open(s.book),
              // The buttons go under the text so the title keeps the width
              // of a phone.
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.describe()),
                  Wrap(
                    spacing: 4,
                    children: [
                      TextButton(
                        onPressed: () => widget.settings
                            .snoozeStalled(s.book.id, DateTime.now()),
                        child: const Text('Keep'),
                      ),
                      TextButton(
                        onPressed: () =>
                            widget.repository.moveTo(s.book.id, Shelf.forLater),
                        child: const Text('For later'),
                      ),
                      TextButton(
                        onPressed: () => widget.repository
                            .moveTo(s.book.id, Shelf.unfinished),
                        child: const Text('Unfinished'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library health')),
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.repository, widget.settings]),
        builder: (context, _) {
          final issues = checkLibrary(widget.repository.books);
          final exact = widget.repository.findDuplicates().length;
          final possible = widget.repository.possibleDuplicates(
            dismissed: widget.settings.notDuplicates,
          ).length;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (issues.isEmpty && exact + possible == 0)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Nothing wrong found in your book details.'),
                ),
              if (exact + possible > 0)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.content_copy_outlined),
                    title: Text(
                      '${exact + possible} possible '
                      '${exact + possible == 1 ? 'duplicate' : 'duplicates'}',
                    ),
                    subtitle: const Text('Open Duplicates to merge them.'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DuplicatesScreen(
                          repository: widget.repository,
                          settings: widget.settings,
                        ),
                      ),
                    ),
                  ),
                ),
              ..._stalledSection(),
              for (final entry in issues.entries)
                _group(
                  icon: Icons.report_outlined,
                  title: entry.key.title,
                  hint: entry.key.hint,
                  count: entry.value.length,
                  action: entry.key == HealthIssueKind.oldIsbn
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton.tonal(
                              onPressed: () => _convertIsbns(entry.value),
                              child: const Text('Change all to ISBN-13'),
                            ),
                          ),
                        )
                      : null,
                  children: [
                    for (final book in entry.value.take(200))
                      _bookTile(
                        book,
                        detail: entry.key == HealthIssueKind.badIsbn ||
                                entry.key == HealthIssueKind.oldIsbn
                            ? 'ISBN ${book.isbn}'
                            : null,
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
