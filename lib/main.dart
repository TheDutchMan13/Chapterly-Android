import 'package:flutter/material.dart';

import 'data/app_settings.dart';
import 'data/book_repository.dart';
import 'data/file_io.dart';
import 'data/open_library_client.dart';
import 'data/phone_sync.dart';
import 'data/sqlite_book_store.dart';
import 'data/theme_options.dart';
import 'screens/library_screen.dart';
import 'screens/lock_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = BookRepository(await SqliteBookStore.open());
  await repository.load();
  final settings = await AppSettings.load();
  final phoneSync = PhoneSync(repository: repository, settings: settings);
  await phoneSync.refresh();
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
        builder: (context, child) => LockGate(
          settings: settings,
          child: child ?? const SizedBox.shrink(),
        ),
        home: LibraryScreen(
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
