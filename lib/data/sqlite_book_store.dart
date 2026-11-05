import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/book.dart';
import 'book_store.dart';

/// Saves books in a SQLite database file on the phone.
class SqliteBookStore implements BookStore {
  SqliteBookStore._(this._db);

  final Database _db;

  static const _createBooksTable = '''
    CREATE TABLE books (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      author TEXT NOT NULL,
      shelf TEXT NOT NULL,
      added_at INTEGER NOT NULL,
      tags TEXT NOT NULL,
      isbn TEXT,
      cover_url TEXT,
      first_publish_year INTEGER,
      pages INTEGER,
      rating INTEGER,
      started_at INTEGER,
      finished_at INTEGER,
      format TEXT,
      favorite INTEGER NOT NULL DEFAULT 0,
      notes TEXT,
      deleted_at INTEGER,
      cover_path TEXT,
      series TEXT,
      series_number INTEGER,
      reading_log TEXT,
      previous_readings TEXT,
      updated_at INTEGER,
      collections TEXT,
      quotes TEXT,
      current_page INTEGER,
      aspect_ratings TEXT,
      priority TEXT,
      buy_at TEXT,
      queue_position INTEGER,
      audio TEXT,
      audio_bookmarks TEXT,
      extras TEXT
    )
  ''';

  static const _createTombstonesTable = '''
    CREATE TABLE tombstones (
      id TEXT PRIMARY KEY,
      deleted_at INTEGER NOT NULL
    )
  ''';

  /// Opens a profile's database. The first profile's is chapterly.db.
  static Future<SqliteBookStore> open({
    String fileName = 'chapterly.db',
  }) async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, fileName),
      version: 10,
      onCreate: (db, version) async {
        await db.execute(_createBooksTable);
        await db.execute(_createTombstonesTable);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Version 2 added pages, rating and reading dates.
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE books ADD COLUMN pages INTEGER');
          await db.execute('ALTER TABLE books ADD COLUMN rating INTEGER');
          await db.execute('ALTER TABLE books ADD COLUMN started_at INTEGER');
          await db.execute('ALTER TABLE books ADD COLUMN finished_at INTEGER');
        }
        // Version 3 added format, favorites, notes, trash, custom covers,
        // the reading log and earlier readings.
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE books ADD COLUMN format TEXT');
          await db.execute(
            'ALTER TABLE books ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute('ALTER TABLE books ADD COLUMN notes TEXT');
          await db.execute('ALTER TABLE books ADD COLUMN deleted_at INTEGER');
          await db.execute('ALTER TABLE books ADD COLUMN cover_path TEXT');
          await db.execute('ALTER TABLE books ADD COLUMN reading_log TEXT');
          await db.execute(
            'ALTER TABLE books ADD COLUMN previous_readings TEXT',
          );
        }
        // Version 4 added series.
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE books ADD COLUMN series TEXT');
          await db.execute(
            'ALTER TABLE books ADD COLUMN series_number INTEGER',
          );
        }
        // Version 5 added the last-changed time (for sync) and the list of
        // permanently deleted books.
        if (oldVersion < 5) {
          await db.execute('ALTER TABLE books ADD COLUMN updated_at INTEGER');
          await db.execute(
            'UPDATE books SET updated_at = added_at WHERE updated_at IS NULL',
          );
          await db.execute(_createTombstonesTable);
        }
        // Version 6 added your own shelves and saved quotes.
        if (oldVersion < 6) {
          await db.execute('ALTER TABLE books ADD COLUMN collections TEXT');
          await db.execute('ALTER TABLE books ADD COLUMN quotes TEXT');
        }
        // Version 7 added the current page and ratings for parts of a book.
        if (oldVersion < 7) {
          await db.execute(
            'ALTER TABLE books ADD COLUMN current_page INTEGER',
          );
          await db.execute('ALTER TABLE books ADD COLUMN aspect_ratings TEXT');
        }
        // Version 8 added the wishlist details: priority, where to buy and
        // the place in the Next up order.
        if (oldVersion < 8) {
          await db.execute('ALTER TABLE books ADD COLUMN priority TEXT');
          await db.execute('ALTER TABLE books ADD COLUMN buy_at TEXT');
          await db.execute(
            'ALTER TABLE books ADD COLUMN queue_position INTEGER',
          );
        }
        // Version 9 added where you are in the audiobook.
        if (oldVersion < 9) {
          await db.execute('ALTER TABLE books ADD COLUMN audio TEXT');
        }
        // Version 10 added audiobook bookmarks (synced with the PC) and
        // book fields from a newer Chapterly that this app does not know.
        if (oldVersion < 10) {
          await db.execute(
            'ALTER TABLE books ADD COLUMN audio_bookmarks TEXT',
          );
          await db.execute('ALTER TABLE books ADD COLUMN extras TEXT');
        }
      },
    );
    return SqliteBookStore._(db);
  }

  /// Books are read and written a few at a time. A cover picture is kept in
  /// its book as text of tens of kilobytes, and a library of a thousand books
  /// read in one go is more than Android lets the app hold at once: Chapterly
  /// stopped on start.
  static const _chunk = 10;

  @override
  Future<List<Book>> loadAll() async {
    final books = <Book>[];
    var after = 0;
    while (true) {
      final rows = await _db.rawQuery(
        'SELECT rowid AS rid, * FROM books WHERE rowid > ? '
        'ORDER BY rowid LIMIT ?',
        [after, _chunk],
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        final map = Map<String, Object?>.of(row);
        after = map.remove('rid') as int;
        books.add(Book.fromMap(map));
      }
    }
    books.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return books;
  }

  /// Writes [books] a few to a batch, so no message to the database is huge.
  Future<void> _insertAll(DatabaseExecutor db, List<Book> books) async {
    for (var i = 0; i < books.length; i += _chunk) {
      final batch = db.batch();
      for (final book in books.skip(i).take(_chunk)) {
        // Two books with one id (a damaged backup) can't stop the write: the
        // later one is kept.
        batch.insert(
          'books',
          book.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    }
  }

  @override
  Future<void> save(Book book) async {
    await _db.insert(
      'books',
      book.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> saveAll(List<Book> books) async {
    await _db.transaction((txn) => _insertAll(txn, books));
  }

  @override
  Future<void> replaceAll(List<Book> books) async {
    await _db.transaction((txn) async {
      await txn.delete('books');
      await _insertAll(txn, books);
    });
  }

  @override
  Future<void> remove(String id) async {
    await _db.delete('books', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<Map<String, DateTime>> loadTombstones() async {
    final rows = await _db.query('tombstones');
    return {
      for (final row in rows)
        row['id'] as String: DateTime.fromMillisecondsSinceEpoch(
          row['deleted_at'] as int,
        ),
    };
  }

  @override
  Future<void> saveTombstones(Map<String, DateTime> tombstones) async {
    await _db.transaction((txn) async {
      await txn.delete('tombstones');
      final batch = txn.batch();
      for (final entry in tombstones.entries) {
        batch.insert('tombstones', {
          'id': entry.key,
          'deleted_at': entry.value.millisecondsSinceEpoch,
        });
      }
      await batch.commit(noResult: true);
    });
  }
}
