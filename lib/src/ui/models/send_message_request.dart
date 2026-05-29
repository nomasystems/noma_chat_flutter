import 'package:flutter/foundation.dart';

import '../../models/message.dart';

/// Payload describing a send action initiated from the composer.
///
/// Carries the text typed by the user together with everything the composer
/// has gathered for that send: optional metadata (e.g. link previews), the
/// message being replied to, and the message being edited.
///
/// Consumers receive an instance via the `onSendMessage` callback on
/// `MessageInput` / `ChatView`, and typically forward it to
/// `ChatUiAdapter.sendMessage` (or build their own request).
@immutable
class SendMessageRequest {
  const SendMessageRequest({
    required this.text,
    this.metadata,
    this.replyTo,
    this.editing,
  });

  /// Trimmed text typed by the user.
  final String text;

  /// Auxiliary metadata gathered by the composer (link previews, mentions,
  /// custom fields). Stored alongside the message on the server.
  final Map<String, dynamic>? metadata;

  /// Message being replied to, when the user composed via the reply preview.
  /// When non-null the message should be sent with
  /// `messageType: MessageType.reply` and `referencedMessageId: replyTo!.id`.
  final ChatMessage? replyTo;

  /// Message being edited, when the composer is in edit mode.
  /// Mutually exclusive with [replyTo] in practice (the composer clears the
  /// reply when entering edit mode).
  final ChatMessage? editing;

  bool get isReply => replyTo != null;
  bool get isEdit => editing != null;

  /// Builds a plain text send (no reply, no edit, no metadata).
  /// Sugar for `SendMessageRequest(text: text)` when the caller is
  /// programmatically sending and just needs a one-liner.
  factory SendMessageRequest.text(String text) =>
      SendMessageRequest(text: text);

  /// Builds a reply send — the text is sent as a reply to [parent].
  /// The composer wires this constructor when the user taps "send"
  /// while the reply preview is active.
  factory SendMessageRequest.reply({
    required String text,
    required ChatMessage parent,
    Map<String, dynamic>? metadata,
  }) => SendMessageRequest(text: text, replyTo: parent, metadata: metadata);

  /// Builds an edit send — replaces [original]'s text.
  factory SendMessageRequest.edit({
    required String text,
    required ChatMessage original,
    Map<String, dynamic>? metadata,
  }) => SendMessageRequest(text: text, editing: original, metadata: metadata);

  /// Returns a copy with the listed fields replaced. Pass `null` to
  /// preserve the existing value; the constructor's `?` parameters do
  /// the rest.
  SendMessageRequest copyWith({
    String? text,
    Map<String, dynamic>? metadata,
    ChatMessage? replyTo,
    ChatMessage? editing,
  }) => SendMessageRequest(
    text: text ?? this.text,
    metadata: metadata ?? this.metadata,
    replyTo: replyTo ?? this.replyTo,
    editing: editing ?? this.editing,
  );
}
