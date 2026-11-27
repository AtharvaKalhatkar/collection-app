import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_collection_app/models/location_timeline_entry.dart';
import 'package:daily_collection_app/models/shop_model.dart';
import 'package:daily_collection_app/models/user_model.dart';
import 'package:daily_collection_app/providers/auth_provider.dart';
import 'package:daily_collection_app/providers/collection_provider.dart';
import 'package:daily_collection_app/screens/live_staff_locations_screen.dart';
import 'package:daily_collection_app/services/location_tracking_service.dart';
import 'package:daily_collection_app/services/storage_service.dart';
import 'package:daily_collection_app/utils/timeline_segment_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Super Admin Location Timeline Tests', () {
    test('LocationTimelineEntry serialization & Supabase user row round-trip', () {
      final now = DateTime(2026, 10, 29, 10, 30);
      final entry = LocationTimelineEntry(
        id: 'tl_user1_1793210000',
        userId: 'user1',
        staffName: 'Driver (user1)',
        staffRole: 'driver',
        timestamp: now,
        latitude: 18.756123,
        longitude: 73.856234,
        landmark: 'Chakan Chowk, Khed',
        eventType: 'deliveryVisit',
        details: 'Delivered goods to Om Traders',
        amount: 2500.0,
        shopName: 'Om Traders',
        routeName: 'Chakan Route',
        billNumber: 'INV-1092',
      );

      expect(entry.isDriver, isTrue);
      expect(entry.isSalesman, isFalse);
      expect(entry.isDelivery, isTrue);
      expect(entry.timeFormatted, '10:30 AM');
      expect(entry.mapsUrl, 'https://maps.google.com/?q=18.756123,73.856234');

      // Test standard JSON round-trip
      final jsonMap = entry.toJson();
      final fromJson = LocationTimelineEntry.fromJson(jsonMap);
      expect(fromJson.id, entry.id);
      expect(fromJson.staffName, 'Driver (user1)');
      expect(fromJson.staffRole, 'driver');
      expect(fromJson.latitude, closeTo(18.756123, 0.000001));
      expect(fromJson.longitude, closeTo(73.856234, 0.000001));
      expect(fromJson.amount, 2500.0);
      expect(fromJson.billNumber, 'INV-1092');

      // Test Supabase user row round-trip (which stores metadata safely in password column)
      final supabaseRow = entry.toSupabaseUserRow();
      expect(supabaseRow['id'], entry.id);
      expect(supabaseRow['role'], 'driver');
      expect(supabaseRow['name'], 'Driver (user1)');
      expect(supabaseRow['password'], startsWith('tl:::deliveryVisit:::'));

      final fromSupabase = LocationTimelineEntry.fromSupabaseUserRow(supabaseRow);
      expect(fromSupabase, isNotNull);
      expect(fromSupabase!.id, entry.id);
      expect(fromSupabase.staffName, 'Driver (user1)');
      expect(fromSupabase.staffRole, 'driver');
      expect(fromSupabase.eventType, 'deliveryVisit');
      expect(fromSupabase.latitude, closeTo(18.756123, 0.000001));
      expect(fromSupabase.longitude, closeTo(73.856234, 0.000001));
      expect(fromSupabase.landmark, 'Chakan Chowk, Khed');
      expect(fromSupabase.details, 'Delivered goods to Om Traders');
      expect(fromSupabase.amount, 2500.0);
      expect(fromSupabase.shopName, 'Om Traders');
      expect(fromSupabase.routeName, 'Chakan Route');
      expect(fromSupabase.billNumber, 'INV-1092');
    });

    test('Salesman collection checkpoint timeline entry', () {
      final now = DateTime(2026, 10, 29, 11, 45);
      final entry = LocationTimelineEntry(
        id: 'tl_salesman_1793215000',
        userId: 'salesman_1',
        staffName: 'Akash',
        staffRole: 'salesman',
        timestamp: now,
        latitude: 18.752000,
        longitude: 73.851000,
        landmark: 'At Shri Ganesh Sweets (Chakan Route)',
        eventType: 'collection',
        details: 'Collected ₹4,500 (Cash) for Bill #INV-1088',
        amount: 4500.0,
        shopName: 'Shri Ganesh Sweets',
        routeName: 'Chakan Route',
        billNumber: 'INV-1088',
      );

      expect(entry.isSalesman, isTrue);
      expect(entry.isDriver, isFalse);
      expect(entry.isCollection, isTrue);
      expect(entry.timeFormatted, '11:45 AM');

      final row = entry.toSupabaseUserRow();
      final restored = LocationTimelineEntry.fromSupabaseUserRow(row);
      expect(restored, isNotNull);
      expect(restored!.staffName, 'Akash');
      expect(restored.isCollection, isTrue);
      expect(restored.amount, 4500.0);
    });

    test('Haversine distance calculation between consecutive timeline stops', () {
      // Point 1: Chakan (18.7600, 73.8600)
      // Point 2: Bhosari (~16 km south: 18.6200, 73.8400)
      final distKm = LocationTrackingService.haversineDistanceKm(
        18.7600,
        73.8600,
        18.6200,
        73.8400,
      );
      expect(distKm, greaterThan(14.0));
      expect(distKm, lessThan(18.0));
    });

    test('StorageService local location timeline cache and deduplication', () async {
      final storage = StorageService();
      final now = DateTime.now();

      final entry1 = LocationTimelineEntry(
        id: 'tl_u1_1',
        userId: 'user1',
        staffName: 'Driver (user1)',
        staffRole: 'driver',
        timestamp: now,
        latitude: 18.756,
        longitude: 73.856,
        landmark: 'Chakan MIDC',
        eventType: 'gpsPing',
      );

      await storage.addLocationTimelineEntry(entry1);
      final list1 = await storage.loadLocationTimeline();
      expect(list1.length, 1);
      expect(list1.first.staffName, 'Driver (user1)');

      // Adding the exact same location ping within 60s is deduplicated
      final entryDuplicate = LocationTimelineEntry(
        id: 'tl_u1_2',
        userId: 'user1',
        staffName: 'Driver (user1)',
        staffRole: 'driver',
        timestamp: now.add(const Duration(seconds: 20)),
        latitude: 18.756,
        longitude: 73.856,
        landmark: 'Chakan MIDC',
        eventType: 'gpsPing',
      );
      await storage.addLocationTimelineEntry(entryDuplicate);
      final list2 = await storage.loadLocationTimeline();
      expect(list2.length, 1); // Deduplicated!

      // Moving to a new stop is recorded
      final entry2 = LocationTimelineEntry(
        id: 'tl_u1_3',
        userId: 'user1',
        staffName: 'Driver (user1)',
        staffRole: 'driver',
        timestamp: now.add(const Duration(minutes: 15)),
        latitude: 18.780,
        longitude: 73.890,
        landmark: 'Rajgurunagar',
        eventType: 'deliveryVisit',
      );
      await storage.addLocationTimelineEntry(entry2);
      final list3 = await storage.loadLocationTimeline();
      expect(list3.length, 2);
      expect(list3.first.landmark, 'Rajgurunagar');
    });

    test('parseNominatimPlace builds full road + locality + city address and replaces generic Khed', () {
      final wagholiPlace = LocationTrackingService.parseNominatimPlace({
        'name': 'Oxy Valley PH-2',
        'address': {
          'road': 'Bakori Rd',
          'suburb': 'Wagholi',
          'city': 'Pune',
          'postcode': '412207',
        },
      });
      expect(wagholiPlace, isNotNull);
      expect(wagholiPlace!.title, 'Oxy Valley PH-2');
      expect(wagholiPlace.address, contains('Bakori Rd'));
      expect(wagholiPlace.address, contains('Wagholi'));
      expect(wagholiPlace.address, contains('Pune'));

      final khedPlace = LocationTrackingService.parseNominatimPlace({
        'address': {
          'road': 'Pune - Nashik Hwy',
          'town': 'Khed',
          'state': 'Maharashtra',
        },
      });
      expect(khedPlace, isNotNull);
      expect(khedPlace!.address, contains('Pune - Nashik Hwy'));
      expect(khedPlace.address, contains('Rajgurunagar'));
      expect(khedPlace.address.toLowerCase(), isNot(contains('khed')));

      // Rejects state-only Nominatim responses like bare {"state": "Maharashtra"}
      expect(
        LocationTrackingService.parseNominatimPlace({
          'address': {'state': 'Maharashtra', 'country': 'India'},
        }),
        isNull,
      );

      // ArcGIS parses POIs, Banks, ST Stands & roads cleanly (normalizing Khed -> Rajgurunagar)
      final arcgisPoi = LocationTrackingService.parseArcGisPlace({
        'PlaceName': 'Shivraj Krushi Seva Kendra',
        'ShortLabel': 'Shivraj Krushi Seva Kendra',
        'Address': 'Wandra Road',
        'District': 'Koye',
        'City': 'Khed',
        'Subregion': 'Pune',
        'Postal': '410505',
      });
      expect(arcgisPoi, isNotNull);
      expect(arcgisPoi!.title, 'Shivraj Krushi Seva Kendra');
      expect(arcgisPoi.address, contains('Wandra Road'));
      expect(arcgisPoi.address, contains('Koye'));
      expect(arcgisPoi.address, contains('Rajgurunagar'));
      expect(arcgisPoi.displayLabel.toLowerCase(), isNot(contains('near ')));

      // Photon parses nearby POIs & roads cleanly
      final photonPoi = LocationTrackingService.parsePhotonPlace({
        'name': 'Reliance Smart Point',
        'street': 'Bakori Road',
        'city': 'Wagholi, Pune',
        'postcode': '412207',
      });
      expect(photonPoi, isNotNull);
      expect(photonPoi!.title, 'Reliance Smart Point');
      expect(photonPoi.address, contains('Bakori Road'));
    });

    test('TimelineSegmentBuilder groups stops cleanly and computes same-staff trips without mixing staff', () {
      final base = DateTime(2026, 11, 27, 9, 30);
      final entries = [
        // Staff A stationary cluster (2 pings at same point) -> 1 Stop (15 min)
        LocationTimelineEntry(
          id: 'tl_a_1',
          userId: 'u_a',
          staffName: 'Akash',
          staffRole: 'salesman',
          timestamp: base,
          latitude: 18.7560,
          longitude: 73.8550,
          landmark: 'Chakan Chowk, Chakan MIDC',
          eventType: 'gpsPing',
        ),
        LocationTimelineEntry(
          id: 'tl_a_2',
          userId: 'u_a',
          staffName: 'Akash',
          staffRole: 'salesman',
          timestamp: base.add(const Duration(minutes: 15)),
          latitude: 18.7561,
          longitude: 73.8551,
          landmark: 'Chakan Chowk, Chakan MIDC',
          eventType: 'collection',
          details: 'Collected ₹5,000 (UPI)',
          amount: 5000,
          shopName: 'Ganesh Mart',
          routeName: 'Chakan',
        ),
        // Staff A traveled ~11 km north to Rajgurunagar in 25 min -> 1 Trip + Stop 2
        LocationTimelineEntry(
          id: 'tl_a_3',
          userId: 'u_a',
          staffName: 'Akash',
          staffRole: 'salesman',
          timestamp: base.add(const Duration(minutes: 40)),
          latitude: 18.8550,
          longitude: 73.8880,
          landmark: 'Wada Road, Rajgurunagar',
          eventType: 'orderBooked',
          details: 'Order #ORD-10 (2 CS)',
          shopName: 'Shiv Krupa',
          routeName: 'Rajgurunagar',
        ),
        // Staff B in Wagholi -> must NOT create a fake trip between Staff A and Staff B
        LocationTimelineEntry(
          id: 'tl_b_1',
          userId: 'u_b',
          staffName: 'Driver Raju',
          staffRole: 'driver',
          timestamp: base.add(const Duration(minutes: 45)),
          latitude: 18.5800,
          longitude: 73.9800,
          landmark: 'Bakori Rd, Wagholi, Pune',
          eventType: 'deliveryVisit',
          shopName: 'Wagholi Mart',
        ),
      ];

      final summary = TimelineSegmentBuilder.build(entries);
      expect(summary.stops.length, 3);
      expect(summary.trips.length, 1);
      expect(summary.trips.first.fromTitle, 'Ganesh Mart');
      expect(summary.trips.first.toTitle, 'Shiv Krupa');
      expect(summary.trips.first.distanceKm, greaterThan(10.0));
      expect(summary.trips.first.distanceKm, lessThan(14.0));
      expect(summary.trips.first.durationMinutes, 25);
      expect(summary.trips.first.travelMode, 'Motorcycling');
      expect(summary.totalCollected, 5000.0);
    });

    testWidgets('LiveStaffLocationsScreen includes all field roles and renders Day/Trips/Places timeline + Live Map',
        (tester) async {
      final admin = UserModel(
        id: 'u_admin',
        phone: '9921977636',
        name: 'Super Admin',
        role: UserRole.superAdmin,
        password: 'p',
      );
      final salesman = UserModel(
        id: 'u_sal',
        phone: '9000000001',
        name: 'Akash',
        role: UserRole.salesman,
        password: 'p',
        latitude: 18.7560,
        longitude: 73.8550,
        locationUpdatedAt: DateTime.now(),
        locationLandmark: 'Pune - Nashik Hwy, Chakan',
      );
      final orderUser = UserModel(
        id: 'u_ord',
        phone: '9000000002',
        name: 'Sagar Order',
        role: UserRole.order,
        password: 'p',
        latitude: 18.8550,
        longitude: 73.8880,
        locationUpdatedAt: DateTime.now(),
        locationLandmark: 'Wada Road, Rajgurunagar',
      );
      final collUser = UserModel(
        id: 'u_col',
        phone: '9000000003',
        name: 'Rohan Coll',
        role: UserRole.collection,
        password: 'p',
      );

      final shop = ShopModel(
        id: 'shop_chakan',
        name: 'Mahalaxmi Super Market',
        routeId: 'r1',
        routeName: 'Chakan',
        mobileNumber: '9822001122',
        address: 'Manik Chowk, Chakan',
        latitude: 18.7560,
        longitude: 73.8550,
      );

      final t1 = DateTime.now().subtract(const Duration(minutes: 45));
      final t2 = DateTime.now().subtract(const Duration(minutes: 15));
      final tl1 = LocationTimelineEntry(
        id: 'tl_sagar_1',
        userId: orderUser.id,
        staffName: orderUser.name,
        staffRole: 'order',
        timestamp: t1,
        latitude: 18.7560,
        longitude: 73.8550,
        landmark: 'Manik Chowk, Chakan',
        eventType: 'gpsPing',
      );
      final tl2 = LocationTimelineEntry(
        id: 'tl_sagar_2',
        userId: orderUser.id,
        staffName: orderUser.name,
        staffRole: 'order',
        timestamp: t2,
        latitude: 18.8550,
        longitude: 73.8880,
        landmark: 'Wada Road, Rajgurunagar',
        eventType: 'orderBooked',
        details: 'Order #ORD-55 (4 CS)',
        shopName: 'New Store',
        routeName: 'Rajgurunagar',
      );

      final tlAdmin = LocationTimelineEntry(
        id: 'tl_admin_ignored',
        userId: admin.id,
        staffName: admin.name,
        staffRole: 'superAdmin',
        timestamp: t2,
        latitude: 18.5900,
        longitude: 74.0000,
        landmark: 'Wagholi',
        eventType: 'gpsPing',
      );

      SharedPreferences.setMockInitialValues({
        'app_sample_data_initialized_v1': true,
        'app_users_cache_v1': jsonEncode([
          admin.toJson(),
          salesman.toJson(),
          orderUser.toJson(),
          collUser.toJson(),
        ]),
        'current_logged_in_user_id_v1': admin.id,
        'app_shops_v1': [jsonEncode(shop.toJson())],
        'app_location_timeline_v1': [
          jsonEncode(tl1.toJson()),
          jsonEncode(tl2.toJson()),
          jsonEncode(tlAdmin.toJson()),
        ],
      });

      final auth = AuthProvider();
      final collection = CollectionProvider();
      await auth.initialize();
      await collection.initialize();

      tester.view.physicalSize = const Size(412, 900);
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
            home: LiveStaffLocationsScreen(initialStaffName: 'Sagar Order'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No 'All Staff' option in Timeline and no Super Admin noise
      expect(find.text('All Staff'), findsNothing);
      expect(find.text('Super Admin'), findsNothing);

      // Includes Salesman, Order, and Collection roles (3 staff in Staff tab!)
      expect(find.text('Staff (3)'), findsOneWidget);
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Trips (1)'), findsOneWidget);
      expect(find.text('Places (2)'), findsOneWidget);

      // Google-Maps-style Day timeline renders stop titles, addresses & trip mode
      expect(find.text('Manik Chowk'), findsOneWidget);
      expect(find.text('Manik Chowk, Chakan'), findsOneWidget);
      expect(find.text('Motorcycling'), findsOneWidget);
      expect(find.text('New Store'), findsOneWidget);
      expect(find.text('Order #ORD-55 (4 CS)'), findsOneWidget);

      // Switch to Trips and Places sub-tabs cleanly
      await tester.tap(find.text('Trips (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Manik Chowk → New Store'), findsOneWidget);

      await tester.tap(find.text('Places (2)'));
      await tester.pumpAndSettle();
      expect(find.text('1 visit'), findsNWidgets(2));

      // Switch to Staff tab and verify Order & Collection users are listed
      await tester.tap(find.text('Staff (3)'));
      await tester.pumpAndSettle();
      expect(find.text('Akash'), findsOneWidget);
      expect(find.text('Sagar Order'), findsOneWidget);
      expect(find.text('Rohan Coll'), findsOneWidget);
    });
  });
}
