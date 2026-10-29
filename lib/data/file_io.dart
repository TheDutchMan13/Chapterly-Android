import 'dart:io';

import 'package:file_selector/file_selector.dart' show XTypeGroup, openFile;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Hands files to and from the phone: share a file out (to Drive,
/// Files, email...), pick a file in, and pick a photo for a book cover.
class FileIo {
  const FileIo();

  /// Writes [content] to a temporary file and opens the share sheet.
  Future<void> shareText({
    required String fileName,
    required String content,
    required String mimeType,
    String? subject,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(content);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: subject,
      ),
    );
  }

  /// Lets the user pick any file and returns its text, or null if cancelled.
  Future<String?> pickTextFile() async {
    final file = await openFile();
    return file?.readAsString();
  }

  /// Lets the user pick a photo and keeps a copy inside the app, so the cover
  /// still works if the photo is moved or deleted. Returns the path of the
  /// copy, or null if cancelled.
  Future<String?> pickCoverImage(String bookId) async {
    const images = XTypeGroup(
      label: 'Images',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
      mimeTypes: ['image/*'],
    );
    final file = await openFile(acceptedTypeGroups: [images]);
    if (file == null) return null;
    final dir = await getApplicationDocumentsDirectory();
    final covers = Directory('${dir.path}/covers');
    await covers.create(recursive: true);
    final target =
        '${covers.path}/$bookId-${DateTime.now().millisecondsSinceEpoch}.img';
    await file.saveTo(target);
    return target;
  }
}
