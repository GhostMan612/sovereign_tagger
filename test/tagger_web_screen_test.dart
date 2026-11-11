// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_tagger/screens/tagger_web_screen.dart';

void main() {
  testWidgets('in-app browser rejects an unapproved HTTPS host before loading', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TaggerWebScreen(
          uri: Uri.parse('https://example.test/login'),
          title: 'Unapproved',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('PAGE UNAVAILABLE'), findsOneWidget);
    expect(find.text('This website is not an approved in-app source.'), findsOneWidget);
  });

  testWidgets('in-app browser rejects insecure HTTP before loading', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TaggerWebScreen(
          uri: Uri.parse('http://genius.com/api-clients'),
          title: 'Insecure',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('PAGE UNAVAILABLE'), findsOneWidget);
    expect(find.text('This website is not an approved in-app source.'), findsOneWidget);
  });
}
