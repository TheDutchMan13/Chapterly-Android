import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/backup.dart';
import '../data/book_repository.dart';
import '../data/csv.dart';
import '../data/date_format.dart';
import '../data/file_io.dart';
import '../data/theme_options.dart';

/// Accent colour and font, backup and restore, and CSV import and export.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repository,
    required this.settings,
    required this.fileIo,
  });

  final BookRepository repository;
  final AppSettings settings;
  final FileIo fileIo;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Runs [action], shows a message if it fails, and blocks double taps.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on FormatException catch (error) {
      if (mounted) _say(error.message);
    } catch (_) {
      if (mounted) _say('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _exportBackup() => _run(() async {
        await widget.fileIo.shareText(
          fileName: 'chapterly-backup-${formatDate(DateTime.now())}.json',
          content: encodeBackup(widget.repository.allBooks),
          mimeType: 'application/json',
          subject: 'Chapterly backup',
        );
      });

  Future<void> _restoreBackup() => _run(() async {
        final text = await widget.fileIo.pickTextFile();
        if (text == null) return;
        final books = decodeBackup(text);
        if (!mounted) return;
        final confirmed = await _confirm(
          title: 'Restore backup?',
          message: 'This replaces your ${widget.repository.books.length} '
              'current books with the ${books.length} books in the backup.',
          action: 'Restore',
        );
        if (!confirmed || !mounted) return;
        await widget.repository.replaceAll(books);
        if (mounted) _say('Restored ${books.length} books.');
      });

  Future<void> _exportCsv() => _run(() async {
        await widget.fileIo.shareText(
          fileName: 'chapterly-books-${formatDate(DateTime.now())}.csv',
          content: encodeBooksCsv(widget.repository.books),
          mimeType: 'text/csv',
          subject: 'Chapterly books',
        );
      });

  Future<void> _importCsv() => _run(() async {
        final text = await widget.fileIo.pickTextFile();
        if (text == null) return;
        final result = importBooksFromCsv(text);
        final added = await widget.repository.importBooks(result.books);
        final duplicates = result.books.length - added;
        if (!mounted) return;
        final parts = ['Imported $added book${added == 1 ? '' : 's'}'];
        if (duplicates > 0) parts.add('$duplicates already in your library');
        if (result.skipped > 0) parts.add('${result.skipped} skipped');
        _say('${parts.join(', ')}.');
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          if (_busy) const LinearProgressIndicator(),
          const _SectionHeader('Appearance'),
          ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final choice in accentChoices)
                        _AccentDot(
                          choice: choice,
                          selected:
                              choice.color.toARGB32() == widget.settings.accent,
                          onTap: () => widget.settings
                              .setAccent(choice.color.toARGB32()),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: widget.settings.fontFamily ?? '',
                  onChanged: (value) => widget.settings.setFontFamily(
                    value == null || value.isEmpty ? null : value,
                  ),
                  child: Column(
                    children: [
                      for (final font in fontChoices)
                        RadioListTile<String>(
                          value: font.family ?? '',
                          title: Text(
                            font.label,
                            style: TextStyle(fontFamily: font.family),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const _SectionHeader('Backup'),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Export backup'),
            subtitle: const Text(
              'Save your whole library as a file. Send it to Drive, email '
              'or Files to keep it safe.',
            ),
            onTap: _exportBackup,
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restore backup'),
            subtitle: const Text(
              'Replace your library with a backup file made by Chapterly.',
            ),
            onTap: _restoreBackup,
          ),
          const _SectionHeader('Spreadsheet (CSV)'),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Export as CSV'),
            subtitle: const Text('Open your books in a spreadsheet app.'),
            onTap: _exportCsv,
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Import from CSV'),
            subtitle: const Text(
              'Add books from a Goodreads export or a Chapterly CSV. '
              'Books you already have are skipped.',
            ),
            onTap: _importCsv,
          ),
          const _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Your library stays on this phone'),
            subtitle: Text(
              'Chapterly has no account, ads or tracking. The only internet '
              'use is searching Open Library and loading cover images.',
            ),
          ),
        ],
      ),
    );
  }
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final AccentChoice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: choice.name,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: CircleAvatar(
          backgroundColor: choice.color,
          radius: 20,
          child: selected
              ? const Icon(Icons.check, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
