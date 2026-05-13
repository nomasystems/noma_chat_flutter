import 'package:noma_chat/noma_chat.dart';

Map<String, dynamic> messageToMap(ChatMessage msg) => {
  'id': msg.id,
  'from': msg.from,
  'timestamp': msg.timestamp.toIso8601String(),
  if (msg.text != null) 'text': msg.text,
  'messageType': msg.messageType.name,
  if (msg.attachmentUrl != null) 'attachmentUrl': msg.attachmentUrl,
  if (msg.referencedMessageId != null)
    'referencedMessageId': msg.referencedMessageId,
  if (msg.reaction != null) 'reaction': msg.reaction,
  if (msg.reply != null) 'reply': msg.reply,
  if (msg.metadata != null) 'metadata': msg.metadata,
  if (msg.receipt != null) 'receipt': msg.receipt!.name,
  if (msg.isEdited) 'isEdited': true,
  if (msg.isDeleted) 'isDeleted': true,
  if (msg.isForwarded) 'isForwarded': true,
  if (msg.isSystem) 'isSystem': true,
  if (msg.mimeType != null) 'mimeType': msg.mimeType,
  if (msg.fileName != null) 'fileName': msg.fileName,
  if (msg.fileSize != null) 'fileSize': msg.fileSize,
  if (msg.thumbnailUrl != null) 'thumbnailUrl': msg.thumbnailUrl,
};

ChatMessage messageFromMap(
  Map<String, dynamic> map, {
  void Function(String)? onWarning,
}) => ChatMessage(
  id: map['id'] as String,
  from: map['from'] as String,
  timestamp: DateTime.parse(map['timestamp'] as String),
  text: map['text'] as String?,
  messageType: _parseMessageType(
    map['messageType'] as String?,
    onWarning: onWarning,
  ),
  attachmentUrl: map['attachmentUrl'] as String?,
  referencedMessageId: map['referencedMessageId'] as String?,
  reaction: map['reaction'] as String?,
  reply: map['reply'] as String?,
  metadata: (map['metadata'] as Map?)?.cast<String, dynamic>(),
  receipt: _parseReceiptStatus(map['receipt'] as String?, onWarning: onWarning),
  isEdited: map['isEdited'] as bool? ?? false,
  isDeleted: map['isDeleted'] as bool? ?? false,
  isForwarded: map['isForwarded'] as bool? ?? false,
  isSystem: map['isSystem'] as bool? ?? false,
  mimeType: map['mimeType'] as String?,
  fileName: map['fileName'] as String?,
  fileSize: map['fileSize'] as String?,
  thumbnailUrl: map['thumbnailUrl'] as String?,
);

Map<String, dynamic> roomToMap(ChatRoom room) => {
  'id': room.id,
  if (room.owner != null) 'owner': room.owner,
  if (room.name != null) 'name': room.name,
  if (room.subject != null) 'subject': room.subject,
  'audience': room.audience.name,
  'allowInvitations': room.allowInvitations,
  'members': room.members,
  if (room.publicToken != null) 'publicToken': room.publicToken,
  if (room.avatarUrl != null) 'avatarUrl': room.avatarUrl,
  if (room.custom != null) 'custom': room.custom,
};

ChatRoom roomFromMap(
  Map<String, dynamic> map, {
  void Function(String)? onWarning,
}) {
  final audienceStr = map['audience'] as String?;
  final RoomAudience audience;
  if (audienceStr == 'public') {
    audience = RoomAudience.public;
  } else if (audienceStr == 'unrestricted') {
    audience = RoomAudience.unrestricted;
  } else if (audienceStr == null || audienceStr == 'contacts') {
    audience = RoomAudience.contacts;
  } else {
    onWarning?.call(
      'Unknown RoomAudience "$audienceStr", defaulting to contacts',
    );
    audience = RoomAudience.contacts;
  }
  return ChatRoom(
    id: map['id'] as String,
    owner: map['owner'] as String?,
    name: map['name'] as String?,
    subject: map['subject'] as String?,
    audience: audience,
    allowInvitations: map['allowInvitations'] as bool? ?? false,
    members: (map['members'] as List?)?.cast<String>() ?? [],
    publicToken: map['publicToken'] as String?,
    avatarUrl: map['avatarUrl'] as String?,
    custom: (map['custom'] as Map?)?.cast<String, dynamic>(),
  );
}

