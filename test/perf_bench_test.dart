// Timings on a big library. Prints "BENCH ..." lines; asserts nothing.
// Run: flutter test test/perf_bench_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/duplicates.dart';
import 'package:chapterly/data/series.dart';
import 'package:chapterly/data/statistics.dart';
import 'package:chapterly/data/sync_covers.dart';
import 'package:chapterly/data/sync_merge.dart';
import 'package:chapterly/data/sync_protocol.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/reading.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

const _surnames = [
  'Smith', 'King', 'Martin', 'Brown', 'Jones', 'Miller', 'Davis', 'Wilson',
  'Taylor', 'Moore', 'Anderson', 'Thomas', 'Jackson', 'White', 'Harris',
  'Clark', 'Lewis', 'Walker', 'Hall', 'Allen', 'Young', 'Hill', 'Wright',
];
const _first = [
  'Anna', 'Ben', 'Clara', 'David', 'Elena', 'Frank', 'Grace', 'Henry', 'Iris',
  'Jack', 'Kate', 'Liam', 'Maya', 'Noah', 'Olive', 'Paul', 'Quinn', 'Rose',
];
const _words = [
  'Dragon', 'Winter', 'Garden', 'Shadow', 'River', 'Empire', 'Silent', 'Last',
  'Crown', 'Night', 'Ocean', 'Iron', 'Glass', 'Storm', 'Forgotten', 'Road',
  'Kingdom', 'Memory', 'Fire', 'Harvest', 'Signal', 'Orbit', 'Letters', 'Salt',
];

Book _book(int i, Random random, {required bool covers}) {
  final surname = i % 3 == 0
      ? _surnames[random.nextInt(_surnames.length)]
      : 'Writer${random.nextInt(1800)}';
  final author = '${_first[random.nextInt(_first.length)]} $surname';
  final title = '${_words[random.nextInt(_words.length)]} of the '
      '${_words[random.nextInt(_words.length)]} $i';
  final finished = random.nextInt(10) < 6;
  final added = DateTime(2020).add(Duration(days: random.nextInt(2500)));
  final inSeries = random.nextInt(4) == 0;
  return Book(
    id: 'book$i',
    title: title,
    author: author,
    shelf: finished
        ? Shelf.finished
        : (random.nextInt(8) == 0 ? Shelf.inProgress : Shelf.forLater),
    addedAt: added,
    tags: [for (var t = 0; t < random.nextInt(4); t++) 'tag${random.nextInt(40)}'],
    isbn: '97800000${(10000 + i).toString()}',
    coverUrl: covers && random.nextInt(10) < 9 ? _cover(random) : null,
    firstPublishYear: 1950 + random.nextInt(75),
    pages: 150 + random.nextInt(700),
    rating: finished ? 1 + random.nextInt(5) : null,
    startedAt: finished ? added : null,
    finishedAt: finished ? added.add(Duration(days: 3 + random.nextInt(40))) : null,
    notes: random.nextInt(5) == 0 ? 'A note about $title. ' * 8 : null,
    series: inSeries ? 'Series ${i ~/ 6}' : null,
    seriesNumber: inSeries ? 1 + i % 6 : null,
    previousReadings: random.nextInt(12) == 0
        ? [Reading(finishedAt: added.add(const Duration(days: 400)))]
        : const [],
    updatedAt: added,
  );
}

/// A picture of about [bytes] bytes that doesn't compress, like a JPEG.
String _cover(Random random, {int bytes = 40 * 1024}) {
  final data = Uint8List(bytes);
  for (var i = 0; i < bytes; i++) {
    data[i] = random.nextInt(256);
  }
  return 'data:image/jpeg;base64,${base64Encode(data)}';
}

final _lines = <String>[];

T _time<T>(String name, T Function() fn, {int runs = 3}) {
  final times = <int>[];
  late T result;
  for (var i = 0; i < runs; i++) {
    final watch = Stopwatch()..start();
    result = fn();
    watch.stop();
    times.add(watch.elapsedMicroseconds);
  }
  times.sort();
  final line = 'BENCH ${name.padRight(46)} ${(times[times.length ~/ 2] / 1000).toStringAsFixed(1).padLeft(9)} ms';
  _lines.add(line);
  // ignore: avoid_print
  print(line);
  return result;
}

void _say(String text) {
  _lines.add('BENCH $text');
  // ignore: avoid_print
  print('BENCH $text');
}

