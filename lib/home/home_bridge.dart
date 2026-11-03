import 'dart:async';

import 'package:flutter/services.dart';

import '../audio/listen_controller.dart';
import '../data/app_settings.dart';
import '../data/book_repository.dart';
import '../screens/book_insights.dart' show forecastFor;
import '../data/reading_nudge.dart';
import '../models/shelf.dart';

/// Keeps Android's side up to date: the home-screen widget (the book you're
/// reading or listening to) and the daily reading reminder (its words for
/// today, or none when you're on track). MainActivity.kt has the other end.
class HomeBridge {
  HomeBridge({
    required this.repository,
    required this.settings,
    this.controller,
    MethodChannel? channel,
    this.wait = const Duration(seconds: 1),
  }) : _channel = channel ?? const MethodChannel('chapterly/home');

  final BookRepository repository;
  final AppSettings settings;
  final ListenController? controller;
  final Duration wait;
  final MethodChannel _channel;
  Timer? _timer;
  String? _lastWidget;
  String? _lastReminder;

  /// Starts listening, sends the first update, and plays or pauses if the
  /// widget's button opened the app.
  Future<void> start() async {
    repository.addListener(_soon);
    settings.addListener(_soon);
    controller?.addListener(_soon);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'toggle') await toggle();
    });
    await push();
    try {
      if (await _channel.invokeMethod<bool>('takeToggle') == true) await toggle();
    } on MissingPluginException {
      // Not on Android.
    }
  }

  void dispose() {
    _timer?.cancel();
    repository.removeListener(_soon);
    settings.removeListener(_soon);
    controller?.removeListener(_soon);
  }

  void _soon() {
    _timer?.cancel();
    _timer = Timer(wait, () => unawaited(push()));
  }

  /// The widget's play/pause: the audiobook in the player, or the one the
  /// widget shows.
  Future<void> toggle() async {
    final player = controller;
    if (player == null) return;
    if (player.bookId != null) {
      await player.toggle();
      return;
    }
    final content = _content();
    final bookId = content.bookId;
    if (content.audio && bookId != null) await player.open(bookId);
  }

  WidgetContent _content() => widgetContent(
        repository.books,
        playerBookId: controller?.bookId,
        playing: controller?.playing ?? false,
      );

  /// Sends what changed. Nothing is sent when nothing changed.
  Future<void> push() async {
    final content = _content();
    final widget = [
      content.title, content.author, content.detail, content.audio, content.playing,
    ].join('\u0000');
    final year = DateTime.now().year;
    final text = reminderText(
      repository.books,
      goal: settings.goalFor(year),
      finishDates: [
        for (final book in repository.booksOn(Shelf.inProgress))
          if (forecastFor(book) case final forecast?) forecast.date,
      ],
    );
    final reminder = '${settings.reminderOn}|${settings.reminderMinutes}|$text';
    try {
      if (widget != _lastWidget) {
        await _channel.invokeMethod<void>('updateWidget', {
          'title': content.title,
          'author': content.author,
          'detail': content.detail,
          'audio': content.audio,
          'playing': content.playing,
        });
        _lastWidget = widget;
      }
      if (reminder != _lastReminder) {
        await _channel.invokeMethod<void>('setReminder', {
          'on': settings.reminderOn,
          'minutes': settings.reminderMinutes,
          'text': text,
        });
        _lastReminder = reminder;
      }
    } on MissingPluginException {
      // Not on Android (tests).
    } on PlatformException {
      // Tried again with the next change.
    }
  }

  /// Asks Android for permission to show the reminder. True when allowed.
  static Future<bool> askNotifications() async {
    try {
      return await const MethodChannel('chapterly/home')
              .invokeMethod<bool>('askNotifications') ??
          false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }
}