Map<String, dynamic> userToMap(ChatUser user) => {
  'id': user.id,
  if (user.displayName != null) 'displayName': user.displayName,
  if (user.avatarUrl != null) 'avatarUrl': user.avatarUrl,
  if (user.bio != null) 'bio': user.bio,
  if (user.email != null) 'email': user.email,
  'role': user.role.name,
  'active': user.active,
  if (user.custom != null) 'custom': user.custom,
  if (user.configuration != null)
    'configuration': _configurationToMap(user.configuration!),
};

ChatUser userFromMap(
  Map<String, dynamic> map, {
  void Function(String)? onWarning,
}) {
  final roleStr = map['role'] as String?;
  final UserRole role;
  switch (roleStr) {
    case 'owner':
      role = UserRole.owner;
    case 'admin':
      role = UserRole.admin;
    case null || 'user':
      role = UserRole.user;
    default:
      onWarning?.call('Unknown UserRole "$roleStr", defaulting to user');
      role = UserRole.user;
  }
  return ChatUser(
    id: map['id'] as String,
    displayName: map['displayName'] as String?,
    avatarUrl: map['avatarUrl'] as String?,
    bio: map['bio'] as String?,
    email: map['email'] as String?,
    role: role,
    active: map['active'] as bool? ?? true,
    custom: (map['custom'] as Map?)?.cast<String, dynamic>(),
    configuration: map['configuration'] != null
        ? _configurationFromMap(
            (map['configuration'] as Map).cast<String, dynamic>(),
            onWarning: onWarning,
          )
        : null,
  );
}

Map<String, dynamic> roomDetailToMap(RoomDetail detail) => {
  'id': detail.id,
  if (detail.name != null) 'name': detail.name,
  if (detail.subject != null) 'subject': detail.subject,
  'type': detail.type.name,
  'memberCount': detail.memberCount,
  'userRole': detail.userRole.name,
  'allowInvitations': detail.config.allowInvitations,
  'muted': detail.muted,
  'pinned': detail.pinned,
  if (detail.hidden) 'hidden': true,
  if (detail.createdAt != null)
    'createdAt': detail.createdAt!.toIso8601String(),
  if (detail.avatarUrl != null) 'avatarUrl': detail.avatarUrl,
  if (detail.custom != null) 'custom': detail.custom,
};

RoomDetail roomDetailFromMap(
  Map<String, dynamic> map, {
  void Function(String)? onWarning,
}) {
  final typeStr = map['type'] as String?;
  final RoomType type;
  if (typeStr == 'oneToOne') {
    type = RoomType.oneToOne;
  } else if (typeStr == 'announcement') {
    type = RoomType.announcement;
  } else if (typeStr == null || typeStr == 'group') {
    type = RoomType.group;
  } else {
    onWarning?.call('Unknown RoomType "$typeStr", defaulting to group');
    type = RoomType.group;
  }
  return RoomDetail(
    id: map['id'] as String,
    name: map['name'] as String?,
    subject: map['subject'] as String?,
    type: type,
    memberCount: map['memberCount'] as int? ?? 0,
    userRole: _parseRoomRole(map['userRole'] as String?, onWarning: onWarning),
    config: RoomConfig(
      allowInvitations: map['allowInvitations'] as bool? ?? false,
    ),
    muted: map['muted'] as bool? ?? false,
    pinned: map['pinned'] as bool? ?? false,
    hidden: map['hidden'] as bool? ?? false,
    createdAt: map['createdAt'] != null
        ? DateTime.parse(map['createdAt'] as String)
        : null,
    avatarUrl: map['avatarUrl'] as String?,
    custom: (map['custom'] as Map?)?.cast<String, dynamic>(),
  );
}

RoomRole _parseRoomRole(String? role, {void Function(String)? onWarning}) {
  switch (role) {
    case 'owner':
      return RoomRole.owner;
    case 'admin':
      return RoomRole.admin;
    case null || 'member' || 'user':
      return RoomRole.member;
    default:
      onWarning?.call('Unknown RoomRole "$role", defaulting to member');
      return RoomRole.member;
  }
}

