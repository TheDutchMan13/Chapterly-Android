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

  /// Pages opened so far: the others are not built until first visited,
  /// which makes starting quicker.
  final _opened = <int>{0};

  Widget _page(int index, Widget Function() make) =>
      _opened.contains(index) ? make() : const SizedBox.shrink();

  void _select(int i) => setState(() {
    _index = i;
    _opened.add(i);
  });

  /// From this width (a tablet, or a phone on its side) the pages are
  /// switched from a rail down the left, as in Chapterly for Windows, which
  /// gives the books the full height of the screen.
  static const _railWidth = 600.0;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _railWidth;
    final pages = _pages();
    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: _select,
                labelType: NavigationRailLabelType.all,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.menu_book_outlined),
                    selectedIcon: Icon(Icons.menu_book),
                    label: Text('Library'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.bar_chart_outlined),
                    selectedIcon: Icon(Icons.bar_chart),
                    label: Text('Statistics'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.more_horiz),
                    label: Text('More'),
                  ),
                ],
              ),
              Expanded(child: pages),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: pages,
      bottomNavigationBar: _bar(
        NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
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
            NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
          ],
        ),
      ),
    );
  }

  /// Kept under one key so turning the screen (rail or bar) does not lose
  /// the scroll position, search and filters on the pages.
  final _pagesKey = GlobalKey();

  Widget _pages() {
    return KeyedSubtree(
      key: _pagesKey,
      child: IndexedStack(
        index: _index,
        children: [
          // Each page is made on first visit.
          _page(
            0,
            () => LibraryScreen(
              repository: widget.repository,
              client: widget.client,
              settings: widget.settings,
              phoneSync: widget.phoneSync,
              fileIo: widget.fileIo,
            ),
          ),
          _page(
            1,
            () => StatisticsScreen(
              repository: widget.repository,
              settings: widget.settings,
              fileIo: widget.fileIo,
            ),
          ),
          _page(
            2,
            () => MoreScreen(
              repository: widget.repository,
              settings: widget.settings,
              phoneSync: widget.phoneSync,
              fileIo: widget.fileIo,
              client: widget.client,
            ),
          ),
        ],
      ),
    );
  }

  /// In the Midnight look the bar floats as a rounded pill above the
  /// bottom of the screen.
  Widget _bar(Widget bar) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        if (widget.settings.look != AppLook.midnight) return bar;
        return SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(33),
              child: MediaQuery.removePadding(
                context: context,
                removeBottom: true,
                child: bar,
              ),
            ),
          ),
        );
      },
    );
  }
}
