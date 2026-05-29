import 'dart:async';

import '../../events/chat_event.dart';
import '../../models/message.dart';

/// Contract that every real-time transport implementation must honour.
///
/// Implementations:
/// * [WsTransport] — bidirectional WebSocket, supports outbound frames.
/// * [SseTransport] — read-only Server-Sent Events stream, outbound is
///   no-op (callers fall back to REST).
/// * `AutoFailoverTransport` — composite of WS + SSE that promotes the
///   active transport based on connectivity (the historical default).
/// * `PollingTransport` — REST polling at a fixed interval.
/// * `ManualTransport` — explicit `refresh()` only.
///
/// The transport publishes [events] and [stateChanges]; orchestration
/// (replay buffer, synthetic events) lives one layer up in
/// [TransportManager].
abstract class RealtimeTransport {
  /// Stream of [ChatEvent]s produced by the transport.
  Stream<ChatEvent> get events;

  /// Stream of connection-state transitions.
  Stream<ChatConnectionState> get stateChanges;

  /// Current connection state.
  ChatConnectionState get state;

  /// `true` when this transport carries an outbound real-time channel
  /// (today only WS). [MessagesApi]/[ContactsApi] gate WS frame attempts
  /// on this getter combined with `state == connected`; everything else
  /// falls back to REST.
  bool get supportsOutboundFrames;

  /// Opens the transport.
  Future<void> connect();

  /// Closes the transport; safe to re-call [connect] afterwards.
  Future<void> disconnect();

  /// Releases resources. The instance must not be used again.
  Future<void> dispose();

  /// Tell the server the auth token was rotated. WS sends an
  /// `auth_refresh` frame; SSE reconnects with the new token; modes
  /// without an active connection are no-op.
  Future<void> notifyTokenRotated();

  /// Outbound typing indicator for a room (WS frame). Transports without
  /// outbound channel ignore silently — callers should branch on
  /// [supportsOutboundFrames] first.
  void sendTyping(String roomId, {String activity});

  /// Outbound typing indicator for a 1-to-1 DM (WS frame).
  void sendDmTyping(String contactId, {String activity});

  /// Outbound read/delivery receipt (WS frame).
  void sendReceipt(String roomId, String messageId, {ReceiptStatus status});

  /// Outbound message via WS (fire-and-forget). [MessagesApi.sendViaWs]
  /// also returns a synthetic [ChatMessage] for optimistic UI; the
  /// server-confirmed message arrives later via [NewMessageEvent].
  void sendMessage(
    String roomId, {
    String? text,
    String messageType,
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
  });

  /// Force a refresh of the underlying state.
  ///
  /// * Streaming transports (WS/SSE/AutoFailover): no-op — the event
  ///   stream already delivers updates as they happen.
  /// * [PollingTransport]: advances the next tick, optionally
  ///   constrained to [singleRoomId].
  /// * `ManualTransport`: the **only** way to receive updates — every
  ///   call diffs the room list and pulls new messages.
  Future<void> refresh({String? singleRoomId});
}
