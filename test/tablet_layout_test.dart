import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/file_io.dart';
import 'package:chapterly/data/open_library_client.dart';
import 'package:chapterly/data/phone_sync.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/screens/book_detail_screen.dart';
import 'package:chapterly/screens/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<BookRepository> _library() async {
  final repository = BookRepository(InMemoryBookStore());
  await repository.load();
  await repository.replaceAll([
    for (var i = 1; i <= 30; i++)
      Book(
        id: 'b$i',
        title: 'Book number $i',
        author: 'Some Author',
        shelf: Shelf.forLater,
        tags: const ['history', 'war', 'biography', 'united states', 'politics',
            'military', 'twentieth century', 'non-fiction'],
        addedAt: DateTime(2026, 1, i),
        updatedAt: DateTime(2026, 1, 1),
      ),
  ]);
  return repository;
}

Future<void> _show(WidgetTester tester, Size size, BookRepository repository,
    AppSettings settings) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
}

void main() {
  testWidgets('on a tablet the book opens beside the list', (tester) async {
    final repository = await _library();
    final settings = AppSettings()..setShowTagsOnCards(true);
    await _show(tester, const Size(1280, 800), repository, settings);
    expect(find.text('Pick a book to see it here.'), findsOneWidget);

    await tester.tap(find.text('Book number 30'));
    await tester.pumpAndSettle();
    // Beside the list, not a page of its own: the list is still there.
    expect(find.byType(BookDetailScreen), findsOneWidget);
    expect(find.text('Book number 29'), findsOneWidget);
    expect(find.text('Pick a book to see it here.'), findsNothing);

    // Another book replaces it.
    await tester.tap(find.text('Book number 29'));
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailScreen), findsOneWidget);

    // Close shows the hint again.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a book to see it here.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a phone the book still opens as a page', (tester) async {
    final repository = await _library();
    final settings = AppSettings();
    await _show(tester, const Size(411, 891), repository, settings);
    expect(find.text('Pick a book to see it here.'), findsNothing);
    await tester.tap(find.text('Book number 30'));
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailScreen), findsOneWidget);
    expect(find.text('Book number 29'), findsNothing, reason: 'a page of its own');
  });

  testWidgets('a phone on its side tucks the filters away and keeps tags to '
      'one line', (tester) async {
    final repository = await _library();
    final settings = AppSettings()..setShowTagsOnCards(true);
    await _show(tester, const Size(800, 360), repository, settings);
    expect(find.text('Favorites'), findsNothing);
    await tester.tap(find.byTooltip('Show filters'));
    await tester.pump();
    expect(find.text('Favorites'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide filters'));
    await tester.pump();
    expect(find.text('Favorites'), findsNothing);
    // The long list of tags stays on one line.
    final tags = tester.widget<Text>(find.textContaining('history · war').first);
    expect(tags.maxLines, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an upright phone shows the filters as before', (tester) async {
    final repository = await _library();
    await _show(tester, const Size(411, 891), repository, AppSettings());
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.byTooltip('Show filters'), findsNothing);
  });
}
