import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../data/file_io.dart';
import '../data/open_library_client.dart';
import '../data/phone_sync.dart';
import 'library_screen.dart';
import 'more_screen.dart';
import 'statistics_screen.dart';

/// The three main pages, Books, Statistics and More, with a bar along the
/// bottom to switch between them. The pages stay alive, so the scroll position, search
/// and filters on Books are still there when you come back.
class HomeShell extends StatefulWidget {
  const HomeShell({
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
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          LibraryScreen(
            repository: widget.repository,
            client: widget.client,
            settings: widget.settings,
            phoneSync: widget.phoneSync,
            fileIo: widget.fileIo,
          ),
          StatisticsScreen(
            repository: widget.repository,
            settings: widget.settings,
            fileIo: widget.fileIo,
          ),
          MoreScreen(
            repository: widget.repository,
            settings: widget.settings,
            phoneSync: widget.phoneSync,
            fileIo: widget.fileIo,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Statistics',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
