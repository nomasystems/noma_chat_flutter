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
}

/// Single error event broadcast by `ChatUiAdapter.operationErrors` whenever
/// any adapter method fails. The original `Result.Failure` is still returned
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
