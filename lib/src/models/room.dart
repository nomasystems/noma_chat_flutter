import 'room_user.dart';
import 'package:flutter/foundation.dart';

/// A chat room with its basic metadata and member list.
@immutable
class ChatRoom {
  final String id;
  final String? owner;
  final String? name;
  final String? subject;
  final RoomAudience audience;
  final bool allowInvitations;
  final List<String> members;
  final String? publicToken;
  final String? avatarUrl;
  final Map<String, dynamic>? custom;

  const ChatRoom({
    required this.id,
    this.owner,
    this.name,
    this.subject,
    this.audience = RoomAudience.contacts,
    this.allowInvitations = false,
    this.members = const [],
    this.publicToken,
    this.avatarUrl,
    this.custom,
  });

  ChatRoom copyWith({
    String? id,
    String? owner,
    String? name,
    String? subject,
    RoomAudience? audience,
    bool? allowInvitations,
    List<String>? members,
    String? publicToken,
    String? avatarUrl,
    Map<String, dynamic>? custom,
  }) => ChatRoom(
    id: id ?? this.id,
    owner: owner ?? this.owner,
    name: name ?? this.name,
    subject: subject ?? this.subject,
    audience: audience ?? this.audience,
    allowInvitations: allowInvitations ?? this.allowInvitations,
    members: members ?? this.members,
    publicToken: publicToken ?? this.publicToken,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    custom: custom ?? this.custom,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ChatRoom && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ChatRoom($id, $name)';
}

/// Detailed room information including the current user's role and room configuration.
@immutable
class RoomDetail {
  final String id;
  final String? name;
  final String? subject;
  final RoomType type;
  final int memberCount;
  final RoomRole userRole;
  final RoomConfig config;
  final bool muted;
  final bool pinned;
  final bool hidden;
  final DateTime? createdAt;
  final String? avatarUrl;
  final Map<String, dynamic>? custom;

  const RoomDetail({
    required this.id,
    this.name,
    this.subject,
    required this.type,
    required this.memberCount,
    required this.userRole,
    required this.config,
    this.muted = false,
    this.pinned = false,
    this.hidden = false,
    this.createdAt,
    this.avatarUrl,
    this.custom,
  });

  bool get isReadOnly =>
      type == RoomType.announcement && userRole != RoomRole.owner;
}

/// Room-level configuration flags.
@immutable
class RoomConfig {
  final bool allowInvitations;

  const RoomConfig({this.allowInvitations = false});
}

/// A public room found via discovery search.
@immutable
class DiscoveredRoom {
  final String id;
  final String? name;
  final String? subject;
  final String? owner;
  final int? memberCount;
  final String? avatarUrl;
  final Map<String, dynamic>? custom;

  const DiscoveredRoom({
    required this.id,
    this.name,
    this.subject,
    this.owner,
    this.memberCount,
    this.avatarUrl,
    this.custom,
  });
}

/// Who can discover and join a room.
///
/// - `public`: anyone can find and join.
/// - `contacts`: only the creator's contacts.
/// - `unrestricted`: invite-only, not listed.
enum RoomAudience { public, contacts, unrestricted }

/// Conversation shape. `oneToOne` rooms hold exactly two users and never
/// promote to a group; `announcement` rooms are read-only for non-admins.
enum RoomType { group, oneToOne, announcement }

/// Behavior for [ChatMembersApi.add]: invite without joining, accept/decline
/// a pending invitation, or invite-and-join atomically.
enum RoomUserMode { invite, acceptInvitation, declineInvitation, inviteAndJoin }
