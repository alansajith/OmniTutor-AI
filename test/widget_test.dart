import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitutor/main.dart';

void main() {
  testWidgets('OmniTutor app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const OmniTutorApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
