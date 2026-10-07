import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../models/route_model.dart';
import '../models/shop_model.dart';
import '../models/collection_model.dart';
import '../models/pending_bill_model.dart';
import '../models/user_model.dart';
import 'firebase_service.dart';

class BackupService {
  static const String _keyLastBackupTime = 'last_auto_backup_timestamp_v1';
  static const String _keyLatestBackupJson = 'latest_backup_snapshot_v1';
  static const int autoBackupIntervalDays = 4;

  final FirebaseService _firebase = FirebaseService();

  Future<DateTime?> getLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_keyLastBackupTime);
    if (millis != null) {
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    return null;
  }

  Future<void> _setLastBackupTime(DateTime dt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastBackupTime, dt.millisecondsSinceEpoch);
  }

  /// Checks if 4 days have elapsed since the last backup, and executes auto backup if needed
  Future<bool> checkAndRunAutoBackup({
    required List<RouteModel> routes,
    required List<ShopModel> shops,
    required List<CollectionModel> collections,
    required List<PendingBillModel> pendingBills,
    required List<UserModel> users,
  }) async {
    try {
      final lastBackup = await getLastBackupTime();
      final now = DateTime.now();

      if (lastBackup == null || now.difference(lastBackup).inDays >= autoBackupIntervalDays) {
        debugPrint('Executing scheduled auto-backup (Interval: $autoBackupIntervalDays days)...');
        final success = await createBackup(
          routes: routes,
          shops: shops,
          collections: collections,
          pendingBills: pendingBills,
          users: users,
          trigger: lastBackup == null ? 'initial_auto' : 'scheduled_4_days',
        );
        return success;
      }
    } catch (e) {
      debugPrint('Error during auto-backup check: $e');
    }
    return false;
  }

  /// Creates a full comprehensive database backup snapshot
  Future<bool> createBackup({
    required List<RouteModel> routes,
    required List<ShopModel> shops,
    required List<CollectionModel> collections,
    required List<PendingBillModel> pendingBills,
    required List<UserModel> users,
    String trigger = 'manual',
  }) async {
    try {
      final now = DateTime.now();
      final backupId = 'backup_${DateFormat('yyyyMMdd_HHmmss').format(now)}';

      final Map<String, dynamic> backupData = {
        'id': backupId,
        'trigger': trigger,
        'createdAt': now.toIso8601String(),
        'createdAtFormatted': DateFormat('dd MMM yyyy, hh:mm a').format(now),
        'summary': {
          'routesCount': routes.length,
          'shopsCount': shops.length,
          'collectionsCount': collections.length,
          'pendingBillsCount': pendingBills.length,
          'usersCount': users.length,
        },
        'routes': routes.map((r) => r.toJson()).toList(),
        'shops': shops.map((s) => s.toJson()).toList(),
        'collections': collections.map((c) => c.toJson()).toList(),
        'pendingBills': pendingBills.map((b) => b.toJson()).toList(),
        'users': users.map((u) => u.toJson()).toList(),
      };

      // 1. Save locally to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLatestBackupJson, jsonEncode(backupData));
      await _setLastBackupTime(now);

      // 2. Save snapshot to Firestore backups collection
      if (_firebase.isInitialized) {
        await _firebase.saveBackup(backupData);
      }

      debugPrint('Backup completed successfully: $backupId (trigger: $trigger)');
      return true;
    } catch (e) {
      debugPrint('Failed to create backup: $e');
      return false;
    }
  }

  /// Fetches latest local backup snapshot
  Future<Map<String, dynamic>?> getLatestLocalBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyLatestBackupJson);
    if (jsonStr != null) {
      try {
        return jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error parsing latest local backup: $e');
      }
    }
    return null;
  }
}
