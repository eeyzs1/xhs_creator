import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:xhs_creator/models/post.dart';
import 'package:xhs_creator/services/api_service.dart';
import 'package:xhs_creator/providers/post_provider.dart';
import 'package:xhs_creator/screens/preview_screen.dart';
import 'package:xhs_creator/theme/app_theme.dart';

class CreateScreen extends StatefulWidget {
  const CreateScreen({super.key});

  static void setTestImages(File? garment, File? street, {String? garmentOriginalUrl, String? streetOriginalUrl}) {
    _CreateScreenState.setTestImages(garment, street, garmentOriginalUrl: garmentOriginalUrl, streetOriginalUrl: streetOriginalUrl);
  }

  static void clearTestImages() {
    _CreateScreenState.clearTestImages();
  }

  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _styleController = TextEditingController();

  int _currentStep = 0;
  File? _garmentImage;
  File? _streetImage;
  bool _isGenerating = false;
  String? _generationError;

  Post? _createdPost;

  static File? _testGarmentImage;
  static File? _testStreetImage;
  static String? _testGarmentOriginalUrl;
  static String? _testStreetOriginalUrl;

  static void setTestImages(File? garment, File? street, {String? garmentOriginalUrl, String? streetOriginalUrl}) {
    _testGarmentImage = garment;
    _testStreetImage = street;
    _testGarmentOriginalUrl = garmentOriginalUrl;
    _testStreetOriginalUrl = streetOriginalUrl;
  }

  static void clearTestImages() {
    _testGarmentImage = null;
    _testStreetImage = null;
    _testGarmentOriginalUrl = null;
    _testStreetOriginalUrl = null;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _descriptionController.dispose();
    _styleController.dispose();
    super.dispose();
  }

  void _scrollToStep(int step) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final offset = step * 300.0;
        _scrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _pickImage(ImageSource source, bool isGarment) async {
    if (isGarment && _testGarmentImage != null) {
      setState(() {
        _garmentImage = _testGarmentImage;
      });
      return;
    }
    if (!isGarment && _testStreetImage != null) {
      setState(() {
        _streetImage = _testStreetImage;
      });
      return;
    }

    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (image != null) {
      setState(() {
        if (isGarment) {
          _garmentImage = File(image.path);
        } else {
          _streetImage = File(image.path);
        }
      });
    }
  }

