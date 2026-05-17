import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gal/gal.dart';
import 'package:xhs_creator/models/post.dart';
import 'package:xhs_creator/services/api_service.dart';
import 'package:xhs_creator/providers/auth_provider.dart';
import 'package:xhs_creator/providers/post_provider.dart';
import 'package:xhs_creator/screens/edit_screen.dart';
import 'package:xhs_creator/theme/app_theme.dart';

class PreviewScreen extends StatefulWidget {
  final Post post;

  const PreviewScreen({super.key, required this.post});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late Post _post;
  bool _isLiked = false;
  bool _isCollected = false;
  bool _isSavingImage = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
  }

  String get _imageUrl {
    final url = _post.hasResult ? _post.resultImage : _post.garmentImage;
    return ApiService().resolveImageUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          _buildImageSliver(),
          _buildContentSliver(authProvider),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildImageSliver() {
    return SliverToBoxAdapter(
      child: Stack(
        children: [
          GestureDetector(
            onLongPress: _isSavingImage ? null : _saveImageToGallery,
            child: Container(
              width: double.infinity,
              height: MediaQuery.of(context).size.width * 1.2,
              color: Colors.grey.shade100,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildMainImage(),
                  if (_isSavingImage)
                    Container(
                      color: Colors.black26,
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 12),
                            Text('保存中...', style: TextStyle(color: Colors.white, fontSize: 15)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: _buildBackButton(),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: _buildShareButton(),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.3)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainImage() {
    if (_imageUrl.isEmpty) {
      return Center(child: Icon(Icons.image_outlined, size: 64, color: Colors.grey.shade300));
    }

    return CachedNetworkImage(
      imageUrl: _imageUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) => Center(
        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.grey.shade400)),
      ),
      errorWidget: (context, url, error) => Center(child: Icon(Icons.broken_image, size: 64, color: Colors.grey.shade400)),
    );
  }

  Widget _buildBackButton() {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), shape: BoxShape.circle),
        child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
      ),
    );
  }

  Widget _buildShareButton() {
    return GestureDetector(
      onTap: _sharePost,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), shape: BoxShape.circle),
        child: const Icon(Icons.share, color: Colors.white, size: 16),
      ),
    );
  }

  Widget _buildContentSliver(AuthProvider authProvider) {
    return SliverToBoxAdapter(
      child: Transform.translate(
        offset: const Offset(0, -1),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              _buildTitle(),
              _buildContent(),
              _buildTags(),
              const Divider(height: 32, indent: 20, endIndent: 20),
              _buildInteractionBar(),
              const Divider(height: 32, indent: 20, endIndent: 20),
              _buildAuthorInfo(authProvider),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    final title = _post.title.isNotEmpty ? _post.title : '今日穿搭分享 ✨';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SelectableText(
        title,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, height: 1.4),
      ),
    );
  }

  Widget _buildContent() {
    if (_post.content.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: SelectableText(
        _post.content,
        style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.8),
      ),
    );
  }

  Widget _buildTags() {
    if (_post.tags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _post.tags.map((tag) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.primaryRed.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text('#$tag', style: const TextStyle(fontSize: 13, color: AppTheme.primaryRed, fontWeight: FontWeight.w500)),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInteractionBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _InteractionButton(
            icon: _isLiked ? Icons.favorite : Icons.favorite_border,
            label: '128',
            color: _isLiked ? AppTheme.primaryRed : Colors.grey,
            onTap: () => setState(() => _isLiked = !_isLiked),
          ),
          const SizedBox(width: 24),
          _InteractionButton(
            icon: Icons.chat_bubble_outline,
            label: '36',
            color: Colors.grey,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('评论功能开发中'), behavior: SnackBarBehavior.floating),
              );
            },
          ),
          const SizedBox(width: 24),
          _InteractionButton(
            icon: _isCollected ? Icons.bookmark : Icons.bookmark_border,
            label: '52',
            color: _isCollected ? const Color(0xFFFF9800) : Colors.grey,
            onTap: () => setState(() => _isCollected = !_isCollected),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _sharePost,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.share, size: 16, color: Colors.grey),
                  SizedBox(width: 4),
                  Text('分享', style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthorInfo(AuthProvider authProvider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [AppTheme.primaryRed, AppTheme.primaryRedLight]),
              boxShadow: [
                BoxShadow(color: AppTheme.primaryRed.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Center(
              child: Text(
                (authProvider.user?.nickname ?? '小').substring(0, 1),
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(authProvider.user?.nickname ?? '小红书创作者', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(_formatDate(_post.createdAt), style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(border: Border.all(color: AppTheme.primaryRed), borderRadius: BorderRadius.circular(14)),
            child: const Text('关注', style: TextStyle(color: AppTheme.primaryRed, fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => EditScreen(post: _post)),
                  ).then((result) {
                    if (result is Post) {
                      setState(() => _post = result);
                    }
                  });
                },
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(22)),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
                      SizedBox(width: 6),
                      Text('编辑', style: TextStyle(color: Colors.grey, fontSize: 15)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: _savePost,
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppTheme.primaryRed, AppTheme.primaryRedLight]),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.save, size: 18, color: Colors.white),
                      SizedBox(width: 6),
                      Text('保存', style: TextStyle(color: Colors.white, fontSize: 15)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _savePost() async {
    final postProvider = context.read<PostProvider>();
    await postProvider.updatePost(_post.id, {'status': 'published'});
    if (!mounted) return;
    setState(() {
      _post = _post.copyWith(status: 'published', updatedAt: DateTime.now());
    });
    _showToast('保存成功！', Colors.green.shade600);
  }

  Future<void> _saveImageToGallery() async {
    if (_imageUrl.isEmpty) return;
    setState(() => _isSavingImage = true);

    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/xhs_save_$timestamp.jpg');

      final response = await http.get(Uri.parse(_imageUrl));
      if (response.statusCode == 200) {
        await tempFile.writeAsBytes(response.bodyBytes);
        await Gal.putImage(tempFile.path);
        if (mounted) _showToast('图片已保存到相册', Colors.green.shade600);
      } else {
        if (mounted) _showToast('保存失败，请重试', Colors.red.shade600);
      }
    } catch (e) {
      if (mounted) _showToast('保存失败：$e', Colors.red.shade600);
    } finally {
      if (mounted) setState(() => _isSavingImage = false);
    }
  }

  Future<void> _sharePost() async {
    final textBuffer = StringBuffer();
    if (_post.title.isNotEmpty) textBuffer.writeln(_post.title);
    if (_post.content.isNotEmpty) textBuffer.writeln(_post.content);
    if (_post.tags.isNotEmpty) {
      textBuffer.writeln(_post.tags.map((t) => '#$t').join(' '));
    }

    if (_imageUrl.isNotEmpty) {
      try {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/xhs_share_${DateTime.now().millisecondsSinceEpoch}.jpg');
        final response = await http.get(Uri.parse(_imageUrl));
        if (response.statusCode == 200) {
          await tempFile.writeAsBytes(response.bodyBytes);
          await Share.shareXFiles(
            [XFile(tempFile.path)],
            text: textBuffer.toString(),
          );
          return;
        }
      } catch (_) {}
    }

    await Share.share(textBuffer.toString());
  }

  void _showToast(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
  }
}

class _InteractionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _InteractionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}