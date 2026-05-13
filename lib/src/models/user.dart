import 'package:flutter/foundation.dart';

/// A chat platform user with profile information and role.
@immutable
class ChatUser {
  final String id;
  final String? displayName;
  final String? avatarUrl;
  final String? bio;
  final String? email;
  final UserRole role;
  final bool active;
  final Map<String, dynamic>? custom;
  final UserConfiguration? configuration;

  const ChatUser({
    required this.id,
    this.displayName,
    this.avatarUrl,
    this.bio,
    this.email,
    this.role = UserRole.user,
    this.active = true,
    this.custom,
    this.configuration,
  });

  ChatUser copyWith({
    String? id,
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? email,
    UserRole? role,
    bool? active,
    Map<String, dynamic>? custom,
    UserConfiguration? configuration,
  }) => ChatUser(
    id: id ?? this.id,
    displayName: displayName ?? this.displayName,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    bio: bio ?? this.bio,
    email: email ?? this.email,
    role: role ?? this.role,
    active: active ?? this.active,
    custom: custom ?? this.custom,
    configuration: configuration ?? this.configuration,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ChatUser && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ChatUser($id, $displayName)';
}

/// User-level configuration including webhook settings and custom metadata.
@immutable
class UserConfiguration {
  final Map<String, dynamic>? metadata;
  final WebhookConfig? webhook;

  const UserConfiguration({this.metadata, this.webhook});
}

/// Webhook configuration for server-to-server notifications.
@immutable
class WebhookConfig {
  final String url;
  final WebhookAuthType authType;
  final String? token;
  final String? username;
  final String? password;

  const WebhookConfig({
    required this.url,
    required this.authType,
    this.token,
    this.username,
    this.password,
  });
}

/// Authentication scheme expected by an outgoing webhook target.
enum WebhookAuthType { bearer, basic }

/// Global privilege level a user holds in the chat backend.
enum UserRole { owner, admin, user }
