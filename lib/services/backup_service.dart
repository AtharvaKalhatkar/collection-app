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

  /// Returns the latest backup timestamp across all devices, querying Cloud Firestore first
  /// so that Akash, Atharva, and Office devices all share the EXACT same backup reference
  Future<DateTime?> getLatestBackupTimeShared() async {
    try {
      if (_firebase.isInitialized) {
        final cloudTime = await _firebase.fetchLatestCloudBackupTime();
        if (cloudTime != null) {
          await _setLastBackupTime(cloudTime);
          return cloudTime;
        }
      }
    } catch (e) {
      debugPrint('Cloud backup time check notice: $e');
    }
    return await getLastBackupTime();
  }

  /// Checks if 4 days have elapsed since the last cloud backup, and executes auto backup if needed.
  /// Prevents multi-device duplication by verifying Firestore before taking a snapshot.
  Future<bool> checkAndRunAutoBackup({
    required List<RouteModel> routes,
    required List<ShopModel> shops,
    required List<CollectionModel> collections,
    required List<PendingBillModel> pendingBills,
    required List<UserModel> users,
  }) async {
    try {
      // 1. Check shared cloud backup time across all devices
      final lastBackup = await getLatestBackupTimeShared();
      final now = DateTime.now();

      if (lastBackup == null || now.difference(lastBackup).inDays >= autoBackupIntervalDays) {
        // 2. Pre-flight concurrency guard: re-verify cloud in case another staff member's device ran it moments ago
        if (_firebase.isInitialized) {
          final cloudCheck = await _firebase.fetchLatestCloudBackupTime();
          if (cloudCheck != null && now.difference(cloudCheck).inDays < autoBackupIntervalDays) {
            debugPrint('Auto-backup already completed by another staff device at $cloudCheck. Skipping duplication.');
            await _setLastBackupTime(cloudCheck);
            return false;
          }
        }

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
