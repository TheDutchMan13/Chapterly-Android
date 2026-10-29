import 'dart:convert';

import 'book_format.dart';
import 'quote.dart';
import 'reading.dart';
import 'shelf.dart';

int _idSequence = 0;

/// A new id that is unique even when several books are added in the same
/// microsecond (which can happen on Windows and in tests).
String newBookId() {
  _idSequence++;
  return '${DateTime.now().microsecondsSinceEpoch}-$_idSequence';
}

DateTime? _dateFromMillis(Object? value) =>
    value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;

DateTime? _dateFromIso(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

BookFormat? _formatFromName(Object? value) =>
    value is String ? BookFormat.values.asNameMap()[value] : null;

List<String> _stringList(Object? value) =>
    value is List ? [for (final item in value) item.toString()] : const [];

Object? _decode(Object? text) => text is String ? jsonDecode(text) : null;

class Book {
  Book({
    required this.id,
    required this.title,
    required this.author,
    required this.shelf,
    required this.addedAt,
    this.tags = const [],
    this.isbn,
    this.coverUrl,
    this.firstPublishYear,
    this.pages,
    this.rating,
    this.startedAt,
    this.finishedAt,
    this.format,
    this.favorite = false,
    this.notes,
    this.deletedAt,
    this.coverPath,
    this.series,
    this.seriesNumber,
    this.readingLog = const [],
    this.previousReadings = const [],
    this.collections = const [],
    this.quotes = const [],
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? addedAt;

  final String id;

  /// When this book last changed. Used to merge changes made on two devices:
  /// the newer copy wins.
  final DateTime updatedAt;
  final String title;
  final String author;
  final Shelf shelf;
  final DateTime addedAt;
  final List<String> tags;
  final String? isbn;
  final String? coverUrl;
  final int? firstPublishYear;
  final int? pages;
  final BookFormat? format;
  final bool favorite;
  final String? notes;

  /// Set when the book is in the trash.
  final DateTime? deletedAt;

  /// A cover picked from the phone. Wins over [coverUrl] when set.
  final String? coverPath;

  /// The series this book belongs to, and its place in it (1, 2, 3...).
  final String? series;
  final int? seriesNumber;

  /// The current reading: 1 to 5 stars (or null), dates, and pages logged.
  final int? rating;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final List<LogEntry> readingLog;

  /// Earlier readings, oldest first. Each one counts as a finished read.
  final List<Reading> previousReadings;

  /// Your own shelves (for example "Book club") this book is on, as well as
  /// its reading shelf.
  final List<String> collections;

  /// Passages saved from this book.
  final List<Quote> quotes;

  Reading get currentReading => Reading(
        startedAt: startedAt,
        finishedAt: finishedAt,
        rating: rating,
        log: readingLog,
      );

  /// Every time this book has been finished, for statistics.
  List<Reading> get finishedReadings => [
        ...previousReadings,
        if (shelf == Shelf.finished) currentReading,
      ];

  /// Fields that can be cleared take a function so that `() => null` means
  /// "clear it" while leaving the argument out means "keep it".
  Book copyWith({
    Shelf? shelf,
    List<String>? tags,
    bool? favorite,
    List<LogEntry>? readingLog,
    List<Reading>? previousReadings,
    List<String>? collections,
    List<Quote>? quotes,
    String? Function()? isbn,
    String? Function()? coverUrl,
    int? Function()? firstPublishYear,
    BookFormat? Function()? format,
    String? Function()? notes,
    String? Function()? coverPath,
    String? Function()? series,
    int? Function()? seriesNumber,
    DateTime? Function()? deletedAt,
    int? Function()? pages,
    int? Function()? rating,
    DateTime? Function()? startedAt,
    DateTime? Function()? finishedAt,
    DateTime? updatedAt,
  }) =>
      Book(
        id: id,
        title: title,
        author: author,
        shelf: shelf ?? this.shelf,
        addedAt: addedAt,
        tags: tags ?? this.tags,
        isbn: isbn != null ? isbn() : this.isbn,
        coverUrl: coverUrl != null ? coverUrl() : this.coverUrl,
        firstPublishYear: firstPublishYear != null
            ? firstPublishYear()
            : this.firstPublishYear,
        pages: pages != null ? pages() : this.pages,
        rating: rating != null ? rating() : this.rating,
        startedAt: startedAt != null ? startedAt() : this.startedAt,
        finishedAt: finishedAt != null ? finishedAt() : this.finishedAt,
        format: format != null ? format() : this.format,
        favorite: favorite ?? this.favorite,
        notes: notes != null ? notes() : this.notes,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
        coverPath: coverPath != null ? coverPath() : this.coverPath,
        series: series != null ? series() : this.series,
        seriesNumber:
            seriesNumber != null ? seriesNumber() : this.seriesNumber,
        readingLog: readingLog ?? this.readingLog,
        previousReadings: previousReadings ?? this.previousReadings,
        collections: collections ?? this.collections,
        quotes: quotes ?? this.quotes,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Column values for the SQLite `books` table.
  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'author': author,
        'shelf': shelf.name,
        'added_at': addedAt.millisecondsSinceEpoch,
        'tags': jsonEncode(tags),
        'isbn': isbn,
        'cover_url': coverUrl,
        'first_publish_year': firstPublishYear,
        'pages': pages,
        'rating': rating,
        'started_at': startedAt?.millisecondsSinceEpoch,
        'finished_at': finishedAt?.millisecondsSinceEpoch,
        'format': format?.name,
        'favorite': favorite ? 1 : 0,
        'notes': notes,
        'deleted_at': deletedAt?.millisecondsSinceEpoch,
        'cover_path': coverPath,
        'series': series,
        'series_number': seriesNumber,
        'reading_log': jsonEncode([for (final e in readingLog) e.toJson()]),
        'previous_readings':
            jsonEncode([for (final r in previousReadings) r.toJson()]),
        'collections': jsonEncode(collections),
        'quotes': jsonEncode([for (final q in quotes) q.toJson()]),
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Book.fromMap(Map<String, Object?> map) => Book(
        id: map['id'] as String,
        title: map['title'] as String,
        author: map['author'] as String,
        shelf: Shelf.values.byName(map['shelf'] as String),
        addedAt: DateTime.fromMillisecondsSinceEpoch(map['added_at'] as int),
        tags: List<String>.from(jsonDecode(map['tags'] as String) as List),
        isbn: map['isbn'] as String?,
        coverUrl: map['cover_url'] as String?,
        firstPublishYear: map['first_publish_year'] as int?,
        pages: map['pages'] as int?,
        rating: map['rating'] as int?,
        startedAt: _dateFromMillis(map['started_at']),
        finishedAt: _dateFromMillis(map['finished_at']),
        format: _formatFromName(map['format']),
        favorite: map['favorite'] == 1,
        notes: map['notes'] as String?,
        deletedAt: _dateFromMillis(map['deleted_at']),
        coverPath: map['cover_path'] as String?,
        series: map['series'] as String?,
        seriesNumber: map['series_number'] as int?,
        readingLog: logEntriesFromJson(_decode(map['reading_log'])),
        previousReadings: readingsFromJson(_decode(map['previous_readings'])),
        collections: _stringList(_decode(map['collections'])),
        quotes: quotesFromJson(_decode(map['quotes'])),
        updatedAt: _dateFromMillis(map['updated_at']),
      );

  /// Readable JSON used in backup files. Custom covers from the phone are not
  /// included, because they are files on this phone.
  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'shelf': shelf.name,
        'addedAt': addedAt.toIso8601String(),
        'tags': tags,
        'isbn': isbn,
        'coverUrl': coverUrl,
        'firstPublishYear': firstPublishYear,
        'pages': pages,
        'rating': rating,
        'startedAt': startedAt?.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'format': format?.name,
        'favorite': favorite,
        'notes': notes,
        'deletedAt': deletedAt?.toIso8601String(),
        'series': series,
        'seriesNumber': seriesNumber,
        'readingLog': [for (final e in readingLog) e.toJson()],
        'previousReadings': [for (final r in previousReadings) r.toJson()],
        'collections': collections,
        'quotes': [for (final q in quotes) q.toJson()],
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Book.fromJson(Map<String, dynamic> json) => Book(
        id: json['id'] as String,
        title: json['title'] as String,
        author: (json['author'] as String?) ?? '',
        shelf: Shelf.values.asNameMap()[json['shelf']] ?? Shelf.forLater,
        addedAt: _dateFromIso(json['addedAt']) ?? DateTime.now(),
        tags: [
          for (final tag in (json['tags'] as List? ?? const [])) tag.toString(),
        ],
        isbn: json['isbn'] as String?,
        coverUrl: json['coverUrl'] as String?,
        firstPublishYear: json['firstPublishYear'] as int?,
        pages: json['pages'] as int?,
        rating: json['rating'] as int?,
        startedAt: _dateFromIso(json['startedAt']),
        finishedAt: _dateFromIso(json['finishedAt']),
        format: _formatFromName(json['format']),
        favorite: json['favorite'] == true,
        notes: json['notes'] as String?,
        deletedAt: _dateFromIso(json['deletedAt']),
        series: json['series'] as String?,
        seriesNumber: json['seriesNumber'] as int?,
        readingLog: logEntriesFromJson(json['readingLog']),
        previousReadings: readingsFromJson(json['previousReadings']),
        collections: _stringList(json['collections']),
        quotes: quotesFromJson(json['quotes']),
        updatedAt: _dateFromIso(json['updatedAt']),
      );
}
