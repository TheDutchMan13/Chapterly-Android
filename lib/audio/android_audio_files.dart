import 'package:flutter/services.dart';

import 'audio_files.dart';
import 'audio_probe.dart';

const _channel = MethodChannel('chapterly/audio_files');

List<PickedFile>? _picked(List<Object?>? items) {
  if (items == null) return null;
  return [
    for (final item in items)
      if (item is Map && item['location'] is String && item['name'] is String)
        PickedFile(
          location: item['location'] as String,
          name: item['name'] as String,
        ),
  ];
}

/// Audio files on Android: picked with the system file picker, which gives
/// content:// addresses. Chapterly keeps permission to read them, so it
/// needs no storage permission. The picking and reading happen in
/// MainActivity.kt.
class AndroidAudioFiles implements AudioFiles {
  const AndroidAudioFiles();

  @override
  Future<List<PickedFile>?> pickFile() async =>
      _picked(await _channel.invokeListMethod<Object?>('pickFile'));

  @override
  Future<List<PickedFile>?> pickFolder() async =>
      _picked(await _channel.invokeListMethod<Object?>('pickFolder'));

  @override
  ByteSource open(String location) => _ContentByteSource(location);

  @override
  Uri playable(String location) => Uri.parse(location);

  /// Every audio file still linked to a book, in any profile on this
  /// phone. Set at start-up. Android's permission to read a file (or the
  /// folder it was picked with) is one for the whole app, so it is only let
  /// go when nothing else still uses it.
  static Future<List<String>> Function()? inUse;

  @override
  Future<void> release(List<String> locations) async {
    if (locations.isEmpty) return;
    List<String> keep;
    try {
      keep = await inUse?.call() ?? const [];
    } catch (_) {
      // Not known what is still used: keep every permission.
      return;
    }
    try {
      await _channel.invokeMethod<void>(
        'release',
        {'uris': locations, 'keep': keep},
      );
    } on PlatformException {
      // Already released.
    }
  }
}

class _ContentByteSource implements ByteSource {
  _ContentByteSource(this.uri);

  final String uri;
  int? _length;

  @override
  Future<int> length() async =>
      _length ??= await _channel.invokeMethod<int>('size', {'uri': uri}) ?? 0;

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (count <= 0) return Uint8List(0);
    final bytes = await _channel.invokeMethod<Uint8List>(
      'read',
      {'uri': uri, 'offset': offset, 'count': count},
    );
    return bytes ?? Uint8List(0);
  }

  @override
  Future<void> close() async {}
}
