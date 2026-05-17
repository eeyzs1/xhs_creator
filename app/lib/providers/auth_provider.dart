import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();

  User? _user;
  bool _isLoading = false;
  String? _error;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;
  String? get error => _error;

  Future<void> init() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final storedToken = _storageService.token;
      if (storedToken != null && storedToken.isNotEmpty) {
        _apiService.setToken(storedToken);
        try {
          final userData = await _apiService.getMe();
          _user = User.fromJson(userData);
          _apiService.setUserId(_user!.id);
        } catch (_) {
          await _clearAuthData();
        }
      }
    } catch (e) {
      _error = '初始化失败: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> register(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _apiService.register(username, password);
      _user = User.fromJson(result['user'] as Map<String, dynamic>);
      final token = result['token'] as String;
      await _storageService.setToken(token);
      await _storageService.setUserId(_user!.id);
      await _storageService.setUsername(_user!.username);
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _apiService.login(username, password);
      _user = User.fromJson(result['user'] as Map<String, dynamic>);
      final token = result['token'] as String;
      await _storageService.setToken(token);
      await _storageService.setUserId(_user!.id);
      await _storageService.setUsername(_user!.username);
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateNickname(String nickname) async {
    if (_user == null) return;
    _user = _user!.copyWith(nickname: nickname);
    await _storageService.setNickname(nickname);
    notifyListeners();
  }

  Future<void> logout() async {
    _user = null;
    _error = null;
    await _apiService.logout();
    await _clearAuthData();
    notifyListeners();
  }

  Future<void> _clearAuthData() async {
    await _storageService.setToken(null);
    await _storageService.setUserId("");
    _apiService.setToken(null);
    _apiService.setUserId(null);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}