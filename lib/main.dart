import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';

import 'audio/android_audio_files.dart';
import 'audio/audio_bookmarks.dart';
import 'audio/audio_library.dart';
import 'audio/background_audio.dart';
import 'audio/listen_controller.dart';
import 'audio/listening.dart';
import 'data/app_settings.dart';
import 'data/auto_backup.dart';
import 'data/auto_series.dart';
import 'data/book_repository.dart';
import 'data/file_io.dart';
import 'data/google_books_fill.dart';
import 'data/open_library_client.dart';
import 'data/phone_sync.dart';
import 'data/pin_lock.dart';
import 'data/profile_files.dart';
import 'data/profiles.dart';
import 'data/sqlite_book_store.dart';
import 'data/sync_three_way.dart';
import 'data/theme_options.dart';
import 'ebook/android_ebook_files.dart';
import 'ebook/ebook_library.dart';
import 'ebook/ebook_reading.dart';
import 'home/home_bridge.dart';
import 'screens/home_shell.dart';
import 'screens/lock_gate.dart';
import 'screens/now_playing.dart';
import 'server/book_server.dart';
import 'server/library_sync.dart';
import 'server/server_downloads.dart';
import 'server/server_state.dart';
import 'server/server_sync.dart';

/// The profile Chapterly opened with. Its files are in [profileFolder].
String _profileId = mainProfileId;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before any PIN is asked for, so waits for wrong PINs hold even if the
  // clock is changed.
  await PinGuard.readDeviceUptime();
  // The open profile. Choosing another one restarts Chapterly with it.
  final profiles = await ProfileStore.load();
  final profile = profiles.active;
  _profileId = profile.id;
  ProfileSwitching.store = profiles;
  ProfileSwitching.switchRestarts = true;
  ProfileSwitching.removeFiles = removeProfileFiles;
  ProfileSwitching.switchTo = (id) async {
    await profiles.setActive(id);
    await _beforeRestart();
    await restartChapterly();
  };
  autoBackupSubfolder = profileBackupFolder(profile);
  try {
    autoBackupPrivateFolder =
        Directory('${(await profileFolder(profile.id)).path}/backups');
  } catch (_) {
    // The app's own backups folder is used.
  }
  final repository = BookRepository(
    await SqliteBookStore.open(fileName: profileDatabaseName(profile.id)),
  );
  await repository.load();
  final settings = await AppSettings.load(profiles.scope(profile.id));
  final phoneSync = PhoneSync(
    repository: repository,
    settings: settings,
    profileName: profiles.hasOthers ? profile.name : null,
  );
  await phoneSync.refresh();
  // Only listens for the PC while Chapterly is open on the screen.
  // The listener stays registered with the app for as long as it runs.
  AppLifecycleListener(
    onPause: () => unawaited(phoneSync.appPaused()),
    onResume: () => unawaited(phoneSync.appResumed()),
  );
  WidgetsBinding.instance.addObserver(
    AutoBackupObserver(repository: repository, settings: settings),
  );
  // Not awaited: the app opens while the backup is written.
  runAutoBackup(repository, settings);
  // Fills in series found in titles, now and as books are added.
  AutoSeries.start(repository, settings);
  // Google Books fills in missing covers, pages and tags (off until switched on).
  GoogleBooksFill.start(repository, settings);
  // Audiobook bookmarks live with the books, so they sync with the PC.
  AudioBookmarking.repository = repository;
  await _setUpListening(repository, settings);
  await _setUpReading(repository);
  await _setUpBookServer(repository, settings);
  // The home-screen widget and the daily reading reminder.
  unawaited(HomeBridge(
    repository: repository,
    settings: settings,
    controller: Listening.controller,
  ).start());
  runApp(
    ChapterlyApp(
      repository: repository,
      client: OpenLibraryClient(),
      settings: settings,
      phoneSync: phoneSync,
      fileIo: const FileIo(),
    ),
  );
}

