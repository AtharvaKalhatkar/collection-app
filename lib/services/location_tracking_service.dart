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

class ResolvedPlace {
  final String title;
  final String address;

  const ResolvedPlace({
    required this.title,
    required this.address,
  });

  String get displayLabel {
    if (address.isEmpty || address.toLowerCase() == title.toLowerCase()) {
      return title;
    }
    if (address.toLowerCase().startsWith(title.toLowerCase())) {
      return address;
    }
    return '$title, $address';
  }
}

class LocationTrackingService {
  static final LocationTrackingService _instance = LocationTrackingService._internal();
  factory LocationTrackingService() => _instance;
  LocationTrackingService._internal();

  static final Map<String, ResolvedPlace> _geocodeCache = {};

  Timer? _initialTimer;
  Timer? _periodicTimer;
  AuthProvider? _activeAuth;
  CollectionProvider? _activeCollectionProvider;
  bool _isTracking = false;
  DateTime? _lastCapturedTime;

  bool get isTracking => _isTracking;
  DateTime? get lastCapturedTime => _lastCapturedTime;

  /// Starts periodic live location tracking for the active user (salesman/driver/order/collection)
  void startTracking({
    required AuthProvider auth,
    required CollectionProvider collectionProvider,
  }) {
    _activeAuth = auth;
    _activeCollectionProvider = collectionProvider;

    if (SupabaseService().isTestMode) return;
    if (_isTracking) return;
    _isTracking = true;

    // Initial capture with small delay so app initialization finishes smoothly
    _initialTimer?.cancel();
    _initialTimer = Timer(const Duration(seconds: 2), () {
      if (_activeAuth != null && _activeCollectionProvider != null) {
        _captureAndSync(_activeAuth!, _activeCollectionProvider!);
      }
    });

    // Periodic capture every 90 seconds while session is active so trips & live location stay fresh
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      if (_activeAuth != null && _activeCollectionProvider != null) {
        _captureAndSync(_activeAuth!, _activeCollectionProvider!);
      }
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
    _activeAuth = auth;
    _activeCollectionProvider = collectionProvider;
    return await _captureAndSync(auth, collectionProvider);
  }

