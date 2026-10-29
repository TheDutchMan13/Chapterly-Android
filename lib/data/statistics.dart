import '../models/book.dart';
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
  });

  /// Finished books in the chosen year (or ever, when no year is chosen).
  final int finishedCount;
  final int pagesRead;
  final double? averageRating;
  final int? averagePages;
  final Book? longest;

  /// Finished books per month (index 0 is January) in the chosen year.
  final List<int> byMonth;

  /// Finished books per year, oldest first. Always covers every year.
  final Map<int, int> byYear;
  final Map<Shelf, int> shelfCounts;

  /// Finished books that have no finish date, so no month or year.
  final int finishedWithoutDate;

  List<int> get yearsNewestFirst =>
      byYear.keys.toList()..sort((a, b) => b.compareTo(a));
}

BookStats computeStats(List<Book> books, {int? year}) {
  final allFinished = [
    for (final book in books)
      if (book.shelf == Shelf.finished) book,
  ];
  final finished = [
    for (final book in allFinished)
      if (year == null || book.finishedAt?.year == year) book,
  ];

  var pagesRead = 0;
  Book? longest;
  for (final book in finished) {
    final pages = book.pages;
    if (pages == null) continue;
    pagesRead += pages;
    if (pages > (longest?.pages ?? 0)) longest = book;
  }

  final ratings = finished.map((b) => b.rating).whereType<int>().toList();
  final pageCounts = finished.map((b) => b.pages).whereType<int>().toList();

  final byMonth = List<int>.filled(12, 0);
  for (final book in finished) {
    final date = book.finishedAt;
    if (date != null) byMonth[date.month - 1]++;
  }

  final yearCounts = <int, int>{};
  var withoutDate = 0;
  for (final book in allFinished) {
    final date = book.finishedAt;
    if (date == null) {
      withoutDate++;
    } else {
      yearCounts[date.year] = (yearCounts[date.year] ?? 0) + 1;
    }
  }
  final sortedYears = yearCounts.keys.toList()..sort();

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
  );
}
