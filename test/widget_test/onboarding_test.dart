import 'package:camelus/routes/nostr/onboarding/onboarding.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('NostrOnboarding widget test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(MaterialApp(home: NostrOnboarding()));

    // Check if the "camelus" title appears
    expect(find.text('camelus'), findsOneWidget);

    // Check if the "early preview" subtitle appears
    expect(find.text('early preview'), findsOneWidget);

    // Check if the "This is your private key:" label appears
    expect(find.text('This is your private key:'), findsOneWidget);

    // Check if the "paste" button appears
    expect(find.widgetWithText(ElevatedButton, 'paste'), findsOneWidget);

    // Check if the "next" button appears
    expect(find.widgetWithText(ElevatedButton, 'next'), findsOneWidget);

    // Check if the "I have read and accept the " label appears
    expect(find.text('I have read and accept the '), findsOneWidget);

    // Check if the "terms and conditions" link appears
    expect(find.text('terms and conditions'), findsOneWidget);

    // Check if the "privacy policy" link appears
    expect(find.text('privacy policy'), findsOneWidget);
  });

  testWidgets('terms not accepted', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(MaterialApp(home: NostrOnboarding()));

    // Find the 'next' button and tap it
    await tester.tap(find.widgetWithText(ElevatedButton, 'next'));
    await tester.pump(); // Rebuild the widget after the button tap

    // Check if the Snackbar is displayed with correct message
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Please read and accept the terms and conditions first'),
        findsOneWidget);
  });

  testWidgets('terms accepted', (WidgetTester tester) async {
    // Build app and trigger a frame.
    await tester.pumpWidget(MaterialApp(home: NostrOnboarding()));

    // Find the checkbox and tap it
    await tester.tap(find.byType(Checkbox));
    await tester.pump(); // Rebuild the widget after the checkbox tap

    // Find the 'next' button and tap it
    await tester.tap(find.widgetWithText(ElevatedButton, 'next'));
    //await tester
    //    .pumpAndSettle(); // Rebuild the widget after the button tap and allow animations to complete

    // Verify success scenario (you would need to specify what happens in your app on success)
    // For example, if the widget navigates to another page, you could check if the current page is no longer in the tree:
    //expect(find.byType(NostrOnboarding), findsNothing);
  });
}
