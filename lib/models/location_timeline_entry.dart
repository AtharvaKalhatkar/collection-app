import 'package:intl/intl.dart';

class LocationTimelineEntry {
  final String id;
  final String userId;
  final String staffName;
  final String staffRole; // 'salesman', 'driver', 'office', 'superAdmin'
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final String landmark;
  final String eventType; // 'gpsPing', 'collection', 'deliveryVisit', 'login'
  final String details;
  final double? amount;
  final String? shopName;
  final String? routeName;
  final String? billNumber;

  LocationTimelineEntry({
    required this.id,
    required this.userId,
    required this.staffName,
    required this.staffRole,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.landmark,
    this.eventType = 'gpsPing',
    this.details = '',
    this.amount,
    this.shopName,
    this.routeName,
    this.billNumber,
  });

  bool get isDriver => staffRole.toLowerCase() == 'driver';
  bool get isSalesman => staffRole.toLowerCase() == 'salesman';
  bool get isCollection => eventType == 'collection';
  bool get isDelivery => eventType == 'deliveryVisit';
  bool get isLogin => eventType == 'login';
  bool get isGpsPing => eventType == 'gpsPing';

  String get mapsUrl => 'https://maps.google.com/?q=$latitude,$longitude';

  String get timeFormatted => DateFormat('hh:mm a').format(timestamp);
  String get dateFormatted => DateFormat('dd MMM yyyy').format(timestamp);

  bool get isToday {
    final now = DateTime.now();
    return timestamp.year == now.year &&
        timestamp.month == now.month &&
        timestamp.day == now.day;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'staffName': staffName,
      'staffRole': staffRole,
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'landmark': landmark,
      'eventType': eventType,
      'details': details,
      'amount': amount,
      'shopName': shopName,
      'routeName': routeName,
      'billNumber': billNumber,
    };
  }

  factory LocationTimelineEntry.fromJson(Map<String, dynamic> json) {
    return LocationTimelineEntry(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      staffName: json['staffName'] as String? ?? 'Staff',
      staffRole: json['staffRole'] as String? ?? 'salesman',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      landmark: json['landmark'] as String? ?? '',
      eventType: json['eventType'] as String? ?? 'gpsPing',
      details: json['details'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble(),
      shopName: json['shopName'] as String?,
      routeName: json['routeName'] as String?,
      billNumber: json['billNumber'] as String?,
    );
  }

  /// Serializes into an `app_users` compatible row for cloud persistence in Supabase
  Map<String, dynamic> toSupabaseUserRow() {
    // Escape any double colons to prevent parsing breakage
    String esc(String? s) => (s ?? '').replaceAll(':::', '--');

    final encodedPayload = [
      'tl',
      esc(eventType),
      latitude.toStringAsFixed(6),
      longitude.toStringAsFixed(6),
      timestamp.toIso8601String(),
      esc(landmark),
      esc(details),
      amount?.toStringAsFixed(2) ?? '',
      esc(shopName),
      esc(routeName),
      esc(billNumber),
    ].join(':::');

    return {
      'id': id,
      'phone': 'tl_${userId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '')}',
      'name': staffName,
      'role': staffRole,
      'password': encodedPayload,
      'isActive': true,
      'createdAt': timestamp.toIso8601String(),
    };
  }

  /// Deserializes an `app_users` row into a LocationTimelineEntry
  static LocationTimelineEntry? fromSupabaseUserRow(Map<String, dynamic> row) {
    try {
      final id = row['id'] as String? ?? '';
      if (!id.startsWith('tl_') && !id.startsWith('timeline_')) return null;

      final staffName = row['name'] as String? ?? 'Staff';
      final staffRole = row['role'] as String? ?? 'salesman';
      final rawPassword = row['password'] as String? ?? '';

      final parts = rawPassword.split(':::');
      if (parts.length < 5 || parts[0] != 'tl') return null;

      final eventType = parts.length > 1 ? parts[1] : 'gpsPing';
      final lat = parts.length > 2 ? double.tryParse(parts[2]) ?? 0.0 : 0.0;
      final lng = parts.length > 3 ? double.tryParse(parts[3]) ?? 0.0 : 0.0;
      final ts = parts.length > 4 && parts[4].isNotEmpty
          ? (DateTime.tryParse(parts[4]) ?? DateTime.now())
          : (row['createdAt'] != null
              ? DateTime.tryParse(row['createdAt'] as String) ?? DateTime.now()
              : DateTime.now());
      final landmark = parts.length > 5 ? parts[5] : '';
      final details = parts.length > 6 ? parts[6] : '';
      final amount = parts.length > 7 && parts[7].isNotEmpty
          ? double.tryParse(parts[7])
          : null;
      final shopName = parts.length > 8 && parts[8].isNotEmpty ? parts[8] : null;
      final routeName = parts.length > 9 && parts[9].isNotEmpty ? parts[9] : null;
      final billNumber = parts.length > 10 && parts[10].isNotEmpty ? parts[10] : null;

      final userId = id.replaceFirst('tl_', '').split('_').first;

      return LocationTimelineEntry(
        id: id,
        userId: userId.isNotEmpty ? userId : staffName,
        staffName: staffName,
        staffRole: staffRole,
        timestamp: ts,
        latitude: lat,
        longitude: lng,
        landmark: landmark,
        eventType: eventType,
        details: details,
        amount: amount,
        shopName: shopName,
        routeName: routeName,
        billNumber: billNumber,
      );
    } catch (_) {
      return null;
    }
  }
}
