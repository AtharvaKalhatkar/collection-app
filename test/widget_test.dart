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

    // Verify Add Store action is present on Dashboard
    expect(find.text('Add Store'), findsWidgets);
  });

  testWidgets('Navigating to Add Store shows all required form fields',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DailyCollectionApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Tap Add Store button
    await tester.tap(find.text('Add Store').first);
    await tester.pumpAndSettle();

    // Verify Add Store Screen fields: Store Name, Route, Contact Number, Address
    expect(find.text('Add New Store'), findsOneWidget);
    expect(find.text('Store / Business Name *'), findsOneWidget);
    expect(find.text('Beat Route'), findsOneWidget);
    expect(find.text('Contact / Mobile Number *'), findsOneWidget);
    expect(find.text('Store Address / Location *'), findsOneWidget);
  });
}
