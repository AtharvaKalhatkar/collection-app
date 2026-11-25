import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import 'supabase_service.dart';

class AuthService {
  static const String _keyUsers = 'app_users_cache_v1';
  static const String _keyCurrentUserId = 'current_logged_in_user_id_v1';
  static const String _keyDirtyUserIds = 'auth_dirty_user_ids_v1';
  static const String _keyDeletedUserIds = 'auth_deleted_user_ids_v1';
  final SupabaseService _supabase = SupabaseService();

  static bool _isValidStaff(UserModel u) {
    if (u.id == 'config_gemini_api' || u.id.startsWith('config_')) return false;
    if (u.id.startsWith('so_') ||
        u.id.startsWith('cp_') ||
        u.id.startsWith('att_') ||
        u.id.startsWith('tl_') ||
        u.id.startsWith('timeline_') ||
        u.id.startsWith('route_order_') ||
        u.id.startsWith('ch_') ||
        u.id.startsWith('vc_') ||
        u.id.startsWith('cfg_')) {
      return false;
    }
    final lowerName = u.name.trim().toLowerCase();
    if (lowerName == 'b g mart' ||
        lowerName == 'g r mart' ||
        lowerName.contains('unknown')) {
      return false;
    }
    return true;
  }

  Future<Set<String>> _getIdSet(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(key) ?? []).toSet();
  }

  Future<void> _saveIdSet(String key, Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, ids.toList());
  }

  List<UserModel> _loadCachedUsersSync(SharedPreferences prefs) {
    final jsonStr = prefs.getString(_keyUsers);
    if (jsonStr == null) return [];
    try {
      final List<dynamic> list = jsonDecode(jsonStr);
      return list
          .map((item) => UserModel.fromJson(item as Map<String, dynamic>))
          .where(_isValidStaff)
          .toList();
    } catch (e) {
      debugPrint('Error decoding users cache: $e');
      return [];
    }
  }

  Future<List<UserModel>> loadUsers() async {
    final prefs = await SharedPreferences.getInstance();
    List<UserModel> users = _loadCachedUsersSync(prefs);
    final dirtyIds = await _getIdSet(_keyDirtyUserIds);
    final deletedIds = await _getIdSet(_keyDeletedUserIds);

    // 2. If empty (fresh install), seed initial users (excluding tombstoned ones)
    if (users.isEmpty && deletedIds.isEmpty) {
      users = UserModel.getInitialUsers();
      await saveUsersLocally(users);
    }

    // 3. Bidirectional Sync with Supabase
    try {
      if (!_supabase.isInitialized) {
        await _supabase.init();
      }
      if (_supabase.isInitialized) {
        // A) Flush pending deletes
        if (deletedIds.isNotEmpty) {
          final remainingDeletes = <String>{};
          for (final id in deletedIds) {
            final ok = await _supabase.deleteUser(id);
            if (!ok) remainingDeletes.add(id);
          }
          await _saveIdSet(_keyDeletedUserIds, remainingDeletes);
          deletedIds
            ..clear()
            ..addAll(remainingDeletes);
        }

        // B) Push any dirty local users
        if (dirtyIds.isNotEmpty) {
          final remainingDirty = <String>{};
          for (final id in dirtyIds) {
            final localMatch = users.where((u) => u.id == id).toList();
            if (localMatch.isNotEmpty) {
              final ok = await _supabase.saveUser(localMatch.first);
              if (!ok) remainingDirty.add(id);
            }
          }
          await _saveIdSet(_keyDirtyUserIds, remainingDirty);
          dirtyIds
            ..clear()
            ..addAll(remainingDirty);
        }

        // C) Fetch authoritative cloud users
        final result = await _supabase.fetchUsersWithStatus();
        if (result.success) {
          final cloudUsers = result.items
              .where((u) => _isValidStaff(u) && !deletedIds.contains(u.id))
              .toList();
          if (cloudUsers.isNotEmpty) {
            final mergedMap = <String, UserModel>{
              for (final cu in cloudUsers) cu.id: cu,
            };
            // Preserve any still-dirty local edits that haven't synced yet
            for (final id in dirtyIds) {
              final localMatch = users.where((u) => u.id == id).toList();
              if (localMatch.isNotEmpty) {
                mergedMap[id] = localMatch.first;
              }
            }
            users = mergedMap.values.toList();
          } else if (users.isNotEmpty) {
            // Seed initial users to empty cloud database
            for (final u in users) {
              if (!deletedIds.contains(u.id)) {
                await _supabase.saveUser(u);
              }
            }
          }

          // Ensure driver user is present if missing and not explicitly deleted
          if (!deletedIds.contains('user_driver_user1') &&
              !users.any((u) => u.phone == 'user1' || u.role == UserRole.driver)) {
            final driver = UserModel(
              id: 'user_driver_user1',
              phone: 'user1',
              name: 'Driver (user1)',
              role: UserRole.driver,
              password: 'pass123',
            );
            users.add(driver);
            await _supabase.saveUser(driver);
          }

          // Ensure order booking user is present if missing and not explicitly deleted
          if (!deletedIds.contains('user_order_1') &&
              !users.any((u) => u.phone == 'order1' || u.role == UserRole.order)) {
            final orderUser = UserModel(
              id: 'user_order_1',
              phone: 'order1',
              name: 'Order 1',
              role: UserRole.order,
              password: 'pass123',
            );
            users.add(orderUser);
            await _supabase.saveUser(orderUser);
          }

          await saveUsersLocally(users);
        }
      }
    } catch (e) {
      debugPrint('Error syncing users with cloud: $e');
    }

    return users.where((u) => !deletedIds.contains(u.id)).toList();
  }

  Future<void> saveUsersLocally(List<UserModel> users) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(users.map((u) => u.toJson()).toList());
    await prefs.setString(_keyUsers, jsonStr);
  }

  Future<UserModel?> getFreshUserById(String userId) async {
    try {
      if (!_supabase.isInitialized) {
        await _supabase.init();
      }
      if (_supabase.isInitialized) {
        final cloudUser = await _supabase.fetchUserById(userId);
        if (cloudUser != null && _isValidStaff(cloudUser)) {
          return cloudUser;
        }
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    final cached = _loadCachedUsersSync(prefs);
    for (final u in cached) {
      if (u.id == userId) return u;
    }
    return null;
  }

  Future<void> persistSessionUser(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    final users = _loadCachedUsersSync(prefs);
    final idx = users.indexWhere((u) => u.id == user.id);
    if (idx >= 0) {
      users[idx] = user;
    } else {
      users.add(user);
    }
    await saveUsersLocally(users);
  }

  Future<void> saveUserLocationOnly(UserModel user) async {
    await persistSessionUser(user);
    try {
      if (!_supabase.isInitialized) {
        await _supabase.init();
      }
      if (_supabase.isInitialized) {
        final ok = await _supabase.saveUser(user);
        if (!ok) {
          final dirty = await _getIdSet(_keyDirtyUserIds);
          dirty.add(user.id);
          await _saveIdSet(_keyDirtyUserIds, dirty);
        }
      }
    } catch (e) {
      debugPrint('Location sync notice: $e');
    }
  }

  Future<UserModel?> login(String phoneInput, String password) async {
    final cleanPhone = UserModel.normalizePhone(phoneInput);
    final users = await loadUsers();

    final user = users.firstWhere(
      (u) =>
          UserModel.normalizePhone(u.phone) == cleanPhone &&
          u.actualPassword == password.trim(),
      orElse: () => UserModel(
        id: '',
        phone: '',
        name: '',
        role: UserRole.salesman,
        password: '',
        isActive: false,
      ),
    );

    if (user.id.isNotEmpty && user.isActive) {
      final updatedUser = user.copyWith(lastLoginAt: DateTime.now());
      await saveUser(updatedUser);
      await saveSession(updatedUser.id);
      return updatedUser;
    }

    return null;
  }

  Future<void> saveUser(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    final users = _loadCachedUsersSync(prefs);
    final index = users.indexWhere((u) => u.id == user.id);
    if (index >= 0) {
      users[index] = user;
    } else {
      users.add(user);
    }
    await saveUsersLocally(users);

    final deletedIds = await _getIdSet(_keyDeletedUserIds);
    deletedIds.remove(user.id);
    await _saveIdSet(_keyDeletedUserIds, deletedIds);

    final dirtyIds = await _getIdSet(_keyDirtyUserIds);
    dirtyIds.add(user.id);
    await _saveIdSet(_keyDirtyUserIds, dirtyIds);

    if (!_supabase.isInitialized) {
      await _supabase.init();
    }
    if (_supabase.isInitialized) {
      final ok = await _supabase.saveUser(user);
      if (ok) {
        dirtyIds.remove(user.id);
        await _saveIdSet(_keyDirtyUserIds, dirtyIds);
      }
    }
  }

  Future<void> deleteUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final users = _loadCachedUsersSync(prefs);
    users.removeWhere((u) => u.id == userId);
    await saveUsersLocally(users);

    final dirtyIds = await _getIdSet(_keyDirtyUserIds);
    dirtyIds.remove(userId);
    await _saveIdSet(_keyDirtyUserIds, dirtyIds);

    final deletedIds = await _getIdSet(_keyDeletedUserIds);
    deletedIds.add(userId);
    await _saveIdSet(_keyDeletedUserIds, deletedIds);

    if (!_supabase.isInitialized) {
      await _supabase.init();
    }
    if (_supabase.isInitialized) {
      final ok = await _supabase.deleteUser(userId);
      if (ok) {
        deletedIds.remove(userId);
        await _saveIdSet(_keyDeletedUserIds, deletedIds);
      }
    }
  }

  Future<void> saveSession(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCurrentUserId, userId);
  }

  Future<String?> getSavedSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCurrentUserId);
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCurrentUserId);
  }
}
