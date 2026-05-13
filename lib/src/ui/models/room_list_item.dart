import 'package:noma_chat/noma_chat.dart';

/// View model for a room in the room list, combining room metadata with unread/presence state.
class RoomListItem {
  final String id;
  final String? name;
  final String? subject;
  final String? avatarUrl;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final String? lastMessageUserId;
  final String? lastMessageId;
  final ReceiptStatus? lastMessageReceipt;
  final MessageType? lastMessageType;
  final String? lastMessageMimeType;
  final String? lastMessageFileName;
  final int? lastMessageDurationMs;
  final bool lastMessageIsDeleted;
  final String? lastMessageReactionEmoji;
  final int unreadCount;
  final bool muted;
  final bool pinned;
  final bool hidden;
  final bool isGroup;
  final bool isAnnouncement;
  final bool? isOnline;
  final PresenceStatus? presenceStatus;
  final String? otherUserId;
  final RoomRole? userRole;
  final int? memberCount;
  final Map<String, dynamic>? custom;
  final Set<String> typingUserIds;

  /// User-facing label for the room.
  ///
  /// Returns [name] when it is non-empty, falling back to [id] otherwise so
  /// the UI always has something to render. Consumers can override the
  /// label by mutating [name] (e.g. via a metadata resolver) — this getter
  /// will pick up that override automatically.
  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    return id;
  }

  const RoomListItem({
    required this.id,
    this.name,
    this.subject,
    this.avatarUrl,
    this.lastMessage,
    this.lastMessageTime,
    this.lastMessageUserId,
    this.lastMessageId,
    this.lastMessageReceipt,
    this.lastMessageType,
    this.lastMessageMimeType,
    this.lastMessageFileName,
    this.lastMessageDurationMs,
    this.lastMessageIsDeleted = false,
    this.lastMessageReactionEmoji,
    this.unreadCount = 0,
    this.muted = false,
    this.pinned = false,
    this.hidden = false,
    this.isGroup = false,
    this.isAnnouncement = false,
    this.isOnline,
    this.presenceStatus,
    this.otherUserId,
    this.userRole,
    this.memberCount,
    this.custom,
    this.typingUserIds = const {},
  });

  bool get isInvitation => custom?['invited'] == true;

  bool get isReadOnly => isAnnouncement && userRole != RoomRole.owner;

  static const _absent = Object();

  RoomListItem copyWith({
    Object? name = _absent,
    Object? subject = _absent,
    Object? avatarUrl = _absent,
    Object? lastMessage = _absent,
    Object? lastMessageTime = _absent,
    Object? lastMessageUserId = _absent,
    Object? lastMessageId = _absent,
    Object? lastMessageReceipt = _absent,
    Object? lastMessageType = _absent,
    Object? lastMessageMimeType = _absent,
    Object? lastMessageFileName = _absent,
    Object? lastMessageDurationMs = _absent,
    bool? lastMessageIsDeleted,
    Object? lastMessageReactionEmoji = _absent,
    int? unreadCount,
    bool? muted,
    bool? pinned,
    bool? hidden,
    bool? isGroup,
    bool? isAnnouncement,
    Object? isOnline = _absent,
    Object? presenceStatus = _absent,
    Object? otherUserId = _absent,
    Object? userRole = _absent,
    int? memberCount,
    Object? custom = _absent,
    Set<String>? typingUserIds,
  }) {
    return RoomListItem(
      id: id,
      name: identical(name, _absent) ? this.name : name as String?,
      subject:
          identical(subject, _absent) ? this.subject : subject as String?,
      avatarUrl:
          identical(avatarUrl, _absent)
              ? this.avatarUrl
              : avatarUrl as String?,
      lastMessage:
          identical(lastMessage, _absent)
              ? this.lastMessage
              : lastMessage as String?,
      lastMessageTime:
          identical(lastMessageTime, _absent)
              ? this.lastMessageTime
              : lastMessageTime as DateTime?,
      lastMessageUserId:
          identical(lastMessageUserId, _absent)
              ? this.lastMessageUserId
              : lastMessageUserId as String?,
      lastMessageId:
          identical(lastMessageId, _absent)
              ? this.lastMessageId
              : lastMessageId as String?,
      lastMessageReceipt:
          identical(lastMessageReceipt, _absent)
              ? this.lastMessageReceipt
              : lastMessageReceipt as ReceiptStatus?,
      lastMessageType:
          identical(lastMessageType, _absent)
              ? this.lastMessageType
              : lastMessageType as MessageType?,
      lastMessageMimeType:
          identical(lastMessageMimeType, _absent)
              ? this.lastMessageMimeType
              : lastMessageMimeType as String?,
      lastMessageFileName:
          identical(lastMessageFileName, _absent)
              ? this.lastMessageFileName
              : lastMessageFileName as String?,
      lastMessageDurationMs:
          identical(lastMessageDurationMs, _absent)
              ? this.lastMessageDurationMs
              : lastMessageDurationMs as int?,
      lastMessageIsDeleted:
          lastMessageIsDeleted ?? this.lastMessageIsDeleted,
      lastMessageReactionEmoji:
          identical(lastMessageReactionEmoji, _absent)
              ? this.lastMessageReactionEmoji
              : lastMessageReactionEmoji as String?,
      unreadCount: unreadCount ?? this.unreadCount,
      muted: muted ?? this.muted,
      pinned: pinned ?? this.pinned,
      hidden: hidden ?? this.hidden,
      isGroup: isGroup ?? this.isGroup,
      isAnnouncement: isAnnouncement ?? this.isAnnouncement,
      isOnline:
          identical(isOnline, _absent) ? this.isOnline : isOnline as bool?,
      presenceStatus:
          identical(presenceStatus, _absent)
              ? this.presenceStatus
              : presenceStatus as PresenceStatus?,
      otherUserId:
          identical(otherUserId, _absent)
              ? this.otherUserId
              : otherUserId as String?,
      userRole:
          identical(userRole, _absent)
              ? this.userRole
              : userRole as RoomRole?,
      memberCount: memberCount ?? this.memberCount,
      custom:
          identical(custom, _absent)
              ? this.custom
              : custom as Map<String, dynamic>?,
      typingUserIds: typingUserIds ?? this.typingUserIds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomListItem &&
          other.id == id &&
          other.name == name &&
          other.subject == subject &&
          other.avatarUrl == avatarUrl &&
          other.lastMessage == lastMessage &&
          other.lastMessageTime == lastMessageTime &&
          other.lastMessageUserId == lastMessageUserId &&
          other.lastMessageId == lastMessageId &&
          other.lastMessageReceipt == lastMessageReceipt &&
          other.lastMessageType == lastMessageType &&
          other.lastMessageMimeType == lastMessageMimeType &&
          other.lastMessageFileName == lastMessageFileName &&
          other.lastMessageDurationMs == lastMessageDurationMs &&
          other.lastMessageIsDeleted == lastMessageIsDeleted &&
          other.lastMessageReactionEmoji == lastMessageReactionEmoji &&
          other.unreadCount == unreadCount &&
          other.muted == muted &&
          other.pinned == pinned &&
          other.hidden == hidden &&
          other.isGroup == isGroup &&
          other.isAnnouncement == isAnnouncement &&
          other.isOnline == isOnline &&
          other.presenceStatus == presenceStatus &&
          other.otherUserId == otherUserId &&
          other.userRole == userRole &&
          other.memberCount == memberCount &&
          identical(custom, other.custom) &&
          _setEquals(other.typingUserIds, typingUserIds);

  @override
  int get hashCode => Object.hashAll([
        id,
        name,
        subject,
        avatarUrl,
        lastMessage,
        lastMessageTime,
        lastMessageUserId,
        lastMessageId,
        lastMessageReceipt,
        lastMessageType,
        lastMessageMimeType,
        lastMessageFileName,
        lastMessageDurationMs,
        lastMessageIsDeleted,
        lastMessageReactionEmoji,
        unreadCount,
        muted,
        pinned,
        hidden,
        isGroup,
        isAnnouncement,
        isOnline,
        presenceStatus,
        otherUserId,
        userRole,
        memberCount,
        Object.hashAllUnordered(typingUserIds),
      ]);

  @override
  String toString() =>
      'RoomListItem(id: $id, name: $name, unread: $unreadCount)';
}

bool _setEquals(Set<String> a, Set<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  return a.containsAll(b);
}
