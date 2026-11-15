import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_model.dart';

/// Strictly 3 attendance statuses as requested: Present, Half Day, Absent
enum AttendanceStatus {
  present,
  halfDay,
  absent,
}

extension AttendanceStatusExtension on AttendanceStatus {
  String get label {
    switch (this) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.halfDay:
        return 'Half Day';
      case AttendanceStatus.absent:
        return 'Absent';
    }
  }

  String get shortCode {
    switch (this) {
      case AttendanceStatus.present:
        return 'P';
      case AttendanceStatus.halfDay:
        return '½';
      case AttendanceStatus.absent:
        return 'A';
    }
  }

  double get payableValue {
    switch (this) {
      case AttendanceStatus.present:
        return 1.0;
      case AttendanceStatus.halfDay:
        return 0.5;
      case AttendanceStatus.absent:
        return 0.0;
    }
  }
}

class AttendanceRecord {
  final String id;
  final String userId;
  final String staffName;
  final String staffRole;
  final DateTime date;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final AttendanceStatus status;
  final String? note;

  AttendanceRecord({
    required this.id,
    required this.userId,
    required this.staffName,
    required this.staffRole,
    required this.date,
    this.checkInTime,
    this.checkOutTime,
    this.status = AttendanceStatus.present,
    this.note,
  });

  String get dateKey =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Duration? get workDuration {
    if (checkInTime == null || checkOutTime == null) return null;
    return checkOutTime!.difference(checkInTime!);
  }

  String get workDurationFormatted {
    final d = workDuration;
    if (d == null) return '--';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '${h}h ${m}m';
  }

  String get statusLabel => status.label;

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'staffName': staffName,
        'staffRole': staffRole,
        'date': date.toIso8601String(),
        'checkInTime': checkInTime?.toIso8601String(),
        'checkOutTime': checkOutTime?.toIso8601String(),
        'status': status.name,
        'note': note,
      };

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    AttendanceStatus parsedStatus = AttendanceStatus.present;
    final s = json['status'] as String? ?? 'present';
    switch (s) {
      case 'absent':
        parsedStatus = AttendanceStatus.absent;
        break;
      case 'halfDay':
        parsedStatus = AttendanceStatus.halfDay;
        break;
      case 'present':
      default:
        parsedStatus = AttendanceStatus.present;
    }
    return AttendanceRecord(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      staffName: json['staffName'] as String? ?? '',
      staffRole: json['staffRole'] as String? ?? '',
      date: DateTime.parse(json['date'] as String),
      checkInTime: json['checkInTime'] != null
          ? DateTime.tryParse(json['checkInTime'] as String)
          : null,
      checkOutTime: json['checkOutTime'] != null
          ? DateTime.tryParse(json['checkOutTime'] as String)
          : null,
      status: parsedStatus,
      note: json['note'] as String?,
    );
  }

  AttendanceRecord copyWith({
    DateTime? checkInTime,
    DateTime? checkOutTime,
    AttendanceStatus? status,
    String? note,
    bool clearCheckOut = false,
  }) {
    return AttendanceRecord(
      id: id,
      userId: userId,
      staffName: staffName,
      staffRole: staffRole,
      date: date,
      checkInTime: checkInTime ?? this.checkInTime,
      checkOutTime: clearCheckOut ? null : (checkOutTime ?? this.checkOutTime),
      status: status ?? this.status,
      note: note ?? this.note,
    );
  }
}

class AttendanceEmployee {
  final String id;
  final String name;
  final String role;
  final String phone;
  final double monthlySalary; // e.g. 20000.0
  final bool isActive;
  final bool isCustom;
  final DateTime? joinedAt;

  static const List<String> allowedRoles = [
    'Sales & Collection',
    'Driver',
    'Helper',
    'Office Staff',
  ];

  AttendanceEmployee({
    required this.id,
    required this.name,
    required this.role,
    this.phone = '',
    this.monthlySalary = 18000.0,
    this.isActive = true,
    this.isCustom = true,
    this.joinedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role,
        'phone': phone,
        'monthlySalary': monthlySalary,
        'isActive': isActive,
        'isCustom': isCustom,
        'joinedAt': joinedAt?.toIso8601String(),
      };

  factory AttendanceEmployee.fromJson(Map<String, dynamic> json) =>
      AttendanceEmployee(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        role: json['role'] as String? ?? 'Sales & Collection',
        phone: json['phone'] as String? ?? '',
        monthlySalary:
            (json['monthlySalary'] as num?)?.toDouble() ?? 18000.0,
        isActive: json['isActive'] as bool? ?? true,
        isCustom: json['isCustom'] as bool? ?? true,
        joinedAt: json['joinedAt'] != null
            ? DateTime.tryParse(json['joinedAt'] as String)
            : null,
      );

  AttendanceEmployee copyWith({
    String? name,
    String? role,
    String? phone,
    double? monthlySalary,
    bool? isActive,
    bool? isCustom,
    DateTime? joinedAt,
  }) =>
      AttendanceEmployee(
        id: id,
        name: name ?? this.name,
        role: role ?? this.role,
        phone: phone ?? this.phone,
        monthlySalary: monthlySalary ?? this.monthlySalary,
        isActive: isActive ?? this.isActive,
        isCustom: isCustom ?? this.isCustom,
        joinedAt: joinedAt ?? this.joinedAt,
      );
}

class SalaryMonthlyAdjustment {
  final String employeeId;
  final int year;
  final int month;
  final double bonus;
  final double advanceDeduction;
  final bool isDisbursed;
  final DateTime? disbursedAt;
  final String? paymentMode;
  final String? note;

