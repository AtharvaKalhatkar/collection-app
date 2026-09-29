import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_collection_app/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Daily Collection App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const DailyCollectionApp());
    // Pump past the async initialize
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify title and salesman name render
    expect(find.textContaining('Purva Enterprises • Manas Sales'), findsOneWidget);
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Tap Pending Bills button
    await tester.tap(find.text('Pending Bills').first);
    await tester.pumpAndSettle();

    // Verify Pending Bills Screen fields
    expect(find.text('Pending Bills by Date'), findsOneWidget);
    expect(find.text('All Firms'), findsOneWidget);
    expect(find.textContaining('Invoice Dates'), findsOneWidget);
  });
}
