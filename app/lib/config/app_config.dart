import '../services/storage_service.dart';

class AppConfig {
  static const String _defaultBaseUrl = 'http://localhost:3001';

  static String get effectiveBaseUrl {
    try {
      final storageUrl = StorageService().serverUrl;
      if (storageUrl != null && storageUrl.isNotEmpty) {
        return storageUrl;
      }
    } catch (_) {}
    return _defaultBaseUrl;
  }

  static Future<void> setCustomBaseUrl(String url) async {
    await StorageService().setServerUrl(url);
  }

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 60);

  static const String registerEndpoint = '/api/auth/register';
  static const String loginEndpoint = '/api/auth/login';
  static const String meEndpoint = '/api/auth/me';
  static const String logoutEndpoint = '/api/auth/logout';
  static const String uploadEndpoint = '/api/upload';
  static const String postsEndpoint = '/api/posts';
  static const String tryOnEndpoint = '/api/ai/try-on';
  static const String generateTextEndpoint = '/api/ai/generate-text';
  static const String modifyPostEndpoint = '/api/ai/modify-post';
  static const String modifyImageEndpoint = '/api/ai/modify-image';
  static const String healthEndpoint = '/api/health';
}