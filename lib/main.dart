import 'package:flutter/material.dart';

import 'data/book_repository.dart';
import 'screens/library_screen.dart';

void main() {
  runApp(const ChapterlyApp());
}

class ChapterlyApp extends StatelessWidget {
  const ChapterlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chapterly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.brown,
        useMaterial3: true,
      ),
      home: LibraryScreen(repository: BookRepository()),
    );
  }
}
