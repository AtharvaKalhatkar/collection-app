import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_collection_app/models/location_timeline_entry.dart';
import 'package:daily_collection_app/services/location_tracking_service.dart';
import 'package:daily_collection_app/services/storage_service.dart';

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
  });
}
