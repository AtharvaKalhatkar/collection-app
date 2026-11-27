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

  bool get isTooBroad {
    final t = title.trim().toLowerCase();
    return t.isEmpty ||
        t == 'maharashtra' ||
        t == 'india' ||
        t == 'pune' ||
        t == 'rajgurunagar' ||
        t == 'khed';
  }

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

  /// Starts periodic live location tracking ONLY for field staff roles
  /// (Sales & Collection, Sales / Order Booking, Collection, Delivery Driver).
  void startTracking({
    required AuthProvider auth,
    required CollectionProvider collectionProvider,
  }) {
    _activeAuth = auth;
    _activeCollectionProvider = collectionProvider;

    if (SupabaseService().isTestMode) return;
    final user = auth.currentUser;
    if (user == null || user.isSuperAdmin || user.isOffice) return;
    if (_isTracking) return;
    _isTracking = true;

    _initialTimer?.cancel();
    _initialTimer = Timer(const Duration(seconds: 2), () {
      if (_activeAuth != null && _activeCollectionProvider != null) {
        _captureAndSync(_activeAuth!, _activeCollectionProvider!);
      }
    });

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
    // Do NOT record Super Admin / Office desk locations into field timeline
    if (user.isSuperAdmin || user.isOffice) return false;

    try {
      final loc = await LocationService.getCurrentLocation();
      if (loc == null) return false;

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
          minDuplicateSeconds: 300,
          minMovedDegrees: 0.0005,
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

  /// Records a dedicated event (collection, orderBooked, deliveryVisit, login)
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
    if (user.isSuperAdmin || user.isOffice) return;
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

  /// Clean helper to normalize Khed -> Rajgurunagar and strip noisy suffixes/prefixes ("Near ", "At ", "IND")
  static String _cleanPlaceToken(dynamic raw) {
    if (raw == null) return '';
    var s = raw.toString().trim();
    if (s.isEmpty) return '';
    s = s.replaceFirst(RegExp(r'^(At|Near)\s+', caseSensitive: false), '').trim();
    if (s.toLowerCase() == 'khed' || s == 'खेड') {
      return 'Rajgurunagar';
    }
    s = s.replaceAll(RegExp(r'\bKhed\b', caseSensitive: false), 'Rajgurunagar');
    s = s.replaceAll('खेड', 'Rajgurunagar');
    s = s.replaceAll(RegExp(r',\s*IND\s*$', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r',\s*India\s*$', caseSensitive: false), '');
    return s.trim();
  }

  /// Parses ArcGIS reverseGeocode JSON into POI / Road + Locality + Town + Pincode
  static ResolvedPlace? parseArcGisPlace(Map<String, dynamic> address) {
    final placeName = _cleanPlaceToken(address['PlaceName']);
    final shortLabel = _cleanPlaceToken(address['ShortLabel']);
    final street = _cleanPlaceToken(address['Address']);
    final block = _cleanPlaceToken(address['Block']);
    final neighborhood = _cleanPlaceToken(address['Neighborhood']);
    final district = _cleanPlaceToken(address['District']);
    final city = _cleanPlaceToken(address['City']);
    final subregion = _cleanPlaceToken(address['Subregion']);
    final region = _cleanPlaceToken(address['Region']);
    final postal = _cleanPlaceToken(address['Postal']);

    final parts = <String>[];
    void addUnique(String val) {
      if (val.isEmpty) return;
      final lower = val.toLowerCase();
      if (lower == 'india' || lower == 'ind') return;
      if (!parts.any((p) => p.toLowerCase() == lower || p.toLowerCase().contains(lower))) {
        parts.add(val);
      }
    }

    final primaryCandidate = placeName.isNotEmpty
        ? placeName
        : (shortLabel.isNotEmpty
            ? shortLabel
            : (street.isNotEmpty
                ? street
                : (neighborhood.isNotEmpty
                    ? neighborhood
                    : (district.isNotEmpty ? district : city))));

    if (primaryCandidate.isEmpty) return null;

    addUnique(placeName);
    addUnique(street);
    addUnique(block);
    addUnique(neighborhood);
    addUnique(district);
    addUnique(city);
    if (subregion.isNotEmpty && subregion.toLowerCase() != city.toLowerCase()) {
      addUnique(subregion);
    }
    if (parts.length <= 1) {
      addUnique(region);
    }
    if (postal.isNotEmpty && parts.isNotEmpty) {
      addUnique(postal);
    }

    return ResolvedPlace(
      title: primaryCandidate,
      address: parts.join(', '),
    );
  }

  /// Parses Photon (Komoot) GeoJSON properties into nearest POI/Landmark + street + locality
  static ResolvedPlace? parsePhotonPlace(Map<String, dynamic> props) {
    final name = _cleanPlaceToken(props['name']);
    final street = _cleanPlaceToken(props['street']);
    final district = _cleanPlaceToken(props['district']);
    final locality = _cleanPlaceToken(props['locality']);
    final city = _cleanPlaceToken(props['city']);
    final postcode = _cleanPlaceToken(props['postcode']);

    final parts = <String>[];
    void addUnique(String val) {
      if (val.isEmpty) return;
      final lower = val.toLowerCase();
      if (!parts.any((p) => p.toLowerCase() == lower || p.toLowerCase().contains(lower))) {
        parts.add(val);
      }
    }

    addUnique(name);
    addUnique(street);
    addUnique(district);
    addUnique(locality);
    addUnique(city);
    addUnique(postcode);

    if (parts.isEmpty) return null;

    final title = name.isNotEmpty
        ? name
        : (street.isNotEmpty
            ? street
            : (district.isNotEmpty ? district : (city.isNotEmpty ? city : parts.first)));

    return ResolvedPlace(title: title, address: parts.join(', '));
  }

  /// Parses Nominatim JSON payload into primary place + street/area address (no state-only bare labels)
  static ResolvedPlace? parseNominatimPlace(Map<String, dynamic> data) {
    final address = data['address'] as Map<String, dynamic>?;
    if (address == null) return null;

    String pick(dynamic raw) => _cleanPlaceToken(raw);

    final poiName = [
      pick(data['name']),
      pick(address['amenity']),
      pick(address['shop']),
      pick(address['building']),
      pick(address['commercial']),
      pick(address['industrial']),
    ].firstWhere((s) => s.isNotEmpty, orElse: () => '');

    final houseNumber = pick(address['house_number']);
    final road = [
      pick(address['road']),
      pick(address['pedestrian']),
      pick(address['street']),
    ].firstWhere((s) => s.isNotEmpty, orElse: () => '');

    final locality = [
      pick(address['neighbourhood']),
      pick(address['suburb']),
      pick(address['residential']),
      pick(address['quarter']),
      pick(address['hamlet']),
    ].firstWhere((s) => s.isNotEmpty, orElse: () => '');

    final town = [
      pick(address['village']),
      pick(address['town']),
      pick(address['city']),
      pick(address['city_district']),
    ].firstWhere((s) => s.isNotEmpty, orElse: () => '');

    final postcode = pick(address['postcode']);

    final roadLine = [
      if (houseNumber.isNotEmpty) houseNumber,
      if (road.isNotEmpty) road,
    ].join(' ');

    final parts = <String>[];
    void addUnique(String val) {
      if (val.isEmpty) return;
      final lower = val.toLowerCase();
      if (!parts.any((existing) =>
          existing.toLowerCase() == lower ||
          existing.toLowerCase().contains(lower))) {
        parts.add(val);
      }
    }

    addUnique(poiName);
    addUnique(roadLine);
    addUnique(locality);
    addUnique(town);
    if (postcode.isNotEmpty && parts.isNotEmpty) {
      addUnique(postcode);
    }

    // Reject bare state-only results (e.g. just "Maharashtra")
    if (parts.isEmpty) return null;

    final title = poiName.isNotEmpty
        ? poiName
        : (roadLine.isNotEmpty
            ? roadLine
            : (locality.isNotEmpty ? locality : town));

    if (title.isEmpty) return null;
    return ResolvedPlace(title: title, address: parts.join(', '));
  }

  /// Cached multi-provider reverse-geocoder:
  /// 1) ArcGIS World GeocodeServer (strongest India rural/town roads + POIs like Banks, ST Stands, shops)
  /// 2) Photon (OSM POIs & streets nearby)
  /// 3) Nominatim fallback
  static Future<ResolvedPlace?> reverseGeocodePlace(double lat, double lng) async {
    if (lat == 0.0 && lng == 0.0) return null;
    final key = '${(lat * 2000).round()}_${(lng * 2000).round()}';
    if (_geocodeCache.containsKey(key)) {
      return _geocodeCache[key];
    }

    if (SupabaseService().isTestMode) return null;

    ResolvedPlace? best;

    // 1. ArcGIS Reverse Geocode (POI + StreetName + District)
    try {
      final poiUri = Uri.parse(
        'https://geocode.arcgis.com/arcgis/rest/services/World/GeocodeServer/reverseGeocode?f=json&location=$lng,$lat&featureTypes=POI,StreetName,PointAddress,StreetAddress',
      );
      final poiResp = await http.get(poiUri).timeout(const Duration(seconds: 4));
      if (poiResp.statusCode == 200) {
        final decoded = jsonDecode(poiResp.body) as Map<String, dynamic>;
        final addr = decoded['address'] as Map<String, dynamic>?;
        if (addr != null) {
          best = parseArcGisPlace(addr);
        }
      }

      // If no POI/Street hit in ArcGIS, fetch general locality/street from ArcGIS without featureTypes filter
      if (best == null || best.isTooBroad) {
        final genUri = Uri.parse(
          'https://geocode.arcgis.com/arcgis/rest/services/World/GeocodeServer/reverseGeocode?f=json&location=$lng,$lat',
        );
        final genResp = await http.get(genUri).timeout(const Duration(seconds: 4));
        if (genResp.statusCode == 200) {
          final decoded = jsonDecode(genResp.body) as Map<String, dynamic>;
          final addr = decoded['address'] as Map<String, dynamic>?;
          if (addr != null) {
            final candidate = parseArcGisPlace(addr);
            if (candidate != null && (best == null || !candidate.isTooBroad)) {
              best = candidate;
            }
          }
        }
      }
    } catch (_) {}

    // 2. Photon nearby POI lookup if still broad or missing street/POI
    if (best == null || best.isTooBroad) {
      try {
        final photonUri = Uri.parse(
          'https://photon.komoot.io/reverse?lon=$lng&lat=$lat&limit=2',
        );
        final photonResp = await http.get(
          photonUri,
          headers: {if (!kIsWeb) 'User-Agent': 'DailyCollectionApp/1.0'},
        ).timeout(const Duration(seconds: 4));
        if (photonResp.statusCode == 200) {
          final decoded = jsonDecode(photonResp.body) as Map<String, dynamic>;
          final features = decoded['features'] as List<dynamic>? ?? [];
          for (final f in features) {
            final props = (f as Map<String, dynamic>)['properties'] as Map<String, dynamic>?;
            if (props == null) continue;
            final candidate = parsePhotonPlace(props);
            if (candidate != null && !candidate.isTooBroad) {
              best = candidate;
              break;
            }
            best ??= candidate;
          }
        }
      } catch (_) {}
    }

    // 3. Nominatim fallback only if still empty
    if (best == null) {
      try {
        final nomUri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1',
        );
        final nomResp = await http.get(
          nomUri,
          headers: {if (!kIsWeb) 'User-Agent': 'DailyCollectionApp/1.0'},
        ).timeout(const Duration(seconds: 4));
        if (nomResp.statusCode == 200) {
          final data = jsonDecode(nomResp.body) as Map<String, dynamic>;
          best = parseNominatimPlace(data);
        }
      } catch (_) {}
    }

    if (best != null) {
      _geocodeCache[key] = best;
    }
    return best;
  }

  static ResolvedPlace? getCachedPlace(double lat, double lng) {
    final key = '${(lat * 2000).round()}_${(lng * 2000).round()}';
    return _geocodeCache[key];
  }

  /// Resolves a rich Google-Maps-style place (never prints "Near ...").
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

    final onlinePlace = await reverseGeocodePlace(lat, lng);

    // If right at a registered outlet (<= 120m), show outlet name + full street/locality address
    if (nearestShop != null && minDistanceKm <= 0.12) {
      final cleanArea = (nearestShop.address.isNotEmpty
              ? nearestShop.address
              : nearestShop.routeName)
          .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
          .trim();
      final addr = (onlinePlace != null && onlinePlace.address.isNotEmpty)
          ? onlinePlace.address
          : cleanArea;
      return ResolvedPlace(
        title: _cleanPlaceToken(nearestShop.name),
        address: addr,
      );
    }

    if (onlinePlace != null && !onlinePlace.isTooBroad) {
      return onlinePlace;
    }

    // If offline/broad, prefer registered outlet within 500m cleanly (WITHOUT "Near " word!)
    if (nearestShop != null && minDistanceKm <= 0.5) {
      final area = nearestShop.routeName.isNotEmpty
          ? nearestShop.routeName
          : nearestShop.address;
      final cleanArea = area.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
      return ResolvedPlace(
        title: _cleanPlaceToken(nearestShop.name),
        address: cleanArea.isNotEmpty
            ? cleanArea
            : (onlinePlace?.address ?? getKnownRegion(lat, lng) ?? ''),
      );
    }

    if (onlinePlace != null && onlinePlace.title.isNotEmpty) {
      return onlinePlace;
    }

    final region = getKnownRegion(lat, lng);
    if (region != null) {
      return ResolvedPlace(title: region, address: 'Pune District');
    }

    if (nearestShop != null && minDistanceKm <= 3.5) {
      final area = nearestShop.routeName.isNotEmpty
          ? nearestShop.routeName
          : nearestShop.address;
      final cleanArea = area.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
      if (cleanArea.isNotEmpty) {
        return ResolvedPlace(title: cleanArea, address: 'Field Beat Route');
      }
    }

    return ResolvedPlace(
      title: 'Location (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})',
      address: 'Pune Region',
    );
  }

  /// Backward-compatible single string resolver
  static Future<String> resolveLandmark(double lat, double lng, List<ShopModel> shops) async {
    final detailed = await resolveDetailedPlace(lat, lng, shops);
    return detailed.displayLabel;
  }

  static Future<String?> reverseGeocodeArea(double lat, double lng) async {
    final place = await reverseGeocodePlace(lat, lng);
    return place?.displayLabel;
  }

  /// Known regional bounds fallback
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

  /// Synchronous fallback helper (never returns "Near ")
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
      return _cleanPlaceToken(nearestShop.name);
    }

    final cached = getCachedPlace(lat, lng);
    if (cached != null && !cached.isTooBroad) return cached.displayLabel;

    final region = getKnownRegion(lat, lng);
    if (region != null) {
      return region;
    }

    return 'GPS: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
  }

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