  SalaryMonthlyAdjustment({
    required this.employeeId,
    required this.year,
    required this.month,
    this.bonus = 0.0,
    this.advanceDeduction = 0.0,
    this.isDisbursed = false,
    this.disbursedAt,
    this.paymentMode,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'year': year,
        'month': month,
        'bonus': bonus,
        'advanceDeduction': advanceDeduction,
        'isDisbursed': isDisbursed,
        'disbursedAt': disbursedAt?.toIso8601String(),
        'paymentMode': paymentMode,
        'note': note,
      };

  factory SalaryMonthlyAdjustment.fromJson(Map<String, dynamic> json) =>
      SalaryMonthlyAdjustment(
        employeeId: json['employeeId'] as String? ?? '',
        year: json['year'] as int? ?? DateTime.now().year,
        month: json['month'] as int? ?? DateTime.now().month,
        bonus: (json['bonus'] as num?)?.toDouble() ?? 0.0,
        advanceDeduction:
            (json['advanceDeduction'] as num?)?.toDouble() ?? 0.0,
        isDisbursed: json['isDisbursed'] as bool? ?? false,
        disbursedAt: json['disbursedAt'] != null
            ? DateTime.tryParse(json['disbursedAt'] as String)
            : null,
        paymentMode: json['paymentMode'] as String?,
        note: json['note'] as String?,
      );
}

class MonthlySalaryCalculation {
  final AttendanceEmployee employee;
  final int year;
  final int month;
  final int totalDaysInMonth;
  final int presentCount;
  final int halfDayCount;
  final int absentCount;
  final double payableDays;
  final double dailyRate;
  final double baseMonthlySalary;
  final double earnedSalary;
  final double bonus;
  final double advanceDeduction;
  final double netSalary;
  final bool isDisbursed;
  final DateTime? disbursedAt;
  final String? paymentMode;
  final List<DateTime> absentDates;

  MonthlySalaryCalculation({
    required this.employee,
    required this.year,
    required this.month,
    required this.totalDaysInMonth,
    required this.presentCount,
    required this.halfDayCount,
    required this.absentCount,
    required this.payableDays,
    required this.dailyRate,
    required this.baseMonthlySalary,
    required this.earnedSalary,
    required this.bonus,
    required this.advanceDeduction,
    required this.netSalary,
    required this.isDisbursed,
    this.disbursedAt,
    this.paymentMode,
    this.absentDates = const [],
  });

  static MonthlySalaryCalculation compute({
    required AttendanceEmployee employee,
    required int year,
    required int month,
    required List<AttendanceRecord> monthRecords,
    SalaryMonthlyAdjustment? adjustment,
  }) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final userRecords =
        monthRecords.where((r) => r.userId == employee.id).toList();

    int present = 0;
    int halfDay = 0;
    int absent = 0;
    final List<DateTime> absentList = [];

    for (final r in userRecords) {
      switch (r.status) {
        case AttendanceStatus.present:
          present++;
          break;
        case AttendanceStatus.halfDay:
          halfDay++;
          break;
        case AttendanceStatus.absent:
          absent++;
          absentList.add(r.date);
          break;
      }
    }

    absentList.sort((a, b) => a.compareTo(b));

    // Payable formula: Present + (HalfDay * 0.5)
    final double payable = present + (halfDay * 0.5);
    final double base = employee.monthlySalary;
    final double daily = daysInMonth > 0 ? (base / daysInMonth) : 0.0;
    final double earned = (payable * daily);
    final double bonus = adjustment?.bonus ?? 0.0;
    final double adv = adjustment?.advanceDeduction ?? 0.0;
    final double net =
        (earned + bonus - adv).clamp(0.0, double.infinity);

