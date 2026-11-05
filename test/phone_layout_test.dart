import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/file_io.dart';
import 'package:chapterly/data/open_library_client.dart';
import 'package:chapterly/data/phone_sync.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/quote.dart';
import 'package:chapterly/models/reading.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/screens/book_detail_screen.dart';
import 'package:chapterly/screens/library_screen.dart';
import 'package:chapterly/screens/more_screen.dart';
import 'package:chapterly/screens/read_next_screen.dart';
import 'package:chapterly/screens/statistics_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// The 1.14.0 additions on a small phone (360 by 740): nothing overflows.

Book _book(
  String id,
  String title, {
  String author = 'Brandon Sanderson',
  Shelf shelf = Shelf.forLater,
  List<String> tags = const ['fantasy'],
  int? rating,
  int? pages = 400,
  String? isbn,
  String? series,
  int? seriesNumber,
  DateTime? startedAt,
  List<Quote> quotes = const [],
  List<LogEntry> log = const [],
}) =>
    Book(
      id: id,
      title: title,
      author: author,
      shelf: shelf,
      addedAt: DateTime(2026, 1, int.tryParse(id) ?? 1),
      tags: tags,
      rating: rating,
      pages: pages,
      isbn: isbn,
      series: series,
      seriesNumber: seriesNumber,
      startedAt: startedAt,
      quotes: quotes,
      readingLog: log,
      finishedAt: shelf == Shelf.finished ? DateTime(2026, 3) : null,
      updatedAt: DateTime(2026, 1, 1),
    );

Future<BookRepository> _library() async {
  final repository = BookRepository(InMemoryBookStore());
  await repository.load();
  final now = DateTime.now();
  await repository.replaceAll([
    for (var i = 1; i <= 10; i++)
      _book(
        'f$i',
        'The Stormlight Archive Volume Number $i With A Long Title',
        shelf: Shelf.finished,
        rating: i.isEven ? 5 : 3,
        series: 'Stormlight',
        seriesNumber: i,
        tags: i.isEven ? ['fantasy', 'epic'] : ['fantasy', 'romance'],
        quotes: [
          Quote(
            text: 'A long quote that goes on and on so that it has to wrap '
                'over several lines on a small phone screen, number $i',
            addedAt: DateTime(2026),
          ),
        ],
      ),
    _book(
      '7',
      'A Book In Progress With A Rather Long Title Indeed',
      shelf: Shelf.inProgress,
      startedAt: now.subtract(const Duration(days: 20)),
      isbn: '0306406152',
      log: [
        LogEntry(
          date: now.subtract(const Duration(days: 3)),
          pages: 40,
          minutes: 60,
        ),
        LogEntry(
          date: now.subtract(const Duration(days: 2)),
          pages: 30,
          minutes: 45,
        ),
      ],
    ),
    _book(
      '8',
      'Stalled Book Nobody Has Touched In A Very Long While',
      shelf: Shelf.inProgress,
      startedAt: DateTime(2025, 1, 1),
    ),
    _book('9', 'Next One', series: 'Stormlight', seriesNumber: 8),
  ]);
  return repository;
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2220);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Finder _vertical() => find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );

Future<void> _scrollAll(WidgetTester tester) async {
  final lists = _vertical();
  if (lists.evaluate().isEmpty) return;
  for (var i = 0; i < 8; i++) {
    await tester.drag(lists.first, const Offset(0, -500), warnIfMissed: false);
    await tester.pump();
  }
}

void main() {
  testWidgets('Library: goal, stalled books, quote and saved filters',
      (tester) async {
    _phone(tester);
    final repository = await _library();
    final settings = AppSettings();
    settings.setGoal(DateTime.now().year, 30);
    await tester.pumpWidget(MaterialApp(
      home: LibraryScreen(
        repository: repository,
        client: OpenLibraryClient(
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
        settings: settings,
        phoneSync: PhoneSync(repository: repository, settings: settings),
        fileIo: const FileIo(),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('goal: 10 of 30'), findsOneWidget);
    expect(find.textContaining('has not moved'), findsOneWidget);
    // The quote waits until the stalled book is dealt with.
    await tester.tap(find.text('Keep'));
    await tester.pump();
    expect(find.byTooltip('Hide for today (turn it off in Settings)'),
        findsOneWidget);
    await tester.tap(find.text('Saved filters'));
    await tester.pumpAndSettle();
    expect(find.text('Save these filters...'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('More: every new screen opens', (tester) async {
    _phone(tester);
    final repository = await _library();
    final settings = AppSettings();
    await tester.pumpWidget(MaterialApp(
      home: MoreScreen(
        repository: repository,
        settings: settings,
        phoneSync: PhoneSync(repository: repository, settings: settings),
        fileIo: const FileIo(),
      ),
    ));
    for (final entry in [
      'Series',
      'Tags',
      'Quotes and notes',
      'Library health',
      'Find duplicates',
    ]) {
      await tester.scrollUntilVisible(find.text(entry), 200);
      await tester.tap(find.text(entry));
      await tester.pumpAndSettle();
      if (entry == 'Quotes and notes') {
        await tester.enterText(find.byType(TextField), 'quote');
        await tester.pump();
      }
      await _scrollAll(tester);
      expect(tester.takeException(), isNull, reason: entry);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('book page: insights on the Reading tab', (tester) async {
    _phone(tester);
    final repository = await _library();
    await tester.pumpWidget(MaterialApp(
      home: BookDetailScreen(
        repository: repository,
        settings: AppSettings(),
        fileIo: const FileIo(),
        bookId: '7',
      ),
    ));
    await tester.pumpAndSettle();
    // A book in progress opens on the Reading tab.
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Suggest'),
      200,
      scrollable: _vertical().hitTestable().first,
    );
    expect(find.text('Suggest'), findsOneWidget);
    await tester.tap(find.text('Reading'));
    await tester.pumpAndSettle();
    await _scrollAll(tester);
    expect(find.text('Reading time'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Read next and Statistics', (tester) async {
    _phone(tester);
    final repository = await _library();
    final settings = AppSettings();
    settings.setGoal(DateTime.now().year, 30);
    await tester.pumpWidget(MaterialApp(
      home: ReadNextScreen(
        repository: repository,
        settings: settings,
        fileIo: const FileIo(),
      ),
    ));
    await tester.pumpAndSettle();
    await _scrollAll(tester);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(MaterialApp(
      home: StatisticsScreen(
        repository: repository,
        settings: settings,
        fileIo: const FileIo(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Your taste'),
      300,
      scrollable: _vertical().hitTestable().first,
    );
    expect(find.text('Your taste'), findsOneWidget);
    await _scrollAll(tester);
    expect(tester.takeException(), isNull);
  });
}
