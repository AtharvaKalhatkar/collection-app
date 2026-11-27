import '../models/location_timeline_entry.dart';
import '../models/shop_model.dart';
import '../models/user_model.dart';
import '../services/location_tracking_service.dart';

sealed class TimelineDayNode {
  const TimelineDayNode();
}

class TimelineStopItem extends TimelineDayNode {
  final String staffKey;
  final String staffName;
  final String staffRole;
  final DateTime startTime;
  final DateTime endTime;
  final double latitude;
  final double longitude;
  final String placeTitle;
  final String placeAddress;
  final String? shopName;
  final List<LocationTimelineEntry> events;
  final double totalAmount;

  const TimelineStopItem({
    required this.staffKey,
    required this.staffName,
    required this.staffRole,
    required this.startTime,
    required this.endTime,
    required this.latitude,
    required this.longitude,
    required this.placeTitle,
    required this.placeAddress,
    this.shopName,
    required this.events,
    required this.totalAmount,
  });

  int get durationMinutes =>
      endTime.difference(startTime).inMinutes.clamp(0, 24 * 60);

  bool get hasCollection => events.any((e) => e.isCollection);
  bool get hasOrder => events.any((e) => e.isOrderBooked);
  bool get hasDelivery => events.any((e) => e.isDelivery);
}

class TimelineTripItem extends TimelineDayNode {
  final String staffKey;
  final String staffName;
  final String staffRole;
  final DateTime startTime;
  final DateTime endTime;
  final String fromTitle;
  final String toTitle;
  final double distanceKm;
  final int durationMinutes;
  final String travelMode; // 'Walking', 'Motorcycling', 'Driving'
  final List<({double lat, double lng})> pathPoints;

  const TimelineTripItem({
    required this.staffKey,
    required this.staffName,
    required this.staffRole,
    required this.startTime,
    required this.endTime,
    required this.fromTitle,
    required this.toTitle,
    required this.distanceKm,
    required this.durationMinutes,
    required this.travelMode,
    required this.pathPoints,
  });
}

class TimelinePlaceSummary {
  final String placeTitle;
  final String placeAddress;
  final double latitude;
  final double longitude;
  final int visitCount;
  final int totalMinutes;
  final double totalAmount;
  final DateTime lastVisited;

  const TimelinePlaceSummary({
    required this.placeTitle,
    required this.placeAddress,
    required this.latitude,
    required this.longitude,
    required this.visitCount,
    required this.totalMinutes,
    required this.totalAmount,
    required this.lastVisited,
  });
}

class TimelineDaySummary {
  final List<TimelineDayNode> dayNodes;
  final List<TimelineStopItem> stops;
  final List<TimelineTripItem> trips;
  final List<TimelinePlaceSummary> places;
  final double totalDistanceKm;
  final double totalCollected;

  const TimelineDaySummary({
    required this.dayNodes,
    required this.stops,
    required this.trips,
    required this.places,
    required this.totalDistanceKm,
    required this.totalCollected,
  });
}

