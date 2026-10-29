import 'package:flutter/material.dart';

import '../models/shelf.dart';

/// Returns a result map with title, author and shelf, or null if cancelled.
Future<Map<String, Object>?> showAddBookDialog(BuildContext context) {
  return showDialog<Map<String, Object>>(
    context: context,
    builder: (_) => const _AddBookDialog(),
  );
}

class _AddBookDialog extends StatefulWidget {
  const _AddBookDialog();

  @override
  State<_AddBookDialog> createState() => _AddBookDialogState();
}

class _AddBookDialogState extends State<_AddBookDialog> {
  final _title = TextEditingController();
  final _author = TextEditingController();
  Shelf _shelf = Shelf.forLater;

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop({
      'title': title,
      'author': _author.text.trim(),
      'shelf': _shelf,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add book'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          TextField(
            controller: _author,
            decoration: const InputDecoration(labelText: 'Author'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Shelf>(
            initialValue: _shelf,
            decoration: const InputDecoration(labelText: 'Shelf'),
            items: [
              for (final shelf in Shelf.values)
                DropdownMenuItem(value: shelf, child: Text(shelf.label)),
            ],
            onChanged: (value) => setState(() => _shelf = value ?? _shelf),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
