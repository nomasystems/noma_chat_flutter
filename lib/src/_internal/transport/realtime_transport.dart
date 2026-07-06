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

  /// `true` once the transport hit a *terminal* auth failure (the server
  /// rejected the credential and reconnecting with it is futile — e.g. WS
  /// close 4005). Set synchronously, before the matching error event /
  /// state change is delivered, so a composing transport
  /// (`AutoFailoverTransport`) can decide not to fail over to a second
  /// transport that would replay the rejected token without depending on
  /// stream-delivery ordering. Defaults to `false`; only [WsTransport]
  /// (the only auth-bearing primary) overrides it.
  bool get authTerminated => false;

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

  /// Outbound consolidated delivered-cursor confirmation (WS frame):
  /// the current user holds every message of [roomId] up to and
  /// including [messageId]. One frame covers any number of messages.
  /// Transports without an outbound channel ignore silently.
  void sendDelivered(String roomId, String messageId);

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

  /// Outbound message via WS that resolves once delivery is confirmed.
  ///
  /// Sends the message and returns `true` when the server acks it (the
  /// backend's `message_acked` frame, correlated by an SDK-injected id) or
  /// `false` when the ack does not arrive before [ackTimeout] or the socket
  /// drops first. Unlike the fire-and-forget [sendMessage], this lets
  /// [MessagesApi.sendViaWs] fall back to the idempotent REST send on a
  /// `false` result instead of silently losing the message on a socket drop.
  ///
  /// Transports without an outbound channel (SSE, polling, manual) keep the
  /// default: they never confirm, returning `false` immediately so the
  /// caller takes the REST path.
  Future<bool> sendMessageAwaitingAck(
    String roomId, {
    String? text,
    String messageType = 'regular',
    String? referencedMessageId,
    String? reaction,
    String? attachmentUrl,
    String? sourceRoomId,
    Map<String, dynamic>? metadata,
    String? clientMessageId,
    Duration ackTimeout = const Duration(seconds: 5),
  }) => Future.value(false);

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
