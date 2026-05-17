import 'package:flutter/material.dart';
import '../models/post.dart';
import '../services/api_service.dart';

class PostProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<Post> _posts = [];
  Post? _currentPost;
  bool _isLoading = false;
  bool _isGenerating = false;
  String? _error;

  List<Post> get posts => _posts;
  Post? get currentPost => _currentPost;
  bool get isLoading => _isLoading;
  bool get isGenerating => _isGenerating;
  String? get error => _error;

  void setCurrentPost(Post? post) {
    _currentPost = post;
    notifyListeners();
  }

  Future<void> loadPosts() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final List<dynamic> data = await _apiService.getPosts();
      _posts =
          data.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      _error = '加载帖子失败: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Post?> createPost({
    required String garmentImage,
    required String streetImage,
    String style = '',
    String? garmentOriginalUrl,
    String? streetOriginalUrl,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final garmentResult = await _apiService.uploadImage(garmentImage, originalUrl: garmentOriginalUrl);
      final streetResult = await _apiService.uploadImage(streetImage, originalUrl: streetOriginalUrl);

      final garmentUrl = garmentResult['url'] as String? ?? '';
      final streetUrl = streetResult['url'] as String? ?? '';

      final data = await _apiService.createPost(
        garmentImage: garmentUrl,
        streetImage: streetUrl,
        style: style,
      );
      final post = Post.fromJson(data);
      _posts.insert(0, post);
      _currentPost = post;
      _isLoading = false;
      notifyListeners();
      return post;
    } catch (e) {
      _error = '创建帖子失败: $e';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<Post?> updatePost(String postId, Map<String, dynamic> data) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _apiService.updatePost(postId, data);
      final updatedPost = Post.fromJson(result);
      final index = _posts.indexWhere((p) => p.id == postId);
      if (index != -1) {
        _posts[index] = updatedPost;
      }
      if (_currentPost?.id == postId) {
        _currentPost = updatedPost;
      }
      _isLoading = false;
      notifyListeners();
      return updatedPost;
    } catch (e) {
      _error = '更新帖子失败: $e';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> deletePost(String postId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _apiService.deletePost(postId);
      _posts.removeWhere((p) => p.id == postId);
      if (_currentPost?.id == postId) {
        _currentPost = null;
      }
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = '删除帖子失败: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<Post?> generateTryOn(String postId,
      {String garmentType = 'upper_body'}) async {
    final post = _posts.firstWhere((p) => p.id == postId);
    if (post.streetImage.isEmpty || post.garmentImage.isEmpty) {
      _error = '请先上传服装和街拍照片';
      notifyListeners();
      return null;
    }

    _isGenerating = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _apiService.virtualTryOn(
        humanImageUrl: post.streetImage,
        garmentImageUrl: post.garmentImage,
        garmentType: garmentType,
      );

      final resultImageUrl = result['result_image_url'] as String? ?? '';
      final updatedPost = await updatePost(postId, {
        'result_image': resultImageUrl,
        'status': 'try_on_done',
      });

      _isGenerating = false;
      notifyListeners();
      return updatedPost;
    } catch (e) {
      _error = '虚拟试穿失败: $e';
      _isGenerating = false;
      notifyListeners();
      return null;
    }
  }

  Future<Post?> generateText(
    String postId, {
    required String garmentDesc,
    String style = '',
  }) async {
    _isGenerating = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _apiService.generateText(
        garmentDesc: garmentDesc,
        style: style,
      );

      final title = result['title'] as String? ?? '';
      final content = result['content'] as String? ?? '';
      final tags = (result['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      final updatedPost = await updatePost(postId, {
        'title': title,
        'content': content,
        'tags': tags,
        'status': 'text_done',
      });

      _isGenerating = false;
      notifyListeners();
      return updatedPost;
    } catch (e) {
      _error = '文案生成失败: $e';
      _isGenerating = false;
      notifyListeners();
      return null;
    }
  }

  Future<Post?> modifyPostWithInstruction(
      String postId, String instruction) async {
    final post = _posts.firstWhere((p) => p.id == postId);

    _isGenerating = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _apiService.modifyPost(
        currentTitle: post.title,
        currentContent: post.content,
        currentTags: post.tags,
        instruction: instruction,
      );

      final title = result['title'] as String? ?? post.title;
      final content = result['content'] as String? ?? post.content;
      final tags = (result['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          post.tags;

      final chatEntry = {
        'role': 'user',
        'content': instruction,
        'timestamp': DateTime.now().toIso8601String(),
      };
      final aiEntry = {
        'role': 'assistant',
        'content': '已根据指令修改文案',
        'timestamp': DateTime.now().toIso8601String(),
      };

      final updatedChatHistory = [...post.chatHistory, chatEntry, aiEntry];

      final updatedPost = await updatePost(postId, {
        'title': title,
        'content': content,
        'tags': tags,
        'chat_history': updatedChatHistory,
      });

      _isGenerating = false;
      notifyListeners();
      return updatedPost;
    } catch (e) {
      _error = '修改文案失败: $e';
      _isGenerating = false;
      notifyListeners();
      return null;
    }
  }

  Future<Post?> modifyImageWithInstruction(
      String postId, String instruction) async {
    final post = _posts.firstWhere((p) => p.id == postId);

    _isGenerating = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _apiService.modifyImage(
        imageUrl: post.resultImage,
        instruction: instruction,
      );

      final resultImageUrl = result['result_image_url'] as String?;
      if (resultImageUrl == null || resultImageUrl.isEmpty) {
        _error = '图片修改失败: 未收到结果图片';
        _isGenerating = false;
        notifyListeners();
        return null;
      }

      final updatedPost = await updatePost(postId, {
        'result_image': resultImageUrl,
      });

      _isGenerating = false;
      notifyListeners();
      return updatedPost;
    } catch (e) {
      _error = '修改图片失败: $e';
      _isGenerating = false;
      notifyListeners();
      return null;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
