import 'package:flutter/foundation.dart';

import '../models/book.dart';
import 'app_settings.dart';
import 'book_repository.dart';
import 'sync_merge.dart';
import 'sync_protocol.dart';
import 'sync_server.dart';

/// Runs the sync server while sync is switched on in Settings. Call [refresh]
/// at start-up and after any change to those settings.
class PhoneSync extends ChangeNotifier {
  PhoneSync({required this.repository, required this.settings});

  final BookRepository repository;
  final AppSettings settings;
  SyncServer? _server;
  String? _error;

  bool get running => _server?.running ?? false;

  /// Why the server could not start, or null.
  String? get error => _error;

  int get port => defaultSyncPort;

  Future<void> refresh() async {
    if (!settings.syncEnabled) {
      await _stop();
      notifyListeners();
      return;
    }
    if (settings.syncCode == null) settings.setSyncCode(newSyncCode());
    await _stop();
    final server = SyncServer(
      token: settings.syncCode!,
      handleSync: _handleSync,
    );
    try {
      await server.start(port: defaultSyncPort);
      _server = server;
      _error = null;
    } catch (_) {
      _error = 'Could not open port $defaultSyncPort. '
          'Is another app using it?';
    }
    notifyListeners();
  }

  Future<void> _stop() async {
    final server = _server;
    _server = null;
    await server?.stop();
  }

  Future<String> _handleSync(String body) async {
    try {
      final remote = decodeSyncPayload(body);
      final local = repository.snapshot();
      final merged = mergeLibraries(
        local: local.books,
        localTombstones: local.tombstones,
        remote: remote.books,
        remoteTombstones: remote.tombstones,
      );
      final changed = _countChanges(local.books, merged.books);
      await repository.applySynced(merged.books, merged.tombstones);
      settings.recordSync(at: DateTime.now(), changed: changed);
      return encodeSyncPayload(merged.books, merged.tombstones);
    } on FormatException catch (error) {
      settings.recordSyncError(error.message);
      rethrow;
    } catch (_) {
      settings.recordSyncError('The sync could not be finished.');
      rethrow;
    }
  }

  /// How many books on this phone were added, changed or removed.
  int _countChanges(List<Book> before, List<Book> after) {
    final old = {for (final book in before) book.id: book};
    final kept = <String>{};
    var changed = 0;
    for (final book in after) {
      kept.add(book.id);
      final previous = old[book.id];
      if (previous == null || previous.updatedAt != book.updatedAt) changed++;
    }
    for (final id in old.keys) {
      if (!kept.contains(id)) changed++;
    }
    return changed;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
