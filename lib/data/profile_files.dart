import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'profiles.dart';

/// The first profile keeps the database it always had.
String profileDatabaseName(String id) =>
    id == mainProfileId ? 'chapterly.db' : 'chapterly_$id.db';

/// Where a profile keeps its reader and audiobook lists, its book server
/// connection and its copies of book files: the app's folder for the first
/// profile, `profiles/<id>` in it for the others.
Future<Directory> profileFolder(String id) async {
  final base = await getApplicationSupportDirectory();
  if (id == mainProfileId) return base;
  final dir = Directory(p.join(base.path, 'profiles', id));
  await dir.create(recursive: true);
  return dir;
}

/// The folder in Documents/Chapterly for a profile's automatic backups,
/// named after the profile and its id ("Anna (k3x9q2ab)"), so two profiles
/// with names that look alike never share one. Null for the first profile,
/// whose backups stay in Documents/Chapterly itself.
String? profileBackupFolder(Profile profile) {
  if (profile.isMain) return null;
  final safe =
      profile.name.trim().replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '_').trim();
  return safe.isEmpty ? profile.id : '$safe (${profile.id})';
}

/// The first profile's files in the app's folder. The other profiles live
/// in the profiles folder beside them, so only these are removed.
const _mainProfileFiles = [
  'ebook_library.json',
  'audio_library.json',
  'book_server.json',
  'book_server_library.json',
  'books',
  'server_audio',
];

/// Removes a profile's books and files from this phone. Its automatic
/// backups in Documents/Chapterly are kept.
Future<void> removeProfileFiles(String id) async {
  try {
    await deleteDatabase(
      p.join(await getDatabasesPath(), profileDatabaseName(id)),
    );
  } catch (_) {
    // Already gone.
  }
  final base = await getApplicationSupportDirectory();
  final paths = id == mainProfileId
      ? [for (final name in _mainProfileFiles) p.join(base.path, name)]
      : [p.join(base.path, 'profiles', id)];
  for (final path in paths) {
    try {
      final type = await FileSystemEntity.type(path);
      if (type == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: true);
      } else if (type == FileSystemEntityType.file) {
        await File(path).delete();
      }
    } on FileSystemException {
      // Left behind; it does no harm.
    }
  }
}

const _app = MethodChannel('chapterly/app');

/// Starts Chapterly again, so it opens with the profile that was just
/// chosen. If that fails, Chapterly closes and opens with it next time.
Future<void> restartChapterly() async {
  try {
    await _app.invokeMethod<void>('restart');
  } catch (_) {
    await SystemNavigator.pop();
  }
}
