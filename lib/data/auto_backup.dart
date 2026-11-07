import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'app_settings.dart';
import 'backup.dart';
import 'book_repository.dart';

/// How many automatic backups are kept in a folder. Older ones are removed.
const autoBackupKeep = 5;

const _prefix = 'chapterly-auto-';

/// The open profile's own folder inside the backup folders, or null for the
/// first profile. Set at start-up.
String? autoBackupSubfolder;

/// Where a profile with a PIN keeps its automatic backups: inside the app's
/// own storage, which other apps and other profiles can't open. Set at
/// start-up; tests may set it too.
Directory? autoBackupPrivateFolder;

/// The folder for automatic backups of a profile with a PIN.
Future<Directory> privateAutoBackupFolder() async {
  final set = autoBackupPrivateFolder;
  if (set != null) return set;
  final base = await getApplicationSupportDirectory();
  return Directory('${base.path}/backups');
}

String _two(int n) => n.toString().padLeft(2, '0');

/// chapterly-auto-2026-10-29-2141.json, so the names sort by date.
String autoBackupFileName(DateTime time) =>
    '$_prefix${time.year}-${_two(time.month)}-${_two(time.day)}-'
    '${_two(time.hour)}${_two(time.minute)}.json';

/// The shared Documents/Chapterly folder first: it is kept when the app is
/// uninstalled and can be seen in the Files app (Android 11 and newer). The
/// app's own folder is the fallback for older phones.
Future<List<Directory>> autoBackupFolders() async {
  final folders = [Directory('/storage/emulated/0/Documents/Chapterly')];
  try {
    final own = await getExternalStorageDirectory();
    if (own != null) folders.add(Directory('${own.path}/backups'));
  } catch (_) {
    // Not on Android (for example in tests).
  }
  final sub = autoBackupSubfolder;
  if (sub == null) return folders;
  return [for (final folder in folders) Directory('${folder.path}/$sub')];
}

/// Removes the oldest automatic backups in [folder], keeping [keep].
/// Files that cannot be removed are left alone. Returns how many went.
Future<int> pruneAutoBackups(Directory folder, {int keep = autoBackupKeep}) async {
  final files = <File>[];
  await for (final entity in folder.list()) {
    final name = entity.uri.pathSegments.last;
    if (entity is File && name.startsWith(_prefix) && name.endsWith('.json')) {
      files.add(entity);
    }
  }
  files.sort((a, b) => b.path.compareTo(a.path));
  var removed = 0;
  for (final file in files.skip(keep)) {
    try {
      await file.delete();
      removed++;
    } on FileSystemException {
      // Made by an earlier install of the app, or locked: leave it.
    }
  }
  return removed;
}

/// Writes [content] to the first of [folders] that works and tidies that
/// folder. Returns the path of the new file. Throws if no folder works.
Future<String> writeAutoBackup({
  required String content,
  required List<Directory> folders,
  required DateTime now,
}) async {
  Object? lastError;
  for (final folder in folders) {
    try {
      await folder.create(recursive: true);
      final file = File('${folder.path}/${autoBackupFileName(now)}');
      await file.writeAsString(content, flush: true);
      await pruneAutoBackups(folder);
      return file.path;
    } on FileSystemException catch (error) {
      lastError = error;
    }
  }
  throw FileSystemException(
    'No folder could be written',
    lastError is FileSystemException ? lastError.path : null,
  );
}

/// Removes this profile's automatic backups from the shared [folders], once
/// newer ones are kept privately (the profile has a PIN). Backups saved by
/// hand are not touched.
Future<void> removeSharedAutoBackups(List<Directory> folders) async {
  for (final folder in folders) {
    try {
      if (await folder.exists()) await pruneAutoBackups(folder, keep: 0);
    } on FileSystemException {
      // Not allowed to look there: nothing to remove.
    }
  }
}

bool _running = false;

/// Makes an automatic backup when it is switched on and due (or always,
/// with [force]) and records the result in [settings].
Future<void> runAutoBackup(
  BookRepository repository,
  AppSettings settings, {
  bool force = false,
  DateTime? now,
}) async {
  final time = now ?? DateTime.now();
  if (_running) return;
  if (!force && !settings.autoBackupDue(time)) return;
  if (!repository.isLoaded || repository.allBooks.isEmpty) return;
  _running = true;
  try {
    final locked = settings.pinEnabled;
    final path = await writeAutoBackup(
      content: encodeBackup(
        await repository.withPictures(repository.allBooks),
        now: time,
      ),
      // A PIN-locked profile's backups stay where only Chapterly, open on
      // that profile, can read them: a shared folder could be restored from
      // another profile, or read by any app.
      folders: locked ? [await privateAutoBackupFolder()] : await autoBackupFolders(),
      now: time,
    );
    if (locked) await removeSharedAutoBackups(await autoBackupFolders());
    settings.recordAutoBackup(at: time, path: path);
  } on FileSystemException catch (error) {
    settings.recordAutoBackupError(error.message);
  } finally {
    _running = false;
  }
}

/// Runs [runAutoBackup] whenever the app comes back to the screen.
class AutoBackupObserver with WidgetsBindingObserver {
  AutoBackupObserver({required this.repository, required this.settings});

  final BookRepository repository;
  final AppSettings settings;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      runAutoBackup(repository, settings);
    }
  }
}
