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
    roomId: (json['roomId'] ?? json['id'] ?? '') as String,
    owner: json['owner'] as String?,
    name: json['name'] as String?,
    subject: json['subject'] as String?,
    audience: json['audience'] as String?,
    allowInvitations: json['allowInvitations'] as bool?,
    members: (json['members'] as List?)?.cast<String>(),
    publicToken: json['publicToken'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
    custom: json['custom'] as Map<String, dynamic>?,
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
  final bool pinned;
  final bool hidden;
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
    this.pinned = false,
    this.hidden = false,
    this.createdAt,
    this.avatarUrl,
    this.custom,
  });

  factory RoomDetailDto.fromJson(Map<String, dynamic> json) => RoomDetailDto(
    id: (json['id'] ?? '') as String,
    name: json['name'] as String?,
    subject: json['subject'] as String?,
    type: (json['type'] ?? 'group') as String,
    memberCount: (json['memberCount'] ?? 0) as int,
    userRole: (json['userRole'] ?? 'user') as String,
    config: json['config'] as Map<String, dynamic>?,
    muted: (json['muted'] ?? false) as bool,
    pinned: (json['pinned'] ?? false) as bool,
    hidden: (json['hidden'] ?? false) as bool,
    createdAt: json['createdAt'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
    custom: json['custom'] as Map<String, dynamic>?,
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
    rooms: (json['rooms'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    invitedRooms:
        (json['invitedRooms'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    hasMore: (json['hasMore'] ?? false) as bool,
  );
}
