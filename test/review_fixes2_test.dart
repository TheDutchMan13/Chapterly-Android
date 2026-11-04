import 'dart:convert';
import 'dart:io';

import 'package:chapterly/audio/audio_library.dart';
import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/auto_backup.dart';
import 'package:chapterly/data/backup.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/pin_lock.dart';
import 'package:chapterly/ebook/ebook_library.dart';
import 'package:chapterly/home/home_bridge.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Book _book(String id, {String title = 'Title', DateTime? updated}) => Book(
      id: id,
      title: title,
      author: 'Author',
      shelf: Shelf.forLater,
      addedAt: DateTime(2026),
      updatedAt: updated,
    );

EbookLink _link(String name) => EbookLink(
      path: '/books/$name',
      name: name,
      bytes: 100,
      format: EbookFormat.epub,
      addedAt: DateTime(2026),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('chapterly_fixes2_');
  });

  tearDown(() async {
    autoBackupPrivateFolder = null;
    await dir.delete(recursive: true);
  });

  group('the reader and audiobook lists', () {
    test('quick saves that nobody waits for all land, in order', () async {
      final file = File('${dir.path}/ebook_library.json');
      final library = await EbookLibrary.load(file);
      final saves = [
        for (final name in ['a', 'b', 'c', 'd', 'e'])
          library.setLink(name, _link('$name.epub')),
      ];
      await Future.wait(saves);
      final again = await EbookLibrary.load(file);
      expect(again.links.keys.toSet(), {'a', 'b', 'c', 'd', 'e'});
      expect(File('${file.path}.tmp').existsSync(), isFalse);
    });

    test('a damaged list is kept aside, not written over', () async {
      final file = File('${dir.path}/ebook_library.json');
      await file.writeAsString('{"links": {"a": ');
      final library = await EbookLibrary.load(file);
      expect(library.links, isEmpty);
      expect(File('${file.path}.bad').readAsStringSync(), '{"links": {"a": ');
      await library.setLink('b', _link('b.epub'));
      expect(File('${file.path}.bad').existsSync(), isTrue);
    });

    test('the audiobook list saves the same careful way', () async {
      final file = File('${dir.path}/audio_library.json');
      final library = await AudioLibrary.load(file);
      const link = AudioLink(
        tracks: [AudioTrack(location: 'x', name: 'Book.m4b', lengthMs: 1000)],
      );
      await Future.wait([
        library.setLink('a', link),
        library.setLink('b', link),
        library.setSpeed(1.25),
      ]);
      final again = await AudioLibrary.load(file);
      expect(again.hasAudio('a') && again.hasAudio('b'), isTrue);
      expect(again.speed, 1.25);

      await file.writeAsString('not json');
      expect((await AudioLibrary.load(file)).hasAudio('a'), isFalse);
      expect(File('${file.path}.bad').existsSync(), isTrue);
    });
  });

  test('a profile with a PIN keeps its automatic backups private', () async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    await repository.add(title: 'Dune', author: 'A', shelf: Shelf.forLater);
    final settings = AppSettings()..setPin('1234');
    autoBackupPrivateFolder = Directory('${dir.path}/private');
    await runAutoBackup(repository, settings, force: true);
    expect(settings.lastAutoBackupError, isNull);
    expect(settings.lastAutoBackupPath, startsWith('${dir.path}/private/'));
  });

  test('moving the clock forward does not end a wait for wrong PINs', () {
    var now = DateTime(2026, 11, 4, 12);
    var up = 0;
    final guard = PinGuard(
      null,
      clock: () => now,
      uptime: () => up,
      uptimeKind: 'boot',
    );
    bool right(String pin) => pin == '1234';
    for (var i = 0; i < 5; i++) {
      guard.attempt('0000', right);
    }
    expect(guard.waitLeft(), const Duration(seconds: 30));
    now = now.add(const Duration(days: 1));
    expect(guard.waitLeft(), const Duration(seconds: 30));
    expect(guard.attempt('1234', right), isFalse);
    up += 31000;
    expect(guard.waitLeft(), Duration.zero);
    expect(guard.attempt('1234', right), isTrue);
  });

  group('backups', () {
    test('two books with one id: the one changed last is kept', () {
      final text = encodeBackup([
        _book('1', title: 'Old', updated: DateTime(2026, 1, 1)),
        _book('1', title: 'New', updated: DateTime(2026, 2, 1)),
        _book('2', title: 'Other'),
      ]);
      final books = decodeBackup(text);
      expect(books.map((b) => b.title), ['New', 'Other']);
    });

    test('restoring marks the books it removes as removed for good',
        () async {
      final repo = BookRepository(InMemoryBookStore());
      await repo.load();
      final keep = await repo.add(
        title: 'Keep',
        author: 'A',
        shelf: Shelf.forLater,
      );
      final gone = await repo.add(
        title: 'Gone',
        author: 'A',
        shelf: Shelf.forLater,
      );
      final kept = repo.byId(keep)!;
      await repo.restoreBackup([kept, kept]);
      expect(repo.books.map((b) => b.id), [keep]);
      final tombstones = repo.snapshot().tombstones;
      expect(tombstones.keys, contains(gone));
      expect(tombstones.keys, isNot(contains(keep)));
    });

    test('the library on the phone changes only once the new one is saved',
        () async {
      final repo = BookRepository(_FailingStore());
      await repo.load();
      await repo.add(title: 'Mine', author: 'A', shelf: Shelf.forLater);
      await expectLater(
        repo.replaceAll([_book('x', title: 'Theirs')]),
        throwsA(isA<StateError>()),
      );
      expect(repo.books.map((b) => b.title), ['Mine']);
    });
  });

  test('with the app lock on, the home-screen widget names no book',
      () async {
    const channel = MethodChannel('chapterly/home');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'takeToggle' ? false : null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    await repository.add(
      title: 'Secret diary',
      author: 'Me',
      shelf: Shelf.inProgress,
    );
    final settings = AppSettings()..setPin('1234');
    final bridge = HomeBridge(
      repository: repository,
      settings: settings,
      wait: const Duration(milliseconds: 1),
    );
    await bridge.start();
    final sent = calls.firstWhere((c) => c.method == 'updateWidget');
    final arguments = sent.arguments as Map;
    expect(arguments['title'], 'Chapterly');
    expect(jsonEncode(arguments), isNot(contains('Secret')));
    expect(arguments['author'], '');
    bridge.dispose();
  });
}

/// A store whose replaceAll fails, like a full disk.
class _FailingStore extends InMemoryBookStore {
  @override
  Future<void> replaceAll(List<Book> books) async {
    throw StateError('disk full');
  }
}
