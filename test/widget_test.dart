// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lora_communicator/main.dart';
import 'package:lora_communicator/screens/loading_screen.dart';

void main() {
  testWidgets('Shows LoadingScreen initially', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the LoadingScreen is shown while the remote config is being
    // checked. In a real test environment, you would mock the remote config
    // service to control the outcome.
    expect(find.byType(LoadingScreen), findsOneWidget);
  });
}
