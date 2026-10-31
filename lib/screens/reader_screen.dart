import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/book_repository.dart';
import '../ebook/ebook_library.dart';
import '../ebook/reader_style.dart';
import '../models/book.dart';

/// Opens the reader for a book that has a book file on this device.
void openReader(
  BuildContext context, {
  required BookRepository repository,
  required EbookLibrary library,
  required String bookId,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ReaderScreen(
        repository: repository,
        library: library,
        bookId: bookId,
      ),
    ),
  );
}

/// Reads a book's EPUB or PDF file. Tap the middle of the page for the
/// tools, the sides to turn the page. Where you are is saved, the book's
/// current page is kept up to date, and the time you spend reading goes
/// into the reading log.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.repository,
    required this.library,
    required this.bookId,
    this.now = DateTime.now,
  });

  final BookRepository repository;
  final EbookLibrary library;
  final String bookId;
  final DateTime Function() now;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  final _epub = EpubController();
  final _pdf = PdfViewerController();

  bool _tools = false;
  EpubLocation? _location;
  List<EpubChapter> _chapters = const [];
  int? _pdfPage;
  int? _pdfPages;
  EpubTextSelection? _selection;
  String? _problem;
  String? _initialLocations;

  /// Where a touch started, to tell a tap from a swipe.
  Offset? _touchStart;

  Timer? _saveTimer;
  EbookPosition? _unsaved;

  /// Reading time not yet in the reading log.
  final _reading = Stopwatch();
  Duration _carried = Duration.zero;
  Timer? _logTimer;

  EbookLink? get _link => widget.library.linkFor(widget.bookId);
  Book? get _book => widget.repository.byId(widget.bookId);
  ReaderPrefs get _prefs => widget.library.prefs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final link = _link;
    if (link == null || !File(link.path).existsSync()) {
      _problem = 'The book file is missing on this phone. Add it again from '
          'the book page.';
    } else if (link.format == EbookFormat.epub) {
      final saved = File('${link.path}.locations');
      if (saved.existsSync()) {
        try {
          _initialLocations = saved.readAsStringSync();
        } catch (_) {
          // Worked out again while reading.
        }
      }
    }
    _reading.start();
    _logTimer = Timer.periodic(const Duration(minutes: 5), (_) => _logTime());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reading.start();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _reading.stop();
      _flush();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _logTimer?.cancel();
    _reading.stop();
    final position = _unsaved;
    _unsaved = null;
    final minutes = _takeMinutes();
    final repository = widget.repository;
    final library = widget.library;
    final bookId = widget.bookId;
    final now = widget.now();
    // Saved just after the screen is gone: saving tells the book page to
    // redraw, which Flutter does not allow while it is removing a screen.
    scheduleMicrotask(() => _writeOut(
          repository: repository,
          library: library,
          bookId: bookId,
          position: position,
          minutes: minutes,
          now: now,
        ));
    super.dispose();
  }

  /// Writes down the position, the current page and the reading time now.
  void _flush() {
    _saveTimer?.cancel();
    final position = _unsaved;
    _unsaved = null;
    _writeOut(
      repository: widget.repository,
      library: widget.library,
      bookId: widget.bookId,
      position: position,
      minutes: _takeMinutes(),
      now: widget.now(),
    );
  }

  /// Takes the whole minutes of reading so far; the seconds left over wait
  /// for the next time.
  int _takeMinutes() {
    final total = _carried + _reading.elapsed;
    _reading.reset();
    final minutes = total.inMinutes;
    _carried = total - Duration(minutes: minutes);
    return minutes;
  }

  void _logTime() {
    final minutes = _takeMinutes();
    if (minutes > 0) {
      widget.repository.addReadingMinutes(widget.bookId, widget.now(), minutes);
    }
  }

  /// Saves the position, keeps the book's current page up to date and adds
  /// the reading time to the reading log.
  static void _writeOut({
    required BookRepository repository,
    required EbookLibrary library,
    required String bookId,
    required EbookPosition? position,
    required int minutes,
    required DateTime now,
  }) {
    if (position != null) {
      library.setPosition(bookId, position);
      final book = repository.byId(bookId);
      final link = library.linkFor(bookId);
      if (book != null && link != null) {
        final page = currentPageFor(
          format: link.format,
          progress: position.progress,
          bookPages: book.pages,
          pdfPage: link.format == EbookFormat.pdf
              ? int.tryParse(position.locator)
              : null,
        );
        if (page != null && page != book.currentPage) {
          repository.setCurrentPage(bookId, page);
        }
      }
    }
    if (minutes > 0) repository.addReadingMinutes(bookId, now, minutes);
  }

  /// Remembers where you are, saving it a moment later so turning pages
  /// quickly does not write the file every time.
  void _moved(EbookPosition position) {
    _unsaved = position;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () {
      final p = _unsaved;
      if (p == null) return;
      _unsaved = null;
      widget.library.setPosition(widget.bookId, p);
    });
  }

  String? get _currentLocator {
    final link = _link;
    if (link == null) return null;
    if (link.format == EbookFormat.pdf) {
      final page = _pdfPage;
      return page == null ? null : '$page';
    }
    return _location?.startCfi;
  }

  double get _progress {
    final link = _link;
    if (link?.format == EbookFormat.pdf) {
      final page = _pdfPage;
      final pages = _pdfPages;
      if (page == null || pages == null || pages <= 1) return 0;
      return (page - 1) / (pages - 1);
    }
    return _location?.progress ?? link?.position?.progress ?? 0;
  }

  // ---- EPUB ----

  void _epubRelocated(EpubLocation location) {
    setState(() => _location = location);
    _moved(EbookPosition(
      locator: location.startCfi,
      progress: location.progress,
    ));
  }

  void _epubLoaded() {
    final link = _link;
    if (link == null) return;
    final colour = readerColors(_prefs.theme).highlight;
    for (final highlight in link.highlights) {
      _epub.addHighlight(cfi: highlight.locator, color: colour, opacity: 0.4);
    }
  }

  void _touchDown(double x, double y) => _touchStart = Offset(x, y);

  void _touchUp(double x, double y) {
    final start = _touchStart;
    _touchStart = null;
    if (start == null || _selection != null) return;
    // A swipe turns the page by itself; only a tap counts here.
    if ((Offset(x, y) - start).distance > 0.03) return;
    final zone = _prefs.scroll ? TapZone.middle : tapZone(x);
    switch (zone) {
      case TapZone.back:
        if (_tools) {
          setState(() => _tools = false);
        } else {
          _epub.prev();
        }
      case TapZone.forward:
        if (_tools) {
          setState(() => _tools = false);
        } else {
          _epub.next();
        }
      case TapZone.middle:
        setState(() => _tools = !_tools);
    }
  }

  void _saveLocations(String locations) {
    final link = _link;
    if (link == null) return;
    try {
      File('${link.path}.locations').writeAsStringSync(locations);
    } catch (_) {
      // Worked out again next time.
    }
  }

  EpubTheme _epubTheme(ReaderPrefs prefs) {
    final colours = readerColors(prefs.theme);
    return EpubTheme.custom(
      backgroundDecoration: BoxDecoration(color: colours.background),
      foregroundColor: colours.foreground,
      customCss: readerCss(prefs),
    );
  }

  Future<void> _saveQuote() async {
    final selection = _selection;
    final book = _book;
    if (selection == null || book == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final text = selection.selectedText.trim();
    _epub.addHighlight(
      cfi: selection.selectionCfi,
      color: readerColors(_prefs.theme).highlight,
      opacity: 0.4,
    );
    _epub.clearSelection();
    setState(() => _selection = null);
    await widget.library.addHighlight(
      widget.bookId,
      EbookHighlight(
        locator: selection.selectionCfi,
        text: text,
        addedAt: widget.now(),
      ),
    );
    final page = _link == null
        ? null
        : currentPageFor(
            format: _link!.format,
            progress: _progress,
            bookPages: book.pages,
          );
    await widget.repository.addQuote(widget.bookId, text, page: page);
    messenger.showSnackBar(
      const SnackBar(content: Text('Highlighted and saved to your quotes')),
    );
  }

  Future<void> _copySelection() async {
    final selection = _selection;
    if (selection == null) return;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: selection.selectedText));
    _epub.clearSelection();
    setState(() => _selection = null);
    messenger.showSnackBar(const SnackBar(content: Text('Copied')));
  }

  Future<void> _highlightTapped(String cfi) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this highlight?'),
        content: const Text(
          'The quote stays on the book page. You can remove it there.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove != true) return;
    _epub.removeHighlight(cfi: cfi);
    await widget.library.removeHighlight(widget.bookId, cfi);
  }

  // ---- PDF ----

  void _pdfPageChanged(int? page) {
    if (page == null) return;
    setState(() => _pdfPage = page);
    _moved(EbookPosition(locator: '$page', progress: _progress));
  }

  void _pdfReady(PdfDocument document, PdfViewerController controller) {
    final pages = document.pages.length;
    setState(() => _pdfPages = pages);
    widget.library.setPageCount(widget.bookId, pages);
    // A PDF's pages are the book's pages when it has none written down.
    final book = _book;
    if (book != null && book.pages == null && pages > 0) {
      widget.repository.setPages(widget.bookId, pages);
    }
  }

  // ---- Tools ----

  void _toggleBookmark() {
    final link = _link;
    final locator = _currentLocator;
    if (link == null || locator == null) return;
    final existing = link.bookmarks.any((b) => b.locator == locator);
    if (existing) {
      widget.library.removeBookmark(widget.bookId, locator);
      return;
    }
    final label = link.format == EbookFormat.pdf
        ? 'Page $locator'
        : _pageLabel() ?? percentText(_progress);
    widget.library.addBookmark(
      widget.bookId,
      EbookBookmark(
        locator: locator,
        progress: _progress,
        label: label,
        addedAt: widget.now(),
      ),
    );
  }

  /// "About page 101 of 266" for an EPUB when the book's pages are known.
  String? _pageLabel() {
    final book = _book;
    final link = _link;
    if (book == null || link == null) return null;
    final page = currentPageFor(
      format: link.format,
      progress: _progress,
      bookPages: book.pages,
      pdfPage: _pdfPage,
    );
    if (page == null) return null;
    return link.format == EbookFormat.pdf
        ? 'Page $page of ${_pdfPages ?? book.pages}'
        : 'About page $page of ${book.pages}';
  }

  void _goTo(String locator) {
    final link = _link;
    if (link == null) return;
    if (link.format == EbookFormat.pdf) {
      final page = int.tryParse(locator);
      if (page != null) _pdf.goToPage(pageNumber: page);
    } else {
      _epub.display(cfi: locator);
    }
  }

  void _goToProgress(double value) {
    final link = _link;
    if (link == null) return;
    if (link.format == EbookFormat.pdf) {
      final pages = _pdfPages;
      if (pages == null || pages <= 0) return;
      _pdf.goToPage(pageNumber: 1 + (value * (pages - 1)).round());
    } else {
      _epub.toProgressPercentage(value);
    }
  }

  Future<void> _applyPrefs(ReaderPrefs prefs) async {
    final old = _prefs;
    await widget.library.setPrefs(prefs);
    if (!mounted) return;
    setState(() {});
    if (_link?.format != EbookFormat.epub) return;
    if (prefs.fontSize != old.fontSize) {
      await _epub.setFontSize(fontSize: prefs.fontSize.toDouble());
    }
    if (prefs.scroll != old.scroll) {
      await _epub.setFlow(
        flow: prefs.scroll ? EpubFlow.scrolled : EpubFlow.paginated,
      );
    }
    if (prefs.theme != old.theme ||
        prefs.font != old.font ||
        prefs.lineSpacing != old.lineSpacing) {
      await _epub.updateTheme(theme: _epubTheme(prefs));
    }
  }

  void _showAppearance() {
    final pdf = _link?.format == EbookFormat.pdf;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _AppearanceSheet(
        library: widget.library,
        pdf: pdf,
        onChanged: _applyPrefs,
      ),
    );
  }

  void _showContents() {
    final link = _link;
    if (link == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scroll) => _ContentsSheet(
          library: widget.library,
          bookId: widget.bookId,
          chapters: link.format == EbookFormat.epub ? _chapters : const [],
          scroll: scroll,
          onGo: (locator) {
            Navigator.of(sheetContext).pop();
            _goTo(locator);
          },
        ),
      ),
    );
  }

  Future<void> _search() async {
    final controller = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Search in the book'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(labelText: 'Words to find'),
          onSubmitted: (text) => Navigator.of(dialogContext).pop(text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Search'),
          ),
        ],
      ),
    );
    controller.dispose();
    final words = query?.trim() ?? '';
    if (words.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    List<EpubSearchResult> results;
    try {
      results = await _epub.search(query: words);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('The search did not work.')),
      );
      return;
    }
    if (!mounted) return;
    if (results.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text('"$words" is not in this book.')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scroll) => ListView.builder(
          controller: scroll,
          itemCount: results.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '${results.length} '
                  '${results.length == 1 ? 'place' : 'places'} with '
                  '"$words"',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              );
            }
            final result = results[i - 1];
            return ListTile(
              title: Text(
                result.excerpt.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _epub.display(cfi: result.cfi);
              },
            );
          },
        ),
      ),
    );
  }

  // ---- Building ----

  Widget _viewer(EbookLink link, ReaderColors colours) {
    if (link.format == EbookFormat.pdf) {
      final saved = int.tryParse(link.position?.locator ?? '');
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => setState(() => _tools = !_tools),
        child: PdfViewer.file(
          link.path,
          controller: _pdf,
          initialPageNumber: saved != null && saved > 0 ? saved : 1,
          params: PdfViewerParams(
            backgroundColor: colours.background,
            onPageChanged: _pdfPageChanged,
            onViewerReady: _pdfReady,
          ),
        ),
      );
    }
    final prefs = _prefs;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: readerMargin(prefs.margins)),
      child: EpubViewer(
        epubController: _epub,
        epubSource: EpubSource.fromFile(File(link.path)),
        initialCfi: link.position?.locator,
        initialLocations: _initialLocations,
        displaySettings: EpubDisplaySettings(
          fontSize: prefs.fontSize,
          flow: prefs.scroll ? EpubFlow.scrolled : EpubFlow.paginated,
          snap: true,
          theme: _epubTheme(prefs),
        ),
        onEpubLoaded: _epubLoaded,
        onChaptersLoaded: (chapters) => setState(() => _chapters = chapters),
        onRelocated: _epubRelocated,
        onLocationsGenerated: _saveLocations,
        onTouchDown: _touchDown,
        onTouchUp: _touchUp,
        onTextSelected: (selection) => setState(() => _selection = selection),
        onDeselection: () {
          if (_selection != null) setState(() => _selection = null);
        },
        onAnnotationClicked: (cfi, rect) => _highlightTapped(cfi),
        onLoadError: (error) => setState(
          () => _problem = 'This book file could not be opened. It may be '
              'damaged or locked (DRM).',
        ),
      ),
    );
  }

  Widget _topBar(Book book, EbookLink link, ReaderColors colours) {
    final locator = _currentLocator;
    final marked =
        locator != null && link.bookmarks.any((b) => b.locator == locator);
    return Material(
      color: colours.bar,
      elevation: 2,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back to the book page',
                color: colours.foreground,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colours.foreground,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (book.author.isNotEmpty)
                      Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colours.muted, fontSize: 12),
                      ),
                  ],
                ),
              ),
              if (link.format == EbookFormat.epub)
                IconButton(
                  tooltip: 'Search in the book',
                  color: colours.foreground,
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
              IconButton(
                tooltip: marked ? 'Remove the bookmark' : 'Bookmark this page',
                color: marked
                    ? Theme.of(context).colorScheme.primary
                    : colours.foreground,
                icon: Icon(marked ? Icons.bookmark : Icons.bookmark_border),
                onPressed: locator == null ? null : _toggleBookmark,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar(EbookLink link, ReaderColors colours) {
    final progress = _progress;
    final location = _location;
    final where = <String>[
      if (link.format == EbookFormat.epub &&
          location?.chapterPage != null &&
          location?.chapterTotalPages != null)
        'Page ${location!.chapterPage} of ${location.chapterTotalPages} '
            'in this chapter',
      ?_pageLabel(),
    ];
    final textStyle = TextStyle(color: colours.muted, fontSize: 12);
    return Material(
      color: colours.bar,
      elevation: 2,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      where.isEmpty ? ' ' : where.join(' · '),
                      style: textStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(percentText(progress), style: textStyle),
                ],
              ),
              _ProgressSlider(
                value: progress,
                onDone: _goToProgress,
              ),
              Row(
                children: [
                  _ToolButton(
                    icon: Icons.format_list_bulleted,
                    label: link.format == EbookFormat.epub
                        ? 'Contents'
                        : 'Bookmarks',
                    colour: colours.foreground,
                    onPressed: _showContents,
                  ),
                  _ToolButton(
                    icon: Icons.text_fields,
                    label: link.format == EbookFormat.epub
                        ? 'Text and theme'
                        : 'Theme',
                    colour: colours.foreground,
                    onPressed: _showAppearance,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectionBar(ReaderColors colours) {
    return Material(
      color: colours.bar,
      elevation: 4,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              onPressed: _saveQuote,
              icon: const Icon(Icons.format_quote),
              label: const Text('Highlight and save quote'),
            ),
            IconButton(
              tooltip: 'Copy',
              color: colours.foreground,
              icon: const Icon(Icons.copy),
              onPressed: _copySelection,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.library,
      builder: (context, _) {
        final colours = readerColors(_prefs.theme);
        final link = _link;
        final book = _book;
        final problem = _problem;
        if (link == null || book == null || problem != null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Reader')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  problem ?? 'This book has no book file on this phone.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        final overlay = colours.isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlay,
          child: Scaffold(
            backgroundColor: colours.background,
            body: Stack(
              children: [
                Positioned.fill(
                  child: SafeArea(child: _viewer(link, colours)),
                ),
                if (_tools)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: _topBar(book, link, colours),
                  ),
                if (_tools)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _bottomBar(link, colours),
                  ),
                if (_selection != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 24,
                    child: SafeArea(
                      top: false,
                      child: Center(child: _selectionBar(colours)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The position slider: moves while you drag, and goes there when you let
/// go.
class _ProgressSlider extends StatefulWidget {
  const _ProgressSlider({required this.value, required this.onDone});

  final double value;
  final ValueChanged<double> onDone;

  @override
  State<_ProgressSlider> createState() => _ProgressSliderState();
}

class _ProgressSliderState extends State<_ProgressSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final value = (_dragging ?? widget.value).clamp(0.0, 1.0);
    return Slider(
      value: value,
      label: percentText(value),
      divisions: 200,
      onChanged: (v) => setState(() => _dragging = v),
      onChangeEnd: (v) {
        setState(() => _dragging = null);
        widget.onDone(v);
      },
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.colour,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color colour;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: colour),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: colour, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Text size, theme, typeface, spacing and how pages turn. A PDF only
/// takes the theme (the colour around the pages).
class _AppearanceSheet extends StatelessWidget {
  const _AppearanceSheet({
    required this.library,
    required this.pdf,
    required this.onChanged,
  });

  final EbookLibrary library;
  final bool pdf;
  final Future<void> Function(ReaderPrefs prefs) onChanged;

  Widget _segments<T>({
    required List<(T, String)> choices,
    required T selected,
    required ValueChanged<T> onSelected,
  }) {
    return SegmentedButton<T>(
      showSelectedIcon: false,
      segments: [
        for (final (value, label) in choices)
          ButtonSegment<T>(value: value, label: Text(label)),
      ],
      selected: {selected},
      onSelectionChanged: (values) => onSelected(values.first),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final prefs = library.prefs;
        Widget label(String text) => Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(text, style: textTheme.labelLarge),
            );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  pdf ? 'Theme' : 'Text and theme',
                  style: textTheme.titleLarge,
                ),
                if (!pdf) ...[
                  label('Text size'),
                  Row(
                    children: [
                      const Text('A', style: TextStyle(fontSize: 14)),
                      Expanded(
                        child: Slider(
                          value: prefs.fontSize.toDouble(),
                          min: ReaderPrefs.minFontSize.toDouble(),
                          max: ReaderPrefs.maxFontSize.toDouble(),
                          divisions:
                              ReaderPrefs.maxFontSize - ReaderPrefs.minFontSize,
                          label: '${prefs.fontSize}',
                          onChanged: (v) =>
                              onChanged(prefs.copyWith(fontSize: v.round())),
                        ),
                      ),
                      const Text('A', style: TextStyle(fontSize: 26)),
                    ],
                  ),
                ],
                label('Theme'),
                Row(
                  children: [
                    for (final theme in ReaderTheme.values)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _ThemeChoice(
                            theme: theme,
                            selected: prefs.theme == theme,
                            onTap: () =>
                                onChanged(prefs.copyWith(theme: theme)),
                          ),
                        ),
                      ),
                  ],
                ),
                if (!pdf) ...[
                  label('Typeface'),
                  _segments<ReaderFont>(
                    choices: const [
                      (ReaderFont.serif, 'Serif'),
                      (ReaderFont.sans, 'Sans'),
                    ],
                    selected: prefs.font,
                    onSelected: (font) => onChanged(prefs.copyWith(font: font)),
                  ),
                  label('Line spacing'),
                  _segments<ReaderSpacing>(
                    choices: [
                      for (final s in ReaderSpacing.values)
                        (s, readerSpacingLabel(s)),
                    ],
                    selected: prefs.lineSpacing,
                    onSelected: (s) =>
                        onChanged(prefs.copyWith(lineSpacing: s)),
                  ),
                  label('Margins'),
                  _segments<ReaderSpacing>(
                    choices: [
                      for (final s in ReaderSpacing.values)
                        (s, readerSpacingLabel(s)),
                    ],
                    selected: prefs.margins,
                    onSelected: (s) => onChanged(prefs.copyWith(margins: s)),
                  ),
                  label('Turn pages by'),
                  _segments<bool>(
                    choices: const [
                      (false, 'Tapping or swiping'),
                      (true, 'Scrolling'),
                    ],
                    selected: prefs.scroll,
                    onSelected: (scroll) =>
                        onChanged(prefs.copyWith(scroll: scroll)),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final ReaderTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colours = readerColors(theme);
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: '${readerThemeLabel(theme)} theme',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: colours.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? accent : colours.muted,
                  width: selected ? 3 : 1,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                'Aa',
                style: TextStyle(
                  color: colours.foreground,
                  fontSize: 20,
                  fontFamily: 'serif',
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              readerThemeLabel(theme),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Chapters (EPUB), bookmarks and highlights.
class _ContentsSheet extends StatelessWidget {
  const _ContentsSheet({
    required this.library,
    required this.bookId,
    required this.chapters,
    required this.scroll,
    required this.onGo,
  });

  final EbookLibrary library;
  final String bookId;
  final List<EpubChapter> chapters;
  final ScrollController scroll;
  final ValueChanged<String> onGo;

  /// Chapters with their sub-chapters, one level of indent each.
  List<(EpubChapter, int)> _flatten(List<EpubChapter> items, int depth) => [
        for (final chapter in items) ...[
          (chapter, depth),
          ..._flatten(chapter.subitems, depth + 1),
        ],
      ];

  @override
  Widget build(BuildContext context) {
    final epub = chapters.isNotEmpty;
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final link = library.linkFor(bookId);
        final bookmarks = link?.bookmarks ?? const <EbookBookmark>[];
        final highlights = link?.highlights ?? const <EbookHighlight>[];
        final tabs = <(String, Widget)>[
          if (epub)
            (
              'Chapters',
              ListView(
                controller: scroll,
                children: [
                  for (final (chapter, depth) in _flatten(chapters, 0))
                    ListTile(
                      contentPadding: EdgeInsets.only(
                        left: 16.0 + depth * 20,
                        right: 16,
                      ),
                      title: Text(chapter.title.trim()),
                      onTap: () => onGo(chapter.href),
                    ),
                ],
              ),
            ),
          (
            'Bookmarks (${bookmarks.length})',
            bookmarks.isEmpty
                ? const _Empty(
                    'No bookmarks yet. Tap the middle of a page, then the '
                    'bookmark at the top.',
                  )
                : ListView(
                    controller: epub ? null : scroll,
                    children: [
                      for (final bookmark in bookmarks)
                        ListTile(
                          leading: const Icon(Icons.bookmark_outline),
                          title: Text(bookmark.label),
                          subtitle: Text(percentText(bookmark.progress)),
                          trailing: IconButton(
                            tooltip: 'Remove the bookmark',
                            icon: const Icon(Icons.clear),
                            onPressed: () => library.removeBookmark(
                              bookId,
                              bookmark.locator,
                            ),
                          ),
                          onTap: () => onGo(bookmark.locator),
                        ),
                    ],
                  ),
          ),
          if (epub)
            (
              'Highlights (${highlights.length})',
              highlights.isEmpty
                  ? const _Empty(
                      'No highlights yet. Press and hold on the text to '
                      'select a passage.',
                    )
                  : ListView(
                      children: [
                        for (final highlight in highlights)
                          ListTile(
                            leading: const Icon(Icons.format_quote),
                            title: Text(
                              highlight.text,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            onTap: () => onGo(highlight.locator),
                          ),
                      ],
                    ),
            ),
        ];
        return DefaultTabController(
          length: tabs.length,
          child: Column(
            children: [
              TabBar(
                isScrollable: tabs.length > 2,
                tabs: [for (final (label, _) in tabs) Tab(text: label)],
              ),
              Expanded(
                child: TabBarView(
                  children: [for (final (_, view) in tabs) view],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
