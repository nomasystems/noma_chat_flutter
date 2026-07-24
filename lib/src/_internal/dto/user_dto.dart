import '../ui_debug_log.dart';
import '../util/json_safe.dart';

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
    id: jsonIdOr(
      json['id'] ?? json['userId'],
      '',
      onEmptyFromPresent: () => uiDebugLog(
        'UserDto',
        'fromJson: id/userId present but coerced to empty (raw: '
            '${json['id'] ?? json['userId']})',
      ),
    ),
    displayName: jsonStringOrNull(json['displayName']),
    avatarUrl: jsonStringOrNull(json['avatarUrl']),
    bio: jsonStringOrNull(json['bio']),
    email: jsonStringOrNull(json['email']),
    role: jsonStringOrNull(json['role']),
    active: jsonBoolOrNull(json['active']),
    custom: jsonMapOrNull(json['custom']),
    configuration: jsonMapOrNull(json['configuration']),
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
