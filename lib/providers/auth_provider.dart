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

  Future<void> refreshUsers() async {
    _users = await _authService.loadUsers();
    notifyListeners();
  }
}
