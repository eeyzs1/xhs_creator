class Post {
  final String id;
  final String userId;
  final String garmentImage;
  final String streetImage;
  final String resultImage;
  final String title;
  final String content;
  final List<String> tags;
  final String style;
  final List<Map<String, dynamic>> chatHistory;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Post({
    required this.id,
    required this.userId,
    required this.garmentImage,
    required this.streetImage,
    this.resultImage = '',
    this.title = '',
    this.content = '',
    this.tags = const [],
    this.style = '',
    this.chatHistory = const [],
    this.status = 'draft',
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isDraft => status == 'draft';
  bool get hasResult => resultImage.isNotEmpty;
  bool get hasContent => title.isNotEmpty || content.isNotEmpty;

  Post copyWith({
    String? id,
    String? userId,
    String? garmentImage,
    String? streetImage,
    String? resultImage,
    String? title,
    String? content,
    List<String>? tags,
    String? style,
    List<Map<String, dynamic>>? chatHistory,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Post(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      garmentImage: garmentImage ?? this.garmentImage,
      streetImage: streetImage ?? this.streetImage,
      resultImage: resultImage ?? this.resultImage,
      title: title ?? this.title,
      content: content ?? this.content,
      tags: tags ?? this.tags,
      style: style ?? this.style,
      chatHistory: chatHistory ?? this.chatHistory,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      garmentImage: json['garment_image'] as String? ?? '',
      streetImage: json['street_image'] as String? ?? '',
      resultImage: json['result_image'] as String? ?? '',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      style: json['style'] as String? ?? '',
      chatHistory: (json['chat_history'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      status: json['status'] as String? ?? 'draft',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'garment_image': garmentImage,
      'street_image': streetImage,
      'result_image': resultImage,
      'title': title,
      'content': content,
      'tags': tags,
      'style': style,
      'chat_history': chatHistory,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toUpdateJson() {
    final json = <String, dynamic>{};
    if (title.isNotEmpty) json['title'] = title;
    if (content.isNotEmpty) json['content'] = content;
    if (tags.isNotEmpty) json['tags'] = tags;
    if (resultImage.isNotEmpty) json['result_image'] = resultImage;
    if (style.isNotEmpty) json['style'] = style;
    if (chatHistory.isNotEmpty) json['chat_history'] = chatHistory;
    json['status'] = status;
    return json;
  }
}
