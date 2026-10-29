import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/backup.dart';
import '../data/book_repository.dart';
import '../data/csv.dart';
import '../data/date_format.dart';
import '../data/file_io.dart';
import '../data/phone_sync.dart';
import '../data/sync_server.dart';
import '../data/theme_options.dart';
import 'pin_dialogs.dart';

/// Accent colour and font, backup and restore, and CSV import and export.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repository,
    required this.settings,
    required this.phoneSync,
    required this.fileIo,
  });

  final BookRepository repository;
  final AppSettings settings;
  final PhoneSync phoneSync;
  final FileIo fileIo;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _setPin() async {
    final pin = await askNewPin(context);
    if (pin == null) return;
    widget.settings.setPin(pin);
  }

  Future<void> _changePin() async {
    if (!await confirmCurrentPin(context, widget.settings)) return;
    if (!mounted) return;
    await _setPin();
  }

  Future<void> _removePin() async {
    if (!await confirmCurrentPin(context, widget.settings)) return;
    widget.settings.clearPin();
  }

  Widget _lockSettings() {
    final settings = widget.settings;
    if (!settings.pinEnabled) {
      return ListTile(
        leading: const Icon(Icons.lock_outline),
        title: const Text('App lock'),
        subtitle: const Text('Ask for a PIN when Chapterly opens.'),
        onTap: _setPin,
      );
    }
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.lock),
          title: const Text('Change PIN'),
          onTap: _changePin,
        ),
        ListTile(
          leading: const Icon(Icons.lock_open),
          title: const Text('Turn off app lock'),
          onTap: _removePin,
        ),
        ListTile(
          title: const Text('Lock after'),
          trailing: DropdownButton<int>(
            value: settings.lockAfterSeconds,
            items: const [
              DropdownMenuItem(value: 0, child: Text('Immediately')),
              DropdownMenuItem(value: 30, child: Text('30 seconds')),
              DropdownMenuItem(value: 60, child: Text('1 minute')),
              DropdownMenuItem(value: 300, child: Text('5 minutes')),
            ],
            onChanged: (seconds) {
              if (seconds != null) settings.setLockAfterSeconds(seconds);
            },
          ),
        ),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('If you forget the PIN'),
          subtitle: Text(
            'The only way back in is clearing the app data, which erases '
            'your library. Keep a backup. PC sync still answers while the '
            'app is locked.',
          ),
        ),
      ],
    );
  }

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
        widget.settings.markBackedUp();
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
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('Phone'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Dark'),
                      ),
                    ],
                    selected: {widget.settings.themeMode},
                    onSelectionChanged: (choice) =>
                        widget.settings.setThemeMode(choice.first),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Pure black in dark mode'),
                  subtitle: const Text(
                    'True black instead of dark grey. Can save battery on '
                    'OLED screens.',
                  ),
                  value: widget.settings.pureBlack,
                  onChanged: widget.settings.setPureBlack,
                ),
                const SizedBox(height: 8),
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
          const _SectionHeader('Backup reminder'),
          ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) {
              final last = widget.settings.lastBackup;
              return Column(
                children: [
                  SwitchListTile(
                    title: const Text('Remind me to back up'),
                    subtitle: Text(
                      last == null
                          ? 'No backup made yet'
                          : 'Last backup: ${formatDate(last)}',
                    ),
                    value: widget.settings.backupReminder,
                    onChanged: widget.settings.setBackupReminder,
                  ),
                  if (widget.settings.backupReminder)
                    ListTile(
                      title: const Text('Remind me after'),
                      trailing: DropdownButton<int>(
                        value: widget.settings.backupDays,
                        items: const [
                          DropdownMenuItem(value: 14, child: Text('2 weeks')),
                          DropdownMenuItem(value: 30, child: Text('1 month')),
                          DropdownMenuItem(value: 60, child: Text('2 months')),
                          DropdownMenuItem(value: 90, child: Text('3 months')),
                        ],
                        onChanged: (days) {
                          if (days != null) widget.settings.setBackupDays(days);
                        },
                      ),
                    ),
                ],
              );
            },
          ),
          const _SectionHeader('Privacy'),
          ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) => _lockSettings(),
          ),
          const _SectionHeader('Sync with a PC'),
          ListenableBuilder(
            listenable: Listenable.merge([widget.settings, widget.phoneSync]),
            builder: (context, _) => _SyncSettings(
              settings: widget.settings,
              phoneSync: widget.phoneSync,
            ),
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

String _groupCode(String code) => [
      for (var i = 0; i < code.length; i += 4)
        code.substring(i, i + 4 > code.length ? code.length : i + 4),
    ].join('-');

class _SyncSettings extends StatelessWidget {
  const _SyncSettings({required this.settings, required this.phoneSync});

  final AppSettings settings;
  final PhoneSync phoneSync;

  String _lastSyncText() {
    final error = settings.lastSyncError;
    if (error != null) return 'Failed: $error';
    final at = settings.lastSyncAt;
    if (at == null) return 'Never';
    final changed = settings.lastSyncChanged;
    final what = changed == 0
        ? 'nothing changed'
        : '$changed ${changed == 1 ? 'book' : 'books'} changed';
    return '${formatDateTime(at)} · $what';
  }

  @override
  Widget build(BuildContext context) {
    final code = settings.syncCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('Allow sync from my PC'),
          subtitle: const Text(
            'Only while Chapterly is open, on your home Wi-Fi. Off by default.',
          ),
          value: settings.syncEnabled,
          onChanged: (value) async {
            settings.setSyncEnabled(value);
            await phoneSync.refresh();
          },
        ),
        if (settings.syncEnabled) ...[
          ListTile(
            leading: const Icon(Icons.wifi),
            title: const Text('Address'),
            subtitle: FutureBuilder<List<String>>(
              future: localAddresses(),
              builder: (context, snapshot) {
                final addresses = snapshot.data;
                if (addresses == null) return const Text('Looking up...');
                if (addresses.isEmpty) {
                  return const Text('No Wi-Fi connection found.');
                }
                return Text(
                  [for (final a in addresses) '$a:${phoneSync.port}'].join('\n'),
                );
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: const Text('Pairing code'),
            subtitle: Text(code == null ? 'Not set' : _groupCode(code)),
            trailing: TextButton(
              onPressed: () async {
                settings.setSyncCode(newSyncCode());
                await phoneSync.refresh();
              },
              child: const Text('New code'),
            ),
          ),
          ListTile(
            leading: Icon(
              phoneSync.running
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
            ),
            title: Text(phoneSync.running ? 'Ready for your PC' : 'Not running'),
            subtitle: phoneSync.error == null ? null : Text(phoneSync.error!),
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Last sync'),
            subtitle: Text(_lastSyncText()),
          ),
        ],
      ],
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
