import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_info.dart';
import '../data/app_settings.dart';
import '../data/auto_backup.dart';
import '../data/backup.dart';
import '../data/book_repository.dart';
import '../data/csv.dart';
import '../data/date_format.dart';
import '../data/file_io.dart';
import '../data/goodreads_export.dart';
import '../data/kindle_clippings.dart';
import '../data/phone_sync.dart';
import '../data/profiles.dart';
import '../data/sync_server.dart';
import '../data/theme_options.dart';
import '../home/home_bridge.dart';
import '../models/book_format.dart';
import '../models/shelf.dart';
import 'pair_scan_screen.dart';
import 'pin_dialogs.dart';
import 'profiles_screen.dart';
import 'reminder_settings.dart';
import 'settings_search.dart';
import 'shelf_order_screen.dart';
import 'whats_new_screen.dart';

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
  final _search = SettingsSearch();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _editDefaultTags() async {
    final controller = TextEditingController(
      text: widget.settings.defaultTags.join(', '),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tags for new books'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tags',
            helperText: 'Separate with commas. Leave empty for none.',
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
    final text = controller.text;
    controller.dispose();
    if (saved != true) return;
    widget.settings.setDefaultTags(parseTags(text));
  }

  void _openShelfOrder() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ShelfOrderScreen(settings: widget.settings),
      ),
    );
  }

  void _openChangelog() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const WhatsNewScreen()),
    );
  }

  Future<void> _openSource() async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await launchUrl(
      Uri.parse(sourceCodeUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the link.')),
      );
    }
  }

  void _openLicence() {
    showLicensePage(
      context: context,
      applicationName: appName,
      applicationVersion: appVersion,
      applicationLegalese: '$licenceName. Full text: $licenceUrl',
    );
  }

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
        subtitle: const Text('Ask for a PIN when this profile opens.'),
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
        SwitchListTile(
          secondary: const Icon(Icons.visibility_off_outlined),
          title: const Text('Hide in recent apps and screenshots'),
          subtitle: const Text(
            'Chapterly shows blank in the list of recent apps, and '
            'screenshots of it come out black.',
          ),
          value: settings.hideScreen,
          onChanged: settings.setHideScreen,
        ),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('If you forget the PIN'),
          subtitle: Text(
            'The only way back in is clearing the app data, which erases '
            'your library. Keep a backup. PC sync answers while Chapterly '
            'is open on the screen, locked or not. Each profile has its '
            'own PIN.',
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
          content: encodeBackup(
            await widget.repository.withPictures(widget.repository.allBooks),
          ),
          mimeType: 'application/json',
          subject: 'Chapterly backup',
        );
        widget.settings.markBackedUp();
      });

  Future<void> _backUpNow() => _run(() async {
        await runAutoBackup(widget.repository, widget.settings, force: true);
        if (!mounted) return;
        final error = widget.settings.lastAutoBackupError;
        _say(error == null ? 'Backup saved.' : 'Backup failed: $error');
      });

  String _autoBackupText() {
    final settings = widget.settings;
    final error = settings.lastAutoBackupError;
    if (error != null) return 'Last try failed: $error';
    final at = settings.lastAutoBackupAt;
    if (at == null) return 'None yet';
    final path = settings.lastAutoBackupPath;
    return path == null
        ? formatDateTime(at)
        : '${formatDateTime(at)}\n$path';
  }

  Future<void> _restoreBackup() => _run(() async {
        final text = await widget.fileIo.pickTextFile();
        if (text == null) return;
        final books = decodeBackup(text);
        if (!mounted) return;
        final confirmed = await _confirm(
          title: 'Restore backup?',
          message: 'This replaces your ${widget.repository.books.length} '
              'current books with the ${books.length} books in the backup. '
              'Books that are not in the backup are removed, also from your '
              'PC and the book server when they next sync.',
          action: 'Restore',
        );
        if (!confirmed || !mounted) return;
        await widget.repository.restoreBackup(books);
        if (mounted) _say('Restored ${books.length} books.');
      });

  Future<void> _exportCsv() => _run(() async {
        await widget.fileIo.shareText(
          fileName: 'chapterly-books-${formatDate(DateTime.now())}.csv',
          content: encodeBooksCsv(
            await widget.repository.withPictures(widget.repository.books),
          ),
          mimeType: 'text/csv',
          subject: 'Chapterly books',
        );
      });

  Future<void> _exportGoodreads() => _run(() async {
        await widget.fileIo.shareText(
          fileName: 'chapterly-goodreads-${formatDate(DateTime.now())}.csv',
          content: encodeGoodreadsCsv(widget.repository.books),
          mimeType: 'text/csv',
          subject: 'Chapterly books for Goodreads or StoryGraph',
        );
      });

  Future<void> _editHardcoverToken() async {
    final controller =
        TextEditingController(text: widget.settings.hardcoverToken ?? '');
    final token = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hardcover token'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Make a free account at hardcover.app, open Settings, then API, '
              'and copy the token. Keep it private. Chapterly uses it only to '
              'look up series. Leave it empty to stop using Hardcover.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Token',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (token != null) widget.settings.setHardcoverToken(token);
  }

  Future<void> _editGoogleKey() async {
    final controller =
        TextEditingController(text: widget.settings.googleBooksKey ?? '');
    final key = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Google Books key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste a free API key from console.cloud.google.com (turn on '
              'the Books API, then create an API key). Keep it private. '
              'Leave it empty to ask without a key.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API key',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (key != null) widget.settings.setGoogleBooksKey(key);
  }

  Future<void> _importCsv() => _run(() async {
        final text = await widget.fileIo.pickTextFile();
        if (text == null) return;
        final result = importBooksFromCsv(text);
        if (result.books.isEmpty) {
          throw const FormatException('No books found in that file.');
        }
        final fresh = widget.repository.newBookCount(result.books);
        final updates = widget.repository.seriesUpdates(result.books);
        var updateSeries = updates.isNotEmpty;
        if (!mounted) return;
        final go = await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) {
              final canGo = fresh > 0 || (updateSeries && updates.isNotEmpty);
              return AlertDialog(
                title: const Text('Import books?'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        '${result.books.length} ${result.books.length == 1 ? 'book' : 'books'} found: '
                            '$fresh new, ${result.books.length - fresh} already in your library.',
                        if (result.skipped > 0)
                          '${result.skipped} ${result.skipped == 1 ? 'row is' : 'rows are'} '
                              'not a book and will be skipped.',
                        'Shelves become Finished, Reading and Want to read. Ratings, '
                            'dates and tags are kept.',
                      ].join('\n\n'),
                    ),
                    if (updates.isNotEmpty)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: updateSeries,
                        onChanged: (value) =>
                            setDialogState(() => updateSeries = value ?? false),
                        title: Text(
                          'Update the series of ${updates.length} '
                          '${updates.length == 1 ? 'book' : 'books'} '
                          'already in your library',
                        ),
                        subtitle: const Text(
                          'Uses the series name and number from this file. '
                          'Nothing else about those books changes.',
                        ),
                      ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: canGo ? () => Navigator.of(context).pop(true) : null,
                    child: Text(fresh > 0
                        ? 'Import $fresh ${fresh == 1 ? 'book' : 'books'}'
                        : 'Update series'),
                  ),
                ],
              );
            },
          ),
        );
        if (go != true) return;
        final added =
            fresh > 0 ? await widget.repository.importBooks(result.books) : 0;
        final changed = updateSeries ? updates.length : 0;
        if (changed > 0) await widget.repository.setSeriesFor(updates);
        final duplicates = result.books.length - added;
        if (!mounted) return;
        final parts = ['Imported $added book${added == 1 ? '' : 's'}'];
        if (changed > 0) {
          parts.add('updated the series of $changed '
              'book${changed == 1 ? '' : 's'}');
        } else if (duplicates > 0) {
          parts.add('$duplicates already in your library');
        }
        if (result.skipped > 0) parts.add('${result.skipped} skipped');
        _say('${parts.join(', ')}.');
      });

  Future<void> _importKindle() => _run(() async {
        final text = await widget.fileIo.pickTextFile();
        if (text == null) return;
        final clippings = parseKindleClippings(text);
        if (clippings.isEmpty) {
          throw const FormatException(
            'No highlights found. Pick the My Clippings.txt file from your '
            'Kindle.',
          );
        }
        final match = matchClippings(widget.repository.books, clippings);
        await widget.repository.addQuotesToBooks(match.quotesByBook);
        if (!mounted) return;
        final added = match.added;
        final lines = <String>[
          'Added $added ${added == 1 ? 'quote' : 'quotes'} to '
              '${match.quotesByBook.length} '
              '${match.quotesByBook.length == 1 ? 'book' : 'books'}.',
          if (match.alreadySaved > 0)
            '${match.alreadySaved} ${match.alreadySaved == 1 ? 'was' : 'were'}'
                ' already saved.',
        ];
        final missing = match.unmatchedTitles;
        if (missing.isNotEmpty) {
          lines.add('');
          lines.add('No book in your library matches:');
          for (final title in missing.take(15)) {
            lines.add('• $title');
          }
          if (missing.length > 15) lines.add('and ${missing.length - 15} more');
          lines.add('');
          lines.add('Add those books, then import again. Highlights you '
              'already have are not added twice.');
        }
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Kindle highlights'),
            content: SingleChildScrollView(child: Text(lines.join('\n'))),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      });

  Widget _profileTile(ProfileStore store) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final active = store.active;
          return ListTile(
            leading: ProfileAvatar(profile: active),
            title: Text(active.name),
            subtitle: Text(
              store.hasOthers
                  ? 'Profile. Open another profile, or add, rename or '
                      'delete one'
                  : 'Profile. Add a profile for someone else who reads '
                      'here',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ProfilesScreen(store: store),
              ),
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final profiles = ProfileSwitching.store;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SettingsSearchScope(
        search: _search,
        // Every section is built, not only those on screen, so the search
        // can read them all.
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          SettingsSearchField(search: _search),
          const SettingsNoMatch(),
          if (_busy) const LinearProgressIndicator(),
          if (profiles != null) _profileTile(profiles),
          SettingsSearchable(
            title: 'Appearance',
            builder: (context, searching) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeader('Appearance'),
          ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SegmentedButton<AppLook>(
                    segments: const [
                      ButtonSegment(
                        value: AppLook.midnight,
                        label: Text('Midnight'),
                      ),
                      ButtonSegment(
                        value: AppLook.classic,
                        label: Text('Classic'),
                      ),
                    ],
                    selected: {widget.settings.look},
                    onSelectionChanged: (choice) =>
                        widget.settings.setLook(choice.first),
                  ),
                ),
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
                  subtitle: Text(
                    widget.settings.look == AppLook.midnight
                        ? 'True black instead of navy. Can save battery on '
                            'OLED screens.'
                        : 'True black instead of dark grey. Can save battery '
                            'on OLED screens.',
                  ),
                  value: widget.settings.pureBlack,
                  onChanged: widget.settings.setPureBlack,
                ),
                if (widget.settings.look == AppLook.classic)
                SwitchListTile(
                  title: const Text('Paper look in light mode'),
                  subtitle: const Text(
                    'A warm, cream page colour instead of white.',
                  ),
                  value: widget.settings.paperLight,
                  onChanged: widget.settings.setPaperLight,
                ),
                SwitchListTile(
                  title: const Text('Continue reading card'),
                  subtitle: const Text(
                    'The book you are reading, at the top of the library.',
                  ),
                  value: widget.settings.continueCard,
                  onChanged: widget.settings.setContinueCard,
                ),
                if (widget.settings.look == AppLook.classic) ...[
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
                      _CustomAccentDot(
                        current: Color(widget.settings.accent),
                        selected: !accentChoices.any(
                          (choice) =>
                              choice.color.toARGB32() ==
                              widget.settings.accent,
                        ),
                        onPick: (colour) =>
                            widget.settings.setAccent(colour.toARGB32()),
                      ),
                    ],
                  ),
                ),
                ],
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
              ],
            ),
          ),
          SettingsSearchable(
            title: 'Adding books',
            builder: (context, searching) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeader('Adding books'),
          ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) => Column(
              children: [
                ListTile(
                  title: const Text('Put new books on'),
                  trailing: DropdownButton<Shelf?>(
                    value: widget.settings.defaultShelf,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Ask every time'),
                      ),
                      for (final shelf in Shelf.values)
                        DropdownMenuItem(
                          value: shelf,
                          child: Text(shelf.label),
                        ),
                    ],
                    onChanged: widget.settings.setDefaultShelf,
                  ),
                ),
                ListTile(
                  title: const Text('Format of new books'),
                  trailing: DropdownButton<BookFormat?>(
                    value: widget.settings.defaultFormat,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Not set'),
                      ),
                      for (final format in BookFormat.values)
                        DropdownMenuItem(
                          value: format,
                          child: Text(format.label),
                        ),
                    ],
                    onChanged: widget.settings.setDefaultFormat,
                  ),
                ),
                SwitchListTile(
                  title: const Text('Find series automatically'),
                  subtitle: const Text(
                    'Fills in the series and number of books that have them in the '
                    'title, like "Mistborn, Book 2". Series you set are never changed.',
                  ),
                  value: widget.settings.autoSeries,
                  onChanged: widget.settings.setAutoSeries,
                ),
                SwitchListTile(
                  title: const Text('Use Google Books'),
                  subtitle: const Text(
                    'Fills in a missing cover, pages, ISBN, year and tags, in the '
                    'background. It sends each title and author to Google. Without a '
                    'key Google allows only a few books a day.',
                  ),
                  value: widget.settings.useGoogleBooks,
                  onChanged: widget.settings.setUseGoogleBooks,
                ),
                ListTile(
                  title: const Text('Google Books key (optional)'),
                  subtitle: Text(
                    widget.settings.googleBooksKey == null
                        ? 'Not set. A free key from Google allows many more books a day.'
                        : 'Set',
                  ),
                  onTap: _editGoogleKey,
                ),
                ListTile(
                  title: const Text('Hardcover token (optional)'),
                  subtitle: Text(
                    widget.settings.hardcoverToken == null
                        ? 'Not set. A free Hardcover account finds series for '
                            'Fix library and the Series screen.'
                        : 'Set',
                  ),
                  onTap: _editHardcoverToken,
                ),
                ListTile(
                  title: const Text('Tags for new books'),
                  subtitle: Text(
                    widget.settings.defaultTags.isEmpty
                        ? 'None'
                        : widget.settings.defaultTags.join(', '),
                  ),
                  onTap: _editDefaultTags,
                ),
              ],
            ),
          ),
              ],
            ),
          ),
          SettingsSearchable(
            title: 'Library',
            builder: (context, searching) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeader('Library'),
          ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) => Column(
              children: [
                SwitchListTile(
                  title: const Text("Show this year's goal on the Library"),
                  subtitle: const Text(
                    'A progress bar above the filters, when you have set a '
                    'reading goal in Statistics',
                  ),
                  value: widget.settings.goalOnLibrary,
                  onChanged: widget.settings.setGoalOnLibrary,
                ),
                ReminderSettings(
                  settings: widget.settings,
                  where: 'as a notification',
                  askPermission: HomeBridge.askNotifications,
                ),
                SwitchListTile(
                  title: const Text('Quote of the day on the Library'),
                  subtitle: const Text(
                    'One of your quotes or highlights each day, the one you '
                    'have not seen for longest first',
                  ),
                  value: widget.settings.quoteOnLibrary,
                  onChanged: widget.settings.setQuoteOnLibrary,
                ),
                SwitchListTile(
                  title: const Text('Rewind a little after a pause'),
                  subtitle: const Text(
                    'When you play an audiobook again, go back a few seconds: '
                    '2 after a short pause, up to 30 after a day.',
                  ),
                  value: widget.settings.smartRewind,
                  onChanged: widget.settings.setSmartRewind,
                ),
                SwitchListTile(
                  title: const Text('Show ratings as numbers'),
                  subtitle: const Text('4/5 instead of stars'),
                  value: widget.settings.ratingAsNumber,
                  onChanged: widget.settings.setRatingAsNumber,
                ),
                SwitchListTile(
                  title: const Text('Show format on book cards'),
                  value: widget.settings.showFormatOnCards,
                  onChanged: widget.settings.setShowFormatOnCards,
                ),
                SwitchListTile(
                  title: const Text('Show tags on book cards'),
                  value: widget.settings.showTagsOnCards,
                  onChanged: widget.settings.setShowTagsOnCards,
                ),
                ListTile(
                  title: const Text('Order of shelf tabs'),
                  subtitle: Text(
                    [for (final s in widget.settings.shelfOrder) s.label]
                        .join(' · '),
                  ),
                  onTap: _openShelfOrder,
                ),
              ],
            ),
          ),
              ],
            ),
          ),
          SettingsSearchable(
            title: 'Backup',
            builder: (context, searching) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
              ],
            ),
          ),
          SettingsSearchable(
            title: 'Automatic backups',
            builder: (context, searching) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeader('Automatic backups'),
          ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) => Column(
              children: [
                SwitchListTile(
                  title: const Text('Back up by itself'),
                  subtitle: Text(
                    widget.settings.pinEnabled
                        ? 'Saves a backup when you open the app, and keeps '
                            'the last $autoBackupKeep. With the app lock on, '
                            'they are kept inside Chapterly where other apps '
                            'and profiles can\'t open them, so they are gone '
                            'if the app is uninstalled. Use Export backup to '
                            'keep a copy elsewhere.'
                        : 'Saves a backup file in Documents/Chapterly when you '
                            'open the app, and keeps the last $autoBackupKeep. '
                            'That folder stays when the app is uninstalled.',
                  ),
                  value: widget.settings.autoBackup,
                  onChanged: widget.settings.setAutoBackup,
                ),
                if (widget.settings.autoBackup) ...[
                  ListTile(
                    title: const Text('How often'),
                    trailing: DropdownButton<int>(
                      value: widget.settings.autoBackupDays,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('Every day')),
                        DropdownMenuItem(value: 7, child: Text('Every week')),
                        DropdownMenuItem(value: 30, child: Text('Every month')),
                      ],
                      onChanged: (days) {
                        if (days != null) widget.settings.setAutoBackupDays(days);
                      },
                    ),
                  ),
                  ListTile(
                    title: const Text('Last automatic backup'),
                    subtitle: Text(_autoBackupText()),
                    trailing: TextButton(
                      onPressed: _backUpNow,
                      child: const Text('Back up now'),
                    ),
                  ),
                ],
              ],
            ),
          ),
              ],
            ),
          ),
          SettingsSearchable(
            title: 'Backup reminder',
            builder: (context, searching) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
              ],
            ),
          ),
          SettingsSearchable(
            title: 'Privacy',
            builder: (context, searching) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeader('Privacy'),
          ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) => _lockSettings(),
          ),
              ],
            ),
          ),
          SettingsSearchable(
            title: 'Sync with a PC',
            builder: (context, searching) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeader('Sync with a PC'),
          ListenableBuilder(
            listenable: Listenable.merge([widget.settings, widget.phoneSync]),
            builder: (context, _) => _SyncSettings(
              settings: widget.settings,
              phoneSync: widget.phoneSync,
            ),
          ),
              ],
            ),
          ),
          SettingsSearchable(
            title: 'Spreadsheet (CSV)',
            builder: (context, searching) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeader('Spreadsheet (CSV)'),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Export as CSV'),
            subtitle: const Text('Open your books in a spreadsheet app.'),
            onTap: _exportCsv,
          ),
          ListTile(
            leading: const Icon(Icons.ios_share_outlined),
            title: const Text('Export for Goodreads or StoryGraph'),
            subtitle: const Text(
              'A CSV in Goodreads\' format. Import it on Goodreads, or on '
              'StoryGraph under Import Goodreads library. Your notes go in '
              'Private Notes, not a public review.',
            ),
            onTap: _exportGoodreads,
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Import from CSV'),
            subtitle: const Text(
              'Add books from a Goodreads, StoryGraph or Libib export, or a '
              'Chapterly CSV. Books you already have are skipped.',
            ),
            onTap: _importCsv,
          ),
              ],
            ),
          ),
          SettingsSearchable(
            title: 'Kindle',
            builder: (context, searching) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeader('Kindle'),
          ListTile(
            leading: const Icon(Icons.format_quote_outlined),
            title: const Text('Import Kindle highlights'),
            subtitle: const Text(
              'Pick the My Clippings.txt file from your Kindle (copy it to '
              'your phone first). Highlights become quotes on books you '
              'already have.',
            ),
            onTap: _importKindle,
          ),
              ],
            ),
          ),
          SettingsSearchable(
            title: 'About',
            builder: (context, searching) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Your library stays on this phone'),
            subtitle: Text(
              'Chapterly has no account, ads or tracking. The only internet '
              'use is searching Open Library and loading cover images.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.rocket_launch_outlined),
            title: Text('Version'),
            subtitle: Text(appVersion),
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('Changelog'),
            subtitle: const Text("See what's new in Chapterly"),
            onTap: _openChangelog,
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Source code'),
            subtitle: const Text('See on GitHub'),
            onTap: _openSource,
          ),
          ListTile(
            leading: const Icon(Icons.copyright_outlined),
            title: const Text('Licence'),
            subtitle: const Text(licenceName),
            onTap: _openLicence,
          ),
              ],
            ),
          ),
            ],
          ),
        ),
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