class TimelineSegmentBuilder {
  /// Splits & groups a day's raw timeline entries into Google-Maps-style Stops and Travel Trips.
  static TimelineDaySummary build(
    List<LocationTimelineEntry> rawEntries, {
    List<ShopModel> shops = const [],
  }) {
    if (rawEntries.isEmpty) {
      return const TimelineDaySummary(
        dayNodes: [],
        stops: [],
        trips: [],
        places: [],
        totalDistanceKm: 0.0,
        totalCollected: 0.0,
      );
    }

    // Group entries by staff member so trips/distances are never computed across two different staff
    final Map<String, List<LocationTimelineEntry>> byStaff = {};
    for (final e in rawEntries) {
      final plain = UserModel.cleanPlainName(e.staffName).toLowerCase();
      final key = plain.isNotEmpty ? plain : e.userId.toLowerCase();
      byStaff.putIfAbsent(key, () => []).add(e);
    }

    final allNodes = <TimelineDayNode>[];
    final allStops = <TimelineStopItem>[];
    final allTrips = <TimelineTripItem>[];
    double totalDist = 0.0;
    double totalCollected = 0.0;

    // Preserve natural staff ordering by earliest activity
    final staffGroups = byStaff.entries.toList()
      ..sort((a, b) {
        final aFirst = a.value.map((e) => e.timestamp).reduce((x, y) => x.isBefore(y) ? x : y);
        final bFirst = b.value.map((e) => e.timestamp).reduce((x, y) => x.isBefore(y) ? x : y);
        return aFirst.compareTo(bFirst);
      });

    for (final group in staffGroups) {
      final sorted = List<LocationTimelineEntry>.from(group.value)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final staffStops = <TimelineStopItem>[];
      List<LocationTimelineEntry> currentCluster = [sorted.first];

      void flushCluster(List<LocationTimelineEntry> cluster) {
        final anchor = cluster.firstWhere(
          (e) => e.shopName != null && e.shopName!.trim().isNotEmpty,
          orElse: () => cluster.first,
        );
        final resolved = _resolveClusterLabel(anchor, cluster, shops);
        final double sumAmount = cluster.fold(
          0.0,
          (sum, e) => sum + (e.isCollection && e.amount != null ? e.amount! : 0.0),
        );
        totalCollected += sumAmount;

        staffStops.add(
          TimelineStopItem(
            staffKey: group.key,
            staffName: UserModel.cleanPlainName(anchor.staffName),
            staffRole: anchor.staffRole,
            startTime: cluster.first.timestamp,
            endTime: cluster.last.timestamp,
            latitude: anchor.latitude,
            longitude: anchor.longitude,
            placeTitle: resolved.title,
            placeAddress: resolved.address,
            shopName: anchor.shopName,
            events: List<LocationTimelineEntry>.unmodifiable(cluster),
            totalAmount: sumAmount,
          ),
        );
      }

      for (int i = 1; i < sorted.length; i++) {
        final prev = currentCluster.last;
        final cur = sorted[i];

        final distKm = _safeDistKm(prev.latitude, prev.longitude, cur.latitude, cur.longitude);
        final prevShop = (prev.shopName ?? '').trim().toLowerCase();
        final curShop = (cur.shopName ?? '').trim().toLowerCase();
        final distinctShops = prevShop.isNotEmpty && curShop.isNotEmpty && prevShop != curShop;

        // Merge consecutive events within 150m unless clearly visiting two different named outlets
        if (distKm <= 0.15 && !distinctShops) {
          currentCluster.add(cur);
        } else {
          flushCluster(currentCluster);
          currentCluster = [cur];
        }
      }
      flushCluster(currentCluster);

      for (int i = 0; i < staffStops.length; i++) {
        final stop = staffStops[i];
        allStops.add(stop);
        allNodes.add(stop);

        if (i < staffStops.length - 1) {
          final nextStop = staffStops[i + 1];
          final distKm = _safeDistKm(
            stop.latitude,
            stop.longitude,
            nextStop.latitude,
            nextStop.longitude,
          );
          if (distKm >= 0.05) {
            final mins = nextStop.startTime.difference(stop.endTime).inMinutes.clamp(1, 24 * 60);
            final hours = mins / 60.0;
            final speedKmh = hours > 0 ? distKm / hours : 0.0;

            String mode;
            if (stop.staffRole.toLowerCase() == 'driver') {
              mode = 'Driving';
            } else if (distKm < 1.0 && speedKmh <= 6.5) {
              mode = 'Walking';
            } else {
              mode = 'Motorcycling';
            }

            final trip = TimelineTripItem(
              staffKey: group.key,
              staffName: stop.staffName,
              staffRole: stop.staffRole,
              startTime: stop.endTime,
              endTime: nextStop.startTime,
              fromTitle: stop.placeTitle,
              toTitle: nextStop.placeTitle,
              distanceKm: distKm,
              durationMinutes: mins,
              travelMode: mode,
              pathPoints: [
                (lat: stop.latitude, lng: stop.longitude),
                (lat: nextStop.latitude, lng: nextStop.longitude),
              ],
            );
            totalDist += distKm;
            allTrips.add(trip);
            allNodes.add(trip);
          }
        }
      }
    }

    // Build deduplicated Places summary
    final Map<String, TimelinePlaceSummary> placeMap = {};
    for (final stop in allStops) {
      final key = stop.placeTitle.trim().toLowerCase();
      final existing = placeMap[key];
      if (existing == null) {
        placeMap[key] = TimelinePlaceSummary(
          placeTitle: stop.placeTitle,
          placeAddress: stop.placeAddress,
          latitude: stop.latitude,
          longitude: stop.longitude,
          visitCount: 1,
          totalMinutes: stop.durationMinutes,
          totalAmount: stop.totalAmount,
          lastVisited: stop.endTime,
        );
      } else {
        placeMap[key] = TimelinePlaceSummary(
          placeTitle: existing.placeTitle,
          placeAddress: existing.placeAddress.isNotEmpty ? existing.placeAddress : stop.placeAddress,
          latitude: existing.latitude,
          longitude: existing.longitude,
          visitCount: existing.visitCount + 1,
          totalMinutes: existing.totalMinutes + stop.durationMinutes,
          totalAmount: existing.totalAmount + stop.totalAmount,
          lastVisited: stop.endTime.isAfter(existing.lastVisited) ? stop.endTime : existing.lastVisited,
        );
      }
    }

    final places = placeMap.values.toList()
      ..sort((a, b) => b.visitCount.compareTo(a.visitCount));

    return TimelineDaySummary(
      dayNodes: allNodes,
      stops: allStops,
      trips: allTrips,
      places: places,
      totalDistanceKm: totalDist,
      totalCollected: totalCollected,
    );
  }

