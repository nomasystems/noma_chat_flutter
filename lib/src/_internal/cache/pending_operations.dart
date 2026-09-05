part of 'offline_queue.dart';

sealed class PendingOperation {
  final String id;
  final DateTime createdAt;
  final int attempts;
  final DateTime? nextRetryAt;

  PendingOperation({
    required this.id,
    DateTime? createdAt,
    this.attempts = 0,
    this.nextRetryAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Id of the optimistic row this operation was queued for, when it has
  /// one — the bubble the UI is showing as failed while the queue holds
  /// its retry. Only the send-shaped operations carry it; everything else
  /// (edits, reactions, membership) acts on already-confirmed server state
  /// and reports `null`. [OfflineQueue.removeForOptimisticId] matches on
  /// this so a row the user discarded does not go out on the next drain.
  String? get optimisticId => null;

  /// Returns a copy with bumped retry metadata. The drain loop calls
  /// this after a failed attempt to re-enqueue the same operation
  /// with `attempts + 1` and an optional `nextRetryAt` backoff
  /// timestamp. Subclasses preserve every other field unchanged.
  PendingOperation withRetry({int? attempts, DateTime? nextRetryAt});

  /// Serializes this operation to a `Map` suitable for the
  /// [ChatLocalDatasource.saveOfflineQueue] hand-off. Every concrete
  /// subclass overrides this with its own payload, including a `'type'`
  /// discriminator (`sendMessage`, `editMessage`, …) that
  /// [PendingOperation.fromJson] reads back to construct the right class.
  ///
  /// Concrete subclasses should spread [baseJson] first so the shared
  /// metadata (`id`, `createdAt`, `attempts`) lands at the top:
  ///
  /// ```dart
  /// @override
  /// Map<String, dynamic> toJson() => {
  ///   ...baseJson(),
  ///   'type': 'editMessage',
  ///   'roomId': roomId,
  ///   ...
  /// };
  /// ```
  Map<String, dynamic> toJson();

  /// Common fields shared by every concrete subclass. Spread at the top
  /// of each [toJson] map. Kept as a method (not a getter) for symmetry
  /// with the [toJson] override.
  Map<String, dynamic> baseJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'attempts': attempts,
  };
}

final class PendingSendMessage extends PendingOperation {
  final String roomId;
  final String? text;
  final MessageType messageType;
  final String? referencedMessageId;
  final String? reaction;
  final String? attachmentUrl;
  final String? attachmentId;
  final String? sourceRoomId;
  final Map<String, dynamic>? metadata;
  final String? tempId;

  /// Idempotency key reused across every retry of this queued send so a
  /// delivery that actually reached the server (before the failure
  /// surfaced) is not duplicated on drain. See [ChatMessagesApi.send].
  final String? clientMessageId;

  @override
  String? get optimisticId => tempId;