class _CustomAccentDot extends StatelessWidget {
  const _CustomAccentDot({
    required this.current,
    required this.selected,
    required this.onPick,
  });

  final Color current;
  final bool selected;
  final ValueChanged<Color> onPick;

  Future<void> _open(BuildContext context) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => _ColourDialog(initial: current),
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Custom colour',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _open(context),
        child: CircleAvatar(
          radius: 20,
          backgroundColor: selected ? current : scheme.surfaceContainerHighest,
          child: Icon(
            selected ? Icons.check : Icons.palette_outlined,
            color: selected ? Colors.white : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ColourDialog extends StatefulWidget {
  const _ColourDialog({required this.initial});

  final Color initial;

  @override
  State<_ColourDialog> createState() => _ColourDialogState();
}

class _ColourDialogState extends State<_ColourDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required HSVColor Function(double) change,
  }) {
    final shown = value < min ? min : (value > max ? max : value);
    return Row(
      children: [
        SizedBox(width: 88, child: Text(label)),
        Expanded(
          child: Slider(
            value: shown,
            min: min,
            max: max,
            onChanged: (next) => setState(() => _hsv = change(next)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colour = _hsv.toColor();
    return AlertDialog(
      title: const Text('Custom colour'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: colour,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 12),
            _slider(
              label: 'Colour',
              value: _hsv.hue,
              min: 0,
              max: 360,
              change: (v) => _hsv.withHue(v),
            ),
            _slider(
              label: 'Strength',
              value: _hsv.saturation,
              min: 0,
              max: 1,
              change: (v) => _hsv.withSaturation(v),
            ),
            _slider(
              label: 'Brightness',
              value: _hsv.value,
              min: 0.25,
              max: 1,
              change: (v) => _hsv.withValue(v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(colour),
          child: const Text('Use this colour'),
        ),
      ],
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

  Future<void> _scanFromPc(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const PairScanScreen()),
    );
    if (code == null) return;
    final wasOff = !settings.syncEnabled;
    // Listening has to be on for the PC to find this phone.
    if (wasOff) settings.setSyncEnabled(true);
    settings.setSyncCode(code);
    // Restarts the server, which derives its key from the new code.
    await phoneSync.refresh();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${wasOff ? 'Sync was turned on. ' : ''}Code set. Your PC will '
            'find this phone in a few seconds \u2014 keep Chapterly open.',
          ),
        ),
      );
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
        ListTile(
          leading: const Icon(Icons.qr_code_scanner),
          title: const Text('Scan code from your PC'),
          subtitle: const Text(
            'Point the camera at the code on your PC to pair.',
          ),
          onTap: () => _scanFromPc(context),
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
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final a in addresses)
                      _CopyLine(
                        text: '$a:${phoneSync.port}',
                        copied: 'Address copied',
                      ),
                  ],
                );
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: const Text('Pairing code'),
            subtitle: code == null
                ? const Text('Not set')
                : _CopyLine(
                    text: _groupCode(code),
                    // Copied without dashes: what the PC accepts and a
                    // password manager can keep as it is.
                    copyText: code,
                    copied: 'Pairing code copied',
                  ),
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
          const ListTile(
            leading: Icon(Icons.people_outline),
            title: Text('Every profile syncs'),
            subtitle: Text(
              'One pairing covers all your profiles. A profile missing on '
              'one side is added there, matched by name. A profile with a '
              'PIN syncs only while it is open on this phone.',
            ),
          ),
        ],
      ],
    );
  }
}

/// A line of text you can tap to copy, for the address and pairing code (to
/// paste into the PC app or keep in a password manager).
class _CopyLine extends StatelessWidget {
  const _CopyLine({required this.text, required this.copied, this.copyText});

  final String text;
  final String? copyText;
  final String copied;

  @override
  Widget build(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    return Tooltip(
      message: 'Copy',
      child: InkWell(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: copyText ?? text));
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(copied)));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(text)),
              const SizedBox(width: 8),
              const Icon(Icons.copy, size: 16),
            ],
          ),
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
