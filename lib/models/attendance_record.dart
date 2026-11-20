import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_model.dart';
import '../services/supabase_service.dart';

// ── Helpers ─────────────────────────────────────────────────────────────────
DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _dateKeyOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Parses ISO strings and converts UTC (cloud) values to local time.
DateTime? _parseDt(dynamic v) {
  if (v is! String) return null;
  return DateTime.tryParse(v)?.toLocal();
}

int _int(dynamic v, int fallback) =>
    v is num ? v.toInt() : (int.tryParse('$v') ?? fallback);

double _dbl(dynamic v, [double fallback = 0.0]) =>
    v is num ? v.toDouble() : (double.tryParse('$v') ?? fallback);

/// Present, Half Day, Absent
enum AttendanceStatus { present, halfDay, absent }

extension AttendanceStatusExtension on AttendanceStatus {
  String get label => switch (this) {
        AttendanceStatus.present => 'Present',
        AttendanceStatus.halfDay => 'Half Day',
        AttendanceStatus.absent => 'Absent',
      };

  String get shortCode => switch (this) {
        AttendanceStatus.present => 'P',
        AttendanceStatus.halfDay => '½',
        AttendanceStatus.absent => 'A',
      };

  double get payableValue => switch (this) {
        AttendanceStatus.present => 1.0,
        AttendanceStatus.halfDay => 0.5,
        AttendanceStatus.absent => 0.0,
      };

  static AttendanceStatus parse(String? s) {
    final v = (s ?? '').toLowerCase().replaceAll(RegExp(r'[\s_]'), '');
    return AttendanceStatus.values.firstWhere(
      (e) => e.name.toLowerCase() == v,
      orElse: () => AttendanceStatus.present,
    );
  }
}

// ── Attendance record ───────────────────────────────────────────────────────
class AttendanceRecord {
  final String id;
  final String userId;
  final String staffName;
  final String staffRole;
  final DateTime date; // always normalized to local midnight
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final AttendanceStatus status;
  final String? note;

  AttendanceRecord({
    required this.id,
    required this.userId,
    required this.staffName,
    required this.staffRole,
    required DateTime date,
    this.checkInTime,
    this.checkOutTime,
    this.status = AttendanceStatus.present,
    this.note,
  }) : date = _dateOnly(date);

  String get dateKey => _dateKeyOf(date);

  Duration? get workDuration {
    if (checkInTime == null || checkOutTime == null) return null;
    final d = checkOutTime!.difference(checkInTime!);
    return d.isNegative ? null : d;
  }

  double? get workHours =>
      workDuration == null ? null : workDuration!.inMinutes / 60.0;

  String get workDurationFormatted {
    final d = workDuration;
    if (d == null) return '--';
    return '${d.inHours}h ${d.inMinutes % 60}m';
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
    final date = _parseDt(json['date']);
    if (date == null) throw const FormatException('Invalid attendance date');
    return AttendanceRecord(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      staffName: json['staffName'] as String? ?? '',
      staffRole: json['staffRole'] as String? ?? '',
      date: date,
      checkInTime: _parseDt(json['checkInTime']),
      checkOutTime: _parseDt(json['checkOutTime']),
      status: AttendanceStatusExtension.parse(json['status'] as String?),
      note: json['note'] as String?,
    );
  }

  AttendanceRecord copyWith({
    DateTime? checkInTime,
    DateTime? checkOutTime,
    AttendanceStatus? status,
    String? note,
    bool clearCheckIn = false,
    bool clearCheckOut = false,
    bool clearNote = false,
  }) {
    return AttendanceRecord(
      id: id,
      userId: userId,
      staffName: staffName,
      staffRole: staffRole,
      date: date,
      checkInTime: clearCheckIn ? null : (checkInTime ?? this.checkInTime),
      checkOutTime: clearCheckOut ? null : (checkOutTime ?? this.checkOutTime),
      status: status ?? this.status,
      note: clearNote ? null : (note ?? this.note),
    );
  }
}

