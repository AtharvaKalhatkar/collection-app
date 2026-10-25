import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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

      // Identify accurate landmark or real locality
      final landmark = await resolveLandmark(
        loc.latitude,
        loc.longitude,
        collectionProvider.shops,
      );

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

  /// Asynchronously resolves the most accurate human-readable location
  static Future<String> resolveLandmark(double lat, double lng, List<ShopModel> shops) async {
    // 1. Check if physically close (< 250m) to a REAL shop (ignore test shops)
    final realShops = shops.where((s) {
      final name = s.name.toLowerCase();
      final route = s.routeName.toLowerCase();
      return !name.contains('test') && !route.contains('test');
    }).toList();

    ShopModel? nearestShop;
    double minDistanceKm = double.infinity;

    for (final s in realShops) {
      if (s.latitude != null && s.longitude != null) {
        final d = haversineDistanceKm(lat, lng, s.latitude!, s.longitude!);
        if (d < minDistanceKm) {
          minDistanceKm = d;
          nearestShop = s;
        }
      }
    }

    if (nearestShop != null && minDistanceKm <= 0.25) {
      final routeStr = nearestShop.routeName.isNotEmpty ? ' (${nearestShop.routeName})' : '';
      if (minDistanceKm <= 0.08) {
        return 'At ${nearestShop.name}$routeStr';
      }
      return 'Near ${nearestShop.name}$routeStr (~${(minDistanceKm * 1000).round()}m)';
    }

    // 2. Beyond 250m, get real locality / suburb / town name via reverse geocoding
    final onlineArea = await reverseGeocodeArea(lat, lng);
    if (onlineArea != null && onlineArea.isNotEmpty) {
      return onlineArea;
    }

    // 3. Known regional bounding box fallback
    final region = getKnownRegion(lat, lng);
    if (region != null) {
      return region;
    }

    // 4. Fallback to clean coordinate string
    return 'GPS: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
  }

  /// Reverse geocodes coordinates to a clean area name (suburb/town, district)
  static Future<String?> reverseGeocodeArea(double lat, double lng) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=14&addressdetails=1',
      );
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'DailyCollectionApp/1.0'},
      ).timeout(const Duration(milliseconds: 2500));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          final place = address['suburb'] ??
              address['town'] ??
              address['village'] ??
              address['neighbourhood'] ??
              address['residential'] ??
              address['city_district'] ??
              address['city'];
          final district = address['county'] ?? address['state_district'] ?? address['state'];
          if (place != null && place.toString().trim().isNotEmpty) {
            final pStr = place.toString().trim();
            final dStr = (district != null) ? district.toString().trim() : '';
            if (dStr.isNotEmpty && dStr.toLowerCase() != pStr.toLowerCase()) {
              return '$pStr, $dStr';
            }
            return pStr;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Known regional bounds fallback for instant offline precision
  static String? getKnownRegion(double lat, double lng) {
    if (lat >= 18.54 && lat <= 18.63 && lng >= 73.94 && lng <= 74.05) return 'Wagholi, Pune';
    if (lat >= 18.72 && lat <= 18.79 && lng >= 73.82 && lng <= 73.89) return 'Chakan, Khed';
    if (lat >= 18.83 && lat <= 18.89 && lng >= 73.85 && lng <= 73.93) return 'Rajgurunagar / Khed';
    if (lat >= 18.59 && lat <= 18.67 && lng >= 73.78 && lng <= 73.87) return 'Bhosari / PCMC';
    if (lat >= 18.65 && lat <= 18.71 && lng >= 73.86 && lng <= 73.93) return 'Alandi, Pune';
    if (lat >= 18.70 && lat <= 18.77 && lng >= 73.65 && lng <= 73.74) return 'Talegaon Dabhade';
    if (lat >= 18.72 && lat <= 18.79 && lng >= 73.76 && lng <= 73.83) return 'Mahalunge / Chakan MIDC';
    if (lat >= 18.70 && lat <= 18.82 && lng >= 74.06 && lng <= 74.20) return 'Shikrapur, Pune';
    if (lat >= 18.95 && lat <= 19.06 && lng >= 73.89 && lng <= 73.98) return 'Manchar, Pune';
    if (lat >= 18.46 && lat <= 18.56 && lng >= 73.80 && lng <= 73.93) return 'Pune City';
    return null;
  }

  /// Synchronous fallback helper for immediate offline evaluation
  static String findNearestLandmark(double lat, double lng, List<ShopModel> shops) {
    // 1. Exclude test shops
    final realShops = shops.where((s) {
      final name = s.name.toLowerCase();
      final route = s.routeName.toLowerCase();
      return !name.contains('test') && !route.contains('test');
    }).toList();

    ShopModel? nearestShop;
    double minDistanceKm = double.infinity;

    for (final s in realShops) {
      if (s.latitude != null && s.longitude != null) {
        final d = haversineDistanceKm(lat, lng, s.latitude!, s.longitude!);
        if (d < minDistanceKm) {
          minDistanceKm = d;
          nearestShop = s;
        }
      }
    }

    if (nearestShop != null && minDistanceKm <= 0.25) {
      final routeStr = nearestShop.routeName.isNotEmpty ? ' (${nearestShop.routeName})' : '';
      if (minDistanceKm <= 0.08) {
        return 'At ${nearestShop.name}$routeStr';
      }
      return 'Near ${nearestShop.name}$routeStr (~${(minDistanceKm * 1000).round()}m)';
    }

    // 2. Known region fallback
    final region = getKnownRegion(lat, lng);
    if (region != null) {
      return region;
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
