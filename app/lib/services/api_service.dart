import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../config/app_config.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => 'ApiException: $message (状态码: $statusCode)';
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String _baseUrl = AppConfig.effectiveBaseUrl;
  String? _userId;
  String? _authToken;

  String get baseUrl => _baseUrl;
  String? get userId => _userId;

  void refreshBaseUrl() {
    _baseUrl = AppConfig.effectiveBaseUrl;
  }

  void setBaseUrl(String url) {
    _baseUrl = url;
  }

  void setUserId(String? userId) {
    _userId = userId;
  }

  void setToken(String? token) {
    _authToken = token;
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  Future<Map<String, dynamic>> _handleResponse(http.Response response) async {
    final body = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body as Map<String, dynamic>;
    }
    throw ApiException(
      (body is Map) ? (body['error'] as String? ?? '请求失败') : '请求失败',
      response.statusCode,
    );
  }

  Future<List<dynamic>> _handleListResponse(http.Response response) async {
    final body = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (body is List) return body;
      if (body is Map) {
        final error = body['error'] as String?;
        throw ApiException(error ?? '请求失败', response.statusCode);
      }
      return [];
    }
    throw ApiException(
      (body is Map) ? (body['error'] as String? ?? '请求失败') : '请求失败',
      response.statusCode,
    );
  }

  Future<Map<String, dynamic>> register(String username, String password) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl${AppConfig.registerEndpoint}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(AppConfig.connectTimeout);

    final result = await _handleResponse(response);
    final token = result['token'] as String?;
    if (token != null) {
      _authToken = token;
    }
    _userId = (result['user'] as Map<String, dynamic>?)?['id'] as String?;
    return result;
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl${AppConfig.loginEndpoint}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(AppConfig.connectTimeout);

    final result = await _handleResponse(response);
    final token = result['token'] as String?;
    if (token != null) {
      _authToken = token;
    }
    _userId = (result['user'] as Map<String, dynamic>?)?['id'] as String?;
    return result;
  }

  Future<Map<String, dynamic>> getMe() async {
    final response = await http
        .get(
          Uri.parse('$_baseUrl${AppConfig.meEndpoint}'),
          headers: _headers,
        )
        .timeout(AppConfig.connectTimeout);

    return _handleResponse(response);
  }

  Future<void> logout() async {
    try {
      await http
          .post(
            Uri.parse('$_baseUrl${AppConfig.logoutEndpoint}'),
            headers: _headers,
          )
          .timeout(AppConfig.connectTimeout);
    } catch (_) {}
    _authToken = null;
    _userId = null;
  }

  Future<Map<String, dynamic>> uploadImage(String filePath, {String? originalUrl}) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl${AppConfig.uploadEndpoint}'),
    );

    if (_authToken != null) {
      request.headers['Authorization'] = 'Bearer $_authToken';
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw ApiException('文件不存在: $filePath');
    }

    final stream = http.ByteStream(file.openRead());
    final length = await file.length();

    final multipartFile = http.MultipartFile(
      'image',
      stream,
      length,
      filename: '${const Uuid().v4()}${_getExtension(filePath)}',
    );

    request.files.add(multipartFile);
    if (originalUrl != null) {
      request.fields['original_url'] = originalUrl;
    }

    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 30),
    );
    final response = await http.Response.fromStream(streamedResponse);
    return _handleResponse(response);
  }

  String _getExtension(String filePath) {
    final dotIndex = filePath.lastIndexOf('.');
    if (dotIndex == -1) return '.jpg';
    return filePath.substring(dotIndex);
  }

  Future<Map<String, dynamic>> createPost({
    required String garmentImage,
    required String streetImage,
    String style = '',
  }) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl${AppConfig.postsEndpoint}'),
          headers: _headers,
          body: jsonEncode({
            'garment_image': garmentImage,
            'street_image': streetImage,
            'style': style,
          }),
        )
        .timeout(AppConfig.connectTimeout);

    return _handleResponse(response);
  }

  Future<List<dynamic>> getPosts() async {
    final response = await http
        .get(
          Uri.parse('$_baseUrl${AppConfig.postsEndpoint}'),
          headers: _headers,
        )
        .timeout(AppConfig.connectTimeout);

    return _handleListResponse(response);
  }

  Future<Map<String, dynamic>> getPost(String postId) async {
    final response = await http
        .get(
          Uri.parse('$_baseUrl${AppConfig.postsEndpoint}/$postId'),
          headers: _headers,
        )
        .timeout(AppConfig.connectTimeout);

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> updatePost(
      String postId, Map<String, dynamic> data) async {
    final response = await http
        .put(
          Uri.parse('$_baseUrl${AppConfig.postsEndpoint}/$postId'),
          headers: _headers,
          body: jsonEncode(data),
        )
        .timeout(AppConfig.connectTimeout);

    return _handleResponse(response);
  }

  Future<void> deletePost(String postId) async {
    final response = await http
        .delete(
          Uri.parse('$_baseUrl${AppConfig.postsEndpoint}/$postId'),
          headers: _headers,
        )
        .timeout(AppConfig.connectTimeout);

    await _handleResponse(response);
  }

  Future<Map<String, dynamic>> virtualTryOn({
    required String humanImageUrl,
    required String garmentImageUrl,
    String garmentType = 'upper_body',
  }) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl${AppConfig.tryOnEndpoint}'),
          headers: _headers,
          body: jsonEncode({
            'human_image_url': humanImageUrl,
            'garment_image_url': garmentImageUrl,
            'garment_type': garmentType,
          }),
        )
        .timeout(const Duration(seconds: 120));

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> generateText({
    required String garmentDesc,
    String style = '',
  }) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl${AppConfig.generateTextEndpoint}'),
          headers: _headers,
          body: jsonEncode({
            'garment_desc': garmentDesc,
            'style': style,
          }),
        )
        .timeout(const Duration(seconds: 60));

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> modifyPost({
    required String currentTitle,
    required String currentContent,
    required List<String> currentTags,
    required String instruction,
  }) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl${AppConfig.modifyPostEndpoint}'),
          headers: _headers,
          body: jsonEncode({
            'current_title': currentTitle,
            'current_content': currentContent,
            'current_tags': currentTags,
            'instruction': instruction,
          }),
        )
        .timeout(const Duration(seconds: 60));

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> modifyImage({
    required String imageUrl,
    required String instruction,
  }) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl${AppConfig.modifyImageEndpoint}'),
          headers: _headers,
          body: jsonEncode({
            'image_url': imageUrl,
            'instruction': instruction,
          }),
        )
        .timeout(const Duration(seconds: 200));

    return _handleResponse(response);
  }

  String resolveImageUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return '';
    if (imageUrl.startsWith('http')) return imageUrl;
    if (imageUrl.startsWith('/uploads/')) return '$_baseUrl$imageUrl';
    return imageUrl;
  }

  Future<bool> checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl${AppConfig.healthEndpoint}'))
          .timeout(AppConfig.connectTimeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}