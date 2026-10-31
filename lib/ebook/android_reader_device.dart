import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'ebook_library.dart';
import 'reader_tools.dart';

/// The phone's side of the reader: keeping the screen on, the brightness,
/// and the volume buttons as page turns. Everything is put back when the
/// reader closes.
class ReaderDevice {
  ReaderDevice._();

  static const _channel = MethodChannel('chapterly/reader');
  static void Function(bool next)? _onVolumeKey;

  static Future<void> _call(String method, [Object? argument]) async {
    try {
      await _channel.invokeMethod<void>(method, argument);
    } catch (_) {
      // Not on a phone (tests), or the phone does not allow it.
    }
  }

  /// Applies [prefs] and sends volume button presses to [onVolumeKey]:
  /// true for the next page, false for the previous one.
  static Future<void> start(
    ReaderPrefs prefs, {
    required void Function(bool next) onVolumeKey,
  }) async {
    _onVolumeKey = onVolumeKey;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'volumeKey') {
        _onVolumeKey?.call(call.arguments == 'next');
      }
      return null;
    });
    await apply(prefs);
  }

  static Future<void> apply(ReaderPrefs prefs) async {
    await _call('keepScreenOn', prefs.keepScreenOn);
    await _call('brightness', prefs.brightness);
    await _call('volumeKeys', prefs.volumeKeys);
  }

  /// Back to the phone's own settings.
  static Future<void> stop() async {
    _onVolumeKey = null;
    await _call('keepScreenOn', false);
    await _call('brightness');
    await _call('volumeKeys', false);
  }
}

/// The phone's text-to-speech voice.
class AndroidSpeaker implements Speaker {
  AndroidSpeaker();

  final _tts = FlutterTts();
  bool _ready = false;
  double _rate = 1.0;

  Future<void> _setUp() async {
    if (_ready) return;
    _ready = true;
    // speak() then finishes only when the text has been read.
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(_rate * 0.5);
  }

  @override
  Future<void> speak(String text) async {
    await _setUp();
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }

  /// On Android 0.5 is the normal speed.
  @override
  Future<void> setRate(double rate) async {
    _rate = rate;
    if (_ready) await _tts.setSpeechRate(rate * 0.5);
  }

  @override
  Future<void> dispose() async {
    await _tts.stop();
  }
}
