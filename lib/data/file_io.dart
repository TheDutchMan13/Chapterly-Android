import 'dart:io';

import 'package:file_selector/file_selector.dart' show openFile;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Hands text files to and from the phone: share a file out (to Drive,
/// Files, email...) and pick a file in.
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
}
