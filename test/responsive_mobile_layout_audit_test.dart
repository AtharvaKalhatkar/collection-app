import 'dart:convert';

import 'package:daily_collection_app/models/location_timeline_entry.dart';
import 'package:daily_collection_app/models/order_model.dart';
import 'package:daily_collection_app/models/route_model.dart';
import 'package:daily_collection_app/models/shop_model.dart';
import 'package:daily_collection_app/models/user_model.dart';
import 'package:daily_collection_app/providers/auth_provider.dart';
import 'package:daily_collection_app/providers/collection_provider.dart';
import 'package:daily_collection_app/screens/admin_products_screen.dart';
import 'package:daily_collection_app/screens/live_staff_locations_screen.dart';
import 'package:daily_collection_app/screens/main_navigation_shell.dart';
import 'package:daily_collection_app/screens/order_dashboard_screen.dart';
import 'package:daily_collection_app/screens/outlet_order_booking_screen.dart';
import 'package:daily_collection_app/screens/routes_shops_screen.dart';
import 'package:daily_collection_app/utils/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({AuthProvider auth, CollectionProvider collection, ShopModel shop, UserModel admin, UserModel salesman})>
      seedTestState({bool asSuperAdmin = true}) async {
    final admin = UserModel(
      id: 'u_admin',
      phone: '9921977636',
      name: 'Super Admin',
      role: UserRole.superAdmin,
      password: 'p',
    );
    final salesman = UserModel(
      id: 'u_akash',
      phone: '9000000001',
      name: 'Akash Shinde',
      role: UserRole.salesman,
      password: 'p',
      assignedRouteIds: const ['r1'],
      latitude: 18.7560,
      longitude: 73.8550,
      locationUpdatedAt: DateTime.now(),
      locationLandmark: 'Pune - Nashik Hwy, Chakan',
    );
    final route = RouteModel(id: 'r1', name: 'Chakan Industrial Beat');
    final shop = ShopModel(
      id: 's1',
      name: 'Tushar Provision Stores',
      routeId: 'r1',
      routeName: 'Chakan Industrial Beat',
      mobileNumber: '9822001122, 9822003344',
      address: 'Manik Chowk, Chakan MIDC',
      latitude: 18.7565,
      longitude: 73.8555,
    );
    final prod = CatalogProduct(
      id: 'prod_1',
      name: 'Santoor White Soap 100g Family Pack',
      company: 'Wipro',
      category: 'Personal Care',
      subcategory: 'Soaps',
      firm: 'Purva Enterprises',
      packing: '100g',
      unitsPerCase: 24,
      defaultUnit: 'Pcs',
      rate: 32.5,
      scheme: '10+1 Free',
      stock: 48,
    );
    final tl = LocationTimelineEntry(
      id: 'tl_1',
      userId: salesman.id,
      staffName: salesman.name,
      staffRole: 'salesman',
      timestamp: DateTime.now().subtract(const Duration(minutes: 20)),
      latitude: 18.7560,
      longitude: 73.8550,
      landmark: 'Manik Chowk, Chakan',
      eventType: 'orderBooked',
      details: 'Order #ORD-10 (2 CS)',
      shopName: shop.name,
      routeName: route.name,
    );

    SharedPreferences.setMockInitialValues({
      'app_sample_data_initialized_v1': true,
      'app_users_cache_v1': jsonEncode([admin.toJson(), salesman.toJson()]),
      'current_logged_in_user_id_v1': asSuperAdmin ? admin.id : salesman.id,
      'app_routes_v1': [jsonEncode(route.toJson())],
      'app_shops_v1': [jsonEncode(shop.toJson())],
      'app_custom_products_v1': [jsonEncode(prod.toJson())],
      'app_location_timeline_v1': [jsonEncode(tl.toJson())],
    });

    final auth = AuthProvider();
    final collection = CollectionProvider();
    await auth.initialize();
    await collection.initialize();
    return (auth: auth, collection: collection, shop: shop, admin: admin, salesman: salesman);
  }

  Future<List<FlutterErrorDetails>> runCapturingErrors(
    WidgetTester tester,
    Future<void> Function() action,
  ) async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details);
    };
    try {
      await action();
    } finally {
      FlutterError.onError = previous;
    }
    return errors;
  }

  Widget wrapApp({
    required AuthProvider auth,
    required CollectionProvider collection,
    required Widget home,
    EdgeInsets padding = EdgeInsets.zero,
    double textScale = 1.0,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: collection),
      ],
      child: Builder(
        builder: (context) => MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (ctx, child) {
            final mq = MediaQuery.of(ctx);
            return MediaQuery(
              data: mq.copyWith(
                padding: padding,
                viewPadding: padding,
                textScaler: TextScaler.linear(textScale),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: home,
        ),
      ),
    );
  }

  group('Responsive Multi-Device & Anti-Overlap Audit Tests', () {
    testWidgets('MainNavigationShell adapts across 320px phone, 360px phone, 780x360 landscape, and 1280px desktop without overflow',
        (tester) async {
      final state = await seedTestState();

      final viewports = <({String name, Size size, EdgeInsets padding, double scale, bool expectRail})>[
        (
          name: 'Small Phone 320x568',
          size: const Size(320, 568),
          padding: const EdgeInsets.only(top: 24, bottom: 16),
          scale: 1.15,
          expectRail: false,
        ),
        (
          name: 'Android Phone 360x780',
          size: const Size(360, 780),
          padding: const EdgeInsets.only(top: 28, bottom: 24),
          scale: 1.15,
          expectRail: false,
        ),
        (
          name: 'Landscape Phone 780x360',
          size: const Size(780, 360),
          padding: EdgeInsets.zero,
          scale: 1.0,
          expectRail: false,
        ),
        (
          name: 'Desktop 1280x800',
          size: const Size(1280, 800),
          padding: EdgeInsets.zero,
          scale: 1.0,
          expectRail: true,
        ),
      ];

      for (final vp in viewports) {
        tester.view.physicalSize = vp.size;
        tester.view.devicePixelRatio = 1.0;

        final errors = await runCapturingErrors(tester, () async {
          await tester.pumpWidget(
            wrapApp(
              auth: state.auth,
              collection: state.collection,
              home: const MainNavigationShell(),
              padding: vp.padding,
              textScale: vp.scale,
            ),
          );
          await tester.pumpAndSettle();
        });

        expect(errors, isEmpty, reason: 'Layout error at ${vp.name}: ${errors.map((e) => e.exceptionAsString()).join('\n')}');
        if (vp.expectRail) {
          expect(find.byType(NavigationRail), findsOneWidget, reason: '${vp.name} should show NavigationRail');
          expect(find.byType(NavigationBar), findsNothing, reason: '${vp.name} should hide mobile bottom NavigationBar');
        } else {
          expect(find.byType(NavigationBar), findsOneWidget, reason: '${vp.name} should show bottom NavigationBar');
        }
      }

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('OutletOrderBookingScreen removes overlapping FAB and avoids card/bottom-bar collisions on 360px & 320px phones',
        (tester) async {
      final state = await seedTestState(asSuperAdmin: false);
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final errors = await runCapturingErrors(tester, () async {
        await tester.pumpWidget(
          wrapApp(
            auth: state.auth,
            collection: state.collection,
            home: OutletOrderBookingScreen(
              shop: state.shop,
              selectedDate: DateTime(2026, 11, 27),
            ),
            padding: const EdgeInsets.only(top: 28, bottom: 20),
            textScale: 1.15,
          ),
        );
        await tester.pumpAndSettle();
      });

      expect(errors, isEmpty, reason: 'Overflow/layout error on OutletOrderBookingScreen: $errors');
      // Detached green square FAB over product cards must NOT exist anymore
      expect(find.byType(FloatingActionButton), findsNothing);
      // Integrated Cart/Review CTA lives inside bottom bar cleanly
      expect(find.byIcon(Icons.shopping_cart_outlined), findsOneWidget);

      final cardFinder = find.text('Santoor White Soap 100g Family Pack');
      final cartBtnFinder = find.byIcon(Icons.shopping_cart_outlined);
      expect(cardFinder, findsOneWidget);
      final cardRect = tester.getRect(cardFinder);
      final cartRect = tester.getRect(cartBtnFinder);
      expect(cardRect.overlaps(cartRect), isFalse, reason: 'Product card and Cart CTA must never overlap');

      // Enter quantity and switch to Submit Order tab at narrow 320px width
      await tester.enterText(find.byType(TextField).first, '2');
      await tester.pump();
      tester.view.physicalSize = const Size(320, 620);
      final submitErrors = await runCapturingErrors(tester, () async {
        await tester.tap(find.text('Review (1)'));
        await tester.pumpAndSettle();
      });
      expect(submitErrors, isEmpty, reason: 'Submit Order tab overflowed at 320px: $submitErrors');
      expect(find.widgetWithText(ElevatedButton, 'Submit Order'), findsOneWidget);
    });

    testWidgets('OrderDashboardScreen & RoutesShopsScreen collapse crowded AppBar actions cleanly on 360px phone',
        (tester) async {
      final state = await seedTestState();
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // OrderDashboardScreen
      final orderErrors = await runCapturingErrors(tester, () async {
        await tester.pumpWidget(
          wrapApp(
            auth: state.auth,
            collection: state.collection,
            home: const OrderDashboardScreen(),
            padding: const EdgeInsets.only(top: 24, bottom: 20),
          ),
        );
        await tester.pumpAndSettle();
      });
      expect(orderErrors, isEmpty);
      expect(find.text('RETAILER'), findsOneWidget);
      expect(find.byTooltip('More Options'), findsOneWidget);

      // RoutesShopsScreen
      final routesErrors = await runCapturingErrors(tester, () async {
        await tester.pumpWidget(
          wrapApp(
            auth: state.auth,
            collection: state.collection,
            home: const RoutesShopsScreen(),
            padding: const EdgeInsets.only(top: 24, bottom: 20),
          ),
        );
        await tester.pumpAndSettle();
      });
      expect(routesErrors, isEmpty);
      expect(find.text('Routes & Outlets'), findsOneWidget);
      expect(find.byTooltip('Route Options'), findsOneWidget);

      // AdminProductsScreen
      final adminProdErrors = await runCapturingErrors(tester, () async {
        await tester.pumpWidget(
          wrapApp(
            auth: state.auth,
            collection: state.collection,
            home: const AdminProductsScreen(),
            padding: const EdgeInsets.only(top: 24, bottom: 20),
          ),
        );
        await tester.pumpAndSettle();
      });
      expect(adminProdErrors, isEmpty);
    });

    testWidgets('LiveStaffLocationsScreen prevents map FAB / selected card overlap across portrait & short landscape phones',
        (tester) async {
      final state = await seedTestState();
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 1. Ultra-narrow 320px portrait timeline stacks date+staff cleanly without overflow
      tester.view.physicalSize = const Size(320, 600);
      final narrowErrors = await runCapturingErrors(tester, () async {
        await tester.pumpWidget(
          wrapApp(
            auth: state.auth,
            collection: state.collection,
            home: const LiveStaffLocationsScreen(initialStaffName: 'Akash Shinde'),
            padding: const EdgeInsets.only(top: 24, bottom: 20),
            textScale: 1.15,
          ),
        );
        await tester.pumpAndSettle();
      });
      expect(narrowErrors, isEmpty, reason: 'Narrow timeline error: $narrowErrors');
      expect(find.text('All Staff'), findsNothing);

      // 2. Landscape phone (780x360) Live Map with selected staff card -> zero overlap between search, FABs, and card
      tester.view.physicalSize = const Size(780, 360);
      final mapErrors = await runCapturingErrors(tester, () async {
        await tester.pumpWidget(
          wrapApp(
            auth: state.auth,
            collection: state.collection,
            home: const LiveStaffLocationsScreen(
              key: ValueKey('landscape_map_audit'),
              initialTabIndex: 1,
              initialStaffName: 'Akash Shinde',
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 250));

        // Tap quick staff chip to open bottom staff card
        final chip = find.byKey(const ValueKey('map_staff_chip_u_akash'));
        expect(chip, findsOneWidget);
        await tester.tap(chip);
        await tester.pump(const Duration(milliseconds: 250));
      });
      expect(mapErrors, isEmpty, reason: 'Landscape map overlay error: $mapErrors');

      final searchRect = tester.getRect(find.byType(TextField).first);
      final fitStaffRect = tester.getRect(find.byTooltip('Fit All Live Staff'));
      final timelineBtnRect = tester.getRect(find.widgetWithText(ElevatedButton, 'Timeline'));
      expect(searchRect.overlaps(fitStaffRect), isFalse, reason: 'Map search bar must not overlap zoom/fit buttons');
      expect(fitStaffRect.overlaps(timelineBtnRect), isFalse, reason: 'Map buttons must sit above selected staff card');
    });
  });
}
