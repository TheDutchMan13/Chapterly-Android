import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/book_repository.dart';
import '../ebook/android_reader_device.dart';
import '../ebook/ebook_library.dart';
import '../ebook/reader_stats.dart';
import '../ebook/reader_style.dart';
import '../ebook/reader_tools.dart';
import '../models/book.dart';
import '../models/shelf.dart';
import 'reader_widgets.dart';

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
/// tools, the sides (or the volume buttons) to turn the page. Where you are
/// is saved, the book's current page is kept up to date, and the time you
/// spend reading goes into the reading log.
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
  late final _pdfSearch = PdfTextSearcher(_pdf);
  late final List<PdfViewerPagePaintCallback> _pdfPaint = [
    _pdfSearch.pageTextMatchPaintCallback,
  ];

  bool _tools = false;
  EpubLocation? _location;
  List<EpubChapter> _chapters = const [];
  int? _pdfPage;
  int? _pdfPages;
  PdfDocument? _pdfDocument;
  List<PdfOutlineNode> _outline = const [];
  String? _pdfSearchWords;
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

  /// The furthest place reached, and the new reading since the time was
  /// last written down, for reading speed.
  double _mark = 0;
  double _newReading = 0;

  bool _offeredFinish = false;
  ReadAloud? _aloud;

  /// Completed when the EPUB moves to another page.
  Completer<void>? _turned;

  EbookLink? get _link => widget.library.linkFor(widget.bookId);
  Book? get _book => widget.repository.byId(widget.bookId);
  ReaderPrefs get _prefs => widget.library.prefsFor(widget.bookId);
  bool get _isPdf => _link?.format == EbookFormat.pdf;

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
    _mark = link?.position?.progress ?? 0;
    _reading.start();
    _logTimer = Timer.periodic(const Duration(minutes: 5), (_) => _logTime());
    if (_problem == null) {
      ReaderDevice.start(_prefs, onVolumeKey: _volumeKey);
      WidgetsBinding.instance.addPostFrameCallback((_) => _moveToReading());
    }
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
    _aloud?.dispose();
    if (_isPdf) _pdfSearch.dispose();
    ReaderDevice.stop();
    final position = _unsaved;
    _unsaved = null;
    final minutes = _takeMinutes();
    final read = minutes > 0 ? _takeReading() : 0.0;
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
          read: read,
          now: now,
        ));
    super.dispose();
  }

  /// Writes down the position, the current page and the reading time now.
  void _flush() {
    _saveTimer?.cancel();
    final position = _unsaved;
    _unsaved = null;
    final minutes = _takeMinutes();
    _writeOut(
      repository: widget.repository,
      library: widget.library,
      bookId: widget.bookId,
      position: position,
      minutes: minutes,
      read: minutes > 0 ? _takeReading() : 0,
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

  double _takeReading() {
    final read = _newReading;
    _newReading = 0;
    return read;
  }

  void _logTime() {
    final minutes = _takeMinutes();
    if (minutes <= 0) return;
    widget.repository.addReadingMinutes(widget.bookId, widget.now(), minutes);
    widget.library.addReaderTime(
      widget.bookId,
      widget.now(),
      minutes: minutes,
      progress: _takeReading(),
    );
  }

  /// Saves the position, keeps the book's current page up to date and adds
  /// the reading time to the reading log.
  static void _writeOut({
    required BookRepository repository,
    required EbookLibrary library,
    required String bookId,
    required EbookPosition? position,
    required int minutes,
    required double read,
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
    if (minutes > 0) {
      repository.addReadingMinutes(bookId, now, minutes);
      library.addReaderTime(bookId, now, minutes: minutes, progress: read);
    }
  }

  /// Remembers where you are, saving it a moment later so turning pages
  /// quickly does not write the file every time.
  void _moved(EbookPosition position) {
    _unsaved = position;
    final step = newReading(_mark, position.progress);
    _mark = step.mark;
    _newReading += step.read;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () {
      final p = _unsaved;
      if (p == null) return;
      _unsaved = null;
      widget.library.setPosition(widget.bookId, p);
    });
    _checkEnd(position.progress);
  }

  // ---- Shelves ----

  /// Opening the book file of a book on For later (or Unfinished) moves it
  /// to In progress, with a way to undo it.
  Future<void> _moveToReading() async {
    final book = _book;
    if (book == null || !mounted) return;
    final target = shelfOnOpen(book.shelf);
    if (target == null) return;
    final messenger = ScaffoldMessenger.of(context);
    await widget.repository.moveTo(widget.bookId, target);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Moved to ${target.label}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.repository.putBack([book]),
        ),
      ),
    );
  }

  /// At the end of a book you are reading, offers to mark it finished.
  void _checkEnd(double progress) {
    if (_offeredFinish || !reachedEnd(progress) || !mounted) return;
    final book = _book;
    if (book == null || book.shelf != Shelf.inProgress) return;
    _offeredFinish = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: const Text('You reached the end of the book.'),
        action: SnackBarAction(label: 'Mark finished', onPressed: _markFinished),
      ),
    );
  }

  Future<void> _markFinished() async {
    final book = _book;
    if (book == null) return;
    await widget.repository.moveTo(widget.bookId, Shelf.finished);
    final pages = _isPdf ? (_pdfPages ?? book.pages) : book.pages;
    if (pages != null && pages > 0) {
      await widget.repository.setCurrentPage(widget.bookId, pages);
    }
  }

  // ---- Where you are ----

  String? get _currentLocator {
    if (_link == null) return null;
    if (_isPdf) {
      final page = _pdfPage;
      return page == null ? null : '$page';
    }
    return _location?.startCfi;
  }

  double get _progress {
    final link = _link;
    if (_isPdf) {
      final page = _pdfPage;
      final pages = _pdfPages;
      if (page == null || pages == null || pages <= 1) return 0;
      return (page - 1) / (pages - 1);
    }
    return _location?.progress ?? link?.position?.progress ?? 0;
  }

  void _volumeKey(bool next) {
    if (_selection != null || !mounted) return;
    _turn(next ? 1 : -1);
  }

  /// The next (1) or previous (-1) page.
  void _turn(int direction) {
    if (_isPdf) {
      final page = (_pdfPage ?? 1) + direction;
      final pages = _pdfPages ?? 1;
      if (page >= 1 && page <= pages) _pdf.goToPage(pageNumber: page);
    } else if (direction > 0) {
      _epub.next();
    } else {
      _epub.prev();
    }
  }

  // ---- EPUB ----

  void _epubRelocated(EpubLocation location) {
    setState(() => _location = location);
    final turned = _turned;
    if (turned != null && !turned.isCompleted) turned.complete();
    _turned = null;
    _moved(EbookPosition(
      locator: location.startCfi,
      progress: location.progress,
    ));
  }

  void _epubLoaded() {
    final link = _link;
    if (link == null) return;
    for (final highlight in link.highlights) {
      _epub.addHighlight(
        cfi: highlight.locator,
        color: highlightSwatch(highlight.colour),
        opacity: 0.4,
      );
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

  Future<void> _saveQuote(HighlightColour colour) async {
    final selection = _selection;
    final book = _book;
    if (selection == null || book == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final text = selection.selectedText.trim();
    _epub.addHighlight(
      cfi: selection.selectionCfi,
      color: highlightSwatch(colour),
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
        colour: colour,
      ),
    );
    final link = _link;
    final page = link == null
        ? null
        : currentPageFor(
            format: link.format,
            progress: _progress,
            bookPages: book.pages,
          );
    await widget.repository.addQuote(widget.bookId, text, page: page);
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Highlighted and saved to your quotes'),
        action: SnackBarAction(
          label: 'Add a note',
          onPressed: () => _editHighlight(selection.selectionCfi),
        ),
      ),
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

  Future<void> _lookUp() async {
    final text = _selection?.selectedText ?? '';
    if (!canLookUp(text)) return;
    final messenger = ScaffoldMessenger.of(context);
    _epub.clearSelection();
    setState(() => _selection = null);
    try {
      final opened = await launchUrl(
        dictionaryUri(text),
        mode: LaunchMode.inAppBrowserView,
      );
      if (!opened) throw StateError('not opened');
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not open the dictionary. Is there a browser?'),
        ),
      );
    }
  }

  /// A tap on a highlight: change its colour or note, or remove it.
  Future<void> _editHighlight(String cfi) async {
    final link = _link;
    if (link == null || !mounted) return;
    final highlight =
        link.highlights.where((h) => h.locator == cfi).firstOrNull;
    if (highlight == null) return;
    final edit = await showHighlightEditor(
      context,
      library: widget.library,
      bookId: widget.bookId,
      highlight: highlight,
    );
    if (edit == null) return;
    _epub.removeHighlight(cfi: cfi);
    if (edit == HighlightEdit.changed) {
      final updated = _link?.highlights.where((h) => h.locator == cfi);
      final colour = updated?.firstOrNull?.colour ?? highlight.colour;
      _epub.addHighlight(cfi: cfi, color: highlightSwatch(colour), opacity: 0.4);
    }
  }

  void _footnote(EpubFootnote note) {
    showFootnote(
      context,
      text: note.text,
      label: note.linkText,
      onGoToNote: () => _epub.display(cfi: note.href),
    );
  }

  // ---- PDF ----

  void _pdfPageChanged(int? page) {
    if (page == null) return;
    setState(() => _pdfPage = page);
    _moved(EbookPosition(locator: '$page', progress: _progress));
  }

  Future<void> _pdfReady(
    PdfDocument document,
    PdfViewerController controller,
  ) async {
    final pages = document.pages.length;
    setState(() {
      _pdfPages = pages;
      _pdfDocument = document;
    });
    widget.library.setPageCount(widget.bookId, pages);
    // A PDF's pages are the book's pages when it has none written down.
    final book = _book;
    if (book != null && book.pages == null && pages > 0) {
      widget.repository.setPages(widget.bookId, pages);
    }
    try {
      final outline = await document.loadOutline();
      if (mounted) setState(() => _outline = outline);
    } catch (_) {
      // No contents list in this PDF.
    }
  }

  Future<void> _searchPdf() async {
    final words = await askForSearchWords(context);
    if (words == null || !mounted) return;
    _pdfSearch.startTextSearch(words, goToFirstMatch: true);
    setState(() {
      _pdfSearchWords = words;
      _tools = false;
    });
  }

  void _closePdfSearch() {
    _pdfSearch.resetTextSearch();
    setState(() => _pdfSearchWords = null);
  }

  // ---- Reading aloud ----

  Future<void> _toggleReadAloud() async {
    var aloud = _aloud;
    if (aloud == null) {
      aloud = _aloud = ReadAloud(AndroidSpeaker());
      aloud.addListener(() {
        if (mounted) setState(() {});
      });
    }
    if (aloud.playing) {
      await aloud.stop();
      return;
    }
    await aloud.setRate(_prefs.speechRate);
    final first = await _pageText();
    if (!mounted) return;
    setState(() => _tools = false);
    unawaited(aloud.start(pieces: first ?? const [], more: _nextPageText));
  }

  /// The words on the page you are on, ready to read aloud.
  Future<List<String>?> _pageText() async {
    try {
      if (_isPdf) {
        final document = _pdfDocument;
        final page = _pdfPage ?? 1;
        if (document == null || page < 1 || page > document.pages.length) {
          return null;
        }
        final text = await document.pages[page - 1].loadStructuredText();
        return speechChunks(text.fullText);
      }
      final result = await _epub.extractCurrentPageText();
      return speechChunks(result.text ?? '');
    } catch (_) {
      return const [];
    }
  }

  /// Turns the page and gives its words, or null at the end of the book.
  Future<List<String>?> _nextPageText() async {
    if (!mounted) return null;
    if (_isPdf) {
      final page = _pdfPage ?? 1;
      final pages = _pdfPages ?? 0;
      if (page >= pages) return null;
      await _pdf.goToPage(pageNumber: page + 1);
      _pdfPage = page + 1;
      return _pageText();
    }
    final before = _location?.startCfi;
    final turned = _turned = Completer<void>();
    _epub.next();
    try {
      await turned.future.timeout(const Duration(seconds: 4));
    } on TimeoutException {
      return null;
    }
    if (!mounted || _location?.startCfi == before) return null;
    return _pageText();
  }

  Future<void> _setSpeechRate(double rate) async {
    await _applyPrefs(_prefs.copyWith(speechRate: rate));
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
    final label = _isPdf
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
    if (_link == null) return;
    if (_isPdf) {
      final page = int.tryParse(locator);
      if (page != null) _pdf.goToPage(pageNumber: page);
    } else {
      _epub.display(cfi: locator);
    }
  }

  void _goToProgress(double value) {
    if (_link == null) return;
    if (_isPdf) {
      final pages = _pdfPages;
      if (pages == null || pages <= 0) return;
      _pdf.goToPage(pageNumber: 1 + (value * (pages - 1)).round());
    } else {
      _epub.toProgressPercentage(value);
    }
  }

  Future<void> _applyPrefs(ReaderPrefs prefs) async {
    final old = _prefs;
    await widget.library.applyPrefs(widget.bookId, prefs);
    if (!mounted) return;
    setState(() {});
    await _prefsChanged(old, _prefs);
  }

  /// Puts changed settings into effect.
  Future<void> _prefsChanged(ReaderPrefs old, ReaderPrefs prefs) async {
    if (prefs.keepScreenOn != old.keepScreenOn ||
        prefs.brightness != old.brightness ||
        prefs.volumeKeys != old.volumeKeys) {
      await ReaderDevice.apply(prefs);
    }
    if (prefs.speechRate != old.speechRate) {
      await _aloud?.setRate(prefs.speechRate);
    }
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
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, scroll) => _AppearanceSheet(
          library: widget.library,
          bookId: widget.bookId,
          pdf: _isPdf,
          scroll: scroll,
          onChanged: _applyPrefs,
          onOwnLook: (own) async {
            final old = _prefs;
            await widget.library.setOwnLook(widget.bookId, own: own);
            if (mounted) await _prefsChanged(old, _prefs);
          },
        ),
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
          outline: link.format == EbookFormat.pdf ? _outline : const [],
          scroll: scroll,
          onGo: (locator) {
            Navigator.of(sheetContext).pop();
            _goTo(locator);
          },
          onEdit: (highlight) {
            Navigator.of(sheetContext).pop();
            _editHighlight(highlight.locator);
          },
        ),
      ),
    );
  }

  Future<void> _search() async {
    if (_isPdf) {
      await _searchPdf();
      return;
    }
    final words = await askForSearchWords(context);
    if (words == null || !mounted) return;
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
            pagePaintCallbacks: _pdfPaint,
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
        onAnnotationClicked: (cfi, rect) => _editHighlight(cfi),
        onFootnoteTapped: _footnote,
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
              IconButton(
                tooltip: 'Search in the book',
                color: colours.foreground,
                icon: const Icon(Icons.search),
                onPressed: _isPdf && _pdfDocument == null ? null : _search,
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
    final reading = _aloud?.playing ?? false;
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
                    label: 'Contents',
                    colour: colours.foreground,
                    onPressed: _showContents,
                  ),
                  _ToolButton(
                    icon: reading
                        ? Icons.stop_circle_outlined
                        : Icons.record_voice_over_outlined,
                    label: reading ? 'Stop reading' : 'Read aloud',
                    colour: colours.foreground,
                    onPressed: _toggleReadAloud,
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
    final text = _selection?.selectedText;
    return Material(
      color: colours.bar,
      elevation: 4,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final colour in HighlightColour.values)
              HighlightDot(
                colour: colour,
                tooltip: 'Highlight in ${colour.label.toLowerCase()} and '
                    'save the quote',
                onTap: () => _saveQuote(colour),
              ),
            const SizedBox(width: 4),
            if (showLookUp(text))
              IconButton(
                tooltip: 'Look up',
                color: colours.foreground,
                icon: const Icon(Icons.menu_book_outlined),
                onPressed: _lookUp,
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
        final aloud = _aloud;
        final searchWords = _pdfSearchWords;
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
                if (searchWords != null && !_tools)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 8,
                    child: SafeArea(
                      bottom: false,
                      child: Center(
                        child: PdfSearchBar(
                          searcher: _pdfSearch,
                          words: searchWords,
                          colours: colours,
                          onClose: _closePdfSearch,
                        ),
                      ),
                    ),
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
                  )
                else if (aloud != null && aloud.playing && !_tools)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 24,
                    child: SafeArea(
                      top: false,
                      child: Center(
                        child: ReadAloudBar(
                          colours: colours,
                          rate: _prefs.speechRate,
                          onStop: aloud.stop,
                          onRate: _setSpeechRate,
                        ),
                      ),
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
              Text(
                label,
                style: TextStyle(color: colour, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Text size, theme, typeface, spacing and how pages turn (a PDF only
/// takes the theme), and the phone settings: screen, brightness, volume
/// buttons and the reading-aloud speed.
class _AppearanceSheet extends StatelessWidget {
  const _AppearanceSheet({
    required this.library,
    required this.bookId,
    required this.pdf,
    required this.scroll,
    required this.onChanged,
    required this.onOwnLook,
  });

  final EbookLibrary library;
  final String bookId;
  final bool pdf;
  final ScrollController scroll;
  final Future<void> Function(ReaderPrefs prefs) onChanged;
  final Future<void> Function(bool own) onOwnLook;

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
        final prefs = library.prefsFor(bookId);
        final own = library.hasOwnLook(bookId);
        Widget label(String text) => Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(text, style: textTheme.labelLarge),
            );
        final brightness = prefs.brightness;
        return SafeArea(
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text(
                pdf ? 'Theme' : 'Text and theme',
                style: textTheme.titleLarge,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Only for this book'),
                subtitle: Text(
                  own
                      ? 'Changes to the text and theme are kept for this '
                          'book.'
                      : 'Changes to the text and theme apply to every book.',
                ),
                value: own,
                onChanged: onOwnLook,
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
                          onTap: () => onChanged(prefs.copyWith(theme: theme)),
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
                  onSelected: (s) => onChanged(prefs.copyWith(lineSpacing: s)),
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
              const Divider(height: 32),
              Text('Phone', style: textTheme.titleMedium),
              label('Brightness'),
              Row(
                children: [
                  const Icon(Icons.brightness_low, size: 20),
                  Expanded(
                    child: Slider(
                      value: brightness ?? 0.5,
                      min: 0.02,
                      max: 1,
                      onChanged: brightness == null
                          ? null
                          : (v) => onChanged(
                                prefs.copyWith(brightness: () => v),
                              ),
                    ),
                  ),
                  const Icon(Icons.brightness_high, size: 20),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Use the phone's brightness"),
                value: brightness == null,
                onChanged: (system) => onChanged(
                  prefs.copyWith(brightness: () => system ? null : 0.5),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep the screen on'),
                subtitle: const Text('While the reader is open'),
                value: prefs.keepScreenOn,
                onChanged: (on) => onChanged(prefs.copyWith(keepScreenOn: on)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Volume buttons turn pages'),
                subtitle: const Text('Down for the next page, up to go back'),
                value: prefs.volumeKeys,
                onChanged: (on) => onChanged(prefs.copyWith(volumeKeys: on)),
              ),
              label('Reading aloud speed'),
              SpeechRateSlider(
                rate: prefs.speechRate,
                onChanged: (rate) => onChanged(prefs.copyWith(speechRate: rate)),
              ),
            ],
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

/// Chapters (EPUB) or the PDF's contents, bookmarks and highlights.
class _ContentsSheet extends StatelessWidget {
  const _ContentsSheet({
    required this.library,
    required this.bookId,
    required this.chapters,
    required this.outline,
    required this.scroll,
    required this.onGo,
    required this.onEdit,
  });

  final EbookLibrary library;
  final String bookId;
  final List<EpubChapter> chapters;
  final List<PdfOutlineNode> outline;
  final ScrollController scroll;
  final ValueChanged<String> onGo;
  final ValueChanged<EbookHighlight> onEdit;

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
    final pdfContents = outline.isNotEmpty;
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final link = library.linkFor(bookId);
        final isEpub = link?.format == EbookFormat.epub;
        final bookmarks = link?.bookmarks ?? const <EbookBookmark>[];
        final highlights = link?.highlights ?? const <EbookHighlight>[];
        // The first tab gets the sheet's scrolling, so dragging it down
        // closes the sheet.
        var first = true;
        ScrollController? takeScroll() {
          if (!first) return null;
          first = false;
          return scroll;
        }

        final tabs = <(String, Widget)>[
          if (epub)
            (
              'Chapters',
              ListView(
                controller: takeScroll(),
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
          if (pdfContents)
            (
              'Contents',
              PdfOutlineList(
                outline: outline,
                controller: takeScroll(),
                onPage: (page) => onGo('$page'),
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
                    controller: takeScroll(),
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
          if (isEpub)
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
                          HighlightTile(
                            highlight: highlight,
                            onGo: () => onGo(highlight.locator),
                            onEdit: () => onEdit(highlight),
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
