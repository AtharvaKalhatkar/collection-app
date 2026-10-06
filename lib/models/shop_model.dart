class ShopModel {
  final String id;
  final String name;
  final String routeId;
  final String routeName;
  final String mobileNumber;
  final String address;
  final String? ownerName;
  final String? locationUrl;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;

  ShopModel({
    required this.id,
    required this.name,
    required this.routeId,
    required this.routeName,
    required this.mobileNumber,
    required this.address,
    this.ownerName,
    this.locationUrl,
    this.latitude,
    this.longitude,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Returns a valid Google Maps URL if either locationUrl or lat/lng coordinates exist
  String? get mapsUrl {
    if (locationUrl != null && locationUrl!.trim().isNotEmpty) {
      final trimmed = locationUrl!.trim();
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        return trimmed;
      }
      return 'https://maps.google.com/?q=${Uri.encodeComponent(trimmed)}';
    }
    if (latitude != null && longitude != null) {
      return 'https://maps.google.com/?q=$latitude,$longitude';
    }
    return null;
  }

  bool get hasLocation => mapsUrl != null && mapsUrl!.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'routeId': routeId,
      'routeName': routeName,
      'mobileNumber': mobileNumber,
      'address': address,
      'ownerName': ownerName,
      'locationUrl': locationUrl,
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ShopModel.fromJson(Map<String, dynamic> json) {
    return ShopModel(
      id: json['id'] as String,
      name: json['name'] as String,
      routeId: json['routeId'] as String,
      routeName: json['routeName'] as String? ?? 'General Route',
      mobileNumber: json['mobileNumber'] as String? ?? '',
      address: json['address'] as String? ?? '',
      ownerName: json['ownerName'] as String?,
      locationUrl: json['locationUrl'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  ShopModel copyWith({
    String? id,
    String? name,
    String? routeId,
    String? routeName,
    String? mobileNumber,
    String? address,
    String? ownerName,
    String? locationUrl,
    double? latitude,
    double? longitude,
    DateTime? createdAt,
    bool clearLocation = false,
  }) {
    return ShopModel(
      id: id ?? this.id,
      name: name ?? this.name,
      routeId: routeId ?? this.routeId,
      routeName: routeName ?? this.routeName,
      mobileNumber: mobileNumber ?? this.mobileNumber,
      address: address ?? this.address,
      ownerName: ownerName ?? this.ownerName,
      locationUrl: clearLocation ? null : (locationUrl ?? this.locationUrl),
      latitude: clearLocation ? null : (latitude ?? this.latitude),
      longitude: clearLocation ? null : (longitude ?? this.longitude),
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
