import '../ui_debug_log.dart';
import '../util/json_safe.dart';

class RoomDto {
  final String roomId;
  final String? owner;
  final String? name;
  final String? subject;
  final String? audience;
  final bool? allowInvitations;
  final List<String>? members;
  final String? publicToken;
  final String? avatarUrl;
  final Map<String, dynamic>? custom;

  const RoomDto({
    required this.roomId,
    this.owner,
    this.name,
    this.subject,
    this.audience,
    this.allowInvitations,
    this.members,
    this.publicToken,
    this.avatarUrl,
    this.custom,
  });

  factory RoomDto.fromJson(Map<String, dynamic> json) => RoomDto(
    roomId: jsonIdOr(
      json['roomId'] ?? json['id'],
      '',
      onEmptyFromPresent: () => uiDebugLog(
        'RoomDto',
        'fromJson: roomId/id present but coerced to empty (raw: '
            '${json['roomId'] ?? json['id']})',
      ),
    ),
    owner: jsonStringOrNull(json['owner']),
    name: jsonStringOrNull(json['name']),
    subject: jsonStringOrNull(json['subject']),
    audience: jsonStringOrNull(json['audience']),
    allowInvitations: jsonBoolOrNull(json['allowInvitations']),
    members: jsonStringListOrNull(json['members']),
    publicToken: jsonStringOrNull(json['publicToken']),
    avatarUrl: jsonStringOrNull(json['avatarUrl']),
    custom: jsonMapOrNull(json['custom']),
  );
}

class RoomDetailDto {
  final String id;
  final String? name;
  final String? subject;
  final String type;
  final int memberCount;
  final String userRole;
  final Map<String, dynamic>? config;
  final bool muted;

  /// ISO-8601 timestamp when the notification mute expires, or `null` for
  /// a permanent mute / not muted.
  final String? muteUntil;
  final bool pinned;
  final bool hidden;

  /// Moderation mute for the current user in this room (admin/owner
  /// silenced them). Distinct from [muted] (notification preference).
  final bool selfMuted;
  final String? createdAt;
  final String? avatarUrl;
  final Map<String, dynamic>? custom;

  const RoomDetailDto({
    required this.id,
    this.name,
    this.subject,
    required this.type,
    required this.memberCount,
    required this.userRole,
    this.config,
    this.muted = false,
    this.muteUntil,
    this.pinned = false,
    this.hidden = false,
    this.selfMuted = false,
    this.createdAt,
    this.avatarUrl,
    this.custom,
  });

  factory RoomDetailDto.fromJson(Map<String, dynamic> json) => RoomDetailDto(
    id: jsonIdOr(
      json['id'],
      '',
      onEmptyFromPresent: () => uiDebugLog(
        'RoomDetailDto',
        'fromJson: id present but coerced to empty (raw: ${json['id']})',
      ),
    ),
    name: jsonStringOrNull(json['name']),
    subject: jsonStringOrNull(json['subject']),
    type: jsonStringOr(json['type'], 'group'),
    memberCount: jsonIntOr(json['memberCount'], 0),
    userRole: jsonStringOr(json['userRole'], 'user'),
    config: jsonMapOrNull(json['config']),
    muted: jsonBoolOr(json['muted'], false),
    muteUntil: jsonStringOrNull(json['muteUntil']),
    pinned: jsonBoolOr(json['pinned'], false),
    hidden: jsonBoolOr(json['hidden'], false),
    selfMuted: jsonBoolOr(json['selfMuted'], false),
    createdAt: jsonStringOrNull(json['createdAt']),
    avatarUrl: jsonStringOrNull(json['avatarUrl']),
    custom: jsonMapOrNull(json['custom']),
  );
}

class UserRoomsDto {
  final List<Map<String, dynamic>> rooms;
  final List<Map<String, dynamic>> invitedRooms;
  final bool hasMore;

  const UserRoomsDto({
    required this.rooms,
    this.invitedRooms = const [],
    this.hasMore = false,
  });

  factory UserRoomsDto.fromJson(Map<String, dynamic> json) => UserRoomsDto(
    rooms: _jsonMapList(json['rooms']),
    invitedRooms: _jsonMapList(json['invitedRooms']),
    hasMore: jsonBoolOr(json['hasMore'], false),
  );

  static List<Map<String, dynamic>> _jsonMapList(Object? value) {
    if (value is! List) return [];
    return [
      for (final e in value)
        if (e is Map<String, dynamic>) e,
    ];
  }
}
