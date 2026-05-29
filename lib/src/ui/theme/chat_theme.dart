import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../l10n/chat_ui_localizations.dart';
import 'bubble_theme.dart';
import 'input_theme.dart';
import 'markdown_theme.dart';
import 'room_list_theme.dart';

part 'chat_theme.freezed.dart';

/// Theming configuration for all chat UI Kit widgets.
///
/// All properties are optional and fall back to sensible defaults. Use
/// [copyWith] to override specific properties while keeping the rest.
///
/// ## Sub-themes
///
/// Theming is organised around four cohesive sub-theme classes plus a
/// flat set of "miscellaneous" slots that don't belong to any of them:
///
/// - [bubble] — [ChatBubbleTheme]: message bubble surface, text styles,
///   timestamps, receipt status, mentions, edited / forwarded labels,
///   sender name, failed-message icon.
/// - [input] — [ChatInputTheme]: composer, side buttons (send / attach /
///   voice / camera), editing banner, reply preview.
/// - [roomList] — [ChatRoomListTheme]: tiles, last-message preview,
///   unread badge, muted / pinned icons, suggestions strip, search bar,
///   section headers.
/// - [markdown] — [ChatMarkdownTheme]: inline `*bold*` / `_italic_` /
///   `` `code` `` / `~~strikethrough~~` / link / `@mention` styles.
///
/// Everything else (background, avatar, presence dots, audio, video,
/// file, link preview, location, banners, reaction picker, context menus,
/// scroll-to-bottom, attachment picker, image viewer…) lives as flat
/// fields on [ChatTheme] itself.
///
/// ## Picking a starting point
///
/// - `ChatTheme.lightPreset()` / `ChatTheme.darkPreset()` — opinionated
///   defaults across every visible surface, ready to use.
/// - `ChatTheme.resolved(context)` — picks light or dark from the
///   platform brightness via `MediaQuery`.
/// - `ChatTheme.branded(accent: …)` — derives a brand-tinted theme from
///   a single accent colour. Drives every accent slot the SDK renders.
@freezed
abstract class ChatTheme with _$ChatTheme {
  const factory ChatTheme({
    @Default(ChatUiLocalizations.en) ChatUiLocalizations l10n,
    @Default(ChatBubbleTheme()) ChatBubbleTheme bubble,
    @Default(ChatInputTheme()) ChatInputTheme input,
    @Default(ChatRoomListTheme()) ChatRoomListTheme roomList,
    @Default(ChatMarkdownTheme()) ChatMarkdownTheme markdown,

    /// Custom builder for the map preview inside `LocationBubble`. When
    /// provided, replaces the default static map image — useful for apps
    /// that already have a maps SDK authorised and want to render a
    /// lightweight interactive map (e.g. `GoogleMap` in lite mode).
    Widget Function(BuildContext, double latitude, double longitude)?
    locationMapBuilder,

    // Date separator + system messages
    TextStyle? dateSeparatorTextStyle,
    Color? dateSeparatorBackgroundColor,
    TextStyle? systemMessageTextStyle,
    Color? systemMessageBackgroundColor,

    // Typing indicator (bubble + status text in room tiles)
    Color? typingIndicatorDotColor,
    TextStyle? typingStatusTextStyle,

    // Reactions (bar + picker + detail sheet + emoji picker)
    Color? reactionBackgroundColor,
    Color? reactionSelectedColor,
    Color? reactionSelectedBorderColor,
    TextStyle? reactionTextStyle,
    double? reactionPickerElevation,
    BorderRadius? reactionPickerBorderRadius,
    double? reactionPickerEmojiSize,
    Color? reactionDetailSheetBackgroundColor,
    TextStyle? reactionDetailUserNameStyle,
    Color? reactionDetailRemoveColor,
    Color? floatingPickerBackgroundColor,
    Color? fullEmojiPickerBackgroundColor,

    // Audio bubble + voice recorder + waveform
    Color? audioPlayButtonColor,
    Color? audioPlayIconColor,
    Color? audioSeekBarColor,
    Color? audioSeekBarActiveColor,
    TextStyle? audioDurationTextStyle,
    Color? audioSpeedButtonColor,
    TextStyle? audioSpeedTextStyle,
    Color? audioListenedIconColor,
    Color? audioUnlistenedIconColor,
    Color? voiceRecorderActiveColor,
    TextStyle? voiceRecorderTimerStyle,
    Color? voiceRecorderOverlayColor,
    Color? voiceRecorderCancelColor,
    Color? voiceRecorderLockIconColor,
    TextStyle? voiceRecorderHintStyle,
    Color? waveformActiveColor,
    Color? waveformInactiveColor,
    Color? waveformRecordingColor,

    // Image / Video / File / Link Preview bubbles
    BorderRadius? imageBorderRadius,
    double? imageMaxHeight,
    double? imageMaxWidth,
    TextStyle? imageCaptionStyle,
    Color? videoPlayIconColor,
    Color? videoPlayIconBackgroundColor,
    Color? videoPlaceholderIconColor,
    double? videoHeight,
    Color? videoPlaceholderColor,
    BorderRadius? videoBorderRadius,
    Color? fileIconColor,
    TextStyle? fileNameTextStyle,
    TextStyle? fileSizeTextStyle,
    Color? linkPreviewBackgroundColor,
    TextStyle? linkPreviewTitleStyle,
    TextStyle? linkPreviewDescriptionStyle,
    BorderRadius? linkPreviewBorderRadius,
    TextStyle? linkPreviewDomainStyle,
    Color? linkPreviewBorderColor,

    // Chat background
    Color? backgroundColor,
    ImageProvider? backgroundImage,
    @Default(ImageRepeat.noRepeat) ImageRepeat backgroundImageRepeat,
    @Default(1.0) double backgroundImageOpacity,
    ColorFilter? backgroundImageColorFilter,

    // Avatar
    Color? avatarBackgroundColor,
    TextStyle? avatarInitialsTextStyle,
    Color? avatarOnlineColor,
    Color? avatarOfflineColor,
    Color? avatarOnlineBorderColor,

    // Connection banner + empty state
    Color? connectionBannerColor,
    TextStyle? connectionBannerTextStyle,
    Color? connectionBannerErrorIconColor,
    Color? emptyStateIconColor,
    TextStyle? emptyStateTitleStyle,
    TextStyle? emptyStateSubtitleStyle,

    // Context menus + scroll to bottom + attachment picker + image viewer
    Color? contextMenuHandleColor,
    Color? contextMenuDestructiveColor,
    Color? scrollToBottomButtonColor,
    Color? scrollToBottomIconColor,
    Color? attachmentPickerCircleColor,
    Color? attachmentPickerIconColor,
    TextStyle? attachmentPickerLabelStyle,
    Color? imageViewerBackgroundColor,
    Color? imageViewerIconColor,

    // Presence dots
    Color? presenceAvailableColor,
    Color? presenceAwayColor,
    Color? presenceBusyColor,
    Color? presenceDndColor,
  }) = _ChatTheme;

  /// Empty defaults — every slot is `null` and falls back to the
  /// widget-level hardcoded baseline. Use as a starting `const`.
  static const ChatTheme defaults = ChatTheme();

  /// Light-mode preset with rich defaults across every visible surface.
  /// Use as a starting point when a host app wants the SDK to "just
  /// look right" without wiring 50+ slots by hand. Override with
  /// [copyWith] for brand colours, or compose with [branded] for a
  /// quick accent-driven tint.
  factory ChatTheme.lightPreset() {
    const surfaceLight = Color(0xFFFFFFFF);
    const surfaceMuted = Color(0xFFF5F5F5);
    const textPrimary = Color(0xFF212121);
    const textSecondary = Color(0xFF757575);
    const accentBlue = Color(0xFF1976D2);
    const accentGreen = Color(0xFF25D366);
    const onAccent = Color(0xFFFFFFFF);
    return const ChatTheme(
      bubble: ChatBubbleTheme(
        outgoingColor: Color(0xFFDCF8C6),
        incomingColor: surfaceLight,
        outgoingTextStyle: TextStyle(color: textPrimary, fontSize: 14),
        incomingTextStyle: TextStyle(color: textPrimary, fontSize: 14),
        timestampStyle: TextStyle(color: textSecondary, fontSize: 11),
        statusColor: Color(0xFF9E9E9E),
      ),
      input: ChatInputTheme(
        backgroundColor: surfaceLight,
        fillColor: surfaceMuted,
        textStyle: TextStyle(color: textPrimary, fontSize: 14),
        hintStyle: TextStyle(color: textSecondary, fontSize: 14),
        sendButtonColor: accentGreen,
        sendButtonIconColor: onAccent,
        attachButtonColor: textSecondary,
        cameraButtonColor: textSecondary,
        voiceButtonColor: textSecondary,
      ),
      roomList: ChatRoomListTheme(
        tileBackgroundColor: surfaceLight,
        nameStyle: TextStyle(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        previewStyle: TextStyle(color: textSecondary, fontSize: 14),
        previewUnreadStyle: TextStyle(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        timestampStyle: TextStyle(color: textSecondary, fontSize: 12),
        timestampUnreadStyle: TextStyle(
          color: accentGreen,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        unreadBadgeColor: accentGreen,
        unreadBadgeTextStyle: TextStyle(
          color: onAccent,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      markdown: ChatMarkdownTheme(
        linkStyle: TextStyle(
          color: accentBlue,
          decoration: TextDecoration.underline,
        ),
        codeStyle: TextStyle(
          color: textPrimary,
          backgroundColor: Color(0xFFEEEEEE),
          fontFamily: 'monospace',
          fontSize: 13,
        ),
      ),
      backgroundColor: Color(0xFFECE5DD),
      dateSeparatorTextStyle: TextStyle(color: textSecondary, fontSize: 12),
      dateSeparatorBackgroundColor: Color(0xFFE1F2FB),
      systemMessageTextStyle: TextStyle(color: textSecondary, fontSize: 12),
      systemMessageBackgroundColor: Color(0xFFE1F2FB),
      connectionBannerColor: Color(0xFFFFF8E1),
      connectionBannerTextStyle: TextStyle(color: textPrimary, fontSize: 13),
      avatarBackgroundColor: Color(0xFFBDBDBD),
      avatarOnlineColor: accentGreen,
      avatarOfflineColor: textSecondary,
      reactionBackgroundColor: surfaceMuted,
      reactionTextStyle: TextStyle(fontSize: 13),
      presenceAvailableColor: accentGreen,
      presenceAwayColor: Color(0xFFFFB300),
      presenceBusyColor: Color(0xFFE53935),
      presenceDndColor: Color(0xFFE53935),
    );
  }

  /// Dark-mode preset with rich defaults across every visible surface.
  factory ChatTheme.darkPreset() {
    const surfaceDark = Color(0xFF121212);
    const surfaceElevated = Color(0xFF1E1E1E);
    const surfaceInput = Color(0xFF263238);
    const textPrimary = Color(0xFFE0E0E0);
    const textSecondary = Color(0xFF9E9E9E);
    const accentTeal = Color(0xFF4CAF50);
    const accentBlue = Color(0xFF64B5F6);
    const onAccent = Color(0xFFFFFFFF);
    return const ChatTheme(
      bubble: ChatBubbleTheme(
        outgoingColor: Color(0xFF1B5E20),
        incomingColor: Color(0xFF37474F),
        outgoingTextStyle: TextStyle(color: textPrimary, fontSize: 14),
        incomingTextStyle: TextStyle(color: textPrimary, fontSize: 14),
        timestampStyle: TextStyle(color: textSecondary, fontSize: 11),
      ),
      input: ChatInputTheme(
        backgroundColor: surfaceInput,
        fillColor: Color(0xFF37474F),
        textStyle: TextStyle(color: textPrimary, fontSize: 14),
        hintStyle: TextStyle(color: textSecondary, fontSize: 14),
        sendButtonColor: accentTeal,
        sendButtonIconColor: onAccent,
        attachButtonColor: textSecondary,
        cameraButtonColor: textSecondary,
        voiceButtonColor: textSecondary,
      ),
      roomList: ChatRoomListTheme(
        tileBackgroundColor: surfaceElevated,
        nameStyle: TextStyle(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        previewStyle: TextStyle(color: textSecondary, fontSize: 14),
        previewUnreadStyle: TextStyle(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        timestampStyle: TextStyle(color: textSecondary, fontSize: 12),
        timestampUnreadStyle: TextStyle(
          color: accentTeal,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unreadBadgeColor: accentTeal,
        unreadBadgeTextStyle: TextStyle(
          color: onAccent,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      markdown: ChatMarkdownTheme(
        linkStyle: TextStyle(
          color: accentBlue,
          decoration: TextDecoration.underline,
        ),
        codeStyle: TextStyle(
          color: Color(0xFFE6E6E6),
          backgroundColor: Color(0xFF3A3A3A),
          fontFamily: 'monospace',
          fontSize: 13,
        ),
      ),
      backgroundColor: surfaceDark,
      dateSeparatorTextStyle: TextStyle(color: textSecondary, fontSize: 12),
      systemMessageTextStyle: TextStyle(color: textSecondary, fontSize: 12),
      connectionBannerColor: surfaceElevated,
      connectionBannerTextStyle: TextStyle(color: textPrimary, fontSize: 13),
      avatarBackgroundColor: Color(0xFF455A64),
      avatarOnlineColor: accentTeal,
      avatarOfflineColor: textSecondary,
      reactionBackgroundColor: surfaceInput,
      reactionTextStyle: TextStyle(fontSize: 13, color: textPrimary),
      presenceAvailableColor: accentTeal,
      presenceAwayColor: Color(0xFFFFB300),
      presenceBusyColor: Color(0xFFE57373),
      presenceDndColor: Color(0xFFE57373),
      audioPlayButtonColor: accentBlue,
      audioListenedIconColor: accentBlue,
      audioUnlistenedIconColor: Color(0xFFB0BEC5),
      linkPreviewBackgroundColor: surfaceInput,
    );
  }

  /// Resolves to [lightPreset] / [darkPreset] based on the platform
  /// brightness exposed by [MediaQuery]. Drop-in for apps that want the
  /// SDK to follow the system theme without wiring custom logic.
  static ChatTheme resolved(BuildContext context) {
    final brightness = MediaQuery.maybeOf(context)?.platformBrightness;
    return brightness == Brightness.dark
        ? ChatTheme.darkPreset()
        : ChatTheme.lightPreset();
  }

  /// Builds a quick brand-tinted theme without having to override every
  /// slot individually. [accent] drives every accent surface the SDK
  /// renders — outgoing bubble, send / attach / camera buttons, audio
  /// play, unread badge, read receipt — so a host app gets a consistent
  /// brand look from a single colour. [contrastingOnAccent] should pass
  /// WCAG AA against [accent] (white for saturated brands; black for
  /// pastels).
  ///
  /// ```dart
  /// final theme = ChatTheme.branded(
  ///   accent: const Color(0xFFE91E63), // Material pink
  /// );
  /// ```
  factory ChatTheme.branded({
    required Color accent,
    Color contrastingOnAccent = const Color(0xFFFFFFFF),
  }) {
    return ChatTheme(
      bubble: ChatBubbleTheme(
        outgoingColor: accent,
        outgoingTextStyle: TextStyle(color: contrastingOnAccent, fontSize: 14),
        statusReadColor: accent,
      ),
      input: ChatInputTheme(
        sendButtonColor: accent,
        sendButtonIconColor: contrastingOnAccent,
        attachButtonColor: accent,
        cameraButtonColor: accent,
        voiceButtonIdleIconColor: accent,
        replyPreviewBarColor: accent,
      ),
      roomList: ChatRoomListTheme(unreadBadgeColor: accent),
      audioPlayButtonColor: accent,
      audioListenedIconColor: accent,
      audioSeekBarActiveColor: accent,
      reactionSelectedBorderColor: accent,
    );
  }

  /// High-contrast preset (WCAG AAA-friendly) for accessibility-first
  /// hosts. Black / white surfaces, 18px+ text, bold weights, strong
  /// connection-banner red. Pair with `MediaQuery.highContrast`.
  factory ChatTheme.highContrast() => const ChatTheme(
    bubble: ChatBubbleTheme(
      outgoingColor: Color(0xFF000000),
      incomingColor: Color(0xFFFFFFFF),
      outgoingTextStyle: TextStyle(
        color: Color(0xFFFFFFFF),
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      incomingTextStyle: TextStyle(
        color: Color(0xFF000000),
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      timestampStyle: TextStyle(
        color: Color(0xFF424242),
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
    input: ChatInputTheme(
      textStyle: TextStyle(color: Color(0xFF000000), fontSize: 18),
      backgroundColor: Color(0xFFFFFFFF),
      sendButtonColor: Color(0xFF000000),
    ),
    roomList: ChatRoomListTheme(
      nameStyle: TextStyle(
        color: Color(0xFF000000),
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      previewStyle: TextStyle(color: Color(0xFF424242), fontSize: 16),
      previewUnreadStyle: TextStyle(
        color: Color(0xFF000000),
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    ),
    markdown: ChatMarkdownTheme(
      codeStyle: TextStyle(
        color: Color(0xFF000000),
        backgroundColor: Color(0xFFE0E0E0),
        fontFamily: 'monospace',
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      linkStyle: TextStyle(
        color: Color(0xFF0000EE),
        decoration: TextDecoration.underline,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    backgroundColor: Color(0xFFF5F5F5),
    dateSeparatorTextStyle: TextStyle(
      color: Color(0xFF212121),
      fontSize: 16,
      fontWeight: FontWeight.bold,
    ),
    connectionBannerColor: Color(0xFFFF0000),
    connectionBannerTextStyle: TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 16,
      fontWeight: FontWeight.bold,
    ),
  );
}
