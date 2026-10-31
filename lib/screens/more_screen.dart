import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/file_io.dart';
import '../data/phone_sync.dart';
import 'duplicates_screen.dart';
import 'manage_shelves_screen.dart';
import 'next_up_screen.dart';
import 'read_next_screen.dart';
import 'settings_screen.dart';
import 'trash_screen.dart';
import 'whats_new_screen.dart';

/// "5 min ago" and the like.
String _syncedAgo(DateTime? at, DateTime now) {
  if (at == null) return 'not synced yet';
  final gap = now.difference(at);
  if (gap.inMinutes < 1) return 'synced just now';
  if (gap.inMinutes < 60) return 'synced ${gap.inMinutes} min ago';
  if (gap.inHours < 24) {
    return 'synced ${gap.inHours} ${gap.inHours == 1 ? 'hour' : 'hours'} ago';
  }
  final days = gap.inDays;
  return days == 1 ? 'synced yesterday' : 'synced $days days ago';
}

/// The third page of the bottom bar: everything that used to be in the
/// library's menu, and how syncing with the PC is going.
class MoreScreen extends StatelessWidget {
  const MoreScreen({
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

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  void _openSettings(BuildContext context) => _push(
        context,
        SettingsScreen(
          repository: repository,
          settings: settings,
          phoneSync: phoneSync,
          fileIo: fileIo,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(
            text,
            style: textTheme.titleSmall?.copyWith(color: scheme.primary),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _SyncStatusCard(
              settings: settings,
              phoneSync: phoneSync,
              onTap: () => _openSettings(context),
            ),
          ),
          heading('Your books'),
          ListTile(
            leading: const Icon(Icons.format_list_numbered),
            title: const Text('Next up'),
            subtitle: const Text('The order you want to read in'),
            onTap: () => _push(
              context,
              NextUpScreen(
                repository: repository,
                settings: settings,
                fileIo: fileIo,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.lightbulb_outline),
            title: const Text('Read next'),
            subtitle: const Text('Ideas from your For later shelf'),
            onTap: () => _push(
              context,
              ReadNextScreen(
                repository: repository,
                settings: settings,
                fileIo: fileIo,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.collections_bookmark_outlined),
            title: const Text('Your shelves'),
            onTap: () => _push(
              context,
              ManageShelvesScreen(repository: repository, settings: settings),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.content_copy_outlined),
            title: const Text('Find duplicates'),
            onTap: () =>
                _push(context, DuplicatesScreen(repository: repository)),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Trash'),
            onTap: () => _push(context, TrashScreen(repository: repository)),
          ),
          heading('App'),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            onTap: () => _openSettings(context),
          ),
          ListTile(
            leading: const Icon(Icons.new_releases_outlined),
            title: const Text("What's new"),
            onTap: () => _push(context, const WhatsNewScreen()),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// The one place on the phone that shows how syncing with the PC is going.
class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard({
    required this.settings,
    required this.phoneSync,
    required this.onTap,
  });

  final AppSettings settings;
  final PhoneSync phoneSync;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([settings, phoneSync]),
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final IconData icon;
        final String text;
        Color? colour;
        final error = phoneSync.error ?? settings.lastSyncError;
        if (!settings.syncEnabled) {
          icon = Icons.sync_disabled;
          text = 'Off. Tap to set it up.';
        } else if (error != null) {
          icon = Icons.sync_problem;
          colour = scheme.error;
          text = error;
        } else if (phoneSync.running) {
          icon = Icons.sync;
          colour = scheme.primary;
          text = 'Ready for your PC, '
              '${_syncedAgo(settings.lastSyncAt, DateTime.now())}';
        } else {
          icon = Icons.sync_problem;
          colour = scheme.error;
          text = 'Not running';
        }
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(icon, color: colour),
            title: const Text('Sync with your PC'),
            subtitle: Text(text),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        );
      },
    );
  }
}
