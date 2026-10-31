import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:path_provider/path_provider.dart';

import '../models/book.dart';
import 'listen_controller.dart';

/// Shows the audiobook in the notification and on the lock screen, keeps it
/// playing with the screen off, and lets headphone buttons control it.
class ChapterlyAudioHandler extends BaseAudioHandler with SeekHandler {
  ChapterlyAudioHandler(this.controller) {
    controller.addListener(_update);
  }

  final ListenController controller;

  /// Covers saved as files for the notification, by book id.
  final _art = <String, Uri?>{};

  bool? _lastPlaying;
  int? _lastTrack;
  int? _lastChapter;
  double? _lastSpeed;
  Duration _lastPosition = Duration.zero;
  DateTime _lastAt = DateTime.now();

  void _update() {
    final book = controller.book;
    if (!controller.active || book == null) {
      if (_lastPlaying != null) {
        _lastPlaying = null;
        playbackState.add(PlaybackState());
        mediaItem.add(null);
      }
      return;
    }
    final chapters = controller.chapters;
    final chapter = controller.chapterIndex;
    final playing = controller.playing;
    final position = controller.trackPosition;
    final now = DateTime.now();

    if (mediaItem.value?.id != book.id ||
        chapter != _lastChapter ||
        controller.track != _lastTrack) {
      mediaItem.add(MediaItem(
        id: book.id,
        title: book.title,
        artist: book.author.isEmpty ? null : book.author,
        album: chapter != null ? chapters[chapter].title : null,
        duration: controller.trackLength,
        artUri: _artFor(book),
      ));
    }

    // The notification works out the position itself while playing, so it
    // is only told again when something changes or the position jumps.
    final expected = (_lastPlaying ?? false)
        ? _lastPosition + now.difference(_lastAt) * (_lastSpeed ?? 1)
        : _lastPosition;
    final jumped = (position - expected).inMilliseconds.abs() > 1500;
    if (playing == _lastPlaying &&
        controller.track == _lastTrack &&
        chapter == _lastChapter &&
        controller.speed == _lastSpeed &&
        !jumped) {
      return;
    }
    _lastPlaying = playing;
    _lastTrack = controller.track;
    _lastChapter = chapter;
    _lastSpeed = controller.speed;
    _lastPosition = position;
    _lastAt = now;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.rewind,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.fastForward,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
      playing: playing,
      updatePosition: position,
      speed: controller.speed,
      updateTime: now,
    ));
  }

  /// A web cover as it is; a cover added on the PC saved to a file first.
  Uri? _artFor(Book book) {
    final url = book.coverUrl;
    if (url == null) return null;
    if (url.startsWith('http')) return Uri.tryParse(url);
    if (!url.startsWith('data:image/')) return null;
    if (_art.containsKey(book.id)) return _art[book.id];
    _art[book.id] = null;
    () async {
      try {
        final bytes = UriData.parse(url).contentAsBytes();
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/cover_${book.id.hashCode}.jpg');
        await file.writeAsBytes(bytes);
        _art[book.id] = file.uri;
        final item = mediaItem.value;
        if (item != null && item.id == book.id) {
          mediaItem.add(item.copyWith(artUri: file.uri));
        }
      } catch (_) {
        // No picture in the notification.
      }
    }();
    return null;
  }

  @override
  Future<void> play() => controller.play();

  @override
  Future<void> pause() => controller.pause();

  @override
  Future<void> seek(Duration position) => controller.seekInTrack(position);

  @override
  Future<void> rewind() => controller.skip(const Duration(seconds: -30));

  @override
  Future<void> fastForward() => controller.skip(const Duration(seconds: 30));

  @override
  Future<void> skipToNext() => controller.nextChapter();

  @override
  Future<void> skipToPrevious() => controller.previousChapter();

  @override
  Future<void> setSpeed(double speed) => controller.setSpeed(speed);

  @override
  Future<void> stop() async {
    await controller.close();
    await super.stop();
  }
}