    return MonthlySalaryCalculation(
      employee: employee,
      year: year,
      month: month,
      totalDaysInMonth: daysInMonth,
      presentCount: present,
      halfDayCount: halfDay,
      absentCount: absent,
      payableDays: payable,
      dailyRate: daily,
      baseMonthlySalary: base,
      earnedSalary: earned,
      bonus: bonus,
      advanceDeduction: adv,
      netSalary: net,
      isDisbursed: adjustment?.isDisbursed ?? false,
      disbursedAt: adjustment?.disbursedAt,
      paymentMode: adjustment?.paymentMode,
      absentDates: absentList,
    );
  }

  String formatWhatsAppSlip() {
    final monthName = _monthNames[month - 1];
    final absentStr = absentDates.isNotEmpty
        ? absentDates.map((d) => '${d.day} $monthName').join(', ')
        : 'None';

    return '''📄 *ATTENDANCE & SALARY SLIP - $monthName $year*
👤 *Employee:* ${employee.name} (${employee.role})
🏢 *Purva Enterprises & Manas Sales*
----------------------------------------
🗓️ Total Month Days: $totalDaysInMonth Days
✅ Present Days: $presentCount
🌗 Half Days: $halfDayCount (${(halfDayCount * 0.5).toStringAsFixed(1)} days)
❌ Absent Days: $absentCount
📌 Absent Dates: $absentStr
⭐ *Payable Days:* ${payableDays.toStringAsFixed(1)} / $totalDaysInMonth Days
----------------------------------------
💰 Base Monthly Salary: ₹${baseMonthlySalary.toStringAsFixed(0)}
💵 Per Day Rate: ₹${dailyRate.toStringAsFixed(2)}
➕ Earned Salary: ₹${earnedSalary.toStringAsFixed(0)}
${bonus > 0 ? '🎁 Bonus / Incentive: ₹${bonus.toStringAsFixed(0)}\n' : ''}${advanceDeduction > 0 ? '➖ Advance Deducted: ₹${advanceDeduction.toStringAsFixed(0)}\n' : ''}----------------------------------------
🎯 *NET SALARY PAYABLE: ₹${netSalary.toStringAsFixed(0)}*
${isDisbursed ? '✅ Status: Disbursed (${paymentMode ?? 'Cash'})' : '⏳ Status: Pending'}
----------------------------------------
_Daily Collection App_''';
  }

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];
}

class AttendanceService {
  static const String _keyPrefix = 'attendance_v2_';
  static const String _empKey = 'attendance_employees_v2';
  static const String _deletedEmpKey = 'attendance_deleted_emp_ids_v2';
  static const String _initFlagKey = 'attendance_roster_initialized_v2';
  static const String _adjPrefix = 'attendance_adj_v2_';

  static String _monthKey(int year, int month) =>
      '$_keyPrefix${year}_${month.toString().padLeft(2, '0')}';

  static String _adjKey(int year, int month) =>
      '$_adjPrefix${year}_${month.toString().padLeft(2, '0')}';

