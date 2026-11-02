import '../audio/audio_library.dart';
import '../ebook/ebook_library.dart';
import '../models/audio_progress.dart';
import '../models/book.dart';

// Like format_sync.dart in the Windows app, which also works out an EPUB
// place; keep the shared parts alike.

/// Where you are in a book's audiobook and in its book file, from 0 to 1.
class FormatPositions {
  const FormatPositions({required this.audio, required this.reader});

  final double audio;
  final double reader;

  /// How far apart, from 0 to 1.
  double get gap => (audio - reader).abs();

  /// Worth offering to line them up: more than 2% apart.
  bool get apart => gap > 0.02;

  bool get audioAhead => audio > reader;
}

/// Both places, or null unless the book has an audiobook with a known
/// length and a book file with a saved place on this device.
FormatPositions? formatPositions(
  Book book, {
  AudioLink? audio,
  EbookLink? ebook,
}) {
  final progress = book.audio;
  final position = ebook?.position;
  if (progress == null || audio == null || position == null) return null;
  final length = audio.lengthMs ?? progress.lengthMs;
  if (length == null || length <= 0) return null;
  final fraction = (progress.positionMs / length).clamp(0.0, 1.0);
  return FormatPositions(audio: fraction, reader: position.progress);
}

/// The place in [link] that is [positionMs] from the start of the book.
({int track, int trackMs}) placeInBook(AudioLink link, int positionMs) {
  var start = 0;
  for (var i = 0; i < link.tracks.length; i++) {
    final length = link.tracks[i].lengthMs;
    final last = i == link.tracks.length - 1;
    if (length == null || last || positionMs < start + length) {
      final inTrack = positionMs - start;
      return (track: i, trackMs: inTrack < 0 ? 0 : inTrack);
    }
    start += length;
  }
  return (track: 0, trackMs: 0);
}

/// The audiobook place for [fraction] of the way through the book.
AudioProgress audioProgressAt(AudioLink link, double fraction) {
  final length = link.lengthMs ?? 0;
  final place = placeInBook(link, (fraction.clamp(0.0, 1.0) * length).round());
  return link.progressAt(place.track, place.trackMs);
}

// On the phone the reader moves to a place by how far through the book it
// is (ReaderScreen.startAt), so there is no reader place to work out here.
