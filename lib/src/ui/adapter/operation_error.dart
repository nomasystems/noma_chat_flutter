import '../../core/result.dart' show ChatFailure;

/// Identifies which adapter operation produced an [OperationError]. Hosts
/// typically branch on this in their snackbar/toast logic.
enum OperationKind {
  loadRooms,
  loadMessages,
  loadMoreMessages,
  sendMessage,
  editMessage,
  deleteMessage,
  sendReaction,
  getReactions,
  deleteReaction,
  sendTyping,
  markAsRead,
  clearChat,
  sendReceipt,
  sendDirectMessage,
  uploadAttachment,
  sendVoiceMessage,
  muteRoom,
  unmuteRoom,
  pinRoom,
  unpinRoom,
  hideRoom,
  unhideRoom,
  blockContact,
  unblockContact,
  loadBlockedUsers,
  addMembers,
  removeMember,
  updateMemberRole,
  updateRoomConfig,
  leaveRoom,
  retrySend,
  loadThread,
  sendThreadReply,
  searchMessages,
  loadReceipts,
  acceptInvitation,
  rejectInvitation,
  pinMessage,
  unpinMessage,
  loadPins,
  forwardMessage,
  reportMessage,
  uploadAvatar,
  updateMyProfile,
  createGroupRoom,
}

/// Single error event broadcast by `ChatUiAdapter.operationErrors` whenever
/// any adapter method fails. The original `ChatResult.ChatFailureResult` is still returned
/// to the caller; this stream is for cross-cutting concerns like global
/// snackbars or telemetry.
class OperationError {
  const OperationError({
    required this.kind,
    required this.failure,
    this.roomId,
    this.messageId,
    this.userId,
  });

  final OperationKind kind;
  final ChatFailure failure;
  final String? roomId;
  final String? messageId;
  final String? userId;

  @override
  String toString() =>
      'OperationError(${kind.name}, roomId: $roomId, messageId: $messageId, failure: $failure)';
}

/// Mirror of [OperationError] for successful operations the consumer
/// might want to confirm to the user (snackbar/toast/etc). Emitted on
/// `ChatUiAdapter.operationSuccesses` when an operation that has
/// user-visible side effects (pin a message, delete a message, forward,
/// mute a room, report, …) completes successfully.
///
/// The default `ChatView` listens to this stream and shows localized
/// SnackBars when `showOperationFeedback: true` (default). Consumers
/// wanting custom UI can either subscribe to the stream directly and
/// disable the built-in feedback, or override individual strings via
/// `ChatUiLocalizations`.
class OperationSuccess {
  const OperationSuccess({
    required this.kind,
    this.roomId,
    this.messageId,
    this.userId,
  });

  final OperationKind kind;
  final String? roomId;
  final String? messageId;
  final String? userId;

  @override
  String toString() =>
      'OperationSuccess(${kind.name}, roomId: $roomId, messageId: $messageId)';
}