Map<String, dynamic> contactToMap(ChatContact contact) => {
  'userId': contact.userId,
};

ChatContact contactFromMap(Map<String, dynamic> map) =>
    ChatContact(userId: map['userId'] as String);

Map<String, dynamic> unreadRoomToMap(UnreadRoom unread) => {
  'roomId': unread.roomId,
  'unreadMessages': unread.unreadMessages,
  if (unread.lastMessage != null) 'lastMessage': unread.lastMessage,
  if (unread.lastMessageTime != null)
    'lastMessageTime': unread.lastMessageTime!.toIso8601String(),
  if (unread.lastMessageUserId != null)
    'lastMessageUserId': unread.lastMessageUserId,
  if (unread.lastMessageId != null) 'lastMessageId': unread.lastMessageId,
  if (unread.lastMessageType != null)
    'lastMessageType': unread.lastMessageType!.name,
  if (unread.lastMessageMimeType != null)
    'lastMessageMimeType': unread.lastMessageMimeType,
  if (unread.lastMessageFileName != null)
    'lastMessageFileName': unread.lastMessageFileName,
  if (unread.lastMessageDurationMs != null)
    'lastMessageDurationMs': unread.lastMessageDurationMs,
  if (unread.lastMessageIsDeleted) 'lastMessageIsDeleted': true,
  if (unread.lastMessageReactionEmoji != null)
    'lastMessageReactionEmoji': unread.lastMessageReactionEmoji,
  if (unread.name != null) 'name': unread.name,
  if (unread.avatarUrl != null) 'avatarUrl': unread.avatarUrl,
  if (unread.type != null) 'type': unread.type,
  if (unread.memberCount != null) 'memberCount': unread.memberCount,
  if (unread.userRole != null) 'userRole': unread.userRole!.name,
  if (unread.muted) 'muted': unread.muted,
  if (unread.pinned) 'pinned': unread.pinned,
  if (unread.hidden) 'hidden': true,
};

UnreadRoom unreadRoomFromMap(
  Map<String, dynamic> map, {
  void Function(String)? onWarning,
}) => UnreadRoom(
  roomId: map['roomId'] as String,
  unreadMessages: map['unreadMessages'] as int? ?? 0,
  lastMessage: map['lastMessage'] as String?,
  lastMessageTime: map['lastMessageTime'] != null
      ? DateTime.parse(map['lastMessageTime'] as String)
      : null,
  lastMessageUserId: map['lastMessageUserId'] as String?,
  lastMessageId: map['lastMessageId'] as String?,
  lastMessageType: map['lastMessageType'] != null
      ? _parseMessageType(
          map['lastMessageType'] as String?,
          onWarning: onWarning,
        )
      : null,
  lastMessageMimeType: map['lastMessageMimeType'] as String?,
  lastMessageFileName: map['lastMessageFileName'] as String?,
  lastMessageDurationMs: (map['lastMessageDurationMs'] as num?)?.toInt(),
  lastMessageIsDeleted: map['lastMessageIsDeleted'] as bool? ?? false,
  lastMessageReactionEmoji: map['lastMessageReactionEmoji'] as String?,
  name: map['name'] as String?,
  avatarUrl: map['avatarUrl'] as String?,
  type: map['type'] as String?,
  memberCount: map['memberCount'] as int?,
  userRole: map['userRole'] != null
      ? _parseRoomRole(map['userRole'] as String?, onWarning: onWarning)
      : null,
  muted: map['muted'] as bool? ?? false,
  pinned: map['pinned'] as bool? ?? false,
  hidden: map['hidden'] as bool? ?? false,
);

Map<String, dynamic> invitedRoomToMap(InvitedRoom invited) => {
  'roomId': invited.roomId,
  'invitedBy': invited.invitedBy,
};

InvitedRoom invitedRoomFromMap(Map<String, dynamic> map) => InvitedRoom(
  roomId: map['roomId'] as String,
  invitedBy: map['invitedBy'] as String,
);

MessageType _parseMessageType(
  String? type, {
  void Function(String)? onWarning,
}) {
  switch (type) {
    case 'attachment':
      return MessageType.attachment;
    case 'reaction':
      return MessageType.reaction;
    case 'reply':
      return MessageType.reply;
    case 'audio':
      return MessageType.audio;
    case 'forward':
      return MessageType.forward;
    case 'location':
      return MessageType.location;
    case null || 'regular':
      return MessageType.regular;
    default:
      onWarning?.call('Unknown MessageType "$type", defaulting to regular');
      return MessageType.regular;
  }
}

