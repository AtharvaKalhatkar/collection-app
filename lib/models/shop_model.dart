class ShopModel {
  final String id;
  final String name;
  final String routeId;
  final String routeName;
  final String mobileNumber;
  final String address;
  final String? ownerName;
  final DateTime createdAt;

  ShopModel({
    required this.id,
    required this.name,
    required this.routeId,
    required this.routeName,
    required this.mobileNumber,
    required this.address,
    this.ownerName,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'routeId': routeId,
      'routeName': routeName,
      'mobileNumber': mobileNumber,
      'address': address,
      'ownerName': ownerName,
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
    DateTime? createdAt,
  }) {
    return ShopModel(
      id: id ?? this.id,
      name: name ?? this.name,
      routeId: routeId ?? this.routeId,
      routeName: routeName ?? this.routeName,
      mobileNumber: mobileNumber ?? this.mobileNumber,
      address: address ?? this.address,
      ownerName: ownerName ?? this.ownerName,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
