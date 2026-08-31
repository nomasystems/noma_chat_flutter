import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../l10n/chat_ui_localizations.dart';
import 'bubble_theme.dart';
import 'input_theme.dart';
import 'markdown_theme.dart';
import 'room_list_theme.dart';

part 'chat_theme.freezed.dart';

/// Theming configuration for all chat UI components widgets.
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
///   sender name, failed-message icon, attachment upload-progress ring.
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
/// scroll-to-bottom, attachment picker, image viewer, media gallery,
/// camera capture, message search…) lives as flat fields on [ChatTheme]
/// itself.
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

    /// Ceiling on the height of a video bubble's poster frame. The frame is
    /// painted at the clip's own aspect ratio, scaled down to fit the bubble
    /// width and this height — it is a maximum, not a fixed height, so a
    /// portrait clip is no longer cropped into a landscape strip. Defaults to
    /// 250, matching [imageMaxHeight]'s default, so a clip and a photo of the
    /// same shape take the same room.
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

    // In-app camera capture (`CameraCapturePage`)
    Color? cameraCaptureBackgroundColor,

    /// Tint of everything drawn over the preview: close / flip icons, the
    /// shutter ring, the elapsed-time text and the error copy.
    Color? cameraCaptureForegroundColor,

    /// Fill of the shutter and of the elapsed-time pill while recording.
    Color? cameraCaptureRecordingColor,

    /// Translucent backing of the "your clip was lost" notice.
    Color? cameraCaptureOverlayColor,

    /// Style of the hint under the shutter and of the interruption notice.
    TextStyle? cameraCaptureHintStyle,

    /// Outer diameter of the shutter. Falls back to
    /// [RoomDefaults.cameraShutterSize].
    double? cameraCaptureShutterSize,

    /// Fill of the "send this shot" button on the capture-review step —
    /// the confirmation the shutter lands on before anything is sent.
    /// Falls back to [DefaultPalette.cameraCaptureSendButton].
    Color? cameraCaptureSendButtonColor,

    /// Style of the review step's Retake label. Falls back to
    /// [cameraCaptureHintStyle], and then to the same white-on-black the
    /// rest of the capture screen uses.
    TextStyle? cameraCaptureReviewActionStyle,

    // Presence dots
    Color? presenceAvailableColor,
    Color? presenceAwayColor,
    Color? presenceBusyColor,
    Color? presenceDndColor,

    // Media Gallery page (`MediaGalleryPage`'s own Scaffold/AppBar/TabBar
    // chrome — everything else in the page already reads `backgroundColor`
    // via its child widgets). `null` falls back to the ambient Material
    // `Theme`, unchanged from before these fields existed.
    Color? galleryAppBarBackgroundColor,
    Color? galleryAppBarForegroundColor,
    Color? galleryTabIndicatorColor,

    /// Surface behind the gallery's media / documents / links tabs. Falls
    /// back to [galleryAppBarBackgroundColor], and only then to the
    /// `Scaffold` default.
    ///
    /// Deliberately **not** [backgroundColor]: that one is the chat
    /// wallpaper, which hosts routinely tint (WhatsApp-style) and which
    /// reads as a stray grey panel once it sits behind a plain tabbed list
    /// instead of behind bubbles.
    Color? galleryBackgroundColor,

    // In-room message search (`MessageSearchView`). The host owns the
    // `Scaffold` / `AppBar` around the view, so these slots cover only
    // what the SDK paints: the surface, the query field and the results.
    // Every one of them is `null` by default and falls back to the look
    // the widget had before they existed.
    /// Surface painted behind the search field and the result list. Falls
    /// back to transparent, i.e. the host `Scaffold`'s own background.
    ///
    /// Deliberately **not** [backgroundColor]: that one is the chat
    /// wallpaper, same reasoning as [galleryBackgroundColor].
    Color? messageSearchBackgroundColor,

    /// Fill of the query field. When non-`null` the field is rendered
    /// filled; when `null` it keeps the unfilled outlined treatment.
    Color? messageSearchFieldFillColor,

    /// Style of the text the user types into the query field.
    TextStyle? messageSearchFieldTextStyle,

    /// Style of the query field's placeholder
    /// ([ChatUiLocalizations.searchMessages]).
    TextStyle? messageSearchFieldHintStyle,

    /// Caret colour inside the query field. Falls back to the ambient
    /// Material `TextSelectionTheme`.
    Color? messageSearchFieldCursorColor,

    /// Colour of the query field's outline in every state (idle, focused,
    /// disabled). Falls back to the ambient Material input decoration.
    Color? messageSearchFieldBorderColor,

    /// Corner radius of the query field's outline. Falls back to the
    /// square-ish Material `OutlineInputBorder` default.
    BorderRadius? messageSearchFieldBorderRadius,

    /// Tint of the leading magnifier and of the trailing clear button.
    /// Falls back to the ambient icon theme.
    Color? messageSearchFieldIconColor,

    /// Style of a result row's top line — the sender's display name.
    TextStyle? messageSearchResultTitleStyle,

    /// Style of a result row's message snippet, for the portions that do
    /// **not** match the query.
    TextStyle? messageSearchResultSnippetStyle,

    /// Style of the matched substrings inside a result snippet. Falls back
    /// to [messageSearchResultSnippetStyle] made bold, so theming only the
    /// snippet still yields a legible highlight.
    TextStyle? messageSearchResultHighlightStyle,

    /// Style of a result row's trailing timestamp.
    TextStyle? messageSearchResultTimestampStyle,

    /// Style of the "no results" copy. Falls back to
    /// [emptyStateTitleStyle], keeping search aligned with every other
    /// empty surface in the SDK unless it is themed apart.
    TextStyle? messageSearchEmptyTextStyle,

    /// Tint of the spinner shown while the first page of results is in
    /// flight. Falls back to [ChatInputTheme.sendButtonColor].
    Color? messageSearchProgressColor,
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
        uploadProgressColor: accentGreen,
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
      // Search is a plain page, not the chat: it takes the surface colour,
      // never the wallpaper. Everything else borrows the room list's
      // typography, which is the closest thing to it on screen — a list of
      // name + preview + timestamp rows.
      messageSearchBackgroundColor: surfaceLight,
      messageSearchFieldFillColor: surfaceMuted,
      messageSearchFieldTextStyle: TextStyle(color: textPrimary, fontSize: 14),
      messageSearchFieldHintStyle: TextStyle(
        color: textSecondary,
        fontSize: 14,
      ),
      messageSearchFieldCursorColor: accentGreen,
      messageSearchFieldBorderColor: Color(0xFFE0E0E0),
      messageSearchFieldBorderRadius: BorderRadius.all(Radius.circular(12)),
      messageSearchFieldIconColor: textSecondary,
      messageSearchResultTitleStyle: TextStyle(
        color: textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      messageSearchResultSnippetStyle: TextStyle(
        color: textSecondary,
        fontSize: 14,
      ),
      messageSearchResultHighlightStyle: TextStyle(
        color: textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      messageSearchResultTimestampStyle: TextStyle(
        color: textSecondary,
        fontSize: 12,
      ),
      messageSearchEmptyTextStyle: TextStyle(
        color: textSecondary,
        fontSize: 16,
      ),
      messageSearchProgressColor: accentGreen,
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
        uploadProgressColor: accentTeal,
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
      // Same reading as the light preset: the page surface, the composer's
      // fill for the query field, room-list typography for the rows. The
      // outline is a shade lighter than the fill so the field still has an
      // edge on a dark surface.
      messageSearchBackgroundColor: surfaceDark,
      messageSearchFieldFillColor: Color(0xFF37474F),
      messageSearchFieldTextStyle: TextStyle(color: textPrimary, fontSize: 14),
      messageSearchFieldHintStyle: TextStyle(
        color: textSecondary,
        fontSize: 14,
      ),
      messageSearchFieldCursorColor: accentTeal,
      messageSearchFieldBorderColor: Color(0xFF455A64),
      messageSearchFieldBorderRadius: BorderRadius.all(Radius.circular(12)),
      messageSearchFieldIconColor: textSecondary,
      messageSearchResultTitleStyle: TextStyle(
        color: textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      messageSearchResultSnippetStyle: TextStyle(
        color: textSecondary,
        fontSize: 14,
      ),
      messageSearchResultHighlightStyle: TextStyle(
        color: textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      messageSearchResultTimestampStyle: TextStyle(
        color: textSecondary,
        fontSize: 12,
      ),
      messageSearchEmptyTextStyle: TextStyle(
        color: textSecondary,
        fontSize: 16,
      ),
      messageSearchProgressColor: accentTeal,
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
  /// play, unread badge, read receipt, attachment upload-progress ring —
  /// so a host app gets a consistent brand look from a single colour.
  /// [contrastingOnAccent] should pass WCAG AA against [accent] (white for
  /// saturated brands; black for pastels).
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
        uploadProgressColor: accent,
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
      // Only the accent-carrying slots of the search screen. Its surfaces
      // and body text stay unthemed on purpose, exactly like the rest of
      // this factory: a brand colour is a tint, not a palette, and the
      // fallback chain already lands on the ambient look.
      messageSearchFieldCursorColor: accent,
      // 13 is the size of the snippet this span sits inside; leaving it out
      // would let the match jump to the ambient body size mid-sentence.
      messageSearchResultHighlightStyle: TextStyle(
        color: accent,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      messageSearchProgressColor: accent,
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
    // Search follows the same rules as every other surface here: pure
    // black on pure white, 16px+ text, a border that is actually visible.
    // The radius is left unset so the field keeps the square 4px outline
    // the rest of this preset implies.
    messageSearchBackgroundColor: Color(0xFFFFFFFF),
    messageSearchFieldFillColor: Color(0xFFFFFFFF),
    messageSearchFieldTextStyle: TextStyle(
      color: Color(0xFF000000),
      fontSize: 18,
    ),
    messageSearchFieldHintStyle: TextStyle(
      color: Color(0xFF424242),
      fontSize: 18,
    ),
    messageSearchFieldCursorColor: Color(0xFF000000),
    messageSearchFieldBorderColor: Color(0xFF000000),
    messageSearchFieldIconColor: Color(0xFF000000),
    messageSearchResultTitleStyle: TextStyle(
      color: Color(0xFF000000),
      fontSize: 18,
      fontWeight: FontWeight.bold,
    ),
    messageSearchResultSnippetStyle: TextStyle(
      color: Color(0xFF424242),
      fontSize: 16,
    ),
    messageSearchResultHighlightStyle: TextStyle(
      color: Color(0xFF000000),
      fontSize: 16,
      fontWeight: FontWeight.bold,
    ),
    messageSearchResultTimestampStyle: TextStyle(
      color: Color(0xFF424242),
      fontSize: 16,
      fontWeight: FontWeight.w500,
    ),
    messageSearchEmptyTextStyle: TextStyle(
      color: Color(0xFF000000),
      fontSize: 18,
      fontWeight: FontWeight.bold,
    ),
    messageSearchProgressColor: Color(0xFF000000),
  );
}

/// Resolves the [ChatUiLocalizations] a widget must render with.
///
/// This is the single string-lookup entry point for every widget in the
/// package: read `theme.l10nOf(context).someKey` instead of
/// `theme.l10n.someKey`, so both wiring routes work.
///
/// Precedence:
///
/// 1. The instance the host put on [ChatTheme.l10n] — an explicit theme
///    always wins, so a host that already routes its own copy through the
///    theme keeps full control and pays only an [identical] check.
/// 2. Otherwise the instance published by the `Localizations` ancestor,
///    via [ChatUiLocalizations.of] — this is what makes
///    `ChatUiLocalizations.delegate` (and `ChatUiLocalizations.override`)
///    actually translate the UI, and what rebuilds it when the app locale
///    changes at runtime.
/// 3. If no delegate is registered, [ChatUiLocalizations.of] falls back to
///    [ChatUiLocalizations.en], i.e. the previous behaviour.
///
/// ## Known limitation
///
/// "The host set [ChatTheme.l10n]" is detected with [identical] against the
/// canonical [ChatUiLocalizations.en] constant, because
/// [ChatUiLocalizations] does not define `operator ==`. So a theme carrying
/// that exact constant is indistinguishable from an untouched default and
/// still resolves from the ancestor. In practice that covers
/// [ChatUiLocalizations.en] itself and every call to
/// `ChatUiLocalizations.forLanguageCode` that returns it: `'en'`, `null`,
/// and any language code outside
/// [ChatUiLocalizations.supportedLanguageCodes].
///
/// A host that wants to pin English regardless of the app locale passes a
/// distinct instance: `ChatUiLocalizations.en.copyWith()` returns a fresh
/// object with identical strings, which step 1 honours. Anything built with
/// [ChatUiLocalizations.copyWith] (the usual way to tweak a few strings) is
/// already a distinct instance and is never affected.
extension ChatThemeL10n on ChatTheme {
  /// See [ChatThemeL10n] for the precedence rules and the `en` caveat.
  ChatUiLocalizations l10nOf(BuildContext context) =>
      identical(l10n, ChatUiLocalizations.en)
      ? ChatUiLocalizations.of(context)
      : l10n;
}

/// Font size of a message that is nothing but emoji.
///
/// A little over twice the 15pt body, which is where a lone `🍺` reads as a
/// gesture rather than as a word — the WhatsApp baseline. Overridable per
/// host through `ChatTheme.bubble.outgoing/incomingTextStyle`, whose own
/// `fontSize` is deliberately *not* honoured here: a host that sets a 13pt
/// body does not thereby ask for 13pt emoji.
const double kChatEmojiOnlyFontSize = 34;

/// How the bubble presents a message made only of emoji.
///
/// The pair moves together on purpose: enlarging the glyph inside the
/// coloured rectangle just makes a taller rectangle, and the point of the
/// baseline is that the emoji lands on the chat background with nothing
/// around it.
extension ChatEmojiOnlyPresentation on ChatTheme {
  /// The body style for an emoji-only message: the ordinary bubble text
  /// style, blown up to [kChatEmojiOnlyFontSize] and given a tight line
  /// height so a row of three does not leave a gutter above and below.
  TextStyle emojiOnlyTextStyle({required bool isOutgoing}) {
    final base =
        (isOutgoing ? bubble.outgoingTextStyle : bubble.incomingTextStyle) ??
        const TextStyle(fontSize: 15);
    return base.copyWith(fontSize: kChatEmojiOnlyFontSize, height: 1.15);
  }
}

/// Corner radius of every bottom sheet the SDK puts up.
///
/// 15, not the 16 the sheets used to hard-code each on their own. The chat
/// lives inside a host app whose own sheets round at 15, and one point of
/// difference is enough for the chat's sheet to read as a different
/// component pasted into the app — which is exactly how it was reported.
/// Overridable per host through `ThemeData.bottomSheetTheme.shape`.
const double kChatBottomSheetCornerRadius = 15;

/// The chrome every bottom sheet the SDK opens should wear.
///
/// Before this, each sheet called `showModalBottomSheet` with its own
/// arguments: eleven hard-coded a 16 radius, four passed no shape at all,
/// and exactly one set a background colour. With no background the sheet
/// falls through to Material's `surfaceContainerLow`, which under a warm
/// seed colour comes out cream — nothing writes that colour anywhere, it is
/// simply what Material derives when nobody says otherwise.
///
/// Both values defer to the host's own `ThemeData.bottomSheetTheme` when it
/// declares one, which is the standard Material lever and reaches every SDK
/// sheet at once; the SDK's defaults only fill the silence.
extension ChatSheetPresentation on ChatTheme {
  /// Background of an SDK bottom sheet: the host's `bottomSheetTheme` if it
  /// has one, else `colorScheme.surface` — the same resolution
  /// `FullEmojiPicker` already used, now shared.
  Color sheetBackgroundColor(BuildContext context) {
    final ambient = Theme.of(context);
    return ambient.bottomSheetTheme.backgroundColor ??
        ambient.colorScheme.surface;
  }

  /// Shape of an SDK bottom sheet: the host's `bottomSheetTheme.shape` if it
  /// has one, else [kChatBottomSheetCornerRadius] rounded on the top edge.
  ShapeBorder sheetShape(BuildContext context) =>
      Theme.of(context).bottomSheetTheme.shape ??
      const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(kChatBottomSheetCornerRadius),
        ),
      );

  /// Opens [builder] as a bottom sheet wearing [sheetBackgroundColor] and
  /// [sheetShape]. The single door every SDK sheet should go through, so
  /// "one bottom sheet for the whole app" stays true by construction
  /// instead of by fifteen call sites agreeing.
  ///
  /// [backgroundColor] exists for the one sheet that already exposed a
  /// dedicated host override ([ChatTheme.fullEmojiPickerBackgroundColor]);
  /// leave it null everywhere else so the sheet inherits the shared chrome.
  Future<T?> showSheet<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    Color? backgroundColor,
    bool? showDragHandle,
    bool isScrollControlled = true,
    bool useRootNavigator = true,
    bool isDismissible = true,
    bool enableDrag = true,
    bool useSafeArea = false,
  }) => showModalBottomSheet<T>(
    context: context,
    backgroundColor: backgroundColor ?? sheetBackgroundColor(context),
    shape: sheetShape(context),
    clipBehavior: Clip.antiAlias,
    showDragHandle: showDragHandle,
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: useSafeArea,
    builder: builder,
  );
}
