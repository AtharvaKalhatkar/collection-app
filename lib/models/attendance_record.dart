import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AttendanceStatus { present, absent, halfDay, leave }

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

  String get dateKey => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

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

  String get statusLabel {
    switch (status) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.halfDay:
        return 'Half Day';
      case AttendanceStatus.leave:
        return 'On Leave';
    }
  }

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
      checkInTime: json['checkInTime'] != null ? DateTime.parse(json['checkInTime'] as String) : null,
      checkOutTime: json['checkOutTime'] != null ? DateTime.parse(json['checkOutTime'] as String) : null,
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

class AttendanceService {
  static const String _keyPrefix = 'attendance_v1_';

  // Returns a unique key per month
  static String _monthKey(int year, int month) =>
      '$_keyPrefix${year}_${month.toString().padLeft(2, '0')}';

  // Load all attendance records for a given month
  static Future<List<AttendanceRecord>> loadForMonth(int year, int month) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_monthKey(year, month)) ?? [];
    final records = <AttendanceRecord>[];
    for (final item in raw) {
      try {
        records.add(AttendanceRecord.fromJson(jsonDecode(item) as Map<String, dynamic>));
      } catch (_) {}
    }
    return records;
  }

  // Save/update a single record for the month
  static Future<void> saveRecord(AttendanceRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _monthKey(record.date.year, record.date.month);
    final raw = prefs.getStringList(key) ?? [];
    final records = <AttendanceRecord>[];
    for (final item in raw) {
      try {
        records.add(AttendanceRecord.fromJson(jsonDecode(item) as Map<String, dynamic>));
      } catch (_) {}
    }

    // Remove existing record for same user+date and replace
    records.removeWhere((r) => r.userId == record.userId && r.dateKey == record.dateKey);
    records.add(record);

    final newRaw = records.map((r) => jsonEncode(r.toJson())).toList();
    await prefs.setStringList(key, newRaw);
  }

  // Load record for a specific user and date
  static Future<AttendanceRecord?> loadForUserAndDate(String userId, DateTime date) async {
    final records = await loadForMonth(date.year, date.month);
    final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    try {
      return records.firstWhere((r) => r.userId == userId && r.dateKey == dateKey);
    } catch (_) {
      return null;
    }
  }

  // Check in: mark present and set check-in time
  static Future<AttendanceRecord> checkIn(String userId, String staffName, String staffRole) async {
    final now = DateTime.now();
    final existing = await loadForUserAndDate(userId, now);

    if (existing != null && existing.checkInTime != null) {
      return existing; // Already checked in
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

  // Check out: set check-out time
  static Future<AttendanceRecord?> checkOut(String userId) async {
    final now = DateTime.now();
    final existing = await loadForUserAndDate(userId, now);
    if (existing == null || existing.checkInTime == null) return null;
    if (existing.checkOutTime != null) return existing; // Already checked out

    final updated = existing.copyWith(checkOutTime: now);
    await saveRecord(updated);
    return updated;
  }

  // Mark as absent/leave/halfday (admin override)
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
    debugPrint('Marked $staffName as ${status.name} on ${record.dateKey}');
  }
}
