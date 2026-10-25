enum UserRole {
  superAdmin,
  office,
  salesman,
  driver,
}

class UserModel {
  final String id;
  final String phone;
  final String name;
  final UserRole role;
  final String password;
  final List<String> assignedRouteIds;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final double? latitude;
  final double? longitude;
  final DateTime? locationUpdatedAt;
  final String? locationLandmark;

  UserModel({
    required this.id,
    required this.phone,
    required this.name,
    required this.role,
    required this.password,
    this.assignedRouteIds = const [],
    this.isActive = true,
    DateTime? createdAt,
    this.lastLoginAt,
    this.latitude,
    this.longitude,
    this.locationUpdatedAt,
    this.locationLandmark,
  }) : createdAt = createdAt ?? DateTime.now();

  String get roleDisplayName {
    switch (role) {
      case UserRole.superAdmin:
        return 'Super Admin';
      case UserRole.office:
        return 'Office Staff';
      case UserRole.salesman:
        return 'Sales & Collection';
      case UserRole.driver:
        return 'Delivery Driver';
    }
  }

  bool get isSuperAdmin => role == UserRole.superAdmin;
  bool get isOffice => role == UserRole.office;
  bool get isSalesman => role == UserRole.salesman;
  bool get isDriver => role == UserRole.driver;

  bool get hasLocation => latitude != null && longitude != null;

  String get mapsUrl => hasLocation ? 'https://maps.google.com/?q=$latitude,$longitude' : '';

  bool get isOnline {
    if (locationUpdatedAt == null) return false;
    return DateTime.now().difference(locationUpdatedAt!).inMinutes < 15;
  }

  bool get isLocationFresh {
    if (locationUpdatedAt == null) return false;
    return DateTime.now().difference(locationUpdatedAt!).inHours < 4;
  }

