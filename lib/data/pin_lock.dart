import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

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
/// count again. The lock screen and deleting a profile use the same count.
/// Each round of [triesBeforeWait] wrong PINs doubles the wait, from 30
/// seconds up to an hour.
class PinGuard {
  PinGuard(this.prefs, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  /// The profile's settings; null keeps the count in memory only.
  final ScopedPrefs? prefs;
  final DateTime Function() _clock;

  static const triesBeforeWait = 5;
  static const firstWait = Duration(seconds: 30);
  static const longestWait = Duration(hours: 1);

  static const _failuresKey = 'pinFailures';
  static const _waitUntilKey = 'pinWaitUntil';

  int _memoryFailures = 0;
  int _memoryWaitUntil = 0;

  int get _failures => prefs?.getInt(_failuresKey) ?? _memoryFailures;
  int get _waitUntil => prefs?.getInt(_waitUntilKey) ?? _memoryWaitUntil;

  void _save(int failures, int waitUntil) {
    _memoryFailures = failures;
    _memoryWaitUntil = waitUntil;
    prefs?.setInt(_failuresKey, failures);
    prefs?.setInt(_waitUntilKey, waitUntil);
  }

  /// How long until another PIN can be tried (zero when one can now).
  Duration waitLeft() {
    final left = Duration(
      milliseconds: _waitUntil - _clock().millisecondsSinceEpoch,
    );
    if (left <= Duration.zero) return Duration.zero;
    // A clock that was put back can't make the wait longer than any wait.
    return left > longestWait ? longestWait : left;
  }

  /// Checks [pin] with [check], counting it when it is wrong. Returns
  /// whether it was right; a try while waiting is never checked.
  bool attempt(String pin, bool Function(String pin) check) {
    if (waitLeft() > Duration.zero) return false;
    if (check(pin)) {
      if (_failures != 0 || _waitUntil != 0) _save(0, 0);
      return true;
    }
    final failures = _failures + 1;
    var waitUntil = _waitUntil;
    if (failures % triesBeforeWait == 0) {
      final round = failures ~/ triesBeforeWait - 1;
      var wait = firstWait * (1 << (round > 7 ? 7 : round));
      if (wait > longestWait) wait = longestWait;
      waitUntil = _clock().add(wait).millisecondsSinceEpoch;
    }
    _save(failures, waitUntil);
    return false;
  }
}
