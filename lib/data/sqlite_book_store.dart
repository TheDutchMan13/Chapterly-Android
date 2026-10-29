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
      finished_at INTEGER
    )
  ''';

  static Future<SqliteBookStore> open() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'chapterly.db'),
      version: 2,
      onCreate: (db, version) => db.execute(_createBooksTable),
      onUpgrade: (db, oldVersion, newVersion) async {
        // Version 2 added pages, rating and reading dates.
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE books ADD COLUMN pages INTEGER');
          await db.execute('ALTER TABLE books ADD COLUMN rating INTEGER');
          await db.execute('ALTER TABLE books ADD COLUMN started_at INTEGER');
          await db.execute('ALTER TABLE books ADD COLUMN finished_at INTEGER');
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
