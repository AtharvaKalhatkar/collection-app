import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_model.dart';

enum AttendanceStatus {
  present,
  absent,
  halfDay,
  holiday,
  leave,
}

extension AttendanceStatusExtension on AttendanceStatus {
  String get label {
    switch (this) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.halfDay:
        return 'Half Day';
      case AttendanceStatus.holiday:
        return 'Holiday / Weekly Off';
      case AttendanceStatus.leave:
        return 'Paid Leave';
    }
  }

  String get shortCode {
    switch (this) {
      case AttendanceStatus.present:
        return 'P';
      case AttendanceStatus.absent:
        return 'A';
      case AttendanceStatus.halfDay:
        return '½';
      case AttendanceStatus.holiday:
        return 'H';
      case AttendanceStatus.leave:
        return 'L';
    }
  }

  double get payableValue {
    switch (this) {
      case AttendanceStatus.present:
        return 1.0;
      case AttendanceStatus.absent:
        return 0.0;
      case AttendanceStatus.halfDay:
        return 0.5;
      case AttendanceStatus.holiday:
        return 1.0;
      case AttendanceStatus.leave:
        return 1.0;
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
      case 'holiday':
        parsedStatus = AttendanceStatus.holiday;
        break;
      case 'leave':
        parsedStatus = AttendanceStatus.leave;
        break;
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
          ? DateTime.parse(json['checkInTime'] as String)
          : null,
      checkOutTime: json['checkOutTime'] != null
          ? DateTime.parse(json['checkOutTime'] as String)
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

  AttendanceEmployee({
    required this.id,
    required this.name,
    required this.role,
    this.phone = '',
    this.monthlySalary = 15000.0,
    this.isActive = true,
    this.isCustom = false,
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
        role: json['role'] as String? ?? 'Salesman',
        phone: json['phone'] as String? ?? '',
        monthlySalary:
            (json['monthlySalary'] as num?)?.toDouble() ?? 15000.0,
        isActive: json['isActive'] as bool? ?? true,
        isCustom: json['isCustom'] as bool? ?? false,
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
  final int holidayCount;
  final int leaveCount;
  final int absentCount;
  final double payableDays;
  final double dailyRate;
  final double baseMonthlySalary;
  final double earnedSalary;
  final double absentDeduction;
  final double bonus;
  final double advanceDeduction;
  final double netSalary;
  final bool isDisbursed;
  final DateTime? disbursedAt;
  final String? paymentMode;

  MonthlySalaryCalculation({
    required this.employee,
    required this.year,
    required this.month,
    required this.totalDaysInMonth,
    required this.presentCount,
    required this.halfDayCount,
    required this.holidayCount,
    required this.leaveCount,
    required this.absentCount,
    required this.payableDays,
    required this.dailyRate,
    required this.baseMonthlySalary,
    required this.earnedSalary,
    required this.absentDeduction,
    required this.bonus,
    required this.advanceDeduction,
    required this.netSalary,
    required this.isDisbursed,
    this.disbursedAt,
    this.paymentMode,
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
    int holiday = 0;
    int leave = 0;
    int absent = 0;

    for (final r in userRecords) {
      switch (r.status) {
        case AttendanceStatus.present:
          present++;
          break;
        case AttendanceStatus.halfDay:
          halfDay++;
          break;
        case AttendanceStatus.holiday:
          holiday++;
          break;
        case AttendanceStatus.leave:
          leave++;
          break;
        case AttendanceStatus.absent:
          absent++;
          break;
      }
    }

    final double payable = present + (halfDay * 0.5) + holiday + leave;
    final double base = employee.monthlySalary;
    final double daily = daysInMonth > 0 ? (base / daysInMonth) : 0.0;
    final double earned = (payable * daily);
    final double absentDed = (absent * daily);
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
      holidayCount: holiday,
      leaveCount: leave,
      absentCount: absent,
      payableDays: payable,
      dailyRate: daily,
      baseMonthlySalary: base,
      earnedSalary: earned,
      absentDeduction: absentDed,
      bonus: bonus,
      advanceDeduction: adv,
      netSalary: net,
      isDisbursed: adjustment?.isDisbursed ?? false,
      disbursedAt: adjustment?.disbursedAt,
      paymentMode: adjustment?.paymentMode,
    );
  }

  String formatWhatsAppSlip() {
    final monthName = _monthNames[month - 1];
    return '''📄 *MONTHLY SALARY SLIP - $monthName $year*
👤 *Employee:* ${employee.name} (${employee.role})
🏢 *Purva & Manas Collection*
----------------------------------------
🗓️ Total Month Days: $totalDaysInMonth Days
✅ Present Days: $presentCount
🌗 Half Days: $halfDayCount (${(halfDayCount * 0.5).toStringAsFixed(1)} days)
🎉 Holidays / Weekly Offs: $holidayCount
🌴 Paid Leaves: $leaveCount
❌ Absent Days: $absentCount
⭐ *Payable Days:* ${payableDays.toStringAsFixed(1)} / $totalDaysInMonth Days
----------------------------------------
💰 Base Monthly Salary: ₹${baseMonthlySalary.toStringAsFixed(0)}
💵 Per Day Rate: ₹${dailyRate.toStringAsFixed(2)}
➕ Earned Amount: ₹${earnedSalary.toStringAsFixed(0)}
${bonus > 0 ? '🎁 Bonus / Incentive: ₹${bonus.toStringAsFixed(0)}\n' : ''}${advanceDeduction > 0 ? '➖ Advance Deducted: ₹${advanceDeduction.toStringAsFixed(0)}\n' : ''}----------------------------------------
🎯 *NET PAYABLE SALARY: ₹${netSalary.toStringAsFixed(0)}*
${isDisbursed ? '✅ Status: Disbursed (${paymentMode ?? 'Cash'})' : '⏳ Status: Pending Payment'}
----------------------------------------
_Generated automatically from Daily Collection App_''';
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
  static const String _keyPrefix = 'attendance_v1_';
  static const String _empKey = 'attendance_employees_v1';
  static const String _adjPrefix = 'attendance_adj_v1_';

  static String _monthKey(int year, int month) =>
      '$_keyPrefix${year}_${month.toString().padLeft(2, '0')}';

  static String _adjKey(int year, int month) =>
      '$_adjPrefix${year}_${month.toString().padLeft(2, '0')}';

  // ── Employees Roster ──────────────────────────────────────────────────────
  static Future<List<AttendanceEmployee>> loadEmployees({
    List<UserModel>? fallbackUsers,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_empKey) ?? [];
    final employees = <AttendanceEmployee>[];

    for (final item in raw) {
      try {
        employees.add(
            AttendanceEmployee.fromJson(jsonDecode(item) as Map<String, dynamic>));
      } catch (_) {}
    }

    // If roster is empty or missing known users, populate/merge from auth users
    if (fallbackUsers != null && fallbackUsers.isNotEmpty) {
      bool changed = false;
      for (final u in fallbackUsers) {
        final exists = employees.any((e) => e.id == u.id || e.name.toLowerCase() == u.name.toLowerCase());
        if (!exists) {
          double defaultSalary = 18000.0;
          if (u.name.toLowerCase().contains('akash')) {
            defaultSalary = 20000.0;
          } else if (u.isSuperAdmin) {
            defaultSalary = 30000.0;
          } else if (u.isOffice) {
            defaultSalary = 22000.0;
          } else if (u.isDriver) {
            defaultSalary = 16000.0;
          }

          employees.add(AttendanceEmployee(
            id: u.id,
            name: u.name,
            role: u.roleDisplayName,
            phone: u.phone,
            monthlySalary: defaultSalary,
            isActive: true,
            isCustom: false,
            joinedAt: u.createdAt,
          ));
          changed = true;
        }
      }
      if (changed) {
        await saveEmployees(employees);
      }
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
    await saveEmployees(list);
  }

  static Future<void> deleteEmployee(String empId) async {
    final list = await loadEmployees();
    list.removeWhere((e) => e.id == empId);
    await saveEmployees(list);
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
      String userId, String staffName, String staffRole) async {
    final now = DateTime.now();
    final existing = await loadForUserAndDate(userId, now);

    if (existing != null && existing.checkInTime != null) {
      return existing;
    }

    final record = existing?.copyWith(
          checkInTime: now,
          status: AttendanceStatus.present,
        ) ??
        AttendanceRecord(
          id: '${userId}_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}',
          userId: userId,
          staffName: staffName,
          staffRole: staffRole,
          date: DateTime(now.year, now.month, now.day),
          checkInTime: now,
          status: AttendanceStatus.present,
        );

    await saveRecord(record);
    return record;
  }

  static Future<AttendanceRecord?> checkOut(String userId) async {
    final now = DateTime.now();
    final existing = await loadForUserAndDate(userId, now);
    if (existing == null || existing.checkInTime == null) return null;
    if (existing.checkOutTime != null) return existing;

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
    String? note,
  }) async {
    final existing = await loadForUserAndDate(userId, date);
    final dateOnly = DateTime(date.year, date.month, date.day);
    final record = existing?.copyWith(status: status, note: note) ??
        AttendanceRecord(
          id: '${userId}_${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}',
          userId: userId,
          staffName: staffName,
          staffRole: staffRole,
          date: dateOnly,
          status: status,
          note: note,
        );
    await saveRecord(record);
  }

  // ── Auto-mark Sundays as Paid Holidays ────────────────────────────────────
  static Future<int> autoMarkSundaysAsHolidays(
      int year, int month, List<AttendanceEmployee> employees) async {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final existingRecords = await loadForMonth(year, month);
    int markedCount = 0;

    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      if (date.weekday == DateTime.sunday) {
        for (final emp in employees) {
          final dateKey =
              '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
          final hasRecord = existingRecords.any(
              (r) => r.userId == emp.id && r.dateKey == dateKey);
          if (!hasRecord) {
            await markStatus(
              userId: emp.id,
              staffName: emp.name,
              staffRole: emp.role,
              date: date,
              status: AttendanceStatus.holiday,
              note: 'Sunday Weekly Off',
            );
            markedCount++;
          }
        }
      }
    }
    return markedCount;
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
