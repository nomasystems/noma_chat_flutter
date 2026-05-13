class UserDto {
  final String id;
  final String? displayName;
  final String? avatarUrl;
  final String? bio;
  final String? email;
  final String? role;
  final bool? active;
  final Map<String, dynamic>? custom;
  final Map<String, dynamic>? configuration;

  const UserDto({
    required this.id,
    this.displayName,
    this.avatarUrl,
    this.bio,
    this.email,
    this.role,
    this.active,
    this.custom,
    this.configuration,
  });

  factory UserDto.fromJson(Map<String, dynamic> json) => UserDto(
        id: (json['id'] ?? json['userId'] ?? '') as String,
        displayName: json['displayName'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        bio: json['bio'] as String?,
        email: json['email'] as String?,
        role: json['role'] as String?,
        active: json['active'] as bool?,
        custom: json['custom'] as Map<String, dynamic>?,
        configuration: json['configuration'] as Map<String, dynamic>?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (displayName != null) 'displayName': displayName,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (bio != null) 'bio': bio,
        if (email != null) 'email': email,
        if (role != null) 'role': role,
        if (active != null) 'active': active,
        if (custom != null) 'custom': custom,
        if (configuration != null) 'configuration': configuration,
      };
}
