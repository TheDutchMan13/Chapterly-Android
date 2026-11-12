import 'package:chapterly/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an empty page says what is missing and what to do', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: EmptyState(
          icon: Icons.auto_stories_outlined,
          title: 'No books on this shelf yet.',
          hint: 'Add one with the + button.',
        ),
      ),
    ));
    expect(find.text('No books on this shelf yet.'), findsOneWidget);
    expect(find.text('Add one with the + button.'), findsOneWidget);
    expect(find.byIcon(Icons.auto_stories_outlined), findsOneWidget);
  });
}
