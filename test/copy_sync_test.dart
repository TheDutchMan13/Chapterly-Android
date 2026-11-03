import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/file_io.dart';
import 'package:chapterly/data/phone_sync.dart';
import 'package:chapterly/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tapping the pairing code copies it without dashes',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    final settings = AppSettings()
      ..setSyncEnabled(true)
      ..setSyncCode('ABCDEFGHJKMNPQRS');
    final phoneSync = PhoneSync(repository: repository, settings: settings);
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        repository: repository,
        settings: settings,
        phoneSync: phoneSync,
        fileIo: FileIo(),
      ),
    ));
    await tester.pump();
    final code = find.text('ABCD-EFGH-JKMN-PQRS');
    await tester.scrollUntilVisible(code, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(code);
    await tester.pumpAndSettle();
    await tester.tap(code);
    await tester.pump();
    expect(copied, 'ABCDEFGHJKMNPQRS');
    expect(find.text('Pairing code copied'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
