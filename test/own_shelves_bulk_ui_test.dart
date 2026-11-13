import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/file_io.dart';
import 'package:chapterly/data/open_library_client.dart';
import 'package:chapterly/data/phone_sync.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/screens/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Book _book(String id, String title, List<String> shelves) => Book(
      id: id,
      title: title,
      author: 'Writer',
      shelf: Shelf.forLater,
      addedAt: DateTime(2026, 1, int.parse(id)),
      tags: const [],
      collections: shelves,
      updatedAt: DateTime(2026, 1, 1),
    );

Future<BookRepository> _open(WidgetTester tester) async {
  // Narrower than a tablet, so the book opens as a page of its own.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = BookRepository(InMemoryBookStore());
  await repository.load();
  await repository.replaceAll([
    _book('1', 'Alpha', ['Beach']),
    _book('2', 'Bravo', ['Beach']),
    _book('3', 'Charlie', ['Gifts']),
  ]);
  final settings = AppSettings();
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
  return repository;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('on a shelf of your own, More can move or remove books',
      (tester) async {
    final repository = await _open(tester);

    // The shelf tabs scroll sideways; bring it into view first.
    await tester.ensureVisible(find.textContaining('Beach ('));
    await tester.pump();
    await tester.tap(find.textContaining('Beach ('));
    await _settle(tester);
    await tester.longPress(find.text('Alpha').first);
    await _settle(tester);
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('More'));
    await _settle(tester);
    expect(find.text('Move to another shelf of mine'), findsOneWidget);
    expect(find.text('Remove from Beach'), findsOneWidget);

    await tester.tap(find.text('Remove from Beach'));
    await _settle(tester);
    expect(repository.byId('1')!.collections, isEmpty);
    expect(repository.byId('2')!.collections, ['Beach']);
    expect(find.textContaining('Took 1 book off Beach'), findsOneWidget);

    // Undo puts the book back on the shelf.
    await tester.tap(find.text('Undo'));
    await _settle(tester);
    expect(repository.byId('1')!.collections, ['Beach']);
  });

  testWidgets('moving books to another of your shelves', (tester) async {
    final repository = await _open(tester);

    // The shelf tabs scroll sideways; bring it into view first.
    await tester.ensureVisible(find.textContaining('Beach ('));
    await tester.pump();
    await tester.tap(find.textContaining('Beach ('));
    await _settle(tester);
    await tester.longPress(find.text('Alpha').first);
    await _settle(tester);
    await tester.tap(find.byTooltip('More'));
    await _settle(tester);
    await tester.tap(find.text('Move to another shelf of mine'));
    await _settle(tester);

    // The shelf you are on is not offered.
    expect(find.text('Gifts'), findsOneWidget);
    expect(find.text('Beach'), findsNothing);
    await tester.tap(find.text('Gifts'));
    await _settle(tester);

    expect(repository.byId('1')!.collections, ['Gifts']);
    expect(repository.byId('2')!.collections, ['Beach']);
    expect(find.textContaining('from Beach to Gifts'), findsOneWidget);
  });

  testWidgets('on a main shelf, More has no shelf moves', (tester) async {
    await _open(tester);

    await tester.tap(find.textContaining('For later ('));
    await _settle(tester);
    await tester.longPress(find.text('Alpha').first);
    await _settle(tester);
    await tester.tap(find.byTooltip('More'));
    await _settle(tester);

    expect(find.text('Change format'), findsOneWidget);
    expect(find.text('Move to another shelf of mine'), findsNothing);
    expect(find.textContaining('Remove from'), findsNothing);
  });
}
