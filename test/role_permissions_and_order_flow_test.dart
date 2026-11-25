import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_collection_app/main.dart';
import 'package:daily_collection_app/models/order_model.dart';
import 'package:daily_collection_app/models/route_model.dart';
import 'package:daily_collection_app/models/shop_model.dart';
import 'package:daily_collection_app/models/user_model.dart';
import 'package:daily_collection_app/providers/auth_provider.dart';
import 'package:daily_collection_app/providers/collection_provider.dart';
import 'package:daily_collection_app/screens/outlet_order_booking_screen.dart';
import 'package:daily_collection_app/widgets/assign_routes_dialog.dart';

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
  });
}