  String get locationTimeAgo {
    if (locationUpdatedAt == null) return 'Never';
    final diff = DateTime.now().difference(locationUpdatedAt!);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  /// Returns clean password without embedded metadata
  String get actualPassword {
    var p = password;
    if (p.contains(':::routes=')) {
      p = p.split(':::routes=').first;
    }
    if (p.contains(':::loc=')) {
      p = p.split(':::loc=').first;
    }
    return p;
  }

  /// Normalizes phone number into 10 standard digits, or preserves alphanumeric usernames like 'user1'
  static String normalizePhone(String input) {
    final trimmed = input.trim();
    if (RegExp(r'[a-zA-Z]').hasMatch(trimmed)) {
      return trimmed.toLowerCase();
    }
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  UserModel copyWith({
    String? id,
    String? phone,
    String? name,
    UserRole? role,
    String? password,
    List<String>? assignedRouteIds,
    bool? isActive,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    double? latitude,
    double? longitude,
    DateTime? locationUpdatedAt,
    String? locationLandmark,
  }) {
    return UserModel(
      id: id ?? this.id,
      phone: phone ?? this.phone,
      name: name ?? this.name,
      role: role ?? this.role,
      password: password ?? this.password,
      assignedRouteIds: assignedRouteIds ?? this.assignedRouteIds,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationUpdatedAt: locationUpdatedAt ?? this.locationUpdatedAt,
      locationLandmark: locationLandmark ?? this.locationLandmark,
    );
  }

  Map<String, dynamic> toJson() {
    final cleanPass = actualPassword;
    var storedPassword = cleanPass;
    if (assignedRouteIds.isNotEmpty) {
      storedPassword += ':::routes=${assignedRouteIds.join(',')}';
    }
    if (hasLocation) {
      final timeStr = (locationUpdatedAt ?? DateTime.now()).toIso8601String();
      final cleanLandmark = (locationLandmark ?? '').replaceAll(':::', '').replaceAll(',', ';');
      storedPassword += ':::loc=$latitude,$longitude,$timeStr,$cleanLandmark';
    }

    return {
      'id': id,
      'phone': normalizePhone(phone),
      'name': name,
      'role': role.name,
      'password': storedPassword,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'lastLoginAt': lastLoginAt?.toIso8601String(),
    };
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    UserRole parsedRole = UserRole.salesman;
    final roleStr = (json['role'] as String? ?? '').toLowerCase();
    if (roleStr == 'superadmin' || roleStr == 'super_admin') {
      parsedRole = UserRole.superAdmin;
    } else if (roleStr == 'office') {
      parsedRole = UserRole.office;
    } else if (roleStr == 'driver') {
      parsedRole = UserRole.driver;
    } else {
      parsedRole = UserRole.salesman;
    }

    final rawPassword = json['password'] as String? ?? 'pass123';
    String parsedPassword = rawPassword;
    List<String> assignedRoutes = [];
    if (rawPassword.contains(':::routes=')) {
      final parts = rawPassword.split(':::routes=');
      parsedPassword = parts[0];
      if (parts.length > 1 && parts[1].isNotEmpty) {
        final routePart = parts[1].split(':::loc=').first;
        assignedRoutes = routePart
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    }
    if (json['assignedRouteIds'] is List) {
      assignedRoutes = (json['assignedRouteIds'] as List)
          .map((e) => e.toString())
          .toList();
    }

    double? lat;
    double? lng;
    DateTime? locTime;
    String? landmark;

    if (rawPassword.contains(':::loc=')) {
      try {
        final locPart = rawPassword.split(':::loc=').last;
        final pieces = locPart.split(',');
        if (pieces.length >= 2) {
          lat = double.tryParse(pieces[0].trim());
          lng = double.tryParse(pieces[1].trim());
        }
        if (pieces.length >= 3 && pieces[2].trim().isNotEmpty) {
          locTime = DateTime.tryParse(pieces[2].trim());
        }
        if (pieces.length >= 4 && pieces[3].trim().isNotEmpty) {
          landmark = pieces.sublist(3).join(',').replaceAll(';', ',').trim();
        }
      } catch (_) {}
    }

    if (json['latitude'] != null) {
      lat = double.tryParse(json['latitude'].toString());
    }
    if (json['longitude'] != null) {
      lng = double.tryParse(json['longitude'].toString());
    }
    if (json['locationLandmark'] != null) {
      landmark = json['locationLandmark'].toString();
    }

    return UserModel(
      id: json['id'] as String? ?? 'user_${DateTime.now().millisecondsSinceEpoch}',
      phone: normalizePhone(json['phone'] as String? ?? ''),
      name: json['name'] as String? ?? 'Staff Member',
      role: parsedRole,
      password: parsedPassword,
      assignedRouteIds: assignedRoutes,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      lastLoginAt: json['lastLoginAt'] != null
          ? DateTime.tryParse(json['lastLoginAt'] as String)
          : null,
      latitude: lat,
      longitude: lng,
      locationUpdatedAt: locTime,
      locationLandmark: landmark,
    );
  }

  /// Initial accounts specified by user
  static List<UserModel> getInitialUsers() {
    return [
      UserModel(
        id: 'user_super_admin',
        phone: '9921977636',
        name: 'Super Admin',
        role: UserRole.superAdmin,
        password: 'pass123',
      ),
      UserModel(
        id: 'user_office_1',
        phone: '7620995547',
        name: 'Office Staff 1',
        role: UserRole.office,
        password: 'pass123',
      ),
      UserModel(
        id: 'user_office_2',
        phone: '8605131764',
        name: 'Office Staff 2',
        role: UserRole.office,
        password: 'pass123',
      ),
      UserModel(
        id: 'user_sales_akash',
        phone: '9309862465',
        name: 'Akash',
        role: UserRole.salesman,
        password: 'pass123',
      ),
      UserModel(
        id: 'user_sales_atharva',
        phone: '8390768833',
        name: 'Atharva',
        role: UserRole.salesman,
        password: 'pass123',
      ),
      UserModel(
        id: 'user_driver_user1',
        phone: 'user1',
        name: 'Driver (user1)',
        role: UserRole.driver,
        password: 'pass123',
        assignedRouteIds: const [],
      ),
    ];
  }
}