ReceiptStatus? _parseReceiptStatus(
  String? status, {
  void Function(String)? onWarning,
}) {
  switch (status) {
    case 'sent':
      return ReceiptStatus.sent;
    case 'delivered':
      return ReceiptStatus.delivered;
    case 'read':
      return ReceiptStatus.read;
    case null:
      return null;
    default:
      onWarning?.call('Unknown ReceiptStatus "$status", defaulting to null');
      return null;
  }
}

Map<String, dynamic> _configurationToMap(UserConfiguration config) => {
  if (config.metadata != null) 'metadata': config.metadata,
  if (config.webhook != null) 'webhook': _webhookToMap(config.webhook!),
};

UserConfiguration _configurationFromMap(
  Map<String, dynamic> map, {
  void Function(String)? onWarning,
}) => UserConfiguration(
  metadata: (map['metadata'] as Map?)?.cast<String, dynamic>(),
  webhook: map['webhook'] != null
      ? _webhookFromMap(
          (map['webhook'] as Map).cast<String, dynamic>(),
          onWarning: onWarning,
        )
      : null,
);

Map<String, dynamic> _webhookToMap(WebhookConfig webhook) => {
  'url': webhook.url,
  'authType': webhook.authType.name,
  if (webhook.token != null) 'token': webhook.token,
  if (webhook.username != null) 'username': webhook.username,
  if (webhook.password != null) 'password': webhook.password,
};

WebhookConfig _webhookFromMap(
  Map<String, dynamic> map, {
  void Function(String)? onWarning,
}) {
  final authStr = map['authType'] as String?;
  final WebhookAuthType authType;
  if (authStr == 'basic') {
    authType = WebhookAuthType.basic;
  } else if (authStr == null || authStr == 'bearer') {
    authType = WebhookAuthType.bearer;
  } else {
    onWarning?.call('Unknown WebhookAuthType "$authStr", defaulting to bearer');
    authType = WebhookAuthType.bearer;
  }
  return WebhookConfig(
    url: map['url'] as String? ?? '',
    authType: authType,
    token: map['token'] as String?,
    username: map['username'] as String?,
    password: map['password'] as String?,
  );
}

// --- Reactions ---

Map<String, dynamic> reactionToMap(AggregatedReaction r) => {
  'emoji': r.emoji,
  'count': r.count,
  'users': r.users,
};

AggregatedReaction reactionFromMap(Map<String, dynamic> map) =>
    AggregatedReaction(
      emoji: map['emoji'] as String? ?? '',
      count: map['count'] as int? ?? 0,
      users: (map['users'] as List?)?.cast<String>() ?? [],
    );

// --- Pins ---

Map<String, dynamic> pinToMap(MessagePin pin) => {
  'roomId': pin.roomId,
  'messageId': pin.messageId,
  'pinnedBy': pin.pinnedBy,
  'pinnedAt': pin.pinnedAt.toIso8601String(),
};

MessagePin pinFromMap(Map<String, dynamic> map) => MessagePin(
  roomId: map['roomId'] as String? ?? '',
  messageId: map['messageId'] as String? ?? '',
  pinnedBy: map['pinnedBy'] as String? ?? '',
  pinnedAt:
      DateTime.tryParse(map['pinnedAt'] as String? ?? '') ?? DateTime.now(),
);

// --- Read Receipts ---

Map<String, dynamic> receiptToMap(ReadReceipt r) => {
  'userId': r.userId,
  if (r.lastReadMessageId != null) 'lastReadMessageId': r.lastReadMessageId,
  if (r.lastReadAt != null) 'lastReadAt': r.lastReadAt!.toIso8601String(),
};

ReadReceipt receiptFromMap(Map<String, dynamic> map) => ReadReceipt(
  userId: map['userId'] as String? ?? '',
  lastReadMessageId: map['lastReadMessageId'] as String?,
  lastReadAt: map['lastReadAt'] != null
      ? DateTime.tryParse(map['lastReadAt'] as String)
      : null,
);
