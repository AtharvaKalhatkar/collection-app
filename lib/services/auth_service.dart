import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import 'firebase_service.dart';

class AuthService {
  static const String _keyUsers = 'app_users_cache_v1';
  static const String _keyCurrentUserId = 'current_logged_in_user_id_v1';
  final FirebaseService _firebase = FirebaseService();

  Future<List<UserModel>> loadUsers() async {
    final prefs = await SharedPreferences.getInstance();
    List<UserModel> users = [];

    // 1. Try local cache
    final jsonStr = prefs.getString(_keyUsers);
    if (jsonStr != null) {
      try {
        final List<dynamic> list = jsonDecode(jsonStr);
        users = list.map((item) => UserModel.fromJson(item as Map<String, dynamic>)).toList();
      } catch (e) {
        debugPrint('Error decoding users cache: $e');
      }
    }

    // 2. If empty, seed initial users
    if (users.isEmpty) {
      users = UserModel.getInitialUsers();
      await saveUsersLocally(users);
    }

    // 3. Sync from Firestore in background / online
    try {
      if (_firebase.isInitialized) {
        final cloudUsers = await _firebase.fetchUsers();
        if (cloudUsers.isNotEmpty) {
          users = cloudUsers;
          await saveUsersLocally(users);
        } else {
          // Push initial users to Firestore
          for (final u in users) {
            await _firebase.saveUser(u);
          }
        }
      }
    } catch (e) {
      debugPrint('Error syncing users with Firestore: $e');
    }

    return users;
  }

  Future<void> saveUsersLocally(List<UserModel> users) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(users.map((u) => u.toJson()).toList());
    await prefs.setString(_keyUsers, jsonStr);
  }

  Future<UserModel?> login(String phoneInput, String password) async {
    final cleanPhone = UserModel.normalizePhone(phoneInput);
    final users = await loadUsers();

    final user = users.firstWhere(
      (u) => UserModel.normalizePhone(u.phone) == cleanPhone && u.password == password.trim(),
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
    final users = await loadUsers();
    final index = users.indexWhere((u) => u.id == user.id);
    if (index >= 0) {
      users[index] = user;
    } else {
      users.add(user);
    }

    await saveUsersLocally(users);
    if (_firebase.isInitialized) {
      await _firebase.saveUser(user);
    }
  }

  Future<void> deleteUser(String userId) async {
    final users = await loadUsers();
    users.removeWhere((u) => u.id == userId);
    await saveUsersLocally(users);

    if (_firebase.isInitialized) {
      await _firebase.deleteUser(userId);
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
