import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';

/// A chat platform user with profile information and role.
///
/// Equality is id-based so user collections (`Set<ChatUser>`, lookup
/// maps) deduplicate by `id` regardless of churn in the profile fields.
@Freezed(equal: false)
abstract class ChatUser with _$ChatUser {
  const ChatUser._();

  const factory ChatUser({
    required String id,
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? email,
    @Default(UserRole.user) UserRole role,
    @Default(true) bool active,
    Map<String, dynamic>? custom,
    UserConfiguration? configuration,
  }) = _ChatUser;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ChatUser && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ChatUser($id, $displayName)';
}

/// User-level configuration including webhook settings and custom metadata.
@freezed
abstract class UserConfiguration with _$UserConfiguration {
  const factory UserConfiguration({
    Map<String, dynamic>? metadata,
    WebhookConfig? webhook,
  }) = _UserConfiguration;
}

/// Webhook configuration for server-to-server notifications.
@freezed
abstract class WebhookConfig with _$WebhookConfig {
  const factory WebhookConfig({
    required String url,
    required WebhookAuthType authType,
    String? token,
    String? username,
    String? password,
  }) = _WebhookConfig;
}

/// Authentication scheme expected by an outgoing webhook target.
enum WebhookAuthType { bearer, basic }

/// Global privilege level a user holds in the chat backend.
enum UserRole { owner, admin, user }
