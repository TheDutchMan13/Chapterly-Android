import '../models/book.dart';
import '../models/book_format.dart';
import '../models/reading.dart';
import '../models/shelf.dart';

class BookStats {
  const BookStats({
    required this.finishedCount,
    required this.pagesRead,
    required this.averageRating,
    required this.averagePages,
    required this.longest,
    required this.byMonth,
    required this.byYear,
    required this.shelfCounts,
    required this.finishedWithoutDate,
    required this.loggedPages,
    required this.loggedByMonth,
    required this.formatCounts,
  });

  /// Finished readings in the chosen year (or ever, when no year is chosen).
  /// A book that was read twice counts twice.
  final int finishedCount;
  final int pagesRead;
  final double? averageRating;
  final int? averagePages;
  final Book? longest;

  /// Finished readings per month (index 0 is January) in the chosen year.
  final List<int> byMonth;

  /// Finished readings per year, oldest first. Always covers every year.
  final Map<int, int> byYear;
  final Map<Shelf, int> shelfCounts;

  /// Finished readings that have no finish date, so no month or year.
  final int finishedWithoutDate;

  /// Pages written down in the reading log, in the chosen year or ever.
  final int loggedPages;

  /// Logged pages per month (index 0 is January).
  final List<int> loggedByMonth;

  /// Finished readings per book format. Books without a format are left out.
  final Map<BookFormat, int> formatCounts;

  List<int> get yearsNewestFirst =>
      byYear.keys.toList()..sort((a, b) => b.compareTo(a));
}

BookStats computeStats(List<Book> books, {int? year}) {
  final all = <(Book, Reading)>[
    for (final book in books)
      for (final reading in book.finishedReadings) (book, reading),
  ];
  final finished = [
    for (final item in all)
      if (year == null || item.$2.finishedAt?.year == year) item,
  ];

  var pagesRead = 0;
  Book? longest;
  final ratings = <int>[];
  final pageCounts = <int>[];
  final formatCounts = <BookFormat, int>{};
  final byMonth = List<int>.filled(12, 0);
  for (final (book, reading) in finished) {
    final pages = book.pages;
    if (pages != null) {
      pagesRead += pages;
      pageCounts.add(pages);
      if (pages > (longest?.pages ?? 0)) longest = book;
    }
    final rating = reading.rating;
    if (rating != null) ratings.add(rating);
    final format = book.format;
    if (format != null) formatCounts[format] = (formatCounts[format] ?? 0) + 1;
    final date = reading.finishedAt;
    if (date != null) byMonth[date.month - 1]++;
  }

  final yearCounts = <int, int>{};
  var withoutDate = 0;
  for (final (_, reading) in all) {
    final date = reading.finishedAt;
    if (date == null) {
      withoutDate++;
    } else {
      yearCounts[date.year] = (yearCounts[date.year] ?? 0) + 1;
    }
  }
  final sortedYears = yearCounts.keys.toList()..sort();

  var loggedPages = 0;
  final loggedByMonth = List<int>.filled(12, 0);
  for (final book in books) {
    final entries = [
      ...book.readingLog,
      for (final reading in book.previousReadings) ...reading.log,
    ];
    for (final entry in entries) {
      if (year != null && entry.date.year != year) continue;
      loggedPages += entry.pages;
      loggedByMonth[entry.date.month - 1] += entry.pages;
    }
  }

  return BookStats(
    finishedCount: finished.length,
    pagesRead: pagesRead,
    averageRating: ratings.isEmpty
        ? null
        : ratings.reduce((a, b) => a + b) / ratings.length,
    averagePages: pageCounts.isEmpty
        ? null
        : (pageCounts.reduce((a, b) => a + b) / pageCounts.length).round(),
    longest: longest,
    byMonth: byMonth,
    byYear: {for (final y in sortedYears) y: yearCounts[y]!},
    shelfCounts: {
      for (final shelf in Shelf.values)
        shelf: books.where((b) => b.shelf == shelf).length,
    },
    finishedWithoutDate: withoutDate,
    loggedPages: loggedPages,
    loggedByMonth: loggedByMonth,
    formatCounts: formatCounts,
  );
}