// ── Employee ────────────────────────────────────────────────────────────────
class AttendanceEmployee {
  final String id;
  final String name;
  final String role;
  final String phone;
  final double monthlySalary;
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
    double monthlySalary = 18000.0,
    this.isActive = true,
    this.isCustom = true,
    this.joinedAt,
  }) : monthlySalary = monthlySalary < 0 ? 0.0 : monthlySalary;

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
        monthlySalary: _dbl(json['monthlySalary'], 18000.0),
        isActive: json['isActive'] as bool? ?? true,
        isCustom: json['isCustom'] as bool? ?? true,
        joinedAt: _parseDt(json['joinedAt']),
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

// ── Advances & adjustments ──────────────────────────────────────────────────
class SalaryAdvanceEntry {
  final String id;
  final String employeeId;
  final int year;
  final int month;
  final double amount;
  final DateTime date;
  final String? note;

  SalaryAdvanceEntry({
    required this.id,
    required this.employeeId,
    required this.year,
    required this.month,
    required this.amount,
    required this.date,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeId': employeeId,
        'year': year,
        'month': month,
        'amount': amount,
        'date': date.toIso8601String(),
        'note': note,
      };

  factory SalaryAdvanceEntry.fromJson(Map<String, dynamic> json) =>
      SalaryAdvanceEntry(
        id: json['id'] as String? ?? '',
        employeeId: json['employeeId'] as String? ?? '',
        year: _int(json['year'], DateTime.now().year),
        month: _int(json['month'], DateTime.now().month),
        amount: _dbl(json['amount']),
        date: _parseDt(json['date']) ?? DateTime.now(),
        note: json['note'] as String?,
      );
}

class SalaryMonthlyAdjustment {
  final String employeeId;
  final int year;
  final int month;
  final double bonus;
  final double advanceDeduction; // legacy fallback when advances is empty
  final List<SalaryAdvanceEntry> advances;
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
    this.advances = const [],
    this.isDisbursed = false,
    this.disbursedAt,
    this.paymentMode,
    this.note,
  });

  double get totalAdvanceDeduction => advances.isNotEmpty
      ? advances.fold(0.0, (sum, a) => sum + a.amount)
      : advanceDeduction;

  SalaryMonthlyAdjustment copyWith({
    double? bonus,
    List<SalaryAdvanceEntry>? advances,
    bool? isDisbursed,
    DateTime? disbursedAt,
    String? paymentMode,
    String? note,
    bool clearDisbursal = false,
  }) {
    final adv = advances ?? this.advances;
    return SalaryMonthlyAdjustment(
      employeeId: employeeId,
      year: year,
      month: month,
      bonus: bonus ?? this.bonus,
      advanceDeduction: advances != null
          ? adv.fold(0.0, (s, a) => s + a.amount)
          : advanceDeduction,
      advances: adv,
      isDisbursed: clearDisbursal ? false : (isDisbursed ?? this.isDisbursed),
      disbursedAt: clearDisbursal ? null : (disbursedAt ?? this.disbursedAt),
      paymentMode: clearDisbursal ? null : (paymentMode ?? this.paymentMode),
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'year': year,
        'month': month,
        'bonus': bonus,
        'advanceDeduction': totalAdvanceDeduction,
        'advances': advances.map((a) => a.toJson()).toList(),
        'isDisbursed': isDisbursed,
        'disbursedAt': disbursedAt?.toIso8601String(),
        'paymentMode': paymentMode,
        'note': note,
      };

  factory SalaryMonthlyAdjustment.fromJson(Map<String, dynamic> json) {
    final parsed = <SalaryAdvanceEntry>[];
    final raw = json['advances'];
    if (raw is List) {
      for (final item in raw) {
        try {
          parsed.add(SalaryAdvanceEntry.fromJson(
              Map<String, dynamic>.from(item as Map)));
        } catch (_) {}
      }
    }
    return SalaryMonthlyAdjustment(
      employeeId: json['employeeId'] as String? ?? '',
      year: _int(json['year'], DateTime.now().year),
      month: _int(json['month'], DateTime.now().month),
      bonus: _dbl(json['bonus']),
      advanceDeduction: _dbl(json['advanceDeduction']),
      advances: parsed,
      isDisbursed: json['isDisbursed'] as bool? ?? false,
      disbursedAt: _parseDt(json['disbursedAt']),
      paymentMode: json['paymentMode'] as String?,
      note: json['note'] as String?,
    );
  }
}