class ChapterlyApp extends StatelessWidget {
  const ChapterlyApp({
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
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'Chapterly',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(settings, Brightness.light),
        darkTheme: buildTheme(settings, Brightness.dark),
        themeMode: settings.themeMode,
        navigatorKey: Listening.navigatorKey,
        builder: (context, child) => LockGate(
          settings: settings,
          child: NowPlayingFrame(
            repository: repository,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: HomeShell(
          repository: repository,
          client: client,
          settings: settings,
          phoneSync: phoneSync,
          fileIo: fileIo,
        ),
      ),
    );
  }
}

/// Saves your place on the book server and stops the player, before
/// Chapterly restarts with another profile.
Future<void> _beforeRestart() async {
  try {
    await BookServer.sync?.send().timeout(const Duration(seconds: 3));
  } catch (_) {
    // Sent next time this profile opens.
  }
  try {
    await Listening.controller?.close();
  } catch (_) {
    // Already stopped.
  }
}

/// The book server: browsing it, downloads, and keeping your place in its
/// books the same on every device. If it fails, the app opens without it.
Future<void> _setUpBookServer(
  BookRepository repository,
  AppSettings settings,
) async {
  try {
    final dir = await profileFolder(_profileId);
    final state = await ServerState.load(File('${dir.path}/book_server.json'));
    final sync = ServerSync(
      state: state,
      repository: repository,
      ebooks: EbookReading.library,
      isOpen: (bookId, kind) => kind == 'ebook'
          ? EbookReading.openBookId == bookId
          : Listening.controller?.bookId == bookId &&
              (Listening.controller?.playing ?? false),
      onAudioMoved: (bookId, progress) async {
        final controller = Listening.controller;
        if (controller == null || controller.bookId != bookId) return;
        // Loaded but paused: go to the new place.
        await controller.seekTo(
          progress.track,
          Duration(milliseconds: progress.trackMs),
        );
      },
    );
    final downloads = ServerDownloads(
      sync: sync,
      repository: repository,
      ebooks: EbookReading.library,
      booksDir: EbookReading.booksDir,
      audio: Listening.controller?.library,
      audioFiles: Listening.files,
      audioDir: Directory('${dir.path}/server_audio'),
    );
    BookServer.sync = sync;
    BookServer.downloads = downloads;
    BookServer.library = LibrarySync(
      sync: sync,
      repository: repository,
      settings: settings,
      base: await SyncBase.load(File('${dir.path}/book_server_library.json')),
    );
    sync.start();
    WidgetsBinding.instance.addObserver(_BookServerObserver(sync));
    unawaited(downloads.cleanUp());
    unawaited(_syncAndTell(sync));
  } catch (_) {
    // No book server this time.
  }
}

/// Syncs, and says so when a book moved on to a place saved elsewhere.
Future<void> _syncAndTell(ServerSync sync) async {
  final text = await BookServer.syncAll();
  if (text == null) return;
  // It may name a book: not shown over the lock screen, but once unlocked.
  await LockGate.whenUnlocked();
  final context = Listening.navigatorKey.currentContext;
  if (context == null || !context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
}

/// Syncs your places when Chapterly comes back to the front, and sends them
/// when it goes to the back.
class _BookServerObserver with WidgetsBindingObserver {
  _BookServerObserver(this.sync);

  final ServerSync sync;
  DateTime? _last;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(sync.send());
    } else if (state == AppLifecycleState.resumed) {
      final last = _last;
      final now = DateTime.now();
      if (last != null && now.difference(last) < const Duration(seconds: 30)) {
        return;
      }
      _last = now;
      unawaited(_syncAndTell(sync));
    }
  }
}

/// The reader: which book file belongs to which book on this phone, and
/// the folder with Chapterly's copies of the files. If it fails, the app
/// still opens without the reader.
Future<void> _setUpReading(BookRepository repository) async {
  try {
    final dir = await profileFolder(_profileId);
    EbookReading.library =
        await EbookLibrary.load(File('${dir.path}/ebook_library.json'));
    EbookReading.files = const AndroidEbookFiles();
    EbookReading.repository = repository;
    EbookReading.booksDir = Directory('${dir.path}/books');
  } catch (_) {
    // No reader this time.
  }
}

/// The audiobook player: which audio belongs to which book on this phone,
/// the player, and the notification that keeps it playing with the screen
/// off. If any of it fails, the app still opens without audio.
Future<void> _setUpListening(
  BookRepository repository,
  AppSettings settings,
) async {
  try {
    final dir = await profileFolder(_profileId);
    final library =
        await AudioLibrary.load(File('${dir.path}/audio_library.json'));
    const files = AndroidAudioFiles();
    AndroidAudioFiles.inUse = () async {
      final ids = [
        for (final p in ProfileSwitching.store?.profiles ?? const <Profile>[])
          p.id,
      ];
      if (!ids.contains(_profileId)) ids.add(_profileId);
      final used = <String>[];
      for (final id in ids) {
        final dir = await profileFolder(id);
        final other = id == _profileId
            ? library
            : await AudioLibrary.load(File('${dir.path}/audio_library.json'));
        used.addAll(other.locations);
      }
      return used;
    };
    final controller = ListenController(
      repository: repository,
      library: library,
      files: files,
    );
    controller.smartRewind = settings.smartRewind;
    controller.pausedAtFor = settings.listenPausedAt;
    controller.onPaused = settings.recordListenPause;
    settings.addListener(() => controller.smartRewind = settings.smartRewind);
    Listening.controller = controller;
    Listening.files = files;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    await AudioService.init(
      builder: () => ChapterlyAudioHandler(
        controller,
        hideTitles: () => settings.pinEnabled,
      ),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.chapterly.audio',
        androidNotificationChannelName: 'Audiobook',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (_) {
    // Without the notification the player still works while the app is
    // open.
  }
}
