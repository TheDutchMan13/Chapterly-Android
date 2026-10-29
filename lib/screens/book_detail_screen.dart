import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/book_repository.dart';
import '../data/date_format.dart';
import '../models/book.dart';
import '../models/shelf.dart';
import '../widgets/book_cover.dart';

/// Shows one book. Change its shelf, rating, dates, pages and tags, or delete it.
class BookDetailScreen extends StatelessWidget {
  const BookDetailScreen({
    super.key,
    required this.repository,
    required this.bookId,
  });

  final BookRepository repository;
  final String bookId;

  Future<void> _editTags(BuildContext context, Book book) async {
    final controller = TextEditingController(text: book.tags.join(', '));
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit tags'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tags',
            helperText: 'Separate with commas',
          ),
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
    if (saved != true) return;
    await repository.setTags(book.id, parseTags(controller.text));
  }

  Future<void> _editPages(BuildContext context, Book book) async {
    final controller = TextEditingController(text: book.pages?.toString() ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Number of pages'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Pages',
            helperText: 'Leave empty to clear',
          ),
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
    if (saved != true) return;
    final pages = int.tryParse(controller.text.trim());
    await repository.setPages(book.id, pages != null && pages > 0 ? pages : null);
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

  Future<void> _confirmDelete(BuildContext context, Book book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete book?'),
        content: Text('"${book.title}" will be removed from your library.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await repository.remove(book.id);
    if (!context.mounted) return;
    Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repository,
      builder: (context, _) {
        final book = repository.byId(bookId);
        if (book == null) return const Scaffold(body: SizedBox.shrink());
        final textTheme = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Book'),
            actions: [
              IconButton(
                tooltip: 'Delete book',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(context, book),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: BookCover(
                  coverUrl: book.coverUrl,
                  width: 120,
                  height: 180,
                ),
              ),
              const SizedBox(height: 16),
              Text(book.title, style: textTheme.headlineSmall),
              const SizedBox(height: 4),
              if (book.author.isNotEmpty) Text(book.author),
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
                    for (final tag in book.tags) Chip(label: Text(tag)),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