// ── Salary calculation ──────────────────────────────────────────────────────
class MonthlySalaryCalculation {
  final AttendanceEmployee employee;
  final int year;
  final int month;
  final int totalDaysInMonth;
  final int presentCount;
  final int halfDayCount;
  final int absentCount;
  final int unmarkedDays; // past days with no attendance entry
  final double payableDays;
  final double dailyRate;
  final double baseMonthlySalary;
  final double earnedSalary;
  final double bonus;
  final double advanceDeduction;
  final double advanceCarryForward; // advance not recoverable this month
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
    this.unmarkedDays = 0,
    this.advanceCarryForward = 0.0,
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
    DateTime? today,
  }) {
    final daysInMonth = DateTime(year, month + 1, 0).day;

    // One record per day, only this employee + this month.
    final byDate = <String, AttendanceRecord>{};
    for (final r in monthRecords) {
      if (r.userId != employee.id || r.date.year != year || r.date.month != month) {
        continue;
      }
      byDate[r.dateKey] = r;
    }

    int present = 0, halfDay = 0, absent = 0;
    final absentList = <DateTime>[];
    for (final r in byDate.values) {
      switch (r.status) {
        case AttendanceStatus.present:
          present++;
        case AttendanceStatus.halfDay:
          halfDay++;
        case AttendanceStatus.absent:
          absent++;
          absentList.add(r.date);
      }
    }
    absentList.sort();

    // Unmarked days: from join date (or day 1) up to today, no entry.
    final now = _dateOnly(today ?? DateTime.now());
    final joined = employee.joinedAt == null ? null : _dateOnly(employee.joinedAt!);
    int unmarked = 0;
    for (var d = 1; d <= daysInMonth; d++) {
      final day = DateTime(year, month, d);
      if (day.isAfter(now)) break;
      if (joined != null && day.isBefore(joined)) continue;
      if (!byDate.containsKey(_dateKeyOf(day))) unmarked++;
    }

    final payable = present + (halfDay * 0.5);
    final base = employee.monthlySalary;
    final daily = daysInMonth > 0 ? base / daysInMonth : 0.0;
    final earned = (payable * daily).roundToDouble();
    final bonus = adjustment?.bonus ?? 0.0;
    final adv = adjustment?.totalAdvanceDeduction ?? 0.0;
    final gross = earned + bonus;

    return MonthlySalaryCalculation(
      employee: employee,
      year: year,
      month: month,
      totalDaysInMonth: daysInMonth,
      presentCount: present,
      halfDayCount: halfDay,
      absentCount: absent,
      unmarkedDays: unmarked,
      payableDays: payable,
      dailyRate: daily,
      baseMonthlySalary: base,
      earnedSalary: earned,
      bonus: bonus,
      advanceDeduction: adv,
      advanceCarryForward: math.max(0.0, adv - gross),
      netSalary: math.max(0.0, gross - adv),
      isDisbursed: adjustment?.isDisbursed ?? false,
      disbursedAt: adjustment?.disbursedAt,
      paymentMode: adjustment?.paymentMode,
      absentDates: absentList,
    );
  }

  String formatWhatsAppSlip({String companyName = 'Purva Enterprises & Manas Sales'}) {
    final monthName = _monthNames[month - 1];
    final absentStr = absentDates.isNotEmpty
        ? absentDates.map((d) => '${d.day} $monthName').join(', ')
        : 'None';

    return '''📄 *ATTENDANCE & SALARY SLIP - $monthName $year*
👤 *Employee:* ${employee.name} (${employee.role})
🏢 *$companyName*
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
${bonus > 0 ? '🎁 Bonus / Incentive: ₹${bonus.toStringAsFixed(0)}\n' : ''}${advanceDeduction > 0 ? '➖ Advance Deducted: ₹${advanceDeduction.toStringAsFixed(0)}\n' : ''}${advanceCarryForward > 0 ? '↪️ Advance Carried Forward: ₹${advanceCarryForward.toStringAsFixed(0)}\n' : ''}----------------------------------------
🎯 *NET SALARY PAYABLE: ₹${netSalary.toStringAsFixed(0)}*
${isDisbursed ? '✅ Status: Disbursed (${paymentMode ?? 'Cash'})' : '⏳ Status: Pending'}
----------------------------------------
_Daily Collection App_''';
  }

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
}