  // ── Employees Roster ──────────────────────────────────────────────────────
  /// User requested: "remove all the employee from that list i will add by my self"
  /// Do not auto-populate from auth users!
  static Future<List<AttendanceEmployee>> loadEmployees({
    List<UserModel>? fallbackUsers,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Check if initialized with fresh user-managed list
    final bool isInitialized = prefs.getBool(_initFlagKey) ?? false;
    if (!isInitialized) {
      // First time on v2: start clean with an empty roster so user can add staff manually
      await prefs.setBool(_initFlagKey, true);
      await prefs.setStringList(_empKey, []);
      return [];
    }

    final raw = prefs.getStringList(_empKey) ?? [];
    final deletedIds = prefs.getStringList(_deletedEmpKey) ?? [];
    final employees = <AttendanceEmployee>[];

    for (final item in raw) {
      try {
        final emp = AttendanceEmployee.fromJson(
            jsonDecode(item) as Map<String, dynamic>);
        if (!deletedIds.contains(emp.id)) {
          employees.add(emp);
        }
      } catch (_) {}
    }

    return employees;
  }

  static Future<void> saveEmployees(List<AttendanceEmployee> list) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = list.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_empKey, raw);
  }

  static Future<void> saveEmployee(AttendanceEmployee emp) async {
    final list = await loadEmployees();
    final idx = list.indexWhere((e) => e.id == emp.id);
    if (idx >= 0) {
      list[idx] = emp;
    } else {
      list.add(emp);
    }
    // Remove from deleted list if re-added
    final prefs = await SharedPreferences.getInstance();
    final deletedIds = prefs.getStringList(_deletedEmpKey) ?? [];
    if (deletedIds.contains(emp.id)) {
      deletedIds.remove(emp.id);
      await prefs.setStringList(_deletedEmpKey, deletedIds);
    }
    await saveEmployees(list);
  }

  static Future<void> deleteEmployee(String empId) async {
    final list = await loadEmployees();
    list.removeWhere((e) => e.id == empId);
    await saveEmployees(list);

    // Record in deleted IDs so it never re-appears
    final prefs = await SharedPreferences.getInstance();
    final deletedIds = prefs.getStringList(_deletedEmpKey) ?? [];
    if (!deletedIds.contains(empId)) {
      deletedIds.add(empId);
      await prefs.setStringList(_deletedEmpKey, deletedIds);
    }
  }

  // ── Monthly Records ───────────────────────────────────────────────────────
  static Future<List<AttendanceRecord>> loadForMonth(int year, int month) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_monthKey(year, month)) ?? [];
    final records = <AttendanceRecord>[];
    for (final item in raw) {
      try {
        records.add(
            AttendanceRecord.fromJson(jsonDecode(item) as Map<String, dynamic>));
      } catch (_) {}
    }
    return records;
  }

  static Future<void> saveRecord(AttendanceRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _monthKey(record.date.year, record.date.month);
    final raw = prefs.getStringList(key) ?? [];
    final records = <AttendanceRecord>[];
    for (final item in raw) {
      try {
        records.add(
            AttendanceRecord.fromJson(jsonDecode(item) as Map<String, dynamic>));
      } catch (_) {}
    }

    records.removeWhere(
        (r) => r.userId == record.userId && r.dateKey == record.dateKey);
    records.add(record);

    final newRaw = records.map((r) => jsonEncode(r.toJson())).toList();
    await prefs.setStringList(key, newRaw);
  }

  static Future<AttendanceRecord?> loadForUserAndDate(
      String userId, DateTime date) async {
    final records = await loadForMonth(date.year, date.month);
    final dateKey =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    try {
      return records.firstWhere((r) => r.userId == userId && r.dateKey == dateKey);
    } catch (_) {
      return null;
    }
  }

  static Future<AttendanceRecord> checkIn(
      String userId, String staffName, String staffRole, {DateTime? customTime}) async {
    final now = customTime ?? DateTime.now();
    final dateOnly = DateTime(now.year, now.month, now.day);
    final existing = await loadForUserAndDate(userId, dateOnly);

    if (existing != null && existing.checkInTime != null) {
      return existing;
    }

    final record = existing?.copyWith(
          checkInTime: now,
          status: AttendanceStatus.present,
        ) ??
        AttendanceRecord(
          id: '${userId}_${dateOnly.year}${dateOnly.month.toString().padLeft(2, '0')}${dateOnly.day.toString().padLeft(2, '0')}',
          userId: userId,
          staffName: staffName,
          staffRole: staffRole,
          date: dateOnly,
          checkInTime: now,
          status: AttendanceStatus.present,
        );

    await saveRecord(record);
    return record;
  }

  static Future<AttendanceRecord?> checkOut(String userId, {DateTime? customTime}) async {
    final now = customTime ?? DateTime.now();
    final dateOnly = DateTime(now.year, now.month, now.day);
    final existing = await loadForUserAndDate(userId, dateOnly);
    if (existing == null) return null;

    final updated = existing.copyWith(checkOutTime: now);
    await saveRecord(updated);
    return updated;
  }

  static Future<void> markStatus({
    required String userId,
    required String staffName,
    required String staffRole,
    required DateTime date,
    required AttendanceStatus status,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    String? note,
  }) async {
    final existing = await loadForUserAndDate(userId, date);
    final dateOnly = DateTime(date.year, date.month, date.day);
    final record = existing?.copyWith(
          status: status,
          checkInTime: checkInTime ?? existing.checkInTime,
          checkOutTime: checkOutTime ?? existing.checkOutTime,
          note: note,
        ) ??
        AttendanceRecord(
          id: '${userId}_${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}',
          userId: userId,
          staffName: staffName,
          staffRole: staffRole,
          date: dateOnly,
          checkInTime: checkInTime,
          checkOutTime: checkOutTime,
          status: status,
          note: note,
        );
    await saveRecord(record);
  }

  // ── Monthly Salary Adjustments (Bonuses, Advances, Disbursed status) ───────
  static Future<List<SalaryMonthlyAdjustment>> loadAdjustments(
      int year, int month) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_adjKey(year, month)) ?? [];
    final list = <SalaryMonthlyAdjustment>[];
    for (final item in raw) {
      try {
        list.add(
            SalaryMonthlyAdjustment.fromJson(jsonDecode(item) as Map<String, dynamic>));
      } catch (_) {}
    }
    return list;
  }

  static Future<void> saveAdjustment(SalaryMonthlyAdjustment adj) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _adjKey(adj.year, adj.month);
    final list = await loadAdjustments(adj.year, adj.month);
    list.removeWhere((a) => a.employeeId == adj.employeeId);
    list.add(adj);
    final raw = list.map((a) => jsonEncode(a.toJson())).toList();
    await prefs.setStringList(key, raw);
  }
}
