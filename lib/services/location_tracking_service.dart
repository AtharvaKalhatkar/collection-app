import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/shop_model.dart';
import '../models/user_model.dart';
import '../models/location_timeline_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/collection_provider.dart';
import 'location_service.dart';
import 'storage_service.dart';
import 'supabase_service.dart';

class LocationTrackingService {
  static final LocationTrackingService _instance = LocationTrackingService._internal();
  factory LocationTrackingService() => _instance;
  LocationTrackingService._internal();

  Timer? _initialTimer;
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
    if (_isTracking || SupabaseService().isTestMode) return;
    _isTracking = true;

    // Initial capture with small delay so app initialization finishes smoothly
    _initialTimer?.cancel();
    _initialTimer = Timer(const Duration(seconds: 3), () {
      _captureAndSync(auth, collectionProvider);
    });

    // Periodic capture every 3 minutes while the app session is active
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      _captureAndSync(auth, collectionProvider);
    });
  }

  void stopTracking() {
    _initialTimer?.cancel();
    _initialTimer = null;
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

      // Record chronological timeline breadcrumb for staff (salesmen, drivers, etc.)
      try {
        final entry = LocationTimelineEntry(
          id: 'tl_${user.id}_${DateTime.now().millisecondsSinceEpoch}',
          userId: user.id,
          staffName: user.name,
          staffRole: user.role.name,
          timestamp: DateTime.now(),
          latitude: loc.latitude,
          longitude: loc.longitude,
          landmark: landmark,
          eventType: 'gpsPing',
          details: user.isDriver ? 'Transit on delivery beat' : 'Active on sales route',
        );
        await _persistAndUploadTimelineEntry(
          entry,
          minDuplicateSeconds: 900, // Deduplicate stationary pings within 15 min
          minMovedDegrees: 0.00025, // ~25 meters movement threshold
        );
      } catch (err) {
        debugPrint('Timeline recording notice: $err');
      }

      return true;
    } catch (e) {
      debugPrint('Location tracking notice: $e');
      return false;
    }
  }

  /// Records a dedicated event (e.g. collection, delivery checkpoint, login)
  Future<void> recordCustomEvent({
    required UserModel user,
    required String eventType,
    required String details,
    double? latitude,
    double? longitude,
    String? landmark,
    double? amount,
    String? shopName,
    String? routeName,
    String? billNumber,
  }) async {
    try {
      final double lat = latitude ?? user.latitude ?? 18.5204;
      final double lng = longitude ?? user.longitude ?? 73.8567;
      final String lm = landmark ?? user.locationLandmark ?? 'Active in Beat';

      final entry = LocationTimelineEntry(
        id: 'tl_${user.id}_${DateTime.now().millisecondsSinceEpoch}',
        userId: user.id,
        staffName: user.name,
        staffRole: user.role.name,
        timestamp: DateTime.now(),
        latitude: lat,
        longitude: lng,
        landmark: lm,
        eventType: eventType,
        details: details,
        amount: amount,
        shopName: shopName,
        routeName: routeName,
        billNumber: billNumber,
      );
      await _persistAndUploadTimelineEntry(
        entry,
        minDuplicateSeconds: 5,
        minMovedDegrees: 0.00001,
      );
    } catch (e) {
      debugPrint('Error recording custom timeline event: $e');
    }
  }

  Future<void> _persistAndUploadTimelineEntry(
    LocationTimelineEntry entry, {
    required int minDuplicateSeconds,
    required double minMovedDegrees,
  }) async {
    final storage = StorageService();
    final inserted = await storage.addLocationTimelineEntry(
      entry,
      minDuplicateSeconds: minDuplicateSeconds,
      minMovedDegrees: minMovedDegrees,
    );
    if (!inserted) return;

    final pending = await storage.loadIdSet(StorageService.keyPendingTimelineIds);
    pending.add(entry.id);
    await storage.saveIdSet(StorageService.keyPendingTimelineIds, pending);

    final ok = await SupabaseService().saveLocationTimelineEntry(entry);
    if (ok) {
      pending.remove(entry.id);
      await storage.saveIdSet(StorageService.keyPendingTimelineIds, pending);
    }
  }

  /// Flushes any locally queued location timeline events captured while offline.
  Future<void> flushPendingTimelineToCloud() async {
    try {
      final storage = StorageService();
      final pendingIds = await storage.loadIdSet(StorageService.keyPendingTimelineIds);
      if (pendingIds.isEmpty) return;

      final timeline = await storage.loadLocationTimeline();
      final pendingEntries =
          timeline.where((e) => pendingIds.contains(e.id)).toList();
      if (pendingEntries.isEmpty) {
        await storage.saveIdSet(StorageService.keyPendingTimelineIds, {});
        return;
      }

      final ok = await SupabaseService().saveLocationTimelineEntriesBulk(pendingEntries);
      if (ok) {
        final remaining = pendingIds.difference(pendingEntries.map((e) => e.id).toSet());
        await storage.saveIdSet(StorageService.keyPendingTimelineIds, remaining);
      }
    } catch (e) {
      debugPrint('Flush pending timeline notice: $e');
    }
  }

  /// Asynchronously resolves the most accurate human-readable location
  static Future<String> resolveLandmark(double lat, double lng, List<ShopModel> shops) async {
    // 1. Check if physically close (< 300m) to a REAL shop (ignore test shops)
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

    if (nearestShop != null && minDistanceKm <= 0.30) {
      return nearestShop.name;
    }

    if (nearestShop != null && minDistanceKm <= 1.2) {
      final area = nearestShop.routeName.isNotEmpty ? nearestShop.routeName : nearestShop.address;
      final cleanArea = area.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
      return 'Near ${nearestShop.name}${cleanArea.isNotEmpty ? " · $cleanArea" : ""}';
    }

    // 2. Beyond 1.2km, get real locality / suburb / town name via reverse geocoding (street/village level)
    final onlineArea = await reverseGeocodeArea(lat, lng);
    if (onlineArea != null &&
        onlineArea.isNotEmpty &&
        onlineArea != 'Khed, खेड' &&
        onlineArea != 'Khed' &&
        onlineArea != 'खेड') {
      return onlineArea;
    }

    // 3. Known regional bounding box fallback
    final region = getKnownRegion(lat, lng);
    if (region != null) {
      return region;
    }

    if (nearestShop != null && minDistanceKm <= 3.5) {
      final area = nearestShop.routeName.isNotEmpty ? nearestShop.routeName : nearestShop.address;
      final cleanArea = area.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
      if (cleanArea.isNotEmpty) return cleanArea;
    }

    return 'Rajgurunagar';
  }

  /// Reverse geocodes coordinates to a clean area name (suburb/town, street level)
  static Future<String?> reverseGeocodeArea(double lat, double lng) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1',
      );
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'DailyCollectionApp/1.0'},
      ).timeout(const Duration(milliseconds: 2500));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          final road = address['road'];
          final suburb = address['suburb'] ??
              address['neighbourhood'] ??
              address['residential'] ??
              address['industrial'] ??
              address['commercial'];
          final village = address['village'] ?? address['hamlet'] ?? address['town'];
          final city = address['city'] ?? address['city_district'];

          final place = suburb ?? village ?? road ?? city;
          if (place != null && place.toString().trim().isNotEmpty) {
            var pStr = place.toString().trim();
            // If it's generic "Khed" or "खेड", translate to actual local town "Rajgurunagar"
            if (pStr.toLowerCase() == 'khed' || pStr == 'खेड') {
              if (road != null && road.toString().trim().isNotEmpty) {
                return '${road.toString().trim()}, Rajgurunagar';
              }
              return 'Rajgurunagar';
            }
            pStr = pStr.replaceAll(RegExp(r',\s*(Khed|खेड)', caseSensitive: false), '').trim();
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
    if (lat >= 18.72 && lat <= 18.79 && lng >= 73.82 && lng <= 73.89) return 'Chakan';
    if (lat >= 18.83 && lat <= 18.89 && lng >= 73.85 && lng <= 73.93) return 'Rajgurunagar';
    if (lat >= 18.59 && lat <= 18.67 && lng >= 73.78 && lng <= 73.87) return 'Bhosari / PCMC';
    if (lat >= 18.65 && lat <= 18.71 && lng >= 73.86 && lng <= 73.93) return 'Alandi';
    if (lat >= 18.70 && lat <= 18.77 && lng >= 73.65 && lng <= 73.74) return 'Talegaon Dabhade';
    if (lat >= 18.72 && lat <= 18.79 && lng >= 73.76 && lng <= 73.83) return 'Mahalunge / Chakan MIDC';
    if (lat >= 18.70 && lat <= 18.82 && lng >= 74.06 && lng <= 74.20) return 'Shikrapur';
    if (lat >= 18.95 && lat <= 19.06 && lng >= 73.89 && lng <= 73.98) return 'Manchar';
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
      return nearestShop.name;
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