// ── Service ─────────────────────────────────────────────────────────────────
/// Offline-first: all reads/writes hit local storage instantly; changes are
/// queued ("dirty") and pushed to Supabase in the background. Unsynced local
/// edits are never overwritten by stale cloud data.
class AttendanceService {
  static const String _keyPrefix = 'attendance_v2_';
  static const String _empKey = 'attendance_employees_v2';
  static const String _adjPrefix = 'attendance_adj_v2_';
  static const String _dirtyKey = 'attendance_dirty_v2';

  /// Checkout earlier than this many hours after check-in => Half Day.
  static const double halfDayBelowHours = 4.0;
  static const Duration _netTimeout = Duration(seconds: 8);

  static SupabaseService get _cloud => SupabaseService();

  static String _monthKey(int y, int m) => '$_keyPrefix${y}_${m.toString().padLeft(2, '0')}';
  static String _adjKey(int y, int m) => '$_adjPrefix${y}_${m.toString().padLeft(2, '0')}';
  static String _recId(String userId, DateTime d) =>
      '${userId}_${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  // Dirty tokens
  static String _tEmp(String id) => 'emp|$id';
  static String _tDel(String id) => 'del|$id';
  static String _tRec(AttendanceRecord r) =>
      'rec|${r.date.year}|${r.date.month}|${r.userId}|${r.dateKey}';
  static String _tAdj(int y, int m, String e) => 'adj|$y|$m|$e';

  // ── Lock (serializes local read-modify-write) ─────────────────────────────
  static Future<void> _lockTail = Future.value();

  static Future<T> _locked<T>(Future<T> Function() fn) {
    final run = _lockTail.then((_) => fn());
    _lockTail = run.then((_) {}, onError: (_) {});
    return run;
  }

