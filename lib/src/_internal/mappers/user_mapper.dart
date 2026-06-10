import 'dart:convert';

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

  /// Parses a single contact from `/v1/contacts`.
  ///
  /// The backend (cht-noma `user_client_contacts`) emits each entry as
  /// `{"jid": "<userId>"}` — `jid` is a legacy XMPP/Jabber identifier name
  /// that survived in this single endpoint while the rest of the API uses
  /// `id` (`/v1/users`) or `userId` (most other places). We accept all
  /// three with a defined precedence: `jid` first (current backend
  /// reality), `userId` (forward-compat if the backend standardises), then
  /// `id`. Empty fallback only when none is present — surfaces a clear
  /// `ChatContact(userId: '')` that consumers can filter/log rather than
  /// silently swallowing a malformed row.
  static ChatContact contactFromJson(Map<String, dynamic> json) {
    final id = (json['jid'] ?? json['userId'] ?? json['id'] ?? '') as String;
    if (id.isEmpty) {
      logger?.call(
        'warn',
        'UserMapper.contactFromJson: contact entry has no jid/userId/id field',
      );
    }
    return ChatContact(userId: id);
  }

  static RoomUser roomUserFromJson(Map<String, dynamic> json) => RoomUser(
    userId: (json['userId'] ?? '') as String,
    // Backend `GET /v1/rooms/:roomId/users` emits `userRole`. Older
    // call sites and the WS payload sometimes use `role`. Accept both
    // so the role badge + promote/demote actions render consistently.
    role: _parseRoomRole((json['userRole'] ?? json['role']) as String?),
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
    if (config.webhook != null) 'webhook': _webhookToWire(config.webhook!),
  };

  // Wire shape expected by the backend (OpenAPI 1.0.0): `{ url, authMethod,
  // authToken }`. The richer SDK model (bearer token, or basic username +
  // password) is collapsed into a single `authToken`: bearer sends the token
  // verbatim; basic sends standard base64(`user:pass`) credentials so the
  // backend can forward `Authorization: Basic <authToken>`.
  static Map<String, dynamic> _webhookToWire(WebhookConfig webhook) {
    final token = _resolveAuthToken(webhook);
    return {
      'url': webhook.url,
      'authMethod': webhook.authType.name,
      if (token != null) 'authToken': token,
    };
  }

  static String? _resolveAuthToken(WebhookConfig webhook) {
    if (webhook.token != null) return webhook.token;
    if (webhook.authType == WebhookAuthType.basic &&
        webhook.username != null &&
        webhook.password != null) {
      return base64Encode(
        utf8.encode('${webhook.username}:${webhook.password}'),
      );
    }
    return null;
  }

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
    // Backend 1.0.0 emits a flat `{ authMethod, authToken }`. Older payloads
    // (and pre-1.0 cached blobs) used a nested `auth` object; accept both so a
    // stale server or cache never crashes the mapper.
    final auth = json['auth'] as Map<String, dynamic>?;
    final method = (json['authMethod'] ?? auth?['type']) as String?;
    return WebhookConfig(
      url: (json['url'] ?? '') as String,
      authType: method == 'basic'
          ? WebhookAuthType.basic
          : WebhookAuthType.bearer,
      token: (json['authToken'] ?? auth?['token']) as String?,
      username: auth?['username'] as String?,
      password: auth?['password'] as String?,
    );
  }
}
