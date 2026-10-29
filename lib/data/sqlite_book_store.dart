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
      previous_readings TEXT
    )
  ''';

  static Future<SqliteBookStore> open() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'chapterly.db'),
      version: 4,
      onCreate: (db, version) => db.execute(_createBooksTable),
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
      },
    );
    return SqliteBookStore._(db);
  }

  @override
  Future<List<Book>> loadAll() async {
    final rows = await _db.query('books', orderBy: 'added_at DESC');
    return rows.map(Book.fromMap).toList();
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
    final batch = _db.batch();
    for (final book in books) {
      batch.insert(
        'books',
        book.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> replaceAll(List<Book> books) async {
    await _db.transaction((txn) async {
      await txn.delete('books');
      final batch = txn.batch();
      for (final book in books) {
        batch.insert('books', book.toMap());
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> remove(String id) async {
    await _db.delete('books', where: 'id = ?', whereArgs: [id]);
  }
}
