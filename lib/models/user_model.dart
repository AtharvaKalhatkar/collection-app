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

  /// Returns clean password without embedded metadata
  String get actualPassword {
    if (password.contains(':::routes=')) {
      return password.split(':::routes=').first;
    }
    return password;
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
    );
  }

  Map<String, dynamic> toJson() {
    final cleanPass = actualPassword;
    final storedPassword = assignedRouteIds.isNotEmpty
        ? '$cleanPass:::routes=${assignedRouteIds.join(',')}'
        : cleanPass;

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
        assignedRoutes = parts[1]
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
