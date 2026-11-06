import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/file_io.dart';
import '../data/open_library_client.dart';
import '../data/phone_sync.dart';
import '../data/profiles.dart';
import '../models/book.dart';
import '../server/book_server.dart';
import 'book_detail_screen.dart';
import 'duplicates_screen.dart';
import 'library_health_screen.dart';
import 'manage_shelves_screen.dart';
import 'next_up_screen.dart';
import 'notes_search_screen.dart';
import 'profiles_screen.dart';
import 'read_next_screen.dart';
import 'review_matches_screen.dart';
import 'server_screen.dart';
import 'series_screen.dart';
import 'settings_screen.dart';
import 'tags_screen.dart';
import 'trash_screen.dart';
import 'update_covers_screen.dart';
import 'wish_list_screen.dart';
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
    this.client,
  });

  /// Open Library, for updating covers. A new one is made when null.
  final OpenLibraryClient? client;

  final BookRepository repository;
  final AppSettings settings;
  final PhoneSync phoneSync;
  final FileIo fileIo;

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  void _openBook(BuildContext context, Book book) => _push(
        context,
        BookDetailScreen(
          repository: repository,
          settings: settings,
          fileIo: fileIo,
          bookId: book.id,
        ),
      );

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
          if (BookServer.sync case final sync?)
            if (BookServer.downloads case final downloads?)
              ListenableBuilder(
                listenable: sync.state,
                builder: (context, _) => ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('Book server'),
                  subtitle: Text(
                    sync.state.connected
                        ? 'Signed in as ${sync.state.name ?? 'you'}'
                        : 'Browse and download your own library',
                  ),
                  onTap: () => _push(
                    context,
                    ServerScreen(
                      repository: repository,
                      settings: settings,
                      fileIo: fileIo,
                      sync: sync,
                      downloads: downloads,
                    ),
                  ),
                ),
              ),
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
            leading: const Icon(Icons.library_books_outlined),
            title: const Text('Series'),
            subtitle: const Text('What you have, what is missing, what is next'),
            onTap: () => _push(
              context,
              SeriesScreen(
                repository: repository,
                onOpenBook: (book) => _openBook(context, book),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.sell_outlined),
            title: const Text('Tags'),
            subtitle: const Text('Rename, merge or delete tags'),
            onTap: () => _push(
              context,
              TagsScreen(repository: repository, settings: settings),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: const Text('Wish list'),
            subtitle: const Text('Books you want but do not have yet'),
            onTap: () => _push(
              context,
              WishListScreen(repository: repository, settings: settings),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.manage_search),
            title: const Text('Quotes and notes'),
            onTap: () => _push(
              context,
              NotesSearchScreen(
                repository: repository,
                onOpenBook: (book) => _openBook(context, book),
              ),
            ),
          ),
          heading('Tidy up'),
          ListTile(
            leading: const Icon(Icons.health_and_safety_outlined),
            title: const Text('Library health'),
            subtitle: const Text('ISBNs, missing details, stalled books'),
            onTap: () => _push(
              context,
              LibraryHealthScreen(
                repository: repository,
                settings: settings,
                onOpenBook: (book) => _openBook(context, book),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('Review matches'),
            subtitle: const Text('Books that may have the wrong details'),
            onTap: () =>
                _push(context, ReviewMatchesScreen(repository: repository)),
          ),
          ListTile(
            leading: const Icon(Icons.image_search_outlined),
            title: const Text('Update covers'),
            subtitle: const Text('Missing or broken Open Library covers'),
            onTap: () => _push(
              context,
              UpdateCoversScreen(
                repository: repository,
                client: client ?? OpenLibraryClient(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.content_copy_outlined),
            title: const Text('Find duplicates'),
            onTap: () => _push(
              context,
              DuplicatesScreen(repository: repository, settings: settings),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Trash'),
            onTap: () => _push(context, TrashScreen(repository: repository)),
          ),
          heading('App'),
          if (ProfileSwitching.store case final profiles?)
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Profiles'),
              subtitle: Text('Open now: ${profiles.active.name}'),
              onTap: () => _push(context, ProfilesScreen(store: profiles)),
            ),
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
