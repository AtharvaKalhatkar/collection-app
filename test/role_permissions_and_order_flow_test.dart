import 'dart:convert';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_collection_app/main.dart';
import 'package:daily_collection_app/models/order_model.dart';
import 'package:daily_collection_app/models/pending_bill_model.dart';
import 'package:daily_collection_app/models/route_model.dart';
import 'package:daily_collection_app/models/shop_model.dart';
import 'package:daily_collection_app/models/user_model.dart';
import 'package:daily_collection_app/providers/auth_provider.dart';
import 'package:daily_collection_app/providers/collection_provider.dart';
import 'package:daily_collection_app/screens/admin_products_screen.dart';
import 'package:daily_collection_app/screens/all_orders_screen.dart';
import 'package:daily_collection_app/screens/driver_dashboard_screen.dart';
import 'package:daily_collection_app/screens/order_dashboard_screen.dart';
import 'package:daily_collection_app/screens/outlet_order_booking_screen.dart';
import 'package:daily_collection_app/services/order_catalog_service.dart';
import 'package:daily_collection_app/services/tally_integration_service.dart';
import 'package:daily_collection_app/widgets/add_product_dialog.dart';
import 'package:daily_collection_app/widgets/assign_routes_dialog.dart';
import 'package:daily_collection_app/widgets/payment_qr_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Role Permissions Matrix (All 6 Staff Roles)', () {
    test('enforces exact Order, Assign Routes, and Tally permissions per role', () {
      final superAdmin = UserModel(
        id: '1',
        phone: '9921977636',
        name: 'Super Admin',
        role: UserRole.superAdmin,
        password: 'p',
      );
      final salesAndColl = UserModel(
        id: '2',
        phone: '8390768833',
        name: 'Atharva',
        role: UserRole.salesman,
        password: 'p',
      );
      final collectionOnly = UserModel(
        id: '3',
        phone: '9000000003',
        name: 'Collector 1',
        role: UserRole.collection,
        password: 'p',
      );
      final salesOrder = UserModel(
        id: '4',
        phone: 'order1',
        name: 'Order 1',
        role: UserRole.order,
        password: 'p',
      );
      final office = UserModel(
        id: '5',
        phone: '7620995547',
        name: 'Office Staff 1',
        role: UserRole.office,
        password: 'p',
      );
      final driver = UserModel(
        id: '6',
        phone: 'user1',
        name: 'Driver',
        role: UserRole.driver,
        password: 'p',
      );

      // Orders visible: Super Admin, Office, Sales & Coll (Akash/Atharva), Sales (order)
      // Orders hidden: Collection-only, Driver
      expect(superAdmin.canAccessOrders, isTrue);
      expect(salesAndColl.canAccessOrders, isTrue);
      expect(office.canAccessOrders, isTrue);
      expect(salesOrder.canAccessOrders, isTrue);
      expect(collectionOnly.canAccessOrders, isFalse);
      expect(driver.canAccessOrders, isFalse);

      // Assign Routes: ONLY Super Admin, Collection, Sales & Collection, Sales
      expect(superAdmin.canAssignRoutes, isTrue);
      expect(salesAndColl.canAssignRoutes, isTrue);
      expect(collectionOnly.canAssignRoutes, isTrue);
      expect(salesOrder.canAssignRoutes, isTrue);
      expect(office.canAssignRoutes, isFalse);
      expect(driver.canAssignRoutes, isFalse);

      // Tally Hub: ONLY Super Admin & Office
      expect(superAdmin.canAccessTally, isTrue);
      expect(office.canAccessTally, isTrue);
      expect(salesAndColl.canAccessTally, isFalse);
      expect(collectionOnly.canAccessTally, isFalse);
      expect(salesOrder.canAccessTally, isFalse);
      expect(driver.canAccessTally, isFalse);
    });

    test('serializes and parses UserRole.collection and per-login routes cleanly', () {
      final collector = UserModel(
        id: 'user_col_1',
        phone: '9111122222',
        name: 'Ramesh',
        role: UserRole.collection,
        password: 'secret',
        assignedRouteIds: const ['r_chakan', 'r_khed'],
      );
      final restored = UserModel.fromJson(collector.toJson());
      expect(restored.role, UserRole.collection);
      expect(restored.isCollection, isTrue);
      expect(restored.canAccessOrders, isFalse);
      expect(restored.canAssignRoutes, isTrue);
      expect(restored.assignedRouteIds, const ['r_chakan', 'r_khed']);
    });
  });

  group('4-Tab Navigation & Role Feature Gating Widgets', () {
    testWidgets('Sales & Coll (Akash) shows 4 tabs, Book Orders, All Booked Orders, and Assign Routes',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const DailyCollectionApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Akash').first);
      await tester.pump();
      await tester.tap(find.text('Log In to Dashboard'));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(find.text('Book Orders'), findsOneWidget);
      expect(find.text('All Booked Orders'), findsOneWidget);
      expect(find.text('Assign Routes'), findsOneWidget);
      expect(find.text('Tally Hub'), findsNothing);
    });

    testWidgets('Collection-only login shows Assign Routes and hides Order options',
        (tester) async {
      final colUser = UserModel(
        id: 'user_col_test',
        phone: '9888877777',
        name: 'Suresh',
        role: UserRole.collection,
        password: 'pass123',
      );
      SharedPreferences.setMockInitialValues({
        'app_users_cache_v1': jsonEncode([
          ...UserModel.getInitialUsers().map((u) => u.toJson()),
          colUser.toJson(),
        ]),
        'current_logged_in_user_id_v1': colUser.id,
      });

      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const DailyCollectionApp());
      await tester.pumpAndSettle();

      expect(find.text('Suresh'), findsWidgets);
      expect(find.text('Assign Routes'), findsOneWidget);
      expect(find.text('Book Orders'), findsNothing);
      expect(find.text('All Booked Orders'), findsNothing);
      expect(find.text('Tally Hub'), findsNothing);
    });

    testWidgets('Office Staff login shows Orders & Tally Hub and hides Assign Routes',
        (tester) async {
      final officeUser = UserModel.getInitialUsers().firstWhere((u) => u.isOffice);
      SharedPreferences.setMockInitialValues({
        'current_logged_in_user_id_v1': officeUser.id,
      });

      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const DailyCollectionApp());
      await tester.pumpAndSettle();

      expect(find.text('Book Orders'), findsOneWidget);
      expect(find.text('All Booked Orders'), findsOneWidget);
      expect(find.text('Tally Hub'), findsOneWidget);
      expect(find.text('Assign Routes'), findsNothing);
    });
  });

  group('Assign Routes & Order Edit Integrity Tests', () {
    testWidgets('AssignRoutesDialog switches between users cleanly and saves distinct routes',
        (tester) async {
      final r1 = RouteModel(id: 'r1', name: 'Chakan');
      final r2 = RouteModel(id: 'r2', name: 'Bhosari');
      final akash = UserModel(
        id: 'u_akash',
        phone: '9309862465',
        name: 'Akash',
        role: UserRole.salesman,
        password: 'pass123',
        assignedRouteIds: const ['r1'],
      );
      final atharva = UserModel(
        id: 'u_atharva',
        phone: '8390768833',
        name: 'Atharva',
        role: UserRole.salesman,
        password: 'pass123',
        assignedRouteIds: const ['r2'],
      );
      final admin = UserModel(
        id: 'u_admin',
        phone: '9921977636',
        name: 'Super Admin',
        role: UserRole.superAdmin,
        password: 'pass123',
      );

      SharedPreferences.setMockInitialValues({
        'app_sample_data_initialized_v1': true,
        'app_users_cache_v1': jsonEncode([admin.toJson(), akash.toJson(), atharva.toJson()]),
        'current_logged_in_user_id_v1': admin.id,
        'app_routes_v1': [jsonEncode(r1.toJson()), jsonEncode(r2.toJson())],
        'app_shops_v1': <String>[],
      });

      final auth = AuthProvider();
      final collection = CollectionProvider();
      await auth.initialize();
      await collection.initialize();

      tester.view.physicalSize = const Size(480, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: collection),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AssignRoutesDialog(initialUser: akash),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch selected staff dropdown to Atharva
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Atharva (Sales & Collection)').last);
      await tester.pumpAndSettle();

      // Now assign Chakan (r1) also to Atharva and save
      await tester.tap(find.text('Chakan'));
      await tester.pump();
      await tester.tap(find.text('Save Routes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final savedAtharva = auth.users.firstWhere((u) => u.id == atharva.id);
      final savedAkash = auth.users.firstWhere((u) => u.id == akash.id);
      expect(savedAtharva.assignedRouteIds, containsAll(['r1', 'r2']));
      expect(savedAkash.assignedRouteIds, ['r1']);
    });

    testWidgets('Editing an existing Billed SalesOrderModel preserves status instead of resetting to Booked',
        (tester) async {
      final shop = ShopModel(
        id: 's1',
        name: 'Om Sai Super Market',
        routeId: 'r1',
        routeName: 'Chakan',
        mobileNumber: '9999999999',
        address: 'Main Road',
      );
      final billedOrder = SalesOrderModel(
        id: 'ord_existing_1',
        orderNumber: 'ORD-261125-1001',
        firm: 'Manas Sales',
        routeId: 'r1',
        routeName: 'Chakan',
        shopId: 's1',
        shopName: 'Om Sai Super Market',
        shopMobile: '9999999999',
        salesmanName: 'Akash',
        orderDate: DateTime(2026, 11, 25),
        items: [
          OrderItem(
            productId: 'p1',
            productName: 'Test Item',
            company: 'Test Co',
            category: 'Cat',
            packing: '100g',
            rate: 50,
            quantity: 24,
            cases: 1,
            units: 0,
            unitsPerCase: 24,
          ),
        ],
        totalAmount: 1200,
        totalQuantity: 24,
        status: 'Billed',
      );

      SharedPreferences.setMockInitialValues({
        'app_sample_data_initialized_v1': true,
        'app_sales_orders_v1': [jsonEncode(billedOrder.toJson())],
      });

      final auth = AuthProvider();
      final collection = CollectionProvider();
      await auth.initialize();
      await collection.initialize();

      tester.view.physicalSize = const Size(480, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: collection),
          ],
          child: MaterialApp(
            home: OutletOrderBookingScreen(
              shop: shop,
              selectedDate: DateTime(2026, 11, 25),
              existingOrder: billedOrder,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Submit Order tab and submit edit
      await tester.tap(find.text('Submit Order'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit Order'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      final saved = collection.salesOrders.firstWhere((o) => o.id == 'ord_existing_1');
      expect(saved.status, 'Billed');
      expect(saved.firm, 'Manas Sales');
    });

    testWidgets('Unassigned Driver sees 0 routes, 0 shops, 0 bills, and ZERO bottom nav count badges',
        (tester) async {
      final r1 = RouteModel(id: 'r_chakan', name: 'Chakan');
      final s1 = ShopModel(
        id: 's1',
        name: 'G R Mart',
        routeId: 'r_chakan',
        routeName: 'Chakan',
        mobileNumber: '9850070556',
        address: 'Main Road',
      );
      final b1 = PendingBillModel(
        id: 'b1',
        businessName: 'Purva Enterprises',
        shopId: 's1',
        shopName: 'G R Mart',
        routeId: 'r_chakan',
        routeName: 'Chakan',
        billNumber: 'INV-1',
        totalAmount: 1000,
        collectedAmount: 0,
        status: 'pending',
        invoiceDate: DateTime.now(),
        deliveryDate: DateTime.now(),
        createdAt: DateTime.now(),
      );
      final driver = UserModel(
        id: 'user_driver_user1',
        phone: 'user1',
        name: 'Driver',
        role: UserRole.driver,
        password: 'user123',
        assignedRouteIds: const [],
      );

      SharedPreferences.setMockInitialValues({
        'app_sample_data_initialized_v1': true,
        'app_users_cache_v1': jsonEncode([driver.toJson()]),
        'current_logged_in_user_id_v1': driver.id,
        'app_routes_v1': [jsonEncode(r1.toJson())],
        'app_shops_v1': [jsonEncode(s1.toJson())],
        'app_pending_bills_v1': [jsonEncode(b1.toJson())],
      });

      final auth = AuthProvider();
      final collection = CollectionProvider();
      await auth.initialize();
      await collection.initialize();
      collection.setCurrentUser(auth.currentUser);

      // Provider scoping: unassigned Driver must get 0 routes, 0 shops, 0 bills
      expect(collection.routes, isEmpty);
      expect(collection.shops, isEmpty);
      expect(collection.pendingBills, isEmpty);

      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: collection),
          ],
          child: const MaterialApp(
            home: DriverDashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No Delivery Route Assigned Today'), findsOneWidget);
      final visibleBadges = find.byWidgetPredicate(
        (w) => w is Badge && w.isLabelVisible,
      );
      expect(visibleBadges, findsNothing);
    });

    test('deleteSalesOrder persists durable tombstones so stale caches cannot resurrect deleted orders',
        () async {
      final ord1 = SalesOrderModel(
        id: 'ord-1795324988775',
        orderNumber: 'ORD-261122-7802',
        firm: 'Purva Enterprises',
        routeId: 'r1',
        routeName: 'Kharabwadi',
        shopId: 's1',
        shopName: 'G R Mart',
        shopMobile: '9850070556',
        salesmanName: 'Akash',
        orderDate: DateTime(2026, 11, 22, 10, 52),
        items: [
          OrderItem(
            productId: 'p1',
            productName: 'Santoor handwash 150gm',
            company: 'Wipro',
            category: 'HC',
            packing: '150gm',
            rate: 27.5,
            quantity: 1,
            cases: 0,
            units: 1,
            unitsPerCase: 24,
            weightKg: 5.07,
          ),
        ],
        totalAmount: 27.5,
        totalQuantity: 1,
      );
      final ord2 = ord1.copyWith(id: 'ord-keep-2', orderNumber: 'ORD-2', shopName: 'Keep Store');

      // Check accurate loose-unit weight math
      expect(ord1.totalWeightKg, closeTo(5.07 / 24, 0.01));

      SharedPreferences.setMockInitialValues({
        'app_sample_data_initialized_v1': true,
        'app_sales_orders_v1': [jsonEncode(ord1.toJson()), jsonEncode(ord2.toJson())],
      });

      final provider = CollectionProvider();
      await provider.initialize();
      expect(provider.salesOrders.length, 2);

      await provider.deleteSalesOrder(ord1.id);
      expect(provider.salesOrders.map((o) => o.id), ['ord-keep-2']);

      // Simulate stale local list still containing ord1 while cloud tombstone was stored
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'app_sales_orders_v1',
        [jsonEncode(ord1.toJson()), jsonEncode(ord2.toJson())],
      );

      final reloaded = CollectionProvider();
      await reloaded.initialize();
      expect(reloaded.salesOrders.map((o) => o.id), ['ord-keep-2']);
    });

    testWidgets('AllOrdersScreen supports All Dates toggle and Status filter chips',
        (tester) async {
      final today = DateTime.now();
      final oldOrder = SalesOrderModel(
        id: 'ord_old',
        orderNumber: 'ORD-OLD',
        firm: 'Purva Enterprises',
        routeId: 'r1',
        routeName: 'Chakan',
        shopId: 's1',
        shopName: 'G R Mart',
        shopMobile: '9999999999',
        salesmanName: 'Akash',
        orderDate: DateTime(2026, 11, 22, 10, 0),
        items: [
          OrderItem(
            productId: 'p1',
            productName: 'Item 1',
            company: 'Wipro',
            category: 'HC',
            packing: '150gm',
            rate: 50,
            quantity: 2,
            cases: 0,
            units: 2,
          ),
        ],
        totalAmount: 100,
        totalQuantity: 2,
        status: 'Booked',
      );
      final todayBilled = oldOrder.copyWith(
        id: 'ord_today',
        orderNumber: 'ORD-TODAY',
        shopName: 'Modern Mart',
        orderDate: today,
        status: 'Billed',
      );

      final admin = UserModel(
        id: 'u_admin',
        phone: '9921977636',
        name: 'Super Admin',
        role: UserRole.superAdmin,
        password: 'p',
      );

      SharedPreferences.setMockInitialValues({
        'app_sample_data_initialized_v1': true,
        'app_users_cache_v1': jsonEncode([admin.toJson()]),
        'current_logged_in_user_id_v1': admin.id,
        'app_sales_orders_v1': [jsonEncode(oldOrder.toJson()), jsonEncode(todayBilled.toJson())],
      });

      final auth = AuthProvider();
      final collection = CollectionProvider();
      await auth.initialize();
      await collection.initialize();

      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: collection),
          ],
          child: const MaterialApp(
            home: AllOrdersScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially today only: shows Modern Mart, not G R Mart
      expect(find.text('Modern Mart'), findsOneWidget);
      expect(find.text('G R Mart'), findsNothing);

      // Tap "All Dates": reveals both orders
      await tester.tap(find.text('All Dates'));
      await tester.pumpAndSettle();
      expect(find.text('Modern Mart'), findsOneWidget);
      expect(find.text('G R Mart'), findsOneWidget);

      // Filter by status chip 'Booked': keeps G R Mart only
      await tester.tap(find.widgetWithText(ChoiceChip, 'Booked'));
      await tester.pumpAndSettle();
      expect(find.text('G R Mart'), findsOneWidget);
      expect(find.text('Modern Mart'), findsNothing);
    });

    testWidgets('PaymentQrDialog displays respected account numbers under Purva, Manas QR 1 (Current), and Manas QR 2 (CC)',
        (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PaymentQrDialog())));
      await tester.pumpAndSettle();

      // Purva QR shows 115925080000004 & Union Bank of India Chakan
      expect(find.textContaining('115925080000004'), findsOneWidget);
      expect(find.textContaining('UBIN0570575'), findsOneWidget);

      // Switch to Manas Sales -> QR 1 (Current A/c 3881437263)
      await tester.tap(find.text('MANAS SALES'));
      await tester.pumpAndSettle();
      expect(find.textContaining('3881437263'), findsOneWidget);
      expect(find.textContaining('CBIN0284624'), findsOneWidget);

      // Switch to Manas QR 2 -> CC A/c 5251719817
      await tester.tap(find.text('CC A/c (QR 2)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('5251719817'), findsOneWidget);
      expect(find.textContaining('CBIN0284624'), findsOneWidget);
    });

    testWidgets('Overview dashboard places Pending Bills forward (left) of Collection',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const DailyCollectionApp());
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Akash'));
      await tester.pump();
      await tester.tap(find.text('Log In to Dashboard'));
      await tester.pumpAndSettle();

      final pendingLeft = tester.getTopLeft(find.text('Pending Bills').first).dx;
      final collectionLeft = tester.getTopLeft(find.text('Collection').first).dx;
      expect(pendingLeft, lessThan(collectionLeft));
    });

    testWidgets('AddProductDialog uses Company/Category/Subcategory selectors, Packaging Unit, Units/Case, Photo without MRP/Rate/Weight',
        (tester) async {
      SharedPreferences.setMockInitialValues({'app_sample_data_initialized_v1': true});
      OrderCatalogService.setCustomProducts([]);
      final collection = CollectionProvider();
      await collection.initialize();

      tester.view.physicalSize = const Size(600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: collection,
          child: const MaterialApp(home: Scaffold(body: AddProductDialog())),
        ),
      );
      await tester.pumpAndSettle();

      // No Trade Rate, MRP, or Weight fields
      expect(find.textContaining('Trade Rate'), findsNothing);
      expect(find.textContaining('MRP (₹)'), findsNothing);
      expect(find.textContaining('Weight (Kg/Case)'), findsNothing);

      // Selectors & Photo buttons exist
      expect(find.text('4. Subcategory'), findsOneWidget);
      expect(find.text('+ New Subcategory'), findsOneWidget);
      expect(find.text('6. Packaging Unit'), findsOneWidget);
      expect(find.text('Units Per Case (CS)'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);

      // Enter product name & save without MRP/Rate
      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. Santoor White 100g (MRP 40)'),
        'Santoor Soap MRP 10',
      );
      await tester.tap(find.text('Save Product'));
      await tester.pumpAndSettle();

      final saved = collection.customProducts.where((p) => p.name == 'Santoor Soap MRP 10').toList();
      expect(saved.length, 1);
      expect(saved.first.rate, 0.0);
      expect(saved.first.mrp, 0.0);
      expect(saved.first.weightKg, 0.0);
      expect(saved.first.unitsPerCase, 24);
    });

    testWidgets('Redesigned OrderDashboardScreen and OutletOrderBookingScreen support Outlet Info, direct CS/UT entry, and tabular Submit Order',
        (tester) async {
      final route = RouteModel(id: 'r_raj', name: 'Rajgurunagar-1');
      final shop = ShopModel(
        id: 'shop_shakti',
        name: 'Shiv Shakti Traders',
        address: 'Rajgurunagar',
        routeId: route.id,
        routeName: route.name,
        mobileNumber: '9822001122',
        ownerName: 'Mahesh',
      );
      const product = CatalogProduct(
        id: 'prod_nip',
        name: 'NIPMB-115GX4(11.04KG)Rs.30 -GREEN',
        category: 'HC',
        subcategory: 'NSB',
        company: 'Wipro',
        firm: 'Purva Enterprises',
        defaultUnit: 'Pcs',
        unitsPerCase: 24,
        rate: 0.0,
      );
      final salesman = UserModel(
        id: 'u_order',
        phone: '8888888888',
        name: 'Order Man',
        role: UserRole.order,
        password: 'p',
        assignedRouteIds: [route.id],
      );

      SharedPreferences.setMockInitialValues({
        'app_sample_data_initialized_v1': true,
        'app_users_cache_v1': jsonEncode([salesman.toJson()]),
        'current_logged_in_user_id_v1': salesman.id,
        'app_routes_v1': [jsonEncode(route.toJson())],
        'app_shops_v1': [jsonEncode(shop.toJson())],
        'app_custom_products_v1': [jsonEncode(product.toJson())],
      });

      final auth = AuthProvider();
      final collection = CollectionProvider();
      await auth.initialize();
      await collection.initialize();

      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: collection),
          ],
          child: const MaterialApp(home: OrderDashboardScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Retailer dashboard renders header, Today strip, tabs, and Outlet card
      expect(find.text('RETAILER'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Pending (1)'), findsOneWidget);
      expect(find.text('SHIV SHAKTI TRADERS'), findsOneWidget);
      expect(find.textContaining('Last Visited:'), findsOneWidget);

      // Tap Info (i) icon -> opens Outlet Info screen
      await tester.tap(find.byIcon(Icons.info_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Outlet Info'), findsOneWidget);
      expect(find.text('Navigate'), findsOneWidget);
      expect(find.text('Update GPS'), findsOneWidget);

      // Tap Book Order -> opens OutletOrderBookingScreen with direct CS/UT inputs
      await tester.tap(find.text('Book Order'));
      await tester.pumpAndSettle();
      expect(find.text('Category'), findsOneWidget);
      expect(find.text('Subcategory'), findsOneWidget);
      expect(find.text('NIPMB-115GX4(11.04KG)Rs.30 -GREEN'), findsOneWidget);

      // Enter 2 in direct CS TextField
      final csField = find.byType(TextField).first;
      await tester.enterText(csField, '2');
      await tester.pumpAndSettle();

      // Go to Submit Order via Floating Cart FAB
      expect(
        find.descendant(
          of: find.byType(FloatingActionButton),
          matching: find.byIcon(Icons.shopping_cart_outlined),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Review & Submit Order'));
      await tester.pumpAndSettle();

      // Tabular Submit Order summary shows Lines, Case/Bags, Unit, and TOTAL ORDER
      expect(find.text('Lines'), findsOneWidget);
      expect(find.text('Case/Bags'), findsOneWidget);
      expect(find.text('TOTAL ORDER:'), findsOneWidget);
      expect(find.text('2 CS, 0 UT'), findsOneWidget);

      // Go back to Order tab and open product detail sheet -> Delete removes custom SKU
      await tester.tap(find.text('Order').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('NIPMB-115GX4(11.04KG)Rs.30 -GREEN'));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Product?'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(collection.customProducts.where((p) => p.id == product.id), isEmpty);
    });

    testWidgets('Double-tapping Save Product and adding matching SKU do not create duplicate custom products',
        (tester) async {
      SharedPreferences.setMockInitialValues({'app_sample_data_initialized_v1': true});
      OrderCatalogService.setCustomProducts([]);
      final collection = CollectionProvider();
      await collection.initialize();

      tester.view.physicalSize = const Size(600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: collection,
          child: const MaterialApp(home: Scaffold(body: AddProductDialog())),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. Santoor White 100g (MRP 40)'),
        'Santoor Soap 100g',
      );
      // Rapid multi-tap Save Product before frame settles
      await tester.tap(find.text('Save Product'));
      await tester.tap(find.text('Save Product'), warnIfMissed: false);
      await tester.pumpAndSettle();

      final firstMatches =
          collection.customProducts.where((p) => p.name == 'Santoor Soap 100g').toList();
      expect(firstMatches.length, 1);
      final firstSaved = firstMatches.first;

      // Re-adding an identical SKU with a different ID replaces instead of duplicating
      await collection.addCustomProduct(
        CatalogProduct(
          id: 'cust-duplicate-test',
          name: '  santoor soap 100g ',
          category: firstSaved.category.toLowerCase(),
          subcategory: firstSaved.subcategory.toLowerCase(),
          company: ' ${firstSaved.company.toLowerCase()} ',
          firm: firstSaved.firm,
          defaultUnit: firstSaved.defaultUnit,
          unitsPerCase: firstSaved.unitsPerCase,
          rate: 0.0,
        ),
      );
      expect(
        collection.customProducts.where((p) => p.name.toLowerCase().contains('santoor soap 100g')).length,
        1,
      );
    });

    test('Tally Stock XML & Excel import updates existing SKU stock and optionally adds unmatched SKUs', () async {
      const existing = CatalogProduct(
        id: 'cust-santoor',
        name: 'Santoor Soap 100g',
        category: 'HC',
        subcategory: 'General',
        company: 'Wipro',
        firm: 'Purva Enterprises',
        defaultUnit: 'Pcs',
        unitsPerCase: 24,
        rate: 0.0,
        stock: 10.0,
        scheme: '5% Off',
      );
      SharedPreferences.setMockInitialValues({
        'app_sample_data_initialized_v1': true,
        'app_custom_products_v1': [jsonEncode(existing.toJson())],
      });
      final collection = CollectionProvider();
      await collection.initialize();

      const tallyXml = '''
<ENVELOPE>
  <BODY>
    <DATA>
      <TALLYMESSAGE>
        <STOCKITEM NAME="Santoor Soap 100g">
          <BASEUNITS>Pcs</BASEUNITS>
          <CLOSINGBALANCE>144.00 Pcs</CLOSINGBALANCE>
          <PARENT>Wipro</PARENT>
        </STOCKITEM>
        <STOCKITEM NAME="Fena Powder 1kg">
          <BASEUNITS>Pcs</BASEUNITS>
          <CLOSINGBALANCE>60 Pcs</CLOSINGBALANCE>
          <PARENT>Fena</PARENT>
        </STOCKITEM>
      </TALLYMESSAGE>
    </DATA>
  </BODY>
</ENVELOPE>''';

      final xmlRes = TallyIntegrationService.parseStockSummaryFromTallyXml(
        xmlContent: tallyXml,
        defaultFirm: 'Purva Enterprises',
      );
      expect(xmlRes.success, isTrue);
      expect(xmlRes.items.length, 2);
      expect(xmlRes.items.first.closingQty, 144.0);

      final applyRes = await collection.importTallyStock(
        xmlRes.items,
        defaultFirm: 'Purva Enterprises',
        createUnmatched: true,
      );
      expect(applyRes.updatedCount, 1);
      expect(applyRes.addedCount, 1);

      final updatedSantoor = collection.customProducts.firstWhere((p) => p.id == 'cust-santoor');
      expect(updatedSantoor.stock, 144.0);
      expect(updatedSantoor.scheme, '5% Off');

      // Excel parsing overrides Fena Powder closing qty & sets scheme
      final wb = xl.Excel.createExcel();
      final sheet = wb['Sheet1'];
      sheet.appendRow([
        xl.TextCellValue('Particulars'),
        xl.TextCellValue('Closing Stock'),
        xl.TextCellValue('Unit'),
        xl.TextCellValue('Scheme'),
      ]);
      sheet.appendRow([
        xl.TextCellValue('Fena Powder 1kg'),
        xl.IntCellValue(96),
        xl.TextCellValue('Pcs'),
        xl.TextCellValue('10+1 Free'),
      ]);
      final excelBytes = wb.save()!;
      final xlRes = TallyIntegrationService.parseStockSummaryFromExcel(
        bytes: excelBytes,
        defaultFirm: 'Purva Enterprises',
      );
      expect(xlRes.success, isTrue);
      expect(xlRes.items.first.closingQty, 96.0);
      expect(xlRes.items.first.scheme, '10+1 Free');

      await collection.importTallyStock(xlRes.items, defaultFirm: 'Purva Enterprises');
      final fena = collection.customProducts.firstWhere((p) => p.name == 'Fena Powder 1kg');
      expect(fena.stock, 96.0);
      expect(fena.scheme, '10+1 Free');
    });

    testWidgets('Super Admin Products, Stock & Schemes screen manages schemes, edits, deletes, and blocks non-admin',
        (tester) async {
      final admin = UserModel(
        id: 'u_admin',
        phone: '9921977636',
        name: 'Super Admin',
        role: UserRole.superAdmin,
        password: 'p',
      );
      final office = UserModel(
        id: 'u_off',
        phone: '9922001122',
        name: 'Office Staff',
        role: UserRole.office,
        password: 'p',
      );
      const prod = CatalogProduct(
        id: 'prod-1',
        name: 'Santoor White 100g',
        category: 'HC',
        subcategory: 'General',
        company: 'Wipro',
        firm: 'Purva Enterprises',
        defaultUnit: 'Pcs',
        unitsPerCase: 24,
        rate: 0.0,
        stock: 80.0,
        scheme: '',
      );

      SharedPreferences.setMockInitialValues({
        'app_sample_data_initialized_v1': true,
        'app_users_cache_v1': jsonEncode([office.toJson(), admin.toJson()]),
        'current_logged_in_user_id_v1': office.id,
        'app_custom_products_v1': [jsonEncode(prod.toJson())],
      });

      final auth = AuthProvider();
      final collection = CollectionProvider();
      await auth.initialize();
      await collection.initialize();

      tester.view.physicalSize = const Size(480, 960);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Non-Super Admin is blocked from AdminProductsScreen
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: collection),
          ],
          child: const MaterialApp(home: AdminProductsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Super Admin Access Only'), findsOneWidget);

      // Switch to Super Admin login
      await auth.login('9921977636', 'p');
      await tester.pumpAndSettle();

      expect(find.text('Products, Stock & Schemes'), findsOneWidget);
      expect(find.text('Santoor White 100g'), findsOneWidget);
      expect(find.text('Stock: 80 Pcs'), findsOneWidget);

      // Quick-change scheme via preset chip
      await tester.tap(find.text('Add Scheme'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10+1 Free'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Scheme'));
      await tester.pumpAndSettle();
      expect(collection.customProducts.first.scheme, '10+1 Free');
      expect(find.text('Scheme: 10+1 Free'), findsOneWidget);

      // Edit product via Edit button
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Product / SKU'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. Santoor White 100g (MRP 40)'),
        'Santoor White 100g Updated',
      );
      await tester.ensureVisible(find.text('Update Product'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update Product'));
      await tester.pumpAndSettle();
      expect(collection.customProducts.first.name, 'Santoor White 100g Updated');
      expect(find.text('Santoor White 100g Updated'), findsOneWidget);

      // Delete product via Delete icon
      await tester.tap(find.byTooltip('Delete Product'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(collection.customProducts, isEmpty);
    });
  });
}
