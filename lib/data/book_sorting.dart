import '../models/book.dart';
import 'app_settings.dart';

int _direction(int result, bool ascending) => ascending ? result : -result;

/// Compares two optional values. Books with no value always go last.
int _compareOptional<T extends Comparable<Object>>(
  T? a,
  T? b,
  bool ascending,
) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return _direction(a.compareTo(b), ascending);
}

/// Returns a sorted copy of [books].
List<Book> sortBooks(
  List<Book> books,
  SortField field, {
  required bool ascending,
}) {
  final sorted = [...books];
  sorted.sort((a, b) => switch (field) {
        SortField.dateAdded =>
          _direction(a.addedAt.compareTo(b.addedAt), ascending),
        SortField.title => _direction(
            a.title.toLowerCase().compareTo(b.title.toLowerCase()),
            ascending,
          ),
        SortField.author => _direction(
            a.author.toLowerCase().compareTo(b.author.toLowerCase()),
            ascending,
          ),
        SortField.rating => _compareOptional(a.rating, b.rating, ascending),
        SortField.pages => _compareOptional(a.pages, b.pages, ascending),
        SortField.dateFinished =>
          _compareOptional(a.finishedAt, b.finishedAt, ascending),
        SortField.format =>
          _compareOptional(a.format?.index, b.format?.index, ascending),
        SortField.favorite => _direction(
            a.favorite == b.favorite ? 0 : (a.favorite ? 1 : -1),
            ascending,
          ),
      });
  return sorted;
}