  static double _safeDistKm(double lat1, double lng1, double lat2, double lng2) {
    if ((lat1 == 0.0 && lng1 == 0.0) || (lat2 == 0.0 && lng2 == 0.0)) return 0.0;
    return LocationTrackingService.haversineDistanceKm(lat1, lng1, lat2, lng2);
  }

  static ({String title, String address}) _resolveClusterLabel(
    LocationTimelineEntry anchor,
    List<LocationTimelineEntry> cluster,
    List<ShopModel> shops,
  ) {
    final hasValidCoords = anchor.latitude != 0.0 && anchor.longitude != 0.0;
    final cachedGeo = hasValidCoords
        ? LocationTrackingService.getCachedPlace(anchor.latitude, anchor.longitude)
        : null;

    // 1. Named Outlet Visit (Collection, Order, Delivery)
    if (anchor.shopName != null && anchor.shopName!.trim().isNotEmpty) {
      final shopName = anchor.shopName!.trim();
      final matchedShop = shops
          .where((s) => s.name.trim().toLowerCase() == shopName.toLowerCase())
          .firstOrNull;
      final shopAddr = [
        if (matchedShop != null && matchedShop.address.trim().isNotEmpty)
          matchedShop.address.trim(),
        if (anchor.routeName != null && anchor.routeName!.trim().isNotEmpty)
          anchor.routeName!.trim(),
      ].join(' • ');

      final fullAddr = (cachedGeo != null && cachedGeo.address.isNotEmpty)
          ? cachedGeo.address
          : (shopAddr.isNotEmpty ? shopAddr : _cleanRawAddress(anchor.landmark, shopName));
      return (title: shopName, address: fullAddr);
    }

    // 2. Cached real geocoded street + area + city
    if (cachedGeo != null && cachedGeo.title.isNotEmpty) {
      return (title: cachedGeo.title, address: cachedGeo.address);
    }

    // 3. Parse existing stored landmark string cleanly (avoid "Near <random store>" if address exists)
    var raw = anchor.landmark.trim();
    raw = raw.replaceAll(';', ',');
    final isStaleNear = raw.toLowerCase().startsWith('near ') && raw.contains('·');
    if (isStaleNear) {
      final parts = raw.split('·');
      final routePart = parts.length > 1 ? parts.last.trim() : '';
      if (hasValidCoords) {
        final reg = LocationTrackingService.getKnownRegion(anchor.latitude, anchor.longitude);
        if (reg != null) {
          return (
            title: routePart.isNotEmpty ? routePart : reg,
            address: '$reg, Maharashtra',
          );
        }
      }
    }

    final isGeneric = raw.isEmpty ||
        raw.startsWith('GPS:') ||
        raw == 'Khed' ||
        raw == 'Khed, खेड' ||
        raw == 'खेड' ||
        raw == 'Active in Beat' ||
        raw == 'Active on sales route' ||
        raw == 'Transit on delivery beat';

    if (!isGeneric) {
      final commaIdx = raw.indexOf(',');
      if (commaIdx > 0 && commaIdx < raw.length - 1) {
        return (
          title: raw.substring(0, commaIdx).trim(),
          address: raw.trim(),
        );
      }
      final fallbackRegion = hasValidCoords
          ? (LocationTrackingService.getKnownRegion(anchor.latitude, anchor.longitude) ?? 'Pune Region')
          : 'Pune Region';
      return (title: raw, address: fallbackRegion);
    }

    if (hasValidCoords) {
      final fallback = LocationTrackingService.findNearestLandmark(
        anchor.latitude,
        anchor.longitude,
        shops,
      );
      final region = LocationTrackingService.getKnownRegion(anchor.latitude, anchor.longitude) ?? '';
      return (
        title: fallback,
        address: region.isNotEmpty && region != fallback ? region : 'Field Beat Route',
      );
    }

    return (title: 'Field Checkpoint', address: anchor.routeName ?? 'Sales Beat');
  }

  static String _cleanRawAddress(String landmark, String skipTitle) {
    final cleaned = landmark
        .replaceAll(';', ',')
        .replaceFirst(RegExp(r'^(At|Near)\s+', caseSensitive: false), '')
        .trim();
    if (cleaned.toLowerCase() == skipTitle.toLowerCase() || cleaned.isEmpty) {
      return '';
    }
    return cleaned;
  }

  static String formatDuration(int minutes) {
    if (minutes <= 0) return '1 min';
    if (minutes < 60) return '$minutes min';
    final hrs = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '$hrs hr';
    return '$hrs hr $mins min';
  }
}