  Future<bool> _captureAndSync(AuthProvider auth, CollectionProvider collectionProvider) async {
    final user = auth.currentUser;
    if (user == null || !user.isActive) return false;

    try {
      final loc = await LocationService.getCurrentLocation();
      if (loc == null) return false;

      // Identify full road / locality / outlet address via Google/OSM reverse geocoding + outlets
      final place = await resolveDetailedPlace(
        loc.latitude,
        loc.longitude,
        collectionProvider.shops,
      );
      final landmark = place.displayLabel;

      await auth.updateCurrentLocation(
        loc.latitude,
        loc.longitude,
        landmark: landmark,
      );
      _lastCapturedTime = DateTime.now();
      debugPrint('Live GPS tracked for ${user.name}: (${loc.latitude}, ${loc.longitude}) - $landmark');

      // Record chronological timeline breadcrumb
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
          details: user.isDriver
              ? 'Delivery vehicle route'
              : (user.isOrder ? 'Sales & Order beat' : 'Field route active'),
        );
        await _persistAndUploadTimelineEntry(
          entry,
          minDuplicateSeconds: 300, // 5 min stationary window before repeating
          minMovedDegrees: 0.0005, // ~55 meters movement captures travel path cleanly
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

  /// Records a dedicated event (e.g. collection, delivery checkpoint, order, login)
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
      double? lat = latitude ?? user.latitude;
      double? lng = longitude ?? user.longitude;
      if ((lat == null || lng == null || lat == 0.0 || lng == 0.0) &&
          !SupabaseService().isTestMode) {
        final live = await LocationService.getCurrentLocation();
        if (live != null) {
          lat = live.latitude;
          lng = live.longitude;
        }
      }
      final double finalLat = lat ?? 18.8550;
      final double finalLng = lng ?? 73.8880;
      final String lm = landmark ?? user.locationLandmark ?? 'Active in Beat';

      final entry = LocationTimelineEntry(
        id: 'tl_${user.id}_${DateTime.now().millisecondsSinceEpoch}',
        userId: user.id,
        staffName: user.name,
        staffRole: user.role.name,
        timestamp: DateTime.now(),
        latitude: finalLat,
        longitude: finalLng,
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

  /// Resolves a rich Google-Maps-style place (title + full street/locality/city address).
  static Future<ResolvedPlace> resolveDetailedPlace(
    double lat,
    double lng,
    List<ShopModel> shops,
  ) async {
    final realShops = shops.where((s) {
      final name = s.name.toLowerCase();
      final route = s.routeName.toLowerCase();
      return !name.contains('test') && !route.contains('test');
    }).toList();

    ShopModel? nearestShop;
    double minDistanceKm = double.infinity;

    for (final s in realShops) {
      if (s.latitude != null && s.longitude != null && s.latitude != 0.0) {
        final d = haversineDistanceKm(lat, lng, s.latitude!, s.longitude!);
        if (d < minDistanceKm) {
          minDistanceKm = d;
          nearestShop = s;
        }
      }
    }

    // Always try reverse-geocoding the real street + locality + city (cached by ~110m grid)
    final onlinePlace = await reverseGeocodePlace(lat, lng);

    // Only count as inside/at a registered store if physically within 120m
    if (nearestShop != null && minDistanceKm <= 0.12) {
      final cleanArea = (nearestShop.address.isNotEmpty
              ? nearestShop.address
              : nearestShop.routeName)
          .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
          .trim();
      final address = (onlinePlace != null && onlinePlace.address.isNotEmpty)
          ? onlinePlace.address
          : cleanArea;
      return ResolvedPlace(
        title: nearestShop.name.trim(),
        address: address,
      );
    }

    if (onlinePlace != null && onlinePlace.title.isNotEmpty) {
      return onlinePlace;
    }

    final region = getKnownRegion(lat, lng);
    if (region != null) {
      return ResolvedPlace(title: region, address: 'Pune District, Maharashtra');
    }

    if (nearestShop != null && minDistanceKm <= 3.5) {
      final area = nearestShop.routeName.isNotEmpty
          ? nearestShop.routeName
          : nearestShop.address;
      final cleanArea = area.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
      if (cleanArea.isNotEmpty) {
        return ResolvedPlace(title: cleanArea, address: 'Field Beat Area');
      }
    }

    return ResolvedPlace(
      title: 'Location (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})',
      address: 'Rajgurunagar / Khed Region',
    );
  }

  /// Backward-compatible single string resolver using rich street/area details
  static Future<String> resolveLandmark(double lat, double lng, List<ShopModel> shops) async {
    final detailed = await resolveDetailedPlace(lat, lng, shops);
    return detailed.displayLabel;
  }

  /// Parses Nominatim JSON payload into a Google-Maps-style primary title + full address line
  static ResolvedPlace? parseNominatimPlace(Map<String, dynamic> data) {
    final address = data['address'] as Map<String, dynamic>?;
    if (address == null) return null;

    String? cleanPart(dynamic raw) {
      if (raw == null) return null;
      var s = raw.toString().trim();
      if (s.isEmpty) return null;
      if (s.toLowerCase() == 'khed' || s == 'खेड') {
        s = 'Rajgurunagar';
      }
      s = s.replaceAll(RegExp(r',\s*(Khed|खेड)', caseSensitive: false), '').trim();
      return s.isEmpty ? null : s;
    }

    final poiName = cleanPart(data['name']) ??
        cleanPart(address['amenity']) ??
        cleanPart(address['shop']) ??
        cleanPart(address['building']) ??
        cleanPart(address['commercial']) ??
        cleanPart(address['industrial']);
    final houseNumber = cleanPart(address['house_number']);
    final road = cleanPart(address['road']) ??
        cleanPart(address['pedestrian']) ??
        cleanPart(address['street']);
    final locality = cleanPart(address['neighbourhood']) ??
        cleanPart(address['suburb']) ??
        cleanPart(address['residential']) ??
        cleanPart(address['quarter']) ??
        cleanPart(address['hamlet']);
    final town = cleanPart(address['village']) ??
        cleanPart(address['town']) ??
        cleanPart(address['city']) ??
        cleanPart(address['city_district']);
    final state = cleanPart(address['state']);
    final postcode = cleanPart(address['postcode']);

    final roadLine = [
      ?houseNumber,
      ?road,
    ].join(' ');

    final parts = <String>[];
    void addUnique(String? val) {
      if (val == null || val.isEmpty) return;
      final lower = val.toLowerCase();
      if (!parts.any((existing) =>
          existing.toLowerCase() == lower ||
          existing.toLowerCase().contains(lower))) {
        parts.add(val);
      }
    }

    addUnique(poiName);
    addUnique(roadLine.isNotEmpty ? roadLine : null);
    addUnique(locality);
    addUnique(town);
    if (parts.length <= 1) {
      addUnique(state);
    }
    if (postcode != null && parts.isNotEmpty) {
      addUnique(postcode);
    }

    if (parts.isEmpty) return null;

    final title = poiName ??
        (roadLine.isNotEmpty ? roadLine : null) ??
        locality ??
        town ??
        parts.first;

    final fullAddress = parts.join(', ');
    return ResolvedPlace(title: title, address: fullAddress);
  }

  /// Cached reverse-geocoder returning Google-Maps-style primary place + street/area address
  static Future<ResolvedPlace?> reverseGeocodePlace(double lat, double lng) async {
    if (lat == 0.0 && lng == 0.0) return null;
    final key = '${(lat * 1000).round()}_${(lng * 1000).round()}';
    if (_geocodeCache.containsKey(key)) {
      return _geocodeCache[key];
    }

    if (SupabaseService().isTestMode) return null;

    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1',
      );
      final response = await http.get(
        uri,
        headers: {if (!kIsWeb) 'User-Agent': 'DailyCollectionApp/1.0'},
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final parsed = parseNominatimPlace(data);
        if (parsed != null) {
          _geocodeCache[key] = parsed;
          return parsed;
        }
      }
    } catch (_) {}
    return null;
  }

  static ResolvedPlace? getCachedPlace(double lat, double lng) {
    final key = '${(lat * 1000).round()}_${(lng * 1000).round()}';
    return _geocodeCache[key];
  }

  /// Reverse geocodes coordinates to a clean area string
  static Future<String?> reverseGeocodeArea(double lat, double lng) async {
    final place = await reverseGeocodePlace(lat, lng);
    return place?.displayLabel;
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

    final cached = getCachedPlace(lat, lng);
    if (cached != null) return cached.displayLabel;

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
