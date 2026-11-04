import 'dart:io';

/// Saves a file one write at a time, each written beside the real file
/// first and then moved over it, so two quick saves can't mix their text and
/// a crash mid-write never leaves a half-written file.
class SafeFileWriter {
  Future<void> _writing = Future.value();

  /// Writes [data] to [file] after any write still running. Errors are
  /// swallowed: the next change tries again.
  Future<void> write(File file, String data) =>
      _writing = _writing.then((_) => writeFileSafely(file, data));
}

/// Writes [data] to a temporary file next to [file], flushed to the disk,
/// then moves it over [file].
Future<void> writeFileSafely(File file, String data) async {
  try {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(data, flush: true);
    await temp.rename(file.path);
  } catch (_) {
    // Kept in memory; written with the next change.
  }
}

/// Moves a file that could not be read to `<name>.bad`, so the next save
/// starts a new one instead of writing over what may still be rescued.
Future<void> setAsideDamaged(File file) async {
  try {
    if (await file.exists()) await file.rename('${file.path}.bad');
  } catch (_) {
    // Left where it is.
  }
}
