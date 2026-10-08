import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_collection_app/models/collection_model.dart';
import 'package:daily_collection_app/providers/collection_provider.dart';
import 'package:daily_collection_app/screens/orders_screen.dart';
import 'package:daily_collection_app/screens/statement_screen.dart';
import 'package:daily_collection_app/widgets/add_product_dialog.dart';
import 'package:daily_collection_app/services/order_catalog_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestApp({required Widget child, required CollectionProvider provider}) {
    return ChangeNotifierProvider<CollectionProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(body: child),
      ),
    );
  }

  group('Challenge Area 1: Dropdown State Reactivity & Cascading Edge Cases', () {
    testWidgets('OrdersScreen: Cascading firm switch resets company, category, and quick SKU without assertion failures', (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final provider = CollectionProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      await tester.pumpWidget(buildTestApp(child: const OrdersScreen(), provider: provider));
      await tester.pumpAndSettle();

      // Initially Purva Enterprises is selected
      expect(find.text('Purva Enterprises'), findsWidgets);

      // Verify Wipro (default company for Purva) is present
      expect(find.text('Wipro'), findsWidgets);

      // Find the Firm DropdownFormField
      final firmDropdownFinder = find.byKey(const ValueKey('order_firm_Purva Enterprises'));
      expect(firmDropdownFinder, findsOneWidget);

      // Tap to switch firm to Manas Sales
      await tester.tap(firmDropdownFinder);
      await tester.pumpAndSettle();

      // Pick 'Manas Sales' in dropdown popup menu
      final manasItemFinder = find.widgetWithText(DropdownMenuItem<String>, 'Manas Sales').last;
      await tester.tap(manasItemFinder);
      await tester.pumpAndSettle();

      // Verification: Firm changed to Manas Sales, company updated to Racket (first company of Manas)
      expect(find.text('Manas Sales'), findsWidgets);
      expect(find.text('Racket'), findsWidgets);

      // Switch back to Purva Enterprises
      final manasDropdownFinder = find.byKey(const ValueKey('order_firm_Manas Sales'));
      expect(manasDropdownFinder, findsOneWidget);

      await tester.tap(manasDropdownFinder);
      await tester.pumpAndSettle();

      final purvaItemFinder = find.widgetWithText(DropdownMenuItem<String>, 'Purva Enterprises').last;
      await tester.tap(purvaItemFinder);
      await tester.pumpAndSettle();

      // Back to Purva, company reset to Wipro
      expect(find.text('Purva Enterprises'), findsWidgets);
      expect(find.text('Wipro'), findsWidgets);
    });

    testWidgets('OrdersScreen: Changing route resets selected shop without FormField assertion errors', (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final provider = CollectionProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      await tester.pumpWidget(buildTestApp(child: const OrdersScreen(), provider: provider));
      await tester.pumpAndSettle();

      // Find route dropdown
      final routeDropdownFinder = find.byKey(const ValueKey('order_route_none'));
      expect(routeDropdownFinder, findsOneWidget);

      // Select Route 1 (Chakan Beat)
      await tester.tap(routeDropdownFinder);
      await tester.pumpAndSettle();

      final chakanRouteFinder = find.textContaining('Chakan').last;
      await tester.tap(chakanRouteFinder);
      await tester.pumpAndSettle();

      // Verify route is selected, shop dropdown now has Chakan shops
      expect(find.byKey(const ValueKey('order_shop_none')), findsOneWidget);

      // Tap shop dropdown and pick a shop (ATA Kirana)
      await tester.tap(find.byKey(const ValueKey('order_shop_none')));
      await tester.pumpAndSettle();

      final ataShopFinder = find.textContaining('ATA Kirana').last;
      await tester.tap(ataShopFinder);
      await tester.pumpAndSettle();

      // Verify ATA Kirana is selected
      expect(find.textContaining('ATA Kirana'), findsWidgets);

      // Now switch route to Shikrapur Beat (where ATA Kirana is NOT present)
      final routeActiveFinder = find.byKey(const ValueKey('order_route_route-chakan'));
      expect(routeActiveFinder, findsOneWidget);

      await tester.tap(routeActiveFinder);
      await tester.pumpAndSettle();

      final shikrapurRouteFinder = find.textContaining('Shikrapur').last;
      await tester.tap(shikrapurRouteFinder);
      await tester.pumpAndSettle();

      // Verify shop dropdown cleanly reverted to order_shop_none without assertion failure
      expect(find.byKey(const ValueKey('order_shop_none')), findsOneWidget);
    });

    testWidgets('AddProductDialog: Firm toggle Purva <-> Manas updates company and category options without assertions', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddProductDialog(
              initialFirm: OrderCatalogService.purva,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial state is Purva Enterprises, default company Wipro
      expect(find.text('Wipro'), findsWidgets);

      // Tap MANAS SALES button
      await tester.tap(find.text('MANAS SALES'));
      await tester.pumpAndSettle();

      // Now company should be Racket (default first company of Manas)
      expect(find.text('Racket'), findsWidgets);
      expect(find.byKey(const ValueKey('add_prod_company_Manas Sales_Racket')), findsOneWidget);

      // Tap PURVA ENTERPRISES button
      await tester.tap(find.text('PURVA ENTERPRISES'));
      await tester.pumpAndSettle();

      // Back to Purva, company is Wipro
      expect(find.text('Wipro'), findsWidgets);
      expect(find.byKey(const ValueKey('add_prod_company_Purva Enterprises_Wipro')), findsOneWidget);

      // Toggle + New Company and back to Choose Existing
      await tester.tap(find.text('+ New Company'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsWidgets);

      await tester.tap(find.text('Choose Existing'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('add_prod_company_Purva Enterprises_Wipro')), findsOneWidget);
    });
  });

  group('Challenge Area 2: Statement Date Range Boundaries & Filtering', () {
    testWidgets('Date boundaries: 00:00:00 included, 23:59:59.999 included, adjacent days excluded', (tester) async {
      final targetDate = DateTime(2026, 10, 5);

      final startOfDayExact = DateTime(2026, 10, 5, 0, 0, 0, 0);
      final midday = DateTime(2026, 10, 5, 14, 30, 0);
      final endOfDayExact = DateTime(2026, 10, 5, 23, 59, 59, 999);
      final priorDay = DateTime(2026, 10, 4, 23, 59, 59, 999);
      final nextDay = DateTime(2026, 10, 6, 0, 0, 0, 0);

      final provider = CollectionProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      // Clear existing sample collections
      for (final col in List.of(provider.collections)) {
        await provider.deleteCollection(col.id);
      }

      await provider.addCollection(CollectionModel(
        id: 'c-start',
        businessName: 'Purva Enterprises',
        shopId: 'shop-ata-kirana',
        shopName: 'Start Shop',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        billNumber: 'B-001',
        billAmount: 1000,
        collectedAmount: 1000,
        balanceRemaining: 0,
        paymentMode: PaymentMode.cash,
        salesmanName: 'Akash',
        collectedAt: startOfDayExact,
      ));

      await provider.addCollection(CollectionModel(
        id: 'c-mid',
        businessName: 'Purva Enterprises',
        shopId: 'shop-ata-kirana',
        shopName: 'Mid Shop',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        billNumber: 'B-002',
        billAmount: 1000,
        collectedAmount: 1000,
        balanceRemaining: 0,
        paymentMode: PaymentMode.upi,
        salesmanName: 'Akash',
        collectedAt: midday,
      ));

      await provider.addCollection(CollectionModel(
        id: 'c-end',
        businessName: 'Purva Enterprises',
        shopId: 'shop-ata-kirana',
        shopName: 'End Shop',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        billNumber: 'B-003',
        billAmount: 1000,
        collectedAmount: 1000,
        balanceRemaining: 0,
        paymentMode: PaymentMode.cheque,
        salesmanName: 'Akash',
        collectedAt: endOfDayExact,
      ));

      await provider.addCollection(CollectionModel(
        id: 'c-prior',
        businessName: 'Purva Enterprises',
        shopId: 'shop-ata-kirana',
        shopName: 'Prior Shop',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        billNumber: 'B-000',
        billAmount: 1000,
        collectedAmount: 1000,
        balanceRemaining: 0,
        paymentMode: PaymentMode.cash,
        salesmanName: 'Akash',
        collectedAt: priorDay,
      ));

      await provider.addCollection(CollectionModel(
        id: 'c-next',
        businessName: 'Purva Enterprises',
        shopId: 'shop-ata-kirana',
        shopName: 'Next Shop',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        billNumber: 'B-004',
        billAmount: 1000,
        collectedAmount: 1000,
        balanceRemaining: 0,
        paymentMode: PaymentMode.cash,
        salesmanName: 'Akash',
        collectedAt: nextDay,
      ));

      // Mount StatementScreen configured for single day 2026-10-05
      await tester.pumpWidget(
        buildTestApp(
          child: StatementScreen(
            initialDate: targetDate,
          ),
          provider: provider,
        ),
      );
      await tester.pumpAndSettle();

      // Check displayed items: Start, Mid, End must be present; Prior, Next must NOT be present
      expect(find.text('Start Shop'), findsOneWidget);
      expect(find.text('Mid Shop'), findsOneWidget);
      expect(find.text('End Shop'), findsOneWidget);
      expect(find.text('Prior Shop'), findsNothing);
      expect(find.text('Next Shop'), findsNothing);
    });

    test('Microsecond edge case analysis on end of day boundary', () {
      final endDate = DateTime(2026, 10, 5);
      final endOfDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);

      final exactMillis = DateTime(2026, 10, 5, 23, 59, 59, 999);
      final withMicroseconds = DateTime(2026, 10, 5, 23, 59, 59, 999, 999);

      // Exact millisecond matches boundary and is not excluded
      expect(exactMillis.isAfter(endOfDay), isFalse);

      // Microseconds > 0 makes isAfter(endOfDay) true!
      // This documents the precision threshold in StatementScreen.
      expect(withMicroseconds.isAfter(endOfDay), isTrue);
    });

    testWidgets('Multi-day date range filtering (Oct 1 to Oct 5) correctly filters boundary items', (tester) async {
      final range = DateTimeRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 5));

      final provider = CollectionProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      for (final col in List.of(provider.collections)) {
        await provider.deleteCollection(col.id);
      }

      await provider.addCollection(CollectionModel(
        id: 'c1',
        businessName: 'Purva Enterprises',
        shopId: 'shop-ata-kirana',
        shopName: 'Day 1 Shop',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        billNumber: 'B-01',
        billAmount: 1000,
        collectedAmount: 1000,
        balanceRemaining: 0,
        paymentMode: PaymentMode.cash,
        salesmanName: 'Akash',
        collectedAt: DateTime(2026, 10, 1, 8, 0),
      ));

      await provider.addCollection(CollectionModel(
        id: 'c3',
        businessName: 'Purva Enterprises',
        shopId: 'shop-ata-kirana',
        shopName: 'Day 3 Shop',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        billNumber: 'B-03',
        billAmount: 1000,
        collectedAmount: 1000,
        balanceRemaining: 0,
        paymentMode: PaymentMode.cash,
        salesmanName: 'Akash',
        collectedAt: DateTime(2026, 10, 3, 12, 0),
      ));

      await provider.addCollection(CollectionModel(
        id: 'c5',
        businessName: 'Purva Enterprises',
        shopId: 'shop-ata-kirana',
        shopName: 'Day 5 Shop',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        billNumber: 'B-05',
        billAmount: 1000,
        collectedAmount: 1000,
        balanceRemaining: 0,
        paymentMode: PaymentMode.cash,
        salesmanName: 'Akash',
        collectedAt: DateTime(2026, 10, 5, 22, 0),
      ));

      await provider.addCollection(CollectionModel(
        id: 'cout',
        businessName: 'Purva Enterprises',
        shopId: 'shop-ata-kirana',
        shopName: 'Day 6 Shop',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        billNumber: 'B-06',
        billAmount: 1000,
        collectedAmount: 1000,
        balanceRemaining: 0,
        paymentMode: PaymentMode.cash,
        salesmanName: 'Akash',
        collectedAt: DateTime(2026, 10, 6, 9, 0),
      ));

      await tester.pumpWidget(
        buildTestApp(
          child: StatementScreen(
            initialDateRange: range,
          ),
          provider: provider,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Day 1 Shop'), findsOneWidget);
      expect(find.text('Day 3 Shop'), findsOneWidget);
      expect(find.text('Day 5 Shop'), findsOneWidget);
      expect(find.text('Day 6 Shop'), findsNothing);
    });

    testWidgets('Toggling "All Dates" displays records across entire historical dataset', (tester) async {
      final provider = CollectionProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      for (final col in List.of(provider.collections)) {
        await provider.deleteCollection(col.id);
      }

      await provider.addCollection(CollectionModel(
        id: 'c-old',
        businessName: 'Purva Enterprises',
        shopId: 'shop-ata-kirana',
        shopName: 'Old Historic Shop',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        billNumber: 'B-OLD',
        billAmount: 2000,
        collectedAmount: 2000,
        balanceRemaining: 0,
        paymentMode: PaymentMode.cash,
        salesmanName: 'Akash',
        collectedAt: DateTime(2025, 5, 10, 10, 0),
      ));

      await provider.addCollection(CollectionModel(
        id: 'c-today',
        businessName: 'Purva Enterprises',
        shopId: 'shop-ata-kirana',
        shopName: 'Today Shop',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        billNumber: 'B-NOW',
        billAmount: 1000,
        collectedAmount: 1000,
        balanceRemaining: 0,
        paymentMode: PaymentMode.cash,
        salesmanName: 'Akash',
        collectedAt: DateTime.now(),
      ));

      await tester.pumpWidget(
        buildTestApp(
          child: const StatementScreen(),
          provider: provider,
        ),
      );
      await tester.pumpAndSettle();

      // Today record is visible, old record is hidden initially
      expect(find.text('Today Shop'), findsOneWidget);
      expect(find.text('Old Historic Shop'), findsNothing);

      // Tap close icon on Date Range button to toggle "All Dates"
      final closeDateIcon = find.byIcon(Icons.close);
      expect(closeDateIcon, findsOneWidget);
      await tester.tap(closeDateIcon);
      await tester.pumpAndSettle();

      // Now both records are visible and text says "All Dates"
      expect(find.text('All Dates'), findsWidgets);
      expect(find.text('Today Shop'), findsOneWidget);
      expect(find.text('Old Historic Shop'), findsOneWidget);
    });
  });

  group('Challenge Area 3: Route & Outlet Cascading Filter Combinations', () {
    testWidgets('Switching routes resets selected outlet if not present in new route', (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final provider = CollectionProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      for (final col in List.of(provider.collections)) {
        await provider.deleteCollection(col.id);
      }

      // Add collections for Chakan route (ATA Kirana) and Shikrapur route (Shree Ganesh)
      await provider.addCollection(CollectionModel(
        id: 'c1',
        businessName: 'Purva Enterprises',
        shopId: 'shop-ata-kirana',
        shopName: 'ATA Kirana',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        billNumber: 'B1',
        billAmount: 1000,
        collectedAmount: 1000,
        balanceRemaining: 0,
        paymentMode: PaymentMode.cash,
        salesmanName: 'Akash',
        collectedAt: DateTime.now(),
      ));

      await provider.addCollection(CollectionModel(
        id: 'c2',
        businessName: 'Purva Enterprises',
        shopId: 'shop-shree-ganesh',
        shopName: 'Shree Ganesh Super Market',
        routeId: 'route-shikrapur',
        routeName: 'Shikrapur',
        billNumber: 'B2',
        billAmount: 1500,
        collectedAmount: 1500,
        balanceRemaining: 0,
        paymentMode: PaymentMode.upi,
        salesmanName: 'Akash',
        collectedAt: DateTime.now(),
      ));

      await tester.pumpWidget(
        buildTestApp(
          child: const StatementScreen(),
          provider: provider,
        ),
      );
      await tester.pumpAndSettle();

      // Select Route: Chakan
      await tester.tap(find.text('All Routes').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chakan').last);
      await tester.pumpAndSettle();

      // Select Outlet: ATA Kirana
      await tester.tap(find.text('All Outlets').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('ATA Kirana').last);
      await tester.pumpAndSettle();

      // Only ATA Kirana collection is shown
      expect(find.text('ATA Kirana'), findsWidgets);
      expect(find.text('Shree Ganesh Super Market'), findsNothing);

      // Now switch Route to Shikrapur
      await tester.tap(find.text('Chakan').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Shikrapur').last);
      await tester.pumpAndSettle();

      // Verification: Outlet was cleared to 'All Outlets', Shree Ganesh Super Market is now visible
      expect(find.text('Shree Ganesh Super Market'), findsWidgets);
      expect(find.text('All Outlets'), findsWidgets);

      // Test Reset Filters button
      expect(find.text('Reset'), findsOneWidget);
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      // Both records visible, routes reset to 'All Routes'
      expect(find.text('All Routes'), findsWidgets);
      expect(find.text('ATA Kirana'), findsWidgets);
      expect(find.text('Shree Ganesh Super Market'), findsWidgets);
    });
  });
}
