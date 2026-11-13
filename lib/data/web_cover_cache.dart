import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Covers that come from a web address, kept on the phone once they were
/// fetched. Before, they were downloaded again every time the app started,
/// and showed blank without a connection. The book still holds the web
/// address, so nothing changes in the library or in a sync.
class WebCoverCache {
  WebCoverCache._();

  /// Where the pictures are kept. Null (as in tests) means covers are not
  /// kept and are fetched as before.
  static Directory? folder;

  /// Fetches a picture; replaced in tests.
  static http.Client Function() client = http.Client.new;

  /// Pictures kept at most. The oldest go first.
  static const maxFiles = 400;

  /// A cover bigger than this is not a cover.
  static const maxBytes = 5 * 1024 * 1024;

  static const _memoryMax = 60;
  static final _memory = <String, Uint8List>{};
  static final _loading = <String, Future<Uint8List?>>{};
  static int _written = 0;

  static String _name(String url) =>
      sha256.convert(url.codeUnits).toString().substring(0, 32);

  /// The picture's bytes if they were read lately.
  static Uint8List? cached(String url) {
    final bytes = _memory.remove(url);
    if (bytes != null) _memory[url] = bytes;
    return bytes;
  }

  static void _remember(String url, Uint8List bytes) {
    if (_memory.length >= _memoryMax) _memory.remove(_memory.keys.first);
    _memory[url] = bytes;
  }

  /// The picture at [url]: from memory, from the phone, or from the web (and
  /// then kept). Null when it can't be had.
  static Future<Uint8List?> load(String url) {
    final known = cached(url);
    if (known != null) return Future.value(known);
    return _loading[url] ??= _load(url).whenComplete(() {
      // A block, not an arrow: remove() returns this same future, and
      // whenComplete would wait for it, so for itself, for ever.
      _loading.remove(url);
    });
  }

  static Future<Uint8List?> _load(String url) async {
    final dir = folder;
    final file = dir == null ? null : File('${dir.path}/${_name(url)}');
    try {
      if (file != null && await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          _remember(url, bytes);
          return bytes;
        }
      }
    } on FileSystemException {
      // Fetched again below.
    }
    final bytes = await _fetch(url);
    if (bytes == null) return null;
    _remember(url, bytes);
    if (file != null) {
      try {
        await file.parent.create(recursive: true);
        final part = File('${file.path}.part');
        await part.writeAsBytes(bytes, flush: true);
        await part.rename(file.path);
        if (++_written % 20 == 1) unawaited(_trim());
      } on FileSystemException {
        // Shown anyway; kept next time.
      }
    }
    return bytes;
  }

  static Future<Uint8List?> _fetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }
    final web = client();
    try {
      final response =
          await web.get(uri).timeout(const Duration(seconds: 15));
      final bytes = response.bodyBytes;
      if (response.statusCode != 200 ||
          bytes.isEmpty ||
          bytes.length > maxBytes ||
          !_looksLikePicture(bytes)) {
        return null;
      }
      return bytes;
    } catch (_) {
      return null; // offline, or a slow or broken site
    } finally {
      web.close();
    }
  }

  /// JPEG, PNG, GIF or WebP, by their first bytes: an error page saved as a
  /// cover would show blank for good.
  static bool _looksLikePicture(Uint8List b) {
    if (b.length < 12) return false;
    if (b[0] == 0xFF && b[1] == 0xD8) return true; // JPEG
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return true; // PNG
    }
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return true; // GIF
    return b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50; // WebP
  }

  /// Keeps the newest [maxFiles] pictures.
  static Future<void> _trim() async {
    final dir = folder;
    if (dir == null) return;
    try {
      final files = <File, DateTime>{};
      await for (final entry in dir.list()) {
        if (entry is File && !entry.path.endsWith('.part')) {
          files[entry] = (await entry.stat()).modified;
        }
      }
      if (files.length <= maxFiles) return;
      final oldest = files.keys.toList()
        ..sort((a, b) => files[a]!.compareTo(files[b]!));
      for (final file in oldest.take(files.length - maxFiles)) {
        await file.delete();
      }
    } on FileSystemException {
      // Tried again later.
    }
  }

  /// Forgets what is in memory (for tests).
  static void clearMemory() => _memory.clear();
}
