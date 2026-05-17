class User {
  final String id;
  final String username;
  final String nickname;
  final String avatar;
  final DateTime createdAt;

  const User({
    required this.id,
    required this.username,
    this.nickname = '小红书创作者',
    this.avatar = '',
    required this.createdAt,
  });

  User copyWith({
    String? id,
    String? username,
    String? nickname,
    String? avatar,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '小红书创作者',
      avatar: json['avatar'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'nickname': nickname,
      'avatar': avatar,
      'created_at': createdAt.toIso8601String(),
    };
  }
}