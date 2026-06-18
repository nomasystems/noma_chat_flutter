import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../widgets/message_status_icon.dart';

part 'bubble_theme.freezed.dart';

/// Theme for the message bubble surface — the rounded card that wraps every
/// regular message, regardless of payload (text / attachment / reply / etc.).
///
/// Resolved by the SDK through [bubbleColorFor] / [textStyleFor] so callers
/// don't have to branch on direction at every render site.
///
/// All fields are optional. Pass an instance to [ChatTheme] to override the
/// flat fields with the same semantics; pass nothing and the existing flat
/// fields keep working unchanged (back-compat).
@freezed
abstract class ChatBubbleTheme with _$ChatBubbleTheme {
  const factory ChatBubbleTheme({
    /// Background of bubbles authored by the current user.
    Color? outgoingColor,

    /// Background of bubbles authored by anyone else.
    Color? incomingColor,

    /// Default text style for outgoing bubble payloads.
    TextStyle? outgoingTextStyle,

    /// Default text style for incoming bubble payloads.
    TextStyle? incomingTextStyle,

    /// Border radius applied to every bubble.
    BorderRadius? borderRadius,

    /// Fallback timestamp style applied at the bubble corner.
    TextStyle? timestampStyle,

    /// Outgoing-side override for [timestampStyle].
    TextStyle? outgoingTimestampStyle,

    /// Incoming-side override for [timestampStyle].
    TextStyle? incomingTimestampStyle,

    /// Color of the receipt status icon (sent / delivered).
    Color? statusColor,

    /// Color of the double-check when the recipient has read the message.
    /// Defaults to a Material-blue (0xFF2196F3) at the [ChatTheme] level.
    Color? statusReadColor,

    /// Color used to highlight `@<word>` mention tokens inside a bubble.
    Color? mentionColor,

    /// Style for the "edited" / "edited by admin" sublabel.
    TextStyle? editedLabelStyle,

    /// Color of the "Forwarded" header on forwarded bubbles.
    Color? forwardedLabelColor,

    /// Style of the "Forwarded" header on forwarded bubbles.
    TextStyle? forwardedLabelStyle,

    /// Style of the sender name rendered above incoming bubbles in group
    /// chats (WhatsApp-style).
    TextStyle? senderNameStyle,

    /// Tint for the warning icon attached to messages that failed to send.
    Color? failedIconColor,

    /// Color of the pending clock shown while a message is in flight.
    /// Falls back to [statusColor].
    Color? statusPendingColor,

    /// Per-state override of the delivery-status icon (bubble corner and
    /// room-list preview). Return `null` for SDK default. Covers all five
    /// states: sending / sent / delivered / read / failed.
    MessageStatusIconBuilder? statusIconBuilder,
  }) = _ChatBubbleTheme;
}
