import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  UserModel? _currentUser;
  List<UserModel> _users = [];
  bool _isLoading = true;
  String? _errorMessage;

  UserModel? get currentUser => _currentUser;
  List<UserModel> get users => _users;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser != null;
  String? get errorMessage => _errorMessage;

  AuthProvider() {
    initialize();
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      _users = await _authService.loadUsers();
      final savedId = await _authService.getSavedSessionId();

      if (savedId != null) {
        final matched = _users.firstWhere(
          (u) => u.id == savedId && u.isActive,
          orElse: () => UserModel(
            id: '',
            phone: '',
            name: '',
            role: UserRole.salesman,
            password: '',
            isActive: false,
          ),
        );
        if (matched.id.isNotEmpty) {
          _currentUser = matched;
        }
      }
    } catch (e) {
      debugPrint('AuthProvider initialization error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> login(String phone, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.login(phone, password);
      if (user != null) {
        _currentUser = user;
        _users = await _authService.loadUsers();
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = 'Invalid mobile number or password.';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Login failed: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _currentUser = null;
    await _authService.clearSession();
    notifyListeners();
  }

  Future<void> saveUser(UserModel user) async {
    await _authService.saveUser(user);
    _users = await _authService.loadUsers();
    if (_currentUser?.id == user.id) {
      _currentUser = user;
    }
    notifyListeners();
  }

  Future<void> deleteUser(String userId) async {
    await _authService.deleteUser(userId);
    _users = await _authService.loadUsers();
    notifyListeners();
  }

  Future<void> updateCurrentLocation(double latitude, double longitude, {String? landmark}) async {
    if (_currentUser == null) return;
    // Merge with latest synced user metadata so periodic GPS pings never overwrite
    // route assignments, password, role, or active status edited by Super Admin.
    final latestUser = await _authService.getFreshUserById(_currentUser!.id) ?? _currentUser!;
    final updated = latestUser.copyWith(
      latitude: latitude,
      longitude: longitude,
      locationUpdatedAt: DateTime.now(),
      locationLandmark: landmark ?? _currentUser!.locationLandmark,
    );
    _currentUser = updated;
    await _authService.saveUserLocationOnly(updated);
    notifyListeners();
  }

  Future<void> refreshUsers() async {
    final loaded = await _authService.loadUsers();
    await applySyncedUsers(loaded);
  }

  /// Applies an already-fetched user list (for example from CollectionProvider sync)
  /// without triggering a redundant network fetch, keeping the signed-in user's
  /// route assignments and active status current.
  Future<void> applySyncedUsers(List<UserModel> syncedUsers) async {
    _users = syncedUsers;
    if (_currentUser != null) {
      final idx = _users.indexWhere((u) => u.id == _currentUser!.id);
      if (idx != -1) {
        final remote = _users[idx];
        if (!remote.isActive) {
          await logout();
          return;
        }
        final keepLocalGps = _currentUser!.locationUpdatedAt != null &&
            (remote.locationUpdatedAt == null ||
                _currentUser!.locationUpdatedAt!.isAfter(remote.locationUpdatedAt!));
        _currentUser = keepLocalGps
            ? remote.copyWith(
                latitude: _currentUser!.latitude,
                longitude: _currentUser!.longitude,
                locationUpdatedAt: _currentUser!.locationUpdatedAt,
                locationLandmark: _currentUser!.locationLandmark,
              )
            : remote;
        await _authService.persistSessionUser(_currentUser!);
      }
    }
    notifyListeners();
  }
}
