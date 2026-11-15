import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_collection_app/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Daily Collection App smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DailyCollectionApp());
    await tester.pumpAndSettle();

    // Verify Login Screen
    expect(find.text('Staff Sign In'), findsOneWidget);

    // Tap Quick Login button for Akash
    await tester.tap(find.textContaining('Akash'));
    await tester.pump();

    // Tap Log In
    await tester.tap(find.text('Log In to Dashboard'));
    await tester.pumpAndSettle();

    // Verify title and salesman name render on dashboard
    expect(find.textContaining('Purva • Manas'), findsOneWidget);
    expect(find.textContaining('Akash'), findsOneWidget);

    // Verify Quick Actions buttons are present on Dashboard
    expect(find.text('Pending Bills'), findsWidgets);
    expect(find.text('Collection'), findsWidgets);
  });

  testWidgets('Navigating to Pending Bills shows filter and list view',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DailyCollectionApp());
    await tester.pumpAndSettle();

    // Log in
    await tester.tap(find.textContaining('Akash'));
    await tester.pump();
    await tester.tap(find.text('Log In to Dashboard'));
    await tester.pumpAndSettle();

    // Tap Pending Bills button
    await tester.tap(find.text('Pending Bills').first);
    await tester.pumpAndSettle();

    // Verify Pending Bills Screen fields
    expect(find.text('Pending Bills'), findsWidgets);
    expect(find.text('All Firms'), findsOneWidget);
    expect(find.textContaining('Dates'), findsWidgets);
  });
}
