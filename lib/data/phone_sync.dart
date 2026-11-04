import 'package:flutter/foundation.dart';

import 'app_settings.dart';
import 'book_repository.dart';
import 'phone_sync_core.dart';
import 'sync_protocol.dart';
import 'sync_server.dart';

/// Runs the sync server while sync is switched on in Settings. Call [refresh]
/// at start-up and after any change to those settings.
class PhoneSync extends ChangeNotifier {
  PhoneSync({
    required this.repository,
    required this.settings,
    this.profileName,
  }) : _core = PhoneSyncCore(repository: repository, settings: settings);

  final BookRepository repository;
  final AppSettings settings;

  /// The open profile, told to the PC so it can say which one it reached.
  final String? profileName;
  final PhoneSyncCore _core;
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
      handleSync: _core.handleSync,
      covers: _core,
      profileName: profileName,
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

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
