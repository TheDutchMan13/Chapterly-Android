import 'shelf.dart';

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.shelf,
    this.tags = const [],
  });

  final String id;
  final String title;
  final String author;
  final Shelf shelf;
  final List<String> tags;

  Book copyWith({Shelf? shelf}) => Book(
        id: id,
        title: title,
        author: author,
        shelf: shelf ?? this.shelf,
        tags: tags,
      );
}
