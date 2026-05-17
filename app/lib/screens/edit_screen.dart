import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:xhs_creator/models/post.dart';
import 'package:xhs_creator/services/api_service.dart';
import 'package:xhs_creator/providers/post_provider.dart';
import 'package:xhs_creator/theme/app_theme.dart';

class EditScreen extends StatefulWidget {
  final Post post;

  const EditScreen({super.key, required this.post});

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  late Post _post;
  final TextEditingController _chatController = TextEditingController();
  final TextEditingController _imageEditController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _chatFocusNode = FocusNode();

  final List<_ChatMessage> _chatMessages = [];
  bool _isProcessing = false;
  bool _isEditingImage = false;
  bool _isEditingImageProcessing = false;
  bool _isSavingImage = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _loadChatHistory();
  }

  @override
  void dispose() {
    _chatController.dispose();
    _imageEditController.dispose();
    _scrollController.dispose();
    _chatFocusNode.dispose();
    super.dispose();
  }

  void _loadChatHistory() {
    for (final entry in _post.chatHistory) {
      final role = entry['role'] as String? ?? 'user';
      final content = entry['content'] as String? ?? '';
      _chatMessages.add(_ChatMessage(role: role, content: content));
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _isProcessing || _isEditingImageProcessing) return;

    _chatController.clear();

    setState(() {
      _chatMessages.add(_ChatMessage(role: 'user', content: text));
      _isProcessing = true;
    });
    _scrollToBottom();

    try {
      final postProvider = context.read<PostProvider>();
      final result = await postProvider.modifyPostWithInstruction(_post.id, text);

      if (result != null) {
        setState(() {
          _post = result;
          _chatMessages.add(const _ChatMessage(role: 'assistant', content: '已根据你的要求修改了笔记内容，看看效果如何？'));
          _isProcessing = false;
        });
      } else {
        setState(() {
          _chatMessages.add(const _ChatMessage(role: 'assistant', content: '抱歉，修改失败了，请换一种方式描述你的需求。'));
          _isProcessing = false;
        });
      }
    } catch (e) {
      setState(() {
        _chatMessages.add(_ChatMessage(role: 'assistant', content: '出了点问题：${e.toString()}，请重试。'));
        _isProcessing = false;
      });
    }

    _scrollToBottom();
  }

  Future<void> _sendImageEdit() async {
    final text = _imageEditController.text.trim();
    if (text.isEmpty || _isEditingImageProcessing) return;

    _imageEditController.clear();

    setState(() {
      _chatMessages.add(_ChatMessage(role: 'user', content: '🖼️ 图片: $text'));
      _isEditingImageProcessing = true;
      _isEditingImage = false;
    });
    _scrollToBottom();

    try {
      final postProvider = context.read<PostProvider>();
      final result = await postProvider.modifyImageWithInstruction(_post.id, text);

      if (result != null) {
        setState(() {
          _post = result;
          _chatMessages.add(const _ChatMessage(role: 'assistant', content: '已根据你的要求修改了图片，看看效果如何？'));
          _isEditingImageProcessing = false;
        });
      } else {
        setState(() {
          _chatMessages.add(const _ChatMessage(role: 'assistant', content: '抱歉，图片修改失败了，请换一种方式描述你的需求。'));
          _isEditingImageProcessing = false;
        });
      }
    } catch (e) {
      setState(() {
        _chatMessages.add(_ChatMessage(role: 'assistant', content: '出了点问题：${e.toString()}，请重试。'));
        _isEditingImageProcessing = false;
      });
    }

    _scrollToBottom();
  }

  void _applyChanges() {
    Navigator.of(context).pop(_post);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('编辑笔记'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton(
            onPressed: _applyChanges,
            child: const Text('完成', style: TextStyle(color: AppTheme.primaryRed, fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(child: _buildPostPreview()),
                if (_isEditingImage) SliverToBoxAdapter(child: _buildImageEditBar()),
                SliverToBoxAdapter(child: _buildChatSection()),
              ],
            ),
          ),
          if (!_isEditingImage) _buildChatInput(),
        ],
      ),
    );
  }

  Widget _buildPostPreview() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_post.hasResult) _buildImagePreview(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('当前内容', style: TextStyle(color: AppTheme.primaryRed, fontSize: 11, fontWeight: FontWeight.w500)),
                    ),
                    const Spacer(),
                    Icon(Icons.access_time, size: 14, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Text(_formatDate(_post.updatedAt), style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _post.title.isNotEmpty ? _post.title : '未命名笔记',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _post.content.isNotEmpty ? _post.content : '暂无内容，试试让AI帮你生成文案吧',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.7),
                ),
                if (_post.tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _post.tags.map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryRed.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('#$tag', style: const TextStyle(fontSize: 12, color: AppTheme.primaryRed)),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    final imageUrl = _post.resultImage;
    final fullUrl = ApiService().resolveImageUrl(imageUrl);

    if (fullUrl.isEmpty) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Stack(
        children: [
          GestureDetector(
            onLongPress: _isSavingImage ? null : _saveImageToGallery,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                CachedNetworkImage(
                  imageUrl: fullUrl,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    height: 200,
                    color: Colors.grey.shade200,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.grey.shade400))),
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 200,
                    color: Colors.grey.shade200,
                    child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                  ),
                ),
                if (_isSavingImage)
                  Container(
                    height: 200,
                    color: Colors.black26,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          SizedBox(height: 8),
                          Text('保存中...', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: GestureDetector(
              onTap: _isEditingImage
                  ? () => setState(() => _isEditingImage = false)
                  : () => setState(() => _isEditingImage = true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.edit, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      _isEditingImage ? '取消' : '编辑图片',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageEditBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryRed.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.primaryRed.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.brush, color: AppTheme.primaryRed, size: 14),
              ),
              const SizedBox(width: 8),
              const Text('编辑图片', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              Icon(Icons.info_outline, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 4),
              Text('如：把衣服改成红色', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: _imageEditController,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendImageEdit(),
                    decoration: InputDecoration(
                      hintText: '描述你对图片的修改需求...',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _sendImageEdit,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _isEditingImageProcessing ? Colors.grey.shade300 : AppTheme.primaryRed,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _isEditingImageProcessing
                      ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))))
                      : const Icon(Icons.send, color: Colors.white, size: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChatSection() {
    if (_chatMessages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryRed.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome, color: AppTheme.primaryRed, size: 24),
                  ),
                  const SizedBox(height: 12),
                  const Text('AI 助手帮你修改笔记', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text('用自然语言描述你想要的修改', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildSuggestionChips(),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('修改记录', style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
          ),
          ..._chatMessages.map((msg) => _buildChatBubble(msg)),
          if (_isProcessing) _buildTypingIndicator(),
        ],
      ),
    );
  }

  Widget _buildSuggestionChips() {
    final suggestions = ['让文案更活泼', '换一种风格', '加更多emoji', '标题更吸引人', '内容更详细', '换个文艺风格'];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: suggestions.map((s) {
        return GestureDetector(
          onTap: () {
            _chatController.text = s;
            _sendMessage();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(s, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildChatBubble(_ChatMessage message) {
    final isUser = message.role == 'user';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.primaryRed.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, color: AppTheme.primaryRed, size: 16),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? AppTheme.primaryRed : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(4),
                  bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
                ),
                boxShadow: isUser
                    ? null
                    : [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
                      ],
              ),
              child: SelectableText(
                message.content,
                style: TextStyle(fontSize: 14, color: isUser ? Colors.white : Colors.grey.shade800, height: 1.5),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle),
              child: const Icon(Icons.person, color: Colors.grey, size: 16),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.primaryRed.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome, color: AppTheme.primaryRed, size: 16),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TypingDot(delay: 0),
                _TypingDot(delay: 200),
                _TypingDot(delay: 400),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatInput() {
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
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: TextField(
                  controller: _chatController,
                  focusNode: _chatFocusNode,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: InputDecoration(
                    hintText: '描述你想要的修改…',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _sendMessage,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppTheme.primaryRed, AppTheme.primaryRedLight]),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: AppTheme.primaryRed.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                child: _isProcessing || _isEditingImageProcessing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                      )
                    : const Icon(Icons.send, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveImageToGallery() async {
    final imageUrl = _post.resultImage;
    final fullUrl = ApiService().resolveImageUrl(imageUrl);
    if (fullUrl.isEmpty) return;

    setState(() => _isSavingImage = true);

    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/xhs_edit_save_$timestamp.jpg');

      final response = await http.get(Uri.parse(fullUrl));
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
    return '${date.month}月${date.day}日 ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _ChatMessage {
  final String role;
  final String content;

  const _ChatMessage({required this.role, required this.content});
}

class _TypingDot extends StatefulWidget {
  final int delay;

  const _TypingDot({required this.delay});

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: AppTheme.primaryRed.withValues(alpha: 0.4 + _controller.value * 0.6),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
