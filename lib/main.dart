import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'audio/android_audio_files.dart';
import 'audio/audio_library.dart';
import 'audio/background_audio.dart';
import 'audio/listen_controller.dart';
import 'audio/listening.dart';
import 'data/app_settings.dart';
import 'data/auto_backup.dart';
import 'data/book_repository.dart';
import 'data/file_io.dart';
import 'data/open_library_client.dart';
import 'data/phone_sync.dart';
import 'data/sqlite_book_store.dart';
import 'data/theme_options.dart';
import 'screens/home_shell.dart';
import 'screens/lock_gate.dart';
import 'screens/now_playing.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = BookRepository(await SqliteBookStore.open());
  await repository.load();
  final settings = await AppSettings.load();
  final phoneSync = PhoneSync(repository: repository, settings: settings);
  await phoneSync.refresh();
  WidgetsBinding.instance.addObserver(
    AutoBackupObserver(repository: repository, settings: settings),
  );
  // Not awaited: the app opens while the backup is written.
  runAutoBackup(repository, settings);
  await _setUpListening(repository);
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

/// The audiobook player: which audio belongs to which book on this phone,
/// the player, and the notification that keeps it playing with the screen
/// off. If any of it fails, the app still opens without audio.
Future<void> _setUpListening(BookRepository repository) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final library =
        await AudioLibrary.load(File('${dir.path}/audio_library.json'));
    const files = AndroidAudioFiles();
    final controller = ListenController(
      repository: repository,
      library: library,
      files: files,
    );
    Listening.controller = controller;
    Listening.files = files;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    await AudioService.init(
      builder: () => ChapterlyAudioHandler(controller),
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