  void _showImageSourcePicker(bool isGarment) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isGarment ? '选择服装照片' : '选择人物照片',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ImageSourceOption(
                      icon: Icons.camera_alt,
                      label: '拍照',
                      onTap: () {
                        Navigator.pop(context);
                        _pickImage(ImageSource.camera, isGarment);
                      },
                    ),
                    _ImageSourceOption(
                      icon: Icons.photo_library,
                      label: '相册',
                      onTap: () {
                        Navigator.pop(context);
                        _pickImage(ImageSource.gallery, isGarment);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _generate() async {
    if (_garmentImage == null || _streetImage == null) {
      _showSnackBar('请先上传服装照片和人物照片');
      return;
    }

    setState(() {
      _isGenerating = true;
      _generationError = null;
      _currentStep = 2;
    });
    _scrollToStep(2);

    try {
      final postProvider = context.read<PostProvider>();

      final post = await postProvider.createPost(
        garmentImage: _garmentImage!.path,
        streetImage: _streetImage!.path,
        style: _styleController.text,
        garmentOriginalUrl: _testGarmentOriginalUrl,
        streetOriginalUrl: _testStreetOriginalUrl,
      );

      if (post == null) throw Exception('创建笔记失败');

      _createdPost = post;

      final tryOnResult = await postProvider.generateTryOn(post.id);

      if (tryOnResult == null) throw Exception('试穿生成失败');

      final textResult = await postProvider.generateText(
        post.id,
        garmentDesc: _descriptionController.text.isNotEmpty
            ? _descriptionController.text
            : '服装穿搭',
        style: _styleController.text,
      );

      if (textResult != null) {
        _createdPost = textResult;
      }

      setState(() {
        _currentStep = 3;
        _isGenerating = false;
      });
      _scrollToStep(3);
    } catch (e) {
      setState(() {
        _generationError = e.toString();
        _isGenerating = false;
      });
      _showSnackBar('生成失败，请重试');
    }
  }

  void _saveAndPreview() {
    if (_createdPost == null) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PreviewScreen(post: _createdPost!),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.primaryRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('创作笔记'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStepIndicator(),
            _buildStep1Upload(),
            _buildStep2Text(),
            _buildStep3Generate(),
            _buildStep4Preview(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomAction(),
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: List.generate(4, (index) {
          final isActive = index <= _currentStep;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 3,
                    decoration: BoxDecoration(
                      color: isActive ? AppTheme.primaryRed : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (index < 3) const SizedBox(width: 4),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStep1Upload() {
    final isComplete = _garmentImage != null && _streetImage != null;
    return _StepSection(
      stepNumber: 1,
      title: '上传照片',
      subtitle: isComplete ? '已完成' : '上传服装和人物照片',
      isActive: _currentStep >= 0,
      isComplete: isComplete,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _ImageUploadCard(
                  label: '服装照片',
                  hint: '上传想要试穿的服装',
                  icon: Icons.checkroom,
                  image: _garmentImage,
                  onTap: () => _showImageSourcePicker(true),
                  onRemove: () => setState(() => _garmentImage = null),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ImageUploadCard(
                  label: '人物照片',
                  hint: '上传穿搭人物照片',
                  icon: Icons.person,
                  image: _streetImage,
                  onTap: () => _showImageSourcePicker(false),
                  onRemove: () => setState(() => _streetImage = null),
                ),
              ),
            ],
          ),
          if (_garmentImage != null && _streetImage != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _currentStep = 1);
                    _scrollToStep(1);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('下一步', style: TextStyle(fontSize: 15)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStep2Text() {
    if (_currentStep < 1) return const SizedBox.shrink();
    final isComplete = _descriptionController.text.isNotEmpty;

    return _StepSection(
      stepNumber: 2,
      title: '描述文案',
      subtitle: isComplete ? '已完成' : '描述服装和想要的风格',
      isActive: _currentStep >= 1,
      isComplete: isComplete,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: TextField(
              controller: _descriptionController,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '描述一下这件服装，比如：白色法式连衣裙，蕾丝边设计，适合约会穿…',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: TextField(
              controller: _styleController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '想要的文案风格，如：甜美可爱、高级感、文艺清新…',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
                prefixIcon: Icon(Icons.palette_outlined, color: Colors.grey.shade400),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildStyleChips(),
        ],
      ),
    );
  }

  Widget _buildStyleChips() {
    final styles = ['甜美可爱', '高级感', '文艺清新', '潮流街头', '温柔知性', '活泼元气'];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: styles.map((style) {
        final isSelected = _styleController.text == style;
        return GestureDetector(
          onTap: () => setState(() => _styleController.text = style),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primaryRed.withValues(alpha: 0.1) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isSelected ? AppTheme.primaryRed : Colors.grey.shade300),
            ),
            child: Text(
              style,
              style: TextStyle(
                color: isSelected ? AppTheme.primaryRed : Colors.grey.shade600,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStep3Generate() {
    if (_currentStep < 2) return const SizedBox.shrink();

    return _StepSection(
      stepNumber: 3,
      title: 'AI 生成',
      subtitle: _isGenerating ? '正在生成中…' : (_generationError != null ? '生成失败' : '生成试穿和文案'),
      isActive: _currentStep >= 2,
      isComplete: _createdPost != null && _createdPost!.hasContent,
      child: _isGenerating
          ? _buildGeneratingIndicator()
          : _generationError != null
              ? _buildErrorState()
              : _createdPost != null && _createdPost!.hasContent
                  ? _buildGenerationSuccess()
                  : const SizedBox.shrink(),
    );
  }

  Widget _buildGeneratingIndicator() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryRed),
            ),
          ),
          const SizedBox(height: 16),
          const Text('AI 正在为你生成…', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text(
            '正在分析服装和人物，生成试穿效果和爆款文案',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ProgressDot(label: '分析服装', isActive: true),
              _ProgressDot(label: '虚拟试穿', isActive: true),
              _ProgressDot(label: '生成文案', isActive: false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade400, size: 32),
          const SizedBox(height: 8),
          Text('生成失败，请重试', style: TextStyle(color: Colors.red.shade700, fontSize: 14)),
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: ElevatedButton(
              onPressed: _generate,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('重新生成'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerationSuccess() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green.shade600, size: 28),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('生成完成！', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF2E7D32))),
                SizedBox(height: 2),
                Text('试穿效果和文案已生成，可以预览和编辑', style: TextStyle(fontSize: 12, color: Color(0xFF4CAF50))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep4Preview() {
    if (_currentStep < 3 || _createdPost == null) return const SizedBox.shrink();

    return _StepSection(
      stepNumber: 4,
      title: '预览结果',
      subtitle: '查看生成效果',
      isActive: _currentStep >= 3,
      isComplete: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_createdPost!.hasResult || _garmentImage != null)
            Container(
              height: 240,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey.shade200,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _createdPost!.hasResult
                    ? CachedNetworkImage(
                        imageUrl: ApiService().resolveImageUrl(_createdPost!.resultImage),
                        fit: BoxFit.cover,
                        placeholder: (context, url) => _buildLocalImage(),
                        errorWidget: (context, url, error) => _buildLocalImage(),
                      )
                    : _buildLocalImage(),
              ),
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _createdPost!.title.isNotEmpty ? _createdPost!.title : '今日穿搭分享 ✨',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _createdPost!.content.isNotEmpty ? _createdPost!.content : '文案生成中…',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.6),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_createdPost!.tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _createdPost!.tags.map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryRed.withValues(alpha: 0.08),
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

  Widget _buildLocalImage() {
    if (_garmentImage != null) {
      return Image.file(_garmentImage!, fit: BoxFit.cover);
    }
    return Center(child: Icon(Icons.image_outlined, size: 48, color: Colors.grey.shade400));
  }

  Widget _buildBottomAction() {
    if (_isGenerating) {
      return Container(
        padding: const EdgeInsets.all(16),
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
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.grey.shade600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('生成中…', style: TextStyle(color: Colors.grey.shade600, fontSize: 15)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_currentStep == 3 && _createdPost != null) {
      return Container(
        padding: const EdgeInsets.all(16),
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
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _currentStep = 1;
                      _createdPost = null;
                    });
                    _scrollToStep(1);
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.primaryRed),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    minimumSize: const Size(0, 48),
                  ),
                  child: const Text('重新编辑', style: TextStyle(color: AppTheme.primaryRed)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveAndPreview,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    minimumSize: const Size(0, 48),
                  ),
                  child: const Text('预览保存'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    String buttonText;
    bool isEnabled;
    VoidCallback? onPressed;

    if (_currentStep == 0) {
      isEnabled = _garmentImage != null && _streetImage != null;
      buttonText = '下一步';
      onPressed = isEnabled
          ? () {
              setState(() => _currentStep = 1);
              _scrollToStep(1);
            }
          : null;
    } else if (_currentStep == 1) {
      isEnabled = true;
      buttonText = '开始生成';
      onPressed = _generate;
    } else {
      isEnabled = false;
      buttonText = '生成中…';
      onPressed = null;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: isEnabled ? AppTheme.primaryRed : Colors.grey.shade300,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              disabledForegroundColor: Colors.white70,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            child: Text(buttonText, style: const TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );
  }
}

class _StepSection extends StatelessWidget {
  final int stepNumber;
  final String title;
  final String subtitle;
  final bool isActive;
  final bool isComplete;
  final Widget child;

  const _StepSection({
    required this.stepNumber,
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.isComplete,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: isActive ? 1.0 : 0.4,
      child: Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
          ],
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
                    shape: BoxShape.circle,
                    color: isComplete
                        ? Colors.green
                        : isActive
                            ? AppTheme.primaryRed
                            : Colors.grey.shade300,
                  ),
                  child: Center(
                    child: isComplete
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : Text(
                            '$stepNumber',
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.grey.shade600,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _ImageUploadCard extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final File? image;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _ImageUploadCard({
    required this.label,
    required this.hint,
    required this.icon,
    this.image,
    required this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: image != null ? AppTheme.primaryRed.withValues(alpha: 0.3) : Colors.grey.shade200,
            width: image != null ? 2 : 1,
          ),
        ),
        child: image != null ? _buildImagePreview() : _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppTheme.primaryRed.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppTheme.primaryRed, size: 24),
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(hint, style: TextStyle(fontSize: 11, color: Colors.grey.shade400), textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildImagePreview() {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(image!, width: double.infinity, height: double.infinity, fit: BoxFit.cover),
        ),
        if (onRemove != null)
          Positioned(
            top: 6,
            right: 6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
            ),
            child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ),
      ],
    );
  }
}

class _ImageSourceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ImageSourceOption({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppTheme.primaryRed.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppTheme.primaryRed, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}

class _ProgressDot extends StatelessWidget {
  final String label;
  final bool isActive;

  const _ProgressDot({required this.label, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? AppTheme.primaryRed : Colors.grey.shade300,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, color: isActive ? AppTheme.primaryRed : Colors.grey.shade400)),
        ],
      ),
    );
  }
}