  static List<T> _decode<T>(
      List<String>? raw, T Function(Map<String, dynamic>) fromJson) {
    final out = <T>[];
    for (final s in raw ?? const <String>[]) {
      try {
        out.add(fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map)));
      } catch (_) {}
    }
    return out;
  }

  // ── Dirty queue ───────────────────────────────────────────────────────────
  static final Map<String, int> _gen = {};
  static bool _flushing = false;

  static Future<void> _dirtyAdd(SharedPreferences p, Iterable<String> t) async {
    final s = (p.getStringList(_dirtyKey) ?? const <String>[]).toSet()..addAll(t);
    await p.setStringList(_dirtyKey, s.toList());
  }

  static Future<void> _markDirty(String t) {
    _gen[t] = (_gen[t] ?? 0) + 1;
    return _locked(() async =>
        _dirtyAdd(await SharedPreferences.getInstance(), [t]));
  }

  static Future<void> _dirtyRemove(String t) => _locked(() async {
        final p = await SharedPreferences.getInstance();
        final s = (p.getStringList(_dirtyKey) ?? const <String>[]).toSet()..remove(t);
        await p.setStringList(_dirtyKey, s.toList());
      });

  static Future<int> pendingSyncCount() async =>
      ((await SharedPreferences.getInstance()).getStringList(_dirtyKey) ?? const []).length;

  /// Pushes queued changes to Supabase. Safe to call any time; never throws.
  static Future<void> flushPending() async {
    if (_flushing) return;
    _flushing = true;
    try {
      for (var pass = 0; pass < 3; pass++) {
        var retry = false;
        final p = await SharedPreferences.getInstance();
        for (final t in (p.getStringList(_dirtyKey) ?? const <String>[]).toList()) {
          final g = _gen[t];
          final parts = t.split('|');
          try {
            if (parts[0] == 'del') {
              await _cloud.deleteAttendanceEmployee(parts[1]).timeout(_netTimeout);
            } else if (parts[0] == 'emp') {
              final e = _decode(p.getStringList(_empKey), AttendanceEmployee.fromJson)
                  .where((x) => x.id == parts[1]);
              if (e.isNotEmpty) {
                await _cloud.saveAttendanceEmployee(e.first).timeout(_netTimeout);
              }
            } else if (parts[0] == 'rec') {
              final y = int.parse(parts[1]), m = int.parse(parts[2]);
              final r = _decode(p.getStringList(_monthKey(y, m)), AttendanceRecord.fromJson)
                  .where((x) => x.userId == parts[3] && x.dateKey == parts[4]);
              if (r.isNotEmpty) {
                await _cloud.saveAttendanceRecord(r.last).timeout(_netTimeout);
              }
            } else if (parts[0] == 'adj') {
              final y = int.parse(parts[1]), m = int.parse(parts[2]);
              final a = _decode(p.getStringList(_adjKey(y, m)), SalaryMonthlyAdjustment.fromJson)
                  .where((x) => x.employeeId == parts[3]);
              if (a.isNotEmpty) {
                await _cloud.saveAttendanceAdjustment(a.first).timeout(_netTimeout);
              }
            }
            if (_gen[t] == g) {
              await _dirtyRemove(t);
            } else {
              retry = true; // edited again while pushing
            }
          } catch (e) {
            debugPrint('Attendance sync paused (offline?): $e');
            return;
          }
        }
        if (!retry) break;
      }
    } finally {
      _flushing = false;
    }
  }

  /// Merge cloud into local. Unsynced local items win; local-only items are
  /// queued for upload; items with a pending delete stay deleted.
  static Future<void> _pullAndMerge<T>({
    required String storageKey,
    required List<T> cloud,
    required T Function(Map<String, dynamic>) fromJson,
    required Map<String, dynamic> Function(T) toJson,
    required String Function(T) key,
    required String Function(T) token,
  }) =>
      _locked(() async {
        final p = await SharedPreferences.getInstance();
        final dirty = (p.getStringList(_dirtyKey) ?? const <String>[]).toSet();
        final local = _decode(p.getStringList(storageKey), fromJson);
        final merged = <String, T>{for (final c in cloud) key(c): c};
        final newDirty = <String>[];
        for (final l in local) {
          final k = key(l);
          if (!merged.containsKey(k)) {
            newDirty.add(token(l));
            merged[k] = l;
          } else if (dirty.contains(token(l))) {
            merged[k] = l;
          }
        }
        merged.removeWhere((k, _) => dirty.contains('del|$k'));
        await p.setStringList(
            storageKey, merged.values.map((e) => jsonEncode(toJson(e))).toList());
        if (newDirty.isNotEmpty) await _dirtyAdd(p, newDirty);
      });

  // ── Employees ─────────────────────────────────────────────────────────────
  /// [fallbackUsers] kept for API compatibility.
  static Future<List<AttendanceEmployee>> loadEmployees({
    List<UserModel>? fallbackUsers,
    bool activeOnly = false,
    bool sync = true,
  }) async {
    if (sync) {
      try {
        await flushPending();
        final cloud = await _cloud.fetchAttendanceEmployees().timeout(_netTimeout);
        await _pullAndMerge<AttendanceEmployee>(
          storageKey: _empKey,
          cloud: cloud,
          fromJson: AttendanceEmployee.fromJson,
          toJson: (e) => e.toJson(),
          key: (e) => e.id,
          token: (e) => _tEmp(e.id),
        );
        unawaited(flushPending());
      } catch (e) {
        debugPrint('Employee sync skipped: $e');
      }
    }
    final p = await SharedPreferences.getInstance();
    final list = _decode(p.getStringList(_empKey), AttendanceEmployee.fromJson)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return activeOnly ? list.where((e) => e.isActive).toList() : list;
  }

  static Future<void> saveEmployees(List<AttendanceEmployee> list) async {
    await _locked(() async {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_empKey, list.map((e) => jsonEncode(e.toJson())).toList());
    });
    for (final e in list) {
      await _markDirty(_tEmp(e.id));
    }
    unawaited(flushPending());
  }

  static Future<void> saveEmployee(AttendanceEmployee emp) async {
    await _locked(() async {
      final p = await SharedPreferences.getInstance();
      final list = _decode(p.getStringList(_empKey), AttendanceEmployee.fromJson);
      final i = list.indexWhere((e) => e.id == emp.id);
      if (i >= 0) {
        list[i] = emp;
      } else {
        list.add(emp);
      }
      await p.setStringList(_empKey, list.map((e) => jsonEncode(e.toJson())).toList());
    });
    await _markDirty(_tEmp(emp.id));
    unawaited(flushPending());
  }

  /// Default = soft delete (keeps salary history, syncs everywhere).
  /// [permanent] removes the employee entirely.
  static Future<void> deleteEmployee(String empId, {bool permanent = false}) async {
    if (!permanent) {
      final all = await loadEmployees(sync: false);
      final idx = all.indexWhere((e) => e.id == empId);
      if (idx >= 0) await saveEmployee(all[idx].copyWith(isActive: false));
      return;
    }
    await _locked(() async {
      final p = await SharedPreferences.getInstance();
      final list = _decode(p.getStringList(_empKey), AttendanceEmployee.fromJson)
        ..removeWhere((e) => e.id == empId);
      await p.setStringList(_empKey, list.map((e) => jsonEncode(e.toJson())).toList());
    });
    await _dirtyRemove(_tEmp(empId));
    await _markDirty(_tDel(empId));
    unawaited(flushPending());
  }

  // ── Records ───────────────────────────────────────────────────────────────
  static Future<List<AttendanceRecord>> loadForMonth(int year, int month,
      {bool sync = true}) async {
    if (sync) {
      try {
        await flushPending();
        final cloud =
            await _cloud.fetchAttendanceRecords(year, month).timeout(_netTimeout);
        await _pullAndMerge<AttendanceRecord>(
          storageKey: _monthKey(year, month),
          cloud: cloud,
          fromJson: AttendanceRecord.fromJson,
          toJson: (r) => r.toJson(),
          key: (r) => '${r.userId}_${r.dateKey}',
          token: _tRec,
        );
        unawaited(flushPending());
      } catch (e) {
        debugPrint('Attendance sync skipped: $e');
      }
    }
    final p = await SharedPreferences.getInstance();
    return _decode(p.getStringList(_monthKey(year, month)), AttendanceRecord.fromJson);
  }

  /// Atomic read-modify-write on local storage (no network), then queue sync.
  /// [fn] returns the new record, the same instance (no change) or null.
  static Future<AttendanceRecord?> _updateRecord(String userId, DateTime date,
      AttendanceRecord? Function(AttendanceRecord? cur) fn) async {
    final d = _dateOnly(date);
    final dk = _dateKeyOf(d);
    AttendanceRecord? result;
    var changed = false;
    await _locked(() async {
      final p = await SharedPreferences.getInstance();
      final k = _monthKey(d.year, d.month);
      final list = _decode(p.getStringList(k), AttendanceRecord.fromJson);
      final matches = list.where((r) => r.userId == userId && r.dateKey == dk);
      final cur = matches.isEmpty ? null : matches.last;
      final next = fn(cur);
      result = next;
      if (next == null || identical(next, cur)) return;
      changed = true;
      list.removeWhere((r) => r.userId == userId && r.dateKey == dk);
      list.add(next);
      await p.setStringList(k, list.map((r) => jsonEncode(r.toJson())).toList());
    });
    if (changed && result != null) {
      await _markDirty(_tRec(result!));
      unawaited(flushPending());
    }
    return result;
  }

  static Future<void> saveRecord(AttendanceRecord record) =>
      _updateRecord(record.userId, record.date, (_) => record);

  /// Local-only by default (instant). Pass sync: true to refresh from cloud first.
  static Future<AttendanceRecord?> loadForUserAndDate(String userId, DateTime date,
      {bool sync = false}) async {
    final key = _dateKeyOf(date);
    final records = await loadForMonth(date.year, date.month, sync: sync);
    for (final r in records.reversed) {
      if (r.userId == userId && r.dateKey == key) return r;
    }
    return null;
  }

  static Future<AttendanceRecord> checkIn(
      String userId, String staffName, String staffRole,
      {DateTime? customTime}) async {
    final now = customTime ?? DateTime.now();
    final r = await _updateRecord(userId, now, (cur) {
      if (cur?.checkInTime != null) return cur; // already checked in
      if (cur == null) {
        return AttendanceRecord(
          id: _recId(userId, _dateOnly(now)),
          userId: userId,
          staffName: staffName,
          staffRole: staffRole,
          date: now,
          checkInTime: now,
          status: AttendanceStatus.present,
        );
      }
      return cur.copyWith(
        checkInTime: now,
        // keep a manual Half Day; only flip Absent -> Present
        status: cur.status == AttendanceStatus.absent
            ? AttendanceStatus.present
            : cur.status,
      );
    });
    return r!;
  }

  /// Returns null if there is no check-in to close.
  static Future<AttendanceRecord?> checkOut(String userId,
      {DateTime? customTime, bool autoStatus = true}) {
    final now = customTime ?? DateTime.now();
    return _updateRecord(userId, now, (cur) {
      if (cur == null || cur.checkInTime == null) return null;
      if (cur.checkOutTime != null) return cur; // already checked out
      if (now.isBefore(cur.checkInTime!)) return cur;
      var status = cur.status;
      if (autoStatus && status == AttendanceStatus.present) {
        final hours = now.difference(cur.checkInTime!).inMinutes / 60.0;
        if (hours < halfDayBelowHours) status = AttendanceStatus.halfDay;
      }
      return cur.copyWith(checkOutTime: now, status: status);
    });
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
    final isAbsent = status == AttendanceStatus.absent;
    final out = (checkInTime != null &&
            checkOutTime != null &&
            checkOutTime.isBefore(checkInTime))
        ? null
        : checkOutTime;
    await _updateRecord(
      userId,
      date,
      (cur) => AttendanceRecord(
        id: cur?.id.isNotEmpty == true ? cur!.id : _recId(userId, _dateOnly(date)),
        userId: userId,
        staffName: staffName,
        staffRole: staffRole,
        date: date,
        checkInTime: isAbsent ? null : checkInTime,
        checkOutTime: isAbsent ? null : out,
        status: status,
        note: note ?? cur?.note,
      ),
    );
  }

  /// Marks every active employee who has no entry on [date] (default Present).
  /// Skips days before an employee's join date. Returns how many were marked.
  static Future<int> markAllUnmarked(
    List<AttendanceEmployee> employees,
    DateTime date, {
    AttendanceStatus status = AttendanceStatus.present,
  }) async {
    final d = _dateOnly(date);
    final records = await loadForMonth(d.year, d.month, sync: false);
    final marked =
        records.where((r) => r.dateKey == _dateKeyOf(d)).map((r) => r.userId).toSet();
    var n = 0;
    for (final e in employees) {
      if (!e.isActive || marked.contains(e.id)) continue;
      if (e.joinedAt != null && d.isBefore(_dateOnly(e.joinedAt!))) continue;
      await markStatus(
        userId: e.id,
        staffName: e.name,
        staffRole: e.role,
        date: d,
        status: status,
      );
      n++;
    }
    return n;
  }

  // ── Adjustments (bonus / advances / disbursal) ────────────────────────────
  static Future<List<SalaryMonthlyAdjustment>> loadAdjustments(int year, int month,
      {bool sync = true}) async {
    if (sync) {
      try {
        await flushPending();
        final cloud =
            await _cloud.fetchAttendanceAdjustments(year, month).timeout(_netTimeout);
        await _pullAndMerge<SalaryMonthlyAdjustment>(
          storageKey: _adjKey(year, month),
          cloud: cloud,
          fromJson: SalaryMonthlyAdjustment.fromJson,
          toJson: (a) => a.toJson(),
          key: (a) => a.employeeId,
          token: (a) => _tAdj(a.year, a.month, a.employeeId),
        );
        unawaited(flushPending());
      } catch (e) {
        debugPrint('Adjustment sync skipped: $e');
      }
    }
    final p = await SharedPreferences.getInstance();
    return _decode(
        p.getStringList(_adjKey(year, month)), SalaryMonthlyAdjustment.fromJson);
  }

  static Future<void> _updateAdj(String empId, int y, int m,
      SalaryMonthlyAdjustment Function(SalaryMonthlyAdjustment cur) fn) async {
    await _locked(() async {
      final p = await SharedPreferences.getInstance();
      final k = _adjKey(y, m);
      final list = _decode(p.getStringList(k), SalaryMonthlyAdjustment.fromJson);
      final i = list.indexWhere((a) => a.employeeId == empId);
      final next = fn(i >= 0
          ? list[i]
          : SalaryMonthlyAdjustment(employeeId: empId, year: y, month: m));
      if (i >= 0) {
        list[i] = next;
      } else {
        list.add(next);
      }
      await p.setStringList(k, list.map((a) => jsonEncode(a.toJson())).toList());
    });
    await _markDirty(_tAdj(y, m, empId));
    unawaited(flushPending());
  }

  static Future<void> saveAdjustment(SalaryMonthlyAdjustment adj) =>
      _updateAdj(adj.employeeId, adj.year, adj.month, (_) => adj);

  /// Converts a legacy lump-sum advance into an entry so it isn't lost.
  static List<SalaryAdvanceEntry> _advancesOf(SalaryMonthlyAdjustment a) {
    if (a.advances.isNotEmpty || a.advanceDeduction <= 0) return a.advances;
    return [
      SalaryAdvanceEntry(
        id: 'adv_legacy_${a.employeeId}_${a.year}_${a.month}',
        employeeId: a.employeeId,
        year: a.year,
        month: a.month,
        amount: a.advanceDeduction,
        date: DateTime(a.year, a.month, 1),
        note: 'Previous advance',
      )
    ];
  }

  static Future<void> addAdvance({
    required String employeeId,
    required int year,
    required int month,
    required double amount,
    required DateTime date,
    String? note,
  }) async {
    if (amount <= 0) return;
    await _updateAdj(employeeId, year, month, (cur) {
      final entry = SalaryAdvanceEntry(
        id: 'adv_${DateTime.now().microsecondsSinceEpoch}',
        employeeId: employeeId,
        year: year,
        month: month,
        amount: amount,
        date: date,
        note: note,
      );
      return cur.copyWith(advances: [..._advancesOf(cur), entry]);
    });
  }

  static Future<void> deleteAdvance({
    required String employeeId,
    required String advanceId,
    required int year,
    required int month,
  }) =>
      _updateAdj(
        employeeId,
        year,
        month,
        (cur) => cur.copyWith(
            advances: _advancesOf(cur).where((a) => a.id != advanceId).toList()),
      );

  static Future<void> setBonus({
    required String employeeId,
    required int year,
    required int month,
    required double bonus,
    String? note,
  }) =>
      _updateAdj(employeeId, year, month,
          (cur) => cur.copyWith(bonus: math.max(0.0, bonus), note: note));

  static Future<void> markDisbursed({
    required String employeeId,
    required int year,
    required int month,
    String paymentMode = 'Cash',
    bool undo = false,
  }) =>
      _updateAdj(
        employeeId,
        year,
        month,
        (cur) => undo
            ? cur.copyWith(clearDisbursal: true)
            : cur.copyWith(
                isDisbursed: true,
                disbursedAt: DateTime.now(),
                paymentMode: paymentMode),
      );

  // ── Salary helpers ────────────────────────────────────────────────────────
  static SalaryMonthlyAdjustment? _adjOf(
      List<SalaryMonthlyAdjustment> list, String empId) {
    for (final a in list) {
      if (a.employeeId == empId) return a;
    }
    return null;
  }

  static Future<MonthlySalaryCalculation> computeMonth(
      AttendanceEmployee employee, int year, int month,
      {bool sync = false}) async {
    final recs = await loadForMonth(year, month, sync: sync);
    final adjs = await loadAdjustments(year, month, sync: sync);
    return MonthlySalaryCalculation.compute(
      employee: employee,
      year: year,
      month: month,
      monthRecords: recs,
      adjustment: _adjOf(adjs, employee.id),
    );
  }

  /// Payroll for the month: active employees + anyone who has records that month.
  static Future<List<MonthlySalaryCalculation>> computeAllForMonth(
      int year, int month) async {
    final emps = await loadEmployees();
    final recs = await loadForMonth(year, month);
    final adjs = await loadAdjustments(year, month);
    final withRecords = recs.map((r) => r.userId).toSet();
    return [
      for (final e in emps)
        if (e.isActive || withRecords.contains(e.id))
          MonthlySalaryCalculation.compute(
            employee: e,
            year: year,
            month: month,
            monthRecords: recs,
            adjustment: _adjOf(adjs, e.id),
          ),
    ];
  }
}