import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/home/home_bridge.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('chapterly/home');

  test('sends the widget and the reminder, only when they change', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'takeToggle' ? false : null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    final settings = AppSettings();
    final bridge = HomeBridge(
      repository: repository,
      settings: settings,
      wait: const Duration(milliseconds: 1),
    );
    await bridge.start();
    expect(calls.map((c) => c.method), ['updateWidget', 'setReminder', 'takeToggle']);
    expect((calls.first.arguments as Map)['title'], 'Nothing in progress');

    calls.clear();
    await repository.add(title: 'Dune', author: 'Frank Herbert', shelf: Shelf.inProgress);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls.map((c) => c.method), ['updateWidget']);
    expect((calls.single.arguments as Map)['title'], 'Dune');

    calls.clear();
    settings.setReminder(on: true, minutes: 8 * 60);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls.map((c) => c.method), ['setReminder']);
    expect(calls.single.arguments, {'on': true, 'minutes': 480, 'text': null});

    calls.clear();
    await bridge.push();
    expect(calls, isEmpty);
    bridge.dispose();
  });
}
