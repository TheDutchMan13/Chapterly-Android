import '../data/book_repository.dart';

export '../models/audio_bookmark.dart';

/// Where the app keeps audiobook bookmarks: with the books, so they sync
/// with the PC. Set up in main.dart. Null in tests, which hides the
/// bookmark buttons.
class AudioBookmarking {
  AudioBookmarking._();

  static BookRepository? repository;
}
