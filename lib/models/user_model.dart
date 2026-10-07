enum UserRole {
  superAdmin,
  office,
  salesman,
}

class UserModel {
  final String id;
  final String phone;
  final String name;
  final UserRole role;
  final String password;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  UserModel({
    required this.id,
    required this.phone,
    required this.name,
    required this.role,
    required this.password,
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
    }
  }

  bool get isSuperAdmin => role == UserRole.superAdmin;
  bool get isOffice => role == UserRole.office;
  bool get isSalesman => role == UserRole.salesman;

  /// Normalizes phone number into 10 standard digits
  /// Handles formats like: "76209 95547", "+91 99219 77636", "08605131764"
  static String normalizePhone(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
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
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone': normalizePhone(phone),
      'name': name,
      'role': role.name,
      'password': password,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'lastLoginAt': lastLoginAt?.toIso8601String(),
    };
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    UserRole parsedRole = UserRole.salesman;
    final roleStr = json['role'] as String? ?? '';
    if (roleStr == 'superAdmin' || roleStr == 'super_admin') {
      parsedRole = UserRole.superAdmin;
    } else if (roleStr == 'office') {
      parsedRole = UserRole.office;
    } else {
      parsedRole = UserRole.salesman;
    }

    return UserModel(
      id: json['id'] as String? ?? 'user_${DateTime.now().millisecondsSinceEpoch}',
      phone: normalizePhone(json['phone'] as String? ?? ''),
      name: json['name'] as String? ?? 'Staff Member',
      role: parsedRole,
      password: json['password'] as String? ?? 'pass123',
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
    ];
  }
}