  PendingSendMessage({
    required super.id,
    required this.roomId,
    this.text,
    this.messageType = MessageType.regular,
    this.referencedMessageId,
    this.reaction,
    this.attachmentUrl,
    this.attachmentId,
    this.sourceRoomId,
    this.metadata,
    this.tempId,
    this.clientMessageId,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'sendMessage',
    'roomId': roomId,
    if (text != null) 'text': text,
    'messageType': messageType.name,
    if (referencedMessageId != null) 'referencedMessageId': referencedMessageId,
    if (reaction != null) 'reaction': reaction,
    if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
    if (attachmentId != null) 'attachmentId': attachmentId,
    if (sourceRoomId != null) 'sourceRoomId': sourceRoomId,
    if (metadata != null) 'metadata': metadata,
    if (tempId != null) 'tempId': tempId,
    if (clientMessageId != null) 'clientMessageId': clientMessageId,
  };

  @override
  PendingSendMessage withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingSendMessage(
        id: id,
        roomId: roomId,
        text: text,
        messageType: messageType,
        referencedMessageId: referencedMessageId,
        reaction: reaction,
        attachmentUrl: attachmentUrl,
        attachmentId: attachmentId,
        sourceRoomId: sourceRoomId,
        metadata: metadata,
        tempId: tempId,
        clientMessageId: clientMessageId,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingSendAttachment extends PendingOperation {
  final String roomId;

  /// Raw bytes of the not-yet-uploaded attachment (photo/video/audio/file).
  /// Persisted base64-encoded via [toJson] — see [OfflineQueue._persist] —
  /// so a queued attachment survives an app restart, not just a
  /// reconnect within the same process. The encoding itself is memoized in
  /// [_cachedBase64OfBytes] so repeated persists of an unchanged queue don't
  /// re-encode these bytes every time. `NomaChatClient.enqueueOfflineAttachment`
  /// rejects anything over `CacheConfig.offlineQueueMaxAttachmentBytes`
  /// before it ever reaches here.
  final Uint8List bytes;
  final String mimeType;
  final String? fileName;
  final MessageType messageType;
  final String? text;

  /// Id of the message this attachment answers, carried through so a
  /// reconnect replay of the whole upload+send sequence still cites the
  /// quoted message instead of landing bare — see
  /// `MessagesController.sendAttachment`/`sendVoice`, the only callers of
  /// `NomaChatClient.enqueueOfflineAttachment`.
  final String? referencedMessageId;

  /// Extra fields folded into the eventual `send()` metadata alongside
  /// the post-upload `mimeType`/`attachmentUrl`/`fileName`/`fileSize` —
  /// e.g. `duration`/`waveform` for a queued voice message.
  final Map<String, dynamic>? metadata;
  final String? tempId;

  /// Idempotency key reused across every retry of this queued send —
  /// same rationale as [PendingSendMessage.clientMessageId].
  final String? clientMessageId;

  @override
  String? get optimisticId => tempId;

  PendingSendAttachment({
    required super.id,
    required this.roomId,
    required this.bytes,
    required this.mimeType,
    this.fileName,
    this.messageType = MessageType.attachment,
    this.text,
    this.referencedMessageId,
    this.metadata,
    this.tempId,
    this.clientMessageId,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'sendAttachment',
    'roomId': roomId,
    'bytes': _cachedBase64OfBytes(bytes),
    'mimeType': mimeType,
    if (fileName != null) 'fileName': fileName,
    'messageType': messageType.name,
    if (text != null) 'text': text,
    if (referencedMessageId != null) 'referencedMessageId': referencedMessageId,
    if (metadata != null) 'metadata': metadata,
    if (tempId != null) 'tempId': tempId,
    if (clientMessageId != null) 'clientMessageId': clientMessageId,
  };

  @override
  PendingSendAttachment withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingSendAttachment(
        id: id,
        roomId: roomId,
        bytes: bytes,
        mimeType: mimeType,
        fileName: fileName,
        messageType: messageType,
        text: text,
        referencedMessageId: referencedMessageId,
        metadata: metadata,
        tempId: tempId,
        clientMessageId: clientMessageId,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingSendDirectMessage extends PendingOperation {
  final String contactUserId;
  final String? text;
  final MessageType messageType;
  final String? referencedMessageId;
  final String? reaction;
  final String? attachmentUrl;
  final Map<String, dynamic>? metadata;

  /// Server idempotency key, reused verbatim on every retry so a DM send
  /// that actually landed (failure surfaced after delivery) is not
  /// duplicated on drain. See [ChatContactsApi.sendDirectMessage].
  final String? clientMessageId;

  /// The DM path carries no separate temp id: the optimistic row's id is
  /// what `ChatUiAdapter` hands over as [clientMessageId].
  @override
  String? get optimisticId => clientMessageId;

  PendingSendDirectMessage({
    required super.id,
    required this.contactUserId,
    this.text,
    this.messageType = MessageType.regular,
    this.referencedMessageId,
    this.reaction,
    this.attachmentUrl,
    this.metadata,
    this.clientMessageId,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'sendDirectMessage',
    'contactUserId': contactUserId,
    if (text != null) 'text': text,
    'messageType': messageType.name,
    if (referencedMessageId != null) 'referencedMessageId': referencedMessageId,
    if (reaction != null) 'reaction': reaction,
    if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
    if (metadata != null) 'metadata': metadata,
    if (clientMessageId != null) 'clientMessageId': clientMessageId,
  };

  @override
  PendingSendDirectMessage withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingSendDirectMessage(
        id: id,
        contactUserId: contactUserId,
        text: text,
        messageType: messageType,
        referencedMessageId: referencedMessageId,
        reaction: reaction,
        attachmentUrl: attachmentUrl,
        metadata: metadata,
        clientMessageId: clientMessageId,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingEditMessage extends PendingOperation {
  final String roomId;
  final String messageId;
  final String text;
  final Map<String, dynamic>? metadata;

  PendingEditMessage({
    required super.id,
    required this.roomId,
    required this.messageId,
    required this.text,
    this.metadata,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'editMessage',
    'roomId': roomId,
    'messageId': messageId,
    'text': text,
    if (metadata != null) 'metadata': metadata,
  };

  @override
  PendingEditMessage withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingEditMessage(
        id: id,
        roomId: roomId,
        messageId: messageId,
        text: text,
        metadata: metadata,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingDeleteMessage extends PendingOperation {
  final String roomId;
  final String messageId;

  PendingDeleteMessage({
    required super.id,
    required this.roomId,
    required this.messageId,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'deleteMessage',
    'roomId': roomId,
    'messageId': messageId,
  };

  @override
  PendingDeleteMessage withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingDeleteMessage(
        id: id,
        roomId: roomId,
        messageId: messageId,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingDeleteReaction extends PendingOperation {
  final String roomId;
  final String messageId;

  PendingDeleteReaction({
    required super.id,
    required this.roomId,
    required this.messageId,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'deleteReaction',
    'roomId': roomId,
    'messageId': messageId,
  };

  @override
  PendingDeleteReaction withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingDeleteReaction(
        id: id,
        roomId: roomId,
        messageId: messageId,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingAddReaction extends PendingOperation {
  final String roomId;
  final String messageId;
  final String emoji;

  PendingAddReaction({
    required super.id,
    required this.roomId,
    required this.messageId,
    required this.emoji,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'addReaction',
    'roomId': roomId,
    'messageId': messageId,
    'emoji': emoji,
  };

  @override
  PendingAddReaction withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingAddReaction(
        id: id,
        roomId: roomId,
        messageId: messageId,
        emoji: emoji,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingPinMessage extends PendingOperation {
  final String roomId;
  final String messageId;

  PendingPinMessage({
    required super.id,
    required this.roomId,
    required this.messageId,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'pinMessage',
    'roomId': roomId,
    'messageId': messageId,
  };

  @override
  PendingPinMessage withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingPinMessage(
        id: id,
        roomId: roomId,
        messageId: messageId,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingUnpinMessage extends PendingOperation {
  final String roomId;
  final String messageId;

  PendingUnpinMessage({
    required super.id,
    required this.roomId,
    required this.messageId,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'unpinMessage',
    'roomId': roomId,
    'messageId': messageId,
  };

  @override
  PendingUnpinMessage withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingUnpinMessage(
        id: id,
        roomId: roomId,
        messageId: messageId,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingStarMessage extends PendingOperation {
  final String roomId;
  final String messageId;

  PendingStarMessage({
    required super.id,
    required this.roomId,
    required this.messageId,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'starMessage',
    'roomId': roomId,
    'messageId': messageId,
  };

  @override
  PendingStarMessage withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingStarMessage(
        id: id,
        roomId: roomId,
        messageId: messageId,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingUnstarMessage extends PendingOperation {
  final String roomId;
  final String messageId;

  PendingUnstarMessage({
    required super.id,
    required this.roomId,
    required this.messageId,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'unstarMessage',
    'roomId': roomId,
    'messageId': messageId,
  };

  @override
  PendingUnstarMessage withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingUnstarMessage(
        id: id,
        roomId: roomId,
        messageId: messageId,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingCreateRoom extends PendingOperation {
  final String name;
  final String audience;
  final List<String> members;
  final String? type;
  final String? subject;

  /// Idempotency key reused across every retry of this queued create so a
  /// reconnect that replays it does not mint a second room. Note: today
  /// `RoomsApi.create` derives its own client-side dedup/idempotency key
  /// from the request's canonical content (see `canonicalRequestKey` in
  /// `in_flight_registry.dart`), which already lands on the same value on
  /// every retry of an unchanged payload — this field exists so the queued
  /// operation carries an explicit key of its own, matching the
  /// `clientMessageId` convention on [PendingSendMessage], for whichever
  /// caller wires it through explicitly.
  final String? idempotencyKey;

  PendingCreateRoom({
    required super.id,
    required this.name,
    required this.audience,
    required this.members,
    this.type,
    this.subject,
    this.idempotencyKey,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'createRoom',
    'name': name,
    'audience': audience,
    'members': members,
    if (type != null) 'roomType': type,
    if (subject != null) 'subject': subject,
    if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
  };

  @override
  PendingCreateRoom withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingCreateRoom(
        id: id,
        name: name,
        audience: audience,
        members: members,
        type: type,
        subject: subject,
        idempotencyKey: idempotencyKey,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingUpdateRoomConfig extends PendingOperation {
  final String roomId;
  final String? name;
  final String? subject;
  final String? avatar;
  final bool? allowInvitations;

  /// Idempotency key reused across every retry — same rationale as
  /// [PendingCreateRoom.idempotencyKey].
  final String? idempotencyKey;

  PendingUpdateRoomConfig({
    required super.id,
    required this.roomId,
    this.name,
    this.subject,
    this.avatar,
    this.allowInvitations,
    this.idempotencyKey,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'updateRoomConfig',
    'roomId': roomId,
    if (name != null) 'name': name,
    if (subject != null) 'subject': subject,
    if (avatar != null) 'avatar': avatar,
    if (allowInvitations != null) 'allowInvitations': allowInvitations,
    if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
  };

  @override
  PendingUpdateRoomConfig withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingUpdateRoomConfig(
        id: id,
        roomId: roomId,
        name: name,
        subject: subject,
        avatar: avatar,
        allowInvitations: allowInvitations,
        idempotencyKey: idempotencyKey,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingAddMember extends PendingOperation {
  final String roomId;
  final String userId;
  final String? role;

  /// Idempotency key reused across every retry — same rationale as
  /// [PendingCreateRoom.idempotencyKey].
  final String? idempotencyKey;

  PendingAddMember({
    required super.id,
    required this.roomId,
    required this.userId,
    this.role,
    this.idempotencyKey,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'addMember',
    'roomId': roomId,
    'userId': userId,
    if (role != null) 'role': role,
    if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
  };

  @override
  PendingAddMember withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingAddMember(
        id: id,
        roomId: roomId,
        userId: userId,
        role: role,
        idempotencyKey: idempotencyKey,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

final class PendingRemoveMember extends PendingOperation {
  final String roomId;
  final String userId;

  /// Idempotency key reused across every retry — same rationale as
  /// [PendingCreateRoom.idempotencyKey].
  final String? idempotencyKey;

  PendingRemoveMember({
    required super.id,
    required this.roomId,
    required this.userId,
    this.idempotencyKey,
    super.createdAt,
    super.attempts,
    super.nextRetryAt,
  });

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'type': 'removeMember',
    'roomId': roomId,
    'userId': userId,
    if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
  };

  @override
  PendingRemoveMember withRetry({int? attempts, DateTime? nextRetryAt}) =>
      PendingRemoveMember(
        id: id,
        roomId: roomId,
        userId: userId,
        idempotencyKey: idempotencyKey,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}