int _mb(int bytes) => (bytes / (1024 * 1024)).round();

void main() {
  for (final covers in [true, false]) {
    for (final count in covers ? [1000, 5000] : [5000]) {
      test('library of $count books ${covers ? 'with' : 'without'} covers',
          () async {
        _say('---- $count books, ${covers ? 'covers about 55 KB each' : 'no covers'}');
        final random = Random(7);
        final rssBefore = ProcessInfo.currentRss;
        final books = _time(
          'make the books',
          () => [for (var i = 0; i < count; i++) _book(i, random, covers: covers)],
          runs: 1,
        );
        final store = InMemoryBookStore();
        final apart = Stopwatch()..start();
        await store.replaceAll(books);
        apart.stop();
        _say('${'first open: move covers out (one time)'.padRight(46)} ${(apart.elapsedMicroseconds / 1000).toStringAsFixed(1).padLeft(9)} ms');
        final repository = BookRepository(store);
        final watch = Stopwatch()..start();
        await repository.load();
        watch.stop();
        _say('${'repository.load()'.padRight(46)} ${(watch.elapsedMicroseconds / 1000).toStringAsFixed(1).padLeft(9)} ms');
        final held = repository.allBooks
            .fold<int>(0, (sum, b) => sum + (b.coverUrl?.length ?? 0));
        _say('cover text held by the library in memory        ${(held / 1024).round().toString().padLeft(9)} KB');
        _say('(RSS growth, includes the test store)           ${_mb(ProcessInfo.currentRss - rssBefore).toString().padLeft(9)} MB');
        if (covers) {
          final ref = repository.allBooks.firstWhere((b) => b.coverUrl != null).coverUrl!;
          _say('one cover in a book now: "$ref"');
        }

        // What a library or database save or load touches.
        final maps = _time('Book.toMap for every book', () => [for (final b in books) b.toMap()]);
        _time('Book.fromMap for every book', () => [for (final m in maps) Book.fromMap(m)]);

        // Screens.
        _time('library shelf: booksOn(finished)', () => repository.booksOn(Shelf.finished));
        _time('search: booksOn(finished, "dragon")',
            () => repository.booksOn(Shelf.finished, query: 'dragon'));
        _time('search with a typo: "drgaon"',
            () => repository.booksOn(Shelf.finished, query: 'drgaon'));
        _time('search an author: "smith"',
            () => repository.booksOn(Shelf.forLater, query: 'smith'));
        _time('allTags', () => repository.allTags);
        _time('repository.books (live copy)', () => repository.books);
        _time('Statistics: computeStats(all)', () => computeStats(repository.books));
        _time('Statistics: computeStats(2024)', () => computeStats(repository.books, year: 2024));
        _time('Series: seriesOverview', () => seriesOverview(repository.allBooks));
        _time('Duplicates: exact', () => repository.findDuplicates());
        _time('Duplicates: possible (near matches)',
            () => findPossibleDuplicates(repository.books), runs: 1);
        _time('Duplicates: possible, asked again (kept)',
            () => repository.possibleDuplicates());

        // Sync.
        late String payload;
        _time('sync: snapshot + encodeSyncPayload (no refs)', () {
          final snap = repository.snapshot();
          payload = encodeSyncPayload(snap.books, snap.tombstones);
          return payload;
        }, runs: 1);
        _say('payload size with covers inline                 ${_mb(payload.length).toString().padLeft(9)} MB');
        _time('sync: decodeSyncPayload', () => decodeSyncPayload(payload), runs: 1);
        final pool = CoverPool();
        final refs = _time('sync: withCoverRefs (hash every cover)',
            () => withCoverRefs(repository.snapshot().books, CoverPool()),
            runs: 1);
        withCoverRefs(repository.snapshot().books, pool);
        final refPayload = encodeSyncPayload(refs, const {});
        _say('payload size with cover references              ${(refPayload.length / 1024).round().toString().padLeft(9)} KB');
        _time('sync: mergeLibraries (same library both sides)', () {
          final snap = repository.snapshot();
          return mergeLibraries(
            local: snap.books,
            localTombstones: snap.tombstones,
            remote: snap.books,
            remoteTombstones: snap.tombstones,
          );
        });
      });
    }
  }

  tearDownAll(() {
    // ignore: avoid_print
    print('\n===== BENCH SUMMARY =====\n${_lines.join('\n')}');
  });
}
