import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/shop_model.dart';
import '../providers/auth_provider.dart';
import '../providers/collection_provider.dart';
import 'location_service.dart';

class LocationTrackingService {
  static final LocationTrackingService _instance = LocationTrackingService._internal();
  factory LocationTrackingService() => _instance;
  LocationTrackingService._internal();

  Timer? _periodicTimer;
  bool _isTracking = false;
  DateTime? _lastCapturedTime;

  bool get isTracking => _isTracking;
  DateTime? get lastCapturedTime => _lastCapturedTime;

  /// Starts periodic live location tracking for the active user (salesman/driver)
  void startTracking({
    required AuthProvider auth,
    required CollectionProvider collectionProvider,
  }) {
    if (_isTracking) return;
    _isTracking = true;

    // Initial capture with small delay so app initialization finishes smoothly
    Future.delayed(const Duration(seconds: 3), () {
      _captureAndSync(auth, collectionProvider);
    });

    // Periodic capture every 3 minutes while the app session is active
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      _captureAndSync(auth, collectionProvider);
    });
  }

  void stopTracking() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _isTracking = false;
  }

  /// Manually triggers an immediate GPS fix and syncs to cloud
  Future<bool> captureImmediate({
    required AuthProvider auth,
    required CollectionProvider collectionProvider,
  }) async {
    return await _captureAndSync(auth, collectionProvider);
  }

  Future<bool> _captureAndSync(AuthProvider auth, CollectionProvider collectionProvider) async {
    final user = auth.currentUser;
    if (user == null || !user.isActive) return false;

    try {
      final loc = await LocationService.getCurrentLocation();
      if (loc == null) return false;

      // Identify nearest outlet in beat routes
      final landmark = findNearestLandmark(loc.latitude, loc.longitude, collectionProvider.shops);

      await auth.updateCurrentLocation(
        loc.latitude,
        loc.longitude,
        landmark: landmark,
      );
      _lastCapturedTime = DateTime.now();
      debugPrint('Live GPS tracked for ${user.name}: (${loc.latitude}, ${loc.longitude}) - $landmark');
      return true;
    } catch (e) {
      debugPrint('Location tracking notice: $e');
      return false;
    }
  }

  /// Identifies closest distributor outlet or route to provide human-readable location context
  static String findNearestLandmark(double lat, double lng, List<ShopModel> shops) {
    if (shops.isEmpty) {
      return 'GPS: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
    }

    ShopModel? nearestShop;
    double minDistanceKm = double.infinity;

    for (final s in shops) {
      if (s.latitude != null && s.longitude != null) {
        final d = haversineDistanceKm(lat, lng, s.latitude!, s.longitude!);
        if (d < minDistanceKm) {
          minDistanceKm = d;
          nearestShop = s;
        }
      }
    }

    if (nearestShop != null && minDistanceKm < 25.0) {
      final routeStr = nearestShop.routeName.isNotEmpty ? ' (${nearestShop.routeName})' : '';
      if (minDistanceKm < 0.25) {
        return 'At ${nearestShop.name}$routeStr';
      } else if (minDistanceKm < 1.0) {
        return 'Near ${nearestShop.name}$routeStr (~${(minDistanceKm * 1000).round()}m)';
      } else {
        return 'Near ${nearestShop.name}$routeStr (~${minDistanceKm.toStringAsFixed(1)}km)';
      }
    }

    return 'GPS: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
  }

  /// Great-circle distance between two GPS coordinates in kilometers
  static double haversineDistanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);
}
