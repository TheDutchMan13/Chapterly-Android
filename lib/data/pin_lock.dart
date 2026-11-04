import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'profiles.dart' show ScopedPrefs;

/// A random salt, so the same PIN never gives the same stored value twice.
String newPinSalt([Random? random]) {
  final source = random ?? Random.secure();
  return base64UrlEncode(List.generate(16, (_) => source.nextInt(256)));
}

/// What is stored instead of the PIN itself.
String hashPin(String pin, String salt) =>
    sha256.convert(utf8.encode('$salt:$pin')).toString();

/// Counts wrong PINs and makes you wait after too many, kept with the
/// profile's settings so closing and opening the app does not start the
/// count again. The lock screen, the PIN asked for in Settings and deleting
/// a profile use the same count. Each round of [triesBeforeWait] wrong PINs
/// doubles the wait, from 30 seconds up to an hour.
///
/// A wait must pass on the clock and on the phone's time since it was
/// switched on, which can't be changed in the settings, so moving the clock
/// forward does not end it.
class PinGuard {
  PinGuard(
    this.prefs, {
    DateTime Function()? clock,
    int Function()? uptime,
    String? uptimeKind,
  })  : _clock = clock ?? DateTime.now,
        _uptime = uptime ?? _deviceUptime,
        _uptimeKind = uptimeKind ?? _deviceUptimeKind;

  /// The profile's settings; null keeps the count in memory only.
  final ScopedPrefs? prefs;
  final DateTime Function() _clock;
  final int Function() _uptime;

  /// Which uptime [_uptime] counts: "boot" for the phone's, else one for
  /// this run of the app only, so a wait from another run is not compared
  /// with it.
  final String _uptimeKind;

  static const triesBeforeWait = 5;
  static const firstWait = Duration(seconds: 30);
  static const longestWait = Duration(hours: 1);

  static const _failuresKey = 'pinFailures';
  static const _waitUntilKey = 'pinWaitUntil';
  static const _waitFromUptimeKey = 'pinWaitFromUptime';
  static const _waitUntilUptimeKey = 'pinWaitUntilUptime';
  static const _uptimeKindKey = 'pinWaitUptimeKind';

  static final _sinceLaunch = Stopwatch()..start();

  /// The phone's uptime when [_sinceLaunch] started, once known.
  static int? _bootUptimeAtLaunch;
  static final _runId = 'run-${newPinSalt()}';

  static int _deviceUptime() =>
      (_bootUptimeAtLaunch ?? 0) + _sinceLaunch.elapsedMilliseconds;

  static String get _deviceUptimeKind =>
      _bootUptimeAtLaunch == null ? _runId : 'boot';

  /// Asks Android how long the phone has been on (SystemClock
  /// .elapsedRealtime), so waits hold across restarts of the app. Without
  /// it, a wait is also timed within this run of the app.
  static Future<void> readDeviceUptime() async {
    try {
      final ms = await const MethodChannel('chapterly/app')
          .invokeMethod<int>('uptime');
      if (ms != null) {
        _bootUptimeAtLaunch = ms - _sinceLaunch.elapsedMilliseconds;
      }
    } catch (_) {
      // Not on Android (tests): timed within this run.
    }
  }

  int _memoryFailures = 0;
  int _memoryWaitUntil = 0;
  int _memoryFromUptime = 0;
  int _memoryUntilUptime = 0;
  String? _memoryKind;

  int get _failures => prefs?.getInt(_failuresKey) ?? _memoryFailures;
  int get _waitUntil => prefs?.getInt(_waitUntilKey) ?? _memoryWaitUntil;
  int get _fromUptime =>
      prefs?.getInt(_waitFromUptimeKey) ?? _memoryFromUptime;
  int get _untilUptime =>
      prefs?.getInt(_waitUntilUptimeKey) ?? _memoryUntilUptime;
  String? get _kind => prefs?.getString(_uptimeKindKey) ?? _memoryKind;

  void _save(
    int failures,
    int waitUntil, {
    int fromUptime = 0,
    int untilUptime = 0,
  }) {
    _memoryFailures = failures;
    _memoryWaitUntil = waitUntil;
    _memoryFromUptime = fromUptime;
    _memoryUntilUptime = untilUptime;
    _memoryKind = _uptimeKind;
    prefs?.setInt(_failuresKey, failures);
    prefs?.setInt(_waitUntilKey, waitUntil);
    prefs?.setInt(_waitFromUptimeKey, fromUptime);
    prefs?.setInt(_waitUntilUptimeKey, untilUptime);
    prefs?.setString(_uptimeKindKey, _uptimeKind);
  }

  static Duration _capped(int ms) {
    if (ms <= 0) return Duration.zero;
    final left = Duration(milliseconds: ms);
    // A clock that was put back can't make the wait longer than any wait.
    return left > longestWait ? longestWait : left;
  }

  /// How long until another PIN can be tried (zero when one can now).
  Duration waitLeft() {
    final byClock = _capped(_waitUntil - _clock().millisecondsSinceEpoch);
    var byUptime = Duration.zero;
    final until = _untilUptime;
    if (until != 0 && _kind == _uptimeKind) {
      final now = _uptime();
      // Less time since switching on than when the wait began: the phone
      // was restarted, and only the clock can tell.
      if (now >= _fromUptime) byUptime = _capped(until - now);
    }
    return byClock > byUptime ? byClock : byUptime;
  }

  /// Checks [pin] with [check], counting it when it is wrong. Returns
  /// whether it was right; a try while waiting is never checked.
  bool attempt(String pin, bool Function(String pin) check) {
    if (waitLeft() > Duration.zero) return false;
    if (check(pin)) {
      if (_failures != 0 || _waitUntil != 0 || _untilUptime != 0) _save(0, 0);
      return true;
    }
    final failures = _failures + 1;
    if (failures % triesBeforeWait == 0) {
      final round = failures ~/ triesBeforeWait - 1;
      var wait = firstWait * (1 << (round > 7 ? 7 : round));
      if (wait > longestWait) wait = longestWait;
      final uptime = _uptime();
      _save(
        failures,
        _clock().add(wait).millisecondsSinceEpoch,
        fromUptime: uptime,
        untilUptime: uptime + wait.inMilliseconds,
      );
    } else {
      // The wait (already over) is kept as it was.
      final same = _kind == _uptimeKind;
      _save(
        failures,
        _waitUntil,
        fromUptime: same ? _fromUptime : 0,
        untilUptime: same ? _untilUptime : 0,
      );
    }
    return false;
  }
}
