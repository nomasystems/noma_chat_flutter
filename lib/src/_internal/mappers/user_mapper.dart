import '../../models/user.dart';
import '../../models/contact.dart';
import '../../models/room_user.dart';
import '../../models/managed_user_config.dart';
import '../dto/user_dto.dart';

class UserMapper {
  static void Function(String level, String message)? logger;

  static ChatUser fromDto(UserDto dto) => ChatUser(
    id: dto.id,
    displayName: dto.displayName,
    avatarUrl: dto.avatarUrl,
    bio: dto.bio,
    email: dto.email,
    role: _parseUserRole(dto.role),
    active: dto.active ?? true,
    custom: dto.custom,
    configuration: dto.configuration != null
        ? _parseConfiguration(dto.configuration!)
        : null,
  );

  static ChatUser fromJson(Map<String, dynamic> json) =>
      fromDto(UserDto.fromJson(json));

  static List<ChatUser> fromJsonList(List<dynamic> list) =>
      list.map((e) => fromJson(e as Map<String, dynamic>)).toList();

  static ChatContact contactFromJson(Map<String, dynamic> json) =>
      ChatContact(userId: (json['userId'] ?? '') as String);

  static RoomUser roomUserFromJson(Map<String, dynamic> json) => RoomUser(
    userId: (json['userId'] ?? '') as String,
    role: _parseRoomRole(json['role'] as String?),
  );

  static ManagedUserConfiguration managedConfigFromJson(
    Map<String, dynamic> json,
  ) => ManagedUserConfiguration(
    metadata: json['metadata'] as Map<String, dynamic>?,
    webhook: json['webhook'] != null
        ? _parseWebhookConfig(json['webhook'] as Map<String, dynamic>)
        : null,
  );

  static Map<String, dynamic> managedConfigToJson(
    ManagedUserConfiguration config,
  ) => {
    if (config.metadata != null) 'metadata': config.metadata,
    if (config.webhook != null)
      'webhook': {
        'url': config.webhook!.url,
        'auth': {
          'type': config.webhook!.authType.name,
          if (config.webhook!.token != null) 'token': config.webhook!.token,
          if (config.webhook!.username != null)
            'username': config.webhook!.username,
          if (config.webhook!.password != null)
            'password': config.webhook!.password,
        },
      },
  };

  static UserRole _parseUserRole(String? role) => switch (role) {
    null || 'user' => UserRole.user,
    'owner' => UserRole.owner,
    'admin' => UserRole.admin,
    _ => () {
      logger?.call(
        'warn',
        'UserMapper: unknown userRole "$role", defaulting to user',
      );
      return UserRole.user;
    }(),
  };

  static RoomRole _parseRoomRole(String? role) => switch (role) {
    null || 'member' || 'user' => RoomRole.member,
    'owner' => RoomRole.owner,
    'admin' => RoomRole.admin,
    _ => () {
      logger?.call(
        'warn',
        'UserMapper: unknown roomRole "$role", defaulting to member',
      );
      return RoomRole.member;
    }(),
  };

  static UserConfiguration _parseConfiguration(Map<String, dynamic> json) =>
      UserConfiguration(
        metadata: json['metadata'] as Map<String, dynamic>?,
        webhook: json['webhook'] != null
            ? _parseWebhookConfig(json['webhook'] as Map<String, dynamic>)
            : null,
      );

  static WebhookConfig _parseWebhookConfig(Map<String, dynamic> json) {
    final auth = json['auth'] as Map<String, dynamic>?;
    return WebhookConfig(
      url: (json['url'] ?? '') as String,
      authType: auth?['type'] == 'basic'
          ? WebhookAuthType.basic
          : WebhookAuthType.bearer,
      token: auth?['token'] as String?,
      username: auth?['username'] as String?,
      password: auth?['password'] as String?,
    );
  }
}
