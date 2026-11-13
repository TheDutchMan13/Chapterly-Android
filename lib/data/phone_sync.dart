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
    SyncProfileHost Function(PhoneSyncCore openCore)? profiles,
  }) : _core = PhoneSyncCore(repository: repository, settings: settings) {
    this.profiles = profiles?.call(_core);
  }

  final BookRepository repository;
  final AppSettings settings;

  /// The open profile, told to the PC so it can say which one it reached.
  final String? profileName;
  final PhoneSyncCore _core;

  /// Every profile on this phone, so one pairing syncs them all.
  late final SyncProfileHost? profiles;
  SyncServer? _server;
  String? _error;

  /// Goes up with every start and stop, so a server whose start finishes
  /// after a later stop (or a newer start) is closed instead of kept.
  int _generation = 0;

  /// Chapterly is not on the screen: no server is started until it is.
  bool _paused = false;

  bool get running => _server?.running ?? false;

  /// Why the server could not start, or null.
  String? get error => _error;

  int get port => portOverride;

  /// Starts and stops wait for the one before, so two that overlap (the
  /// app coming back on the screen while sync is still starting) can't both
  /// try to open the port.
  Future<void> _queue = Future.value();

  Future<void> refresh() {
    final next = _queue.then((_) => _refresh());
    // A failed start must not stop later ones.
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _refresh() async {
    if (!settings.syncEnabled || _paused) {
      await _stop();
      notifyListeners();
      return;
    }
    if (settings.syncCode == null) settings.setSyncCode(newSyncCode());
    await _stop();
    final generation = _generation;
    final server = SyncServer(
      token: settings.syncCode!,
      handleSync: _core.handleSync,
      covers: _core,
      profiles: profiles,
    );
    try {
      await server.start(port: port);
      if (generation != _generation ||
          _paused ||
          !settings.syncEnabled ||
          _disposed) {
        // Stopped, paused or started again while the port was opening.
        await server.stop();
        return;
      }
      _server = server;
      _error = null;
    } catch (_) {
      if (generation != _generation) return;
      _error = 'Could not open port $defaultSyncPort. '
          'Is another app using it?';
    }
    notifyListeners();
  }

  /// The port the server listens on. Tests may change it.
  @visibleForTesting
  int portOverride = defaultSyncPort;

  Future<void> _stop({bool force = true}) async {
    _generation++;
    final server = _server;
    _server = null;
    await server?.stop(force: force);
  }

  bool _disposed = false;

  /// Chapterly left the screen: the phone stops listening for the PC, so
  /// nothing on the network can reach it while it isn't being used. A sync
  /// already running is finished first.
  Future<void> appPaused() async {
    _paused = true;
    final wasRunning = _server != null;
    await _stop(force: false);
    if (wasRunning) notifyListeners();
  }

  /// Chapterly is back on the screen: listening again, if sync is on.
  Future<void> appResumed() async {
    _paused = false;
    if (_server != null || !settings.syncEnabled) return;
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _stop();
    super.dispose();
  }
}
