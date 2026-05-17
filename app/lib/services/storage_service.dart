import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  static const String _keyUserId = 'user_id';
  static const String _keyUsername = 'username';
  static const String _keyNickname = 'nickname';
  static const String _keyToken = 'auth_token';
  static const String _keyServerUrl = 'server_url';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  SharedPreferences get _preferences {
    if (_prefs == null) {
      throw StateError('StorageService 未初始化，请先调用 init()');
    }
    return _prefs!;
  }

  String? get userId => _preferences.getString(_keyUserId);

  Future<void> setUserId(String userId) async {
    await _preferences.setString(_keyUserId, userId);
  }

  String? get username => _preferences.getString(_keyUsername);

  Future<void> setUsername(String username) async {
    await _preferences.setString(_keyUsername, username);
  }

  String? get nickname => _preferences.getString(_keyNickname);

  Future<void> setNickname(String nickname) async {
    await _preferences.setString(_keyNickname, nickname);
  }

  String? get token => _preferences.getString(_keyToken);

  Future<void> setToken(String? token) async {
    if (token == null) {
      await _preferences.remove(_keyToken);
    } else {
      await _preferences.setString(_keyToken, token);
    }
  }

  String? get serverUrl => _preferences.getString(_keyServerUrl);

  Future<void> setServerUrl(String? url) async {
    if (url == null) {
      await _preferences.remove(_keyServerUrl);
    } else {
      await _preferences.setString(_keyServerUrl, url);
    }
  }

  Future<void> clear() async {
    await _preferences.clear();
  }
}
