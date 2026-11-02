import 'dart:convert';

import 'package:chapterly/audio/audio_bookmarks.dart';
import 'package:chapterly/audio/audio_library.dart';
import 'package:chapterly/audio/listen_controller.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/duplicates.dart';
import 'package:chapterly/data/sync_merge.dart';
import 'package:chapterly/data/sync_protocol.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/screens/now_playing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audio_test.dart' show FakeEngine, FakeFiles;

AudioBookmark _mark(int n, {String note = ''}) => AudioBookmark(
      track: 0,
      trackMs: n * 1000,
      positionMs: n * 1000,
      addedAt: DateTime(2026, 2, n),
      note: note,
    );

Book _book({List<AudioBookmark> marks = const []}) => Book(
      id: 'a',
      title: 'Dune',
      author: 'Frank Herbert',
      shelf: Shelf.inProgress,
      addedAt: DateTime(2026),
      audioBookmarks: marks,
      updatedAt: DateTime(2026, 1, 1),
    );

Future<BookRepository> _library() async {
  final repository = BookRepository(InMemoryBookStore());
  await repository.load();
  await repository.replaceAll([_book()]);
  return repository;
}

void main() {
  group('audiobook bookmarks on the phone', () {
    test('are kept with the book in order, edited and removed', () async {
      final repository = await _library();
      final before = repository.byId('a')!.updatedAt;
      await repository.addBookmark('a', _mark(9));
      await repository.addBookmark('a', _mark(2, note: 'Start'));
      expect(
        [for (final m in repository.bookmarksFor('a')) m.positionMs],
        [2000, 9000],
      );
      // A change to the book, so the next sync sends it.
      expect(repository.byId('a')!.updatedAt.isAfter(before), isTrue);
      await repository.setBookmarkNote('a', _mark(9), '  The twist ');
      expect(repository.bookmarksFor('a').last.note, 'The twist');
      await repository.removeBookmark('a', _mark(2));
      expect([for (final m in repository.bookmarksFor('a')) m.note],
          ['The twist']);
      expect(repository.bookmarksFor('missing'), isEmpty);
    });

    test('go through JSON (backups, sync) and the database', () {
      final book = _book(marks: [_mark(1, note: 'one'), _mark(2)]);
      final fromJson = Book.fromJson(
        jsonDecode(jsonEncode(book.toJson())) as Map<String, dynamic>,
      );
      expect([for (final m in fromJson.audioBookmarks) m.note], ['one', '']);
      final fromMap = Book.fromMap(book.toMap());
      expect(fromMap.audioBookmarks, hasLength(2));
      expect(fromMap.audioBookmarks.first.addedAt, DateTime(2026, 2, 1));
      // A book without bookmarks looks the same as before to an older app.
      expect(_book().toJson().containsKey('audioBookmarks'), isFalse);
      expect(_book().toMap()['audio_bookmarks'], isNull);
    });

    test('fields from a newer Chapterly are kept and sent back', () {
      final json = _book().toJson()
        ..['shelfColour'] = 'teal'
        ..['readAloud'] = {'voice': 'x'};
      final book = Book.fromJson(json);
      expect(book.extras, {'shelfColour': 'teal', 'readAloud': {'voice': 'x'}});
      expect(book.toJson()['shelfColour'], 'teal');
      // Kept in the database, and through an edit.
      final saved = Book.fromMap(book.toMap()).copyWith(rating: () => 4);
      expect(saved.toJson()['readAloud'], {'voice': 'x'});
      expect(saved.rating, 4);
    });

    test('a field kept in extras is used once this app knows it', () {
      final row = {
        ..._book().toMap(),
        'audio_bookmarks': null,
        'extras': jsonEncode({
          'audioBookmarks': [_mark(1).toJson()],
          'other': true,
        }),
      };
      final book = Book.fromMap(row);
      expect(book.audioBookmarks, hasLength(1));
      expect(book.extras, {'other': true});
      final added = book.copyWith(audioBookmarks: [_mark(1), _mark(2)]);
      expect((added.toJson()['audioBookmarks'] as List).length, 2);
    });

    test('merging duplicates keeps the bookmarks of both copies', () {
      final a = _book(marks: [_mark(1)]);
      final b = Book.fromJson({
        ..._book(marks: [_mark(1), _mark(2)]).toJson(),
        'id': 'b',
      });
      expect(mergeDuplicateGroup([a, b]).audioBookmarks, hasLength(2));
    });

    test('sync messages say the phone keeps bookmarks', () {
      final text = encodeSyncPayload([_book(marks: [_mark(1)])], const {});
      final payload = decodeSyncPayload(text);
      expect(payload.features, contains('audioBookmarks'));
      expect(payload.books.single.audioBookmarks, hasLength(1));
      // An older app sends no list of features.
      final old = jsonDecode(text) as Map<String, dynamic>..remove('features');
      expect(decodeSyncPayload(jsonEncode(old)).features, isEmpty);
    });

    test('the newer copy of a book brings its bookmarks', () {
      final phone = _book(marks: [_mark(1)]);
      final pc = _book(marks: [_mark(1), _mark(2, note: 'from the PC')])
          .copyWith(updatedAt: DateTime(2026, 3));
      final merged = mergeLibraries(
        local: [phone],
        localTombstones: const {},
        remote: [pc],
        remoteTombstones: const {},
      );
      expect(merged.books.single.audioBookmarks, hasLength(2));
    });
  });

  testWidgets('the player adds and lists bookmarks on a small phone',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2220);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repository = await _library();
    final library = AudioLibrary();
    final engine = FakeEngine(const [Duration(minutes: 10)]);
    final controller = ListenController(
      repository: repository,
      library: library,
      files: FakeFiles({}),
      engine: () => engine,
      saveEvery: const Duration(hours: 1),
    );
    AudioBookmarking.repository = repository;
    addTearDown(() => AudioBookmarking.repository = null);
    await tester.runAsync(() async {
      await library.setLink(
        'a',
        const AudioLink(tracks: [
          AudioTrack(location: 'a', name: 'Dune.m4b', lengthMs: 600000),
        ]),
      );
      await controller.open('a', autoplay: false);
      engine.position = const Duration(minutes: 3);
    });
    await tester.pumpWidget(
      MaterialApp(home: PlayerScreen(controller: controller)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Below the cover on a small phone: scroll to it.
    await tester.ensureVisible(find.text('Bookmark'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bookmark'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'The big reveal');
    await tester.tap(find.text('Add'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    final marks = repository.bookmarksFor('a');
    expect(marks.single.note, 'The big reveal');
    expect(marks.single.trackMs, 180000);

    // Let the "Bookmark added" message go away.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Bookmarks (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bookmarks (1)'));
    await tester.pumpAndSettle();
    expect(find.text('The big reveal'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(controller.close);
  });
}
