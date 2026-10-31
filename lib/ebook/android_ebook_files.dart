import 'package:flutter/services.dart';

import '../audio/audio_files.dart';
import 'ebook_files.dart';

const _channel = MethodChannel('chapterly/audio_files');

/// Book files on Android: the system file picker gives a content://
/// address, and MainActivity.kt copies the file into the app's folder.
class AndroidEbookFiles implements EbookFiles {
  const AndroidEbookFiles();

  @override
  Future<PickedFile?> pickBook() async {
    final items = await _channel.invokeListMethod<Object?>('pickBook');
    if (items == null || items.isEmpty) return null;
    final item = items.first;
    if (item is! Map) return null;
    final location = item['location'];
    final name = item['name'];
    if (location is! String || name is! String) return null;
    return PickedFile(location: location, name: name);
  }

  @override
  Future<int> copy(PickedFile picked, String path) async {
    final bytes = await _channel.invokeMethod<int>(
      'copyTo',
      {'uri': picked.location, 'path': path},
    );
    return bytes ?? 0;
  }

  @override
  Future<void> release(PickedFile picked) async {
    try {
      await _channel.invokeMethod<void>('release', {
        'uris': [picked.location],
      });
    } on PlatformException {
      // Already released.
    }
  }
}
