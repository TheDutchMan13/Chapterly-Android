import 'package:flutter/material.dart';

import 'data/app_settings.dart';
import 'data/book_repository.dart';
import 'data/file_io.dart';
import 'data/open_library_client.dart';
import 'data/sqlite_book_store.dart';
import 'screens/library_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = BookRepository(await SqliteBookStore.open());
  await repository.load();
  final settings = await AppSettings.load();
  runApp(
    ChapterlyApp(
      repository: repository,
      client: OpenLibraryClient(),
      settings: settings,
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
    required this.fileIo,
  });

  final BookRepository repository;
  final OpenLibraryClient client;
  final AppSettings settings;
  final FileIo fileIo;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chapterly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.brown, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.brown,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: LibraryScreen(
        repository: repository,
        client: client,
        settings: settings,
        fileIo: fileIo,
      ),
    );
  }
}
