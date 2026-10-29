import 'dart:convert';

import 'shelf.dart';

DateTime? _dateFromMillis(Object? value) =>
    value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;

DateTime? _dateFromIso(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

class Book {
  const Book({
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
  });

  final String id;
  final String title;
  final String author;
  final Shelf shelf;
  final DateTime addedAt;
  final List<String> tags;
  final String? isbn;
  final String? coverUrl;
  final int? firstPublishYear;
  final int? pages;

  /// 1 to 5 stars, or null when not rated.
  final int? rating;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  /// Fields that can be cleared take a function so that `() => null` means
  /// "clear it" while leaving the argument out means "keep it".
  Book copyWith({
    Shelf? shelf,
    List<String>? tags,
    int? Function()? pages,
    int? Function()? rating,
    DateTime? Function()? startedAt,
    DateTime? Function()? finishedAt,
  }) =>
      Book(
        id: id,
        title: title,
        author: author,
        shelf: shelf ?? this.shelf,
        addedAt: addedAt,
        tags: tags ?? this.tags,
        isbn: isbn,
        coverUrl: coverUrl,
        firstPublishYear: firstPublishYear,
        pages: pages != null ? pages() : this.pages,
        rating: rating != null ? rating() : this.rating,
        startedAt: startedAt != null ? startedAt() : this.startedAt,
        finishedAt: finishedAt != null ? finishedAt() : this.finishedAt,
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
      );

  /// Readable JSON used in backup files.
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
      );
}
