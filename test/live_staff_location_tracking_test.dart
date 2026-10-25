import 'package:flutter_test/flutter_test.dart';
import 'package:daily_collection_app/models/user_model.dart';
import 'package:daily_collection_app/models/shop_model.dart';
import 'package:daily_collection_app/services/location_tracking_service.dart';

void main() {
  group('Live Staff Location Tracking & UserModel Tests', () {
    test('UserModel location serialization into password metadata works seamlessly', () {
      final now = DateTime.now();
      final user = UserModel(
        id: 'user_salesman_1',
        name: 'Akash',
        phone: '9876543210',
        role: UserRole.salesman,
        password: 'securePass123',
        assignedRouteIds: ['route_1', 'route_2'],
        latitude: 18.75123,
        longitude: 73.84567,
        locationUpdatedAt: now,
        locationLandmark: 'Near Star Mart',
      );

      expect(user.hasLocation, isTrue);
      expect(user.isOnline, isTrue);
      expect(user.mapsUrl, contains('18.75123,73.84567'));
      expect(user.actualPassword, equals('securePass123'));

      // Serialize to Json (what goes to Supabase app_users table)
      final json = user.toJson();
      final storedPassword = json['password'] as String;

      expect(storedPassword, contains('securePass123:::routes=route_1,route_2:::loc='));
      expect(storedPassword, contains('18.75123,73.84567'));

      // Deserialize back from Json
      final parsedUser = UserModel.fromJson(json);

      expect(parsedUser.name, equals('Akash'));
      expect(parsedUser.actualPassword, equals('securePass123'));
      expect(parsedUser.assignedRouteIds, equals(['route_1', 'route_2']));
      expect(parsedUser.latitude, closeTo(18.75123, 0.0001));
      expect(parsedUser.longitude, closeTo(73.84567, 0.0001));
      expect(parsedUser.locationLandmark, equals('Near Star Mart'));
      expect(parsedUser.hasLocation, isTrue);
      expect(parsedUser.isOnline, isTrue);
    });

    test('Location time ago formatting works accurately', () {
      final recentUser = UserModel(
        id: 'u1',
        name: 'Test',
        phone: '111',
        password: 'pass',
        role: UserRole.driver,
        locationUpdatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        latitude: 18.5,
        longitude: 73.8,
      );
      expect(recentUser.locationTimeAgo, equals('5m ago'));

      final hourAgoUser = UserModel(
        id: 'u2',
        name: 'Test 2',
        phone: '222',
        password: 'pass',
        role: UserRole.salesman,
        locationUpdatedAt: DateTime.now().subtract(const Duration(hours: 2)),
        latitude: 18.5,
        longitude: 73.8,
      );
      expect(hourAgoUser.locationTimeAgo, equals('2h ago'));
    });

    test('Haversine distance calculation and landmark resolution', () {
      // Chakan to Rajgurunagar ~ 17-18 km
      final chakanLat = 18.7547;
      final chakanLng = 73.8580;
      final rajgurunagarLat = 18.8574;
      final rajgurunagarLng = 73.8837;

      final dist = LocationTrackingService.haversineDistanceKm(
        chakanLat,
        chakanLng,
        rajgurunagarLat,
        rajgurunagarLng,
      );
      expect(dist, greaterThan(10.0));
      expect(dist, lessThan(20.0));

      final testShops = [
        ShopModel(
          id: 'shop_1',
          name: 'Star Mart',
          routeId: 'r1',
          routeName: 'Wada Road',
          mobileNumber: '',
          address: '',
          latitude: 18.7549,
          longitude: 73.8581,
        ),
      ];

      // Exact or very close (< 50m)
      final landmarkClose = LocationTrackingService.findNearestLandmark(
        18.7548,
        73.8580,
        testShops,
      );
      expect(landmarkClose, contains('Star Mart'));
    });
  });
}
