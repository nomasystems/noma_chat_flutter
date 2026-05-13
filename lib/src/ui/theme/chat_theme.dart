import 'package:flutter/material.dart';
import '../controller/voice_recording_controller.dart';
import '../l10n/chat_ui_localizations.dart';

/// Theming configuration for all chat UI Kit widgets.
///
/// All properties are optional and fall back to sensible defaults. Use
/// [copyWith] to override specific properties while keeping the rest.
/// Includes colors, text styles, border radii, and icons for every widget.
class ChatTheme {
  const ChatTheme({
    this.l10n = ChatUiLocalizations.en,
    this.outgoingBubbleColor,
    this.incomingBubbleColor,
    this.outgoingTextStyle,
    this.incomingTextStyle,
    this.bubbleBorderRadius,
    this.inputBackgroundColor,
    this.inputTextStyle,
    this.inputHintStyle,
    this.inputBorderColor,
    this.inputBorderWidth,
    this.inputBorderRadius,
    this.inputContainerShadow,
    this.sendButtonColor,
    this.sendButtonIcon,
    this.attachButtonIcon,
    this.attachButtonColor,
    this.voiceButtonIcon,
    this.voiceButtonColor,
    this.cameraButtonIcon,
    this.cameraButtonColor,
    this.attachIconBuilder,
    this.cameraIconBuilder,
    this.voiceIconBuilder,
    this.sendIconBuilder,
    this.recordingComposerBuilder,
    this.lockHintBuilder,
    this.locationMapBuilder,
    this.timestampTextStyle,
    this.outgoingTimestampTextStyle,
    this.incomingTimestampTextStyle,
    this.dateSeparatorTextStyle,
    this.systemMessageTextStyle,
    this.systemMessageBackgroundColor,
    this.typingIndicatorDotColor,
    this.messageStatusColor,
    this.messageStatusReadColor = const Color(0xFF2196F3),
    this.replyPreviewBackgroundColor,
    this.replyPreviewBarColor,
    this.reactionBackgroundColor,
    this.reactionSelectedColor,
    this.reactionSelectedBorderColor,
    this.reactionTextStyle,
    this.audioPlayButtonColor,
    this.audioSeekBarColor,
    this.audioSeekBarActiveColor,
    this.audioDurationTextStyle,
    this.imageBorderRadius,
    this.imageMaxHeight,
    this.videoPlayIconColor,
    this.videoPlayIconBackgroundColor,
    this.fileIconColor,
    this.fileNameTextStyle,
    this.fileSizeTextStyle,
    this.linkPreviewBackgroundColor,
    this.linkPreviewTitleStyle,
    this.linkPreviewDescriptionStyle,
    this.linkPreviewBorderRadius,
    this.voiceRecorderActiveColor,
    this.voiceRecorderTimerStyle,
    this.voiceRecorderOverlayColor,
    this.voiceRecorderCancelColor,
    this.voiceRecorderLockIconColor,
    this.voiceRecorderHintStyle,
    this.waveformActiveColor,
    this.waveformInactiveColor,
    this.waveformRecordingColor,
    this.audioSpeedButtonColor,
    this.audioSpeedTextStyle,
    this.audioListenedIconColor,
    this.audioUnlistenedIconColor,
    this.backgroundColor,
    this.backgroundImage,
    this.backgroundImageRepeat = ImageRepeat.noRepeat,
    this.backgroundImageOpacity = 1.0,
    this.backgroundImageColorFilter,
    this.avatarBackgroundColor,
    this.avatarInitialsTextStyle,
    this.avatarOnlineColor,
    this.avatarOfflineColor,
    this.connectionBannerColor,
    this.connectionBannerTextStyle,
    this.editedLabelTextStyle,
    this.forwardedLabelColor,
    this.forwardedLabelTextStyle,
    this.emptyStateIconColor,
    this.emptyStateTitleStyle,
    this.emptyStateSubtitleStyle,
    this.roomTileBackgroundColor,
    this.roomTileSelectedColor,
    this.roomNameTextStyle,
    this.roomPreviewTextStyle,
    this.roomPreviewUnreadTextStyle,
    this.roomTimestampTextStyle,
    this.roomTimestampUnreadTextStyle,
    this.unreadBadgeColor,
    this.unreadBadgeTextStyle,
    this.mutedIconColor,
    this.pinnedIconColor,
    this.suggestionsBarTitleStyle,
    this.suggestionsBarNameStyle,
    this.searchBarBackgroundColor,
    this.searchBarTextStyle,
    this.roomListHeaderTextStyle,
    this.editingBackgroundColor,
    this.editingBorderColor,
    this.editingLabelStyle,
    this.editingPreviewStyle,
    this.inputFillColor,
    this.sendButtonDisabledColor,
    this.dateSeparatorBackgroundColor,
    this.replyPreviewSenderStyle,
    this.replyPreviewTextStyle,
    this.senderNameStyle,
    this.avatarOnlineBorderColor,
    this.imageCaptionStyle,
    this.imageMaxWidth,
    this.linkPreviewDomainStyle,
    this.videoHeight,
    this.videoPlaceholderColor,
    this.videoBorderRadius,
    this.contextMenuHandleColor,
    this.contextMenuDestructiveColor,
    this.sendButtonIconColor,
    this.scrollToBottomButtonColor,
    this.scrollToBottomIconColor,
    this.attachmentPickerCircleColor,
    this.attachmentPickerIconColor,
    this.attachmentPickerLabelStyle,
    this.imageViewerBackgroundColor,
    this.imageViewerIconColor,
    this.linkPreviewBorderColor,
    this.connectionBannerErrorIconColor,
    this.roomListHeaderSelectedStyle,
    this.audioPlayIconColor,
    this.voiceButtonIdleIconColor,
    this.videoPlaceholderIconColor,
    this.reactionPickerElevation,
    this.reactionPickerBorderRadius,
    this.reactionPickerEmojiSize,
    this.reactionDetailSheetBackgroundColor,
    this.reactionDetailUserNameStyle,
    this.reactionDetailRemoveColor,
    this.floatingPickerBackgroundColor,
    this.fullEmojiPickerBackgroundColor,
    this.failedMessageIconColor,
    this.presenceAvailableColor,
    this.presenceAwayColor,
    this.presenceBusyColor,
    this.presenceDndColor,
    this.markdownBoldStyle,
    this.markdownItalicStyle,
    this.markdownCodeStyle,
    this.markdownStrikethroughStyle,
    this.markdownLinkStyle,
    this.markdownMentionStyle,
    this.typingStatusTextStyle,
  });

  final Color? outgoingBubbleColor;
  final Color? incomingBubbleColor;
  final TextStyle? outgoingTextStyle;
  final TextStyle? incomingTextStyle;
  final BorderRadius? bubbleBorderRadius;

  final Color? inputBackgroundColor;
  final TextStyle? inputTextStyle;

  /// Style applied to the placeholder text shown when the composer is empty.
  /// Falls back to the default Material hint when null.
  final TextStyle? inputHintStyle;

  /// Color of the composer text field's border. When null, no visible border
  /// is drawn (Material default).
  final Color? inputBorderColor;

  /// Width of the composer text field's border. Defaults to 1 when
  /// [inputBorderColor] is set and this is null.
  final double? inputBorderWidth;

  /// Radius of the composer text field's rounded corners. Defaults to 24 when
  /// null (legacy pill shape).
  final BorderRadius? inputBorderRadius;

  /// Optional shadow rendered behind the composer container. Useful to lift
  /// the input area above the conversation, mirroring a bottom navigation
  /// bar. Pass an empty list (or leave null) to disable.
  final List<BoxShadow>? inputContainerShadow;

  final Color? sendButtonColor;
  final IconData? sendButtonIcon;
  final IconData? attachButtonIcon;
  final Color? attachButtonColor;
  final IconData? voiceButtonIcon;
  final Color? voiceButtonColor;
  final IconData? cameraButtonIcon;
  final Color? cameraButtonColor;

  /// When provided, the composer renders this widget for the attach button
  /// instead of the [attachButtonIcon]. Useful for SVG/custom icons.
  final Widget Function(BuildContext context)? attachIconBuilder;

  /// Same as [attachIconBuilder] but for the camera shortcut button.
  final Widget Function(BuildContext context)? cameraIconBuilder;

  /// Same as [attachIconBuilder] but for the voice (microphone) button.
  final Widget Function(BuildContext context)? voiceIconBuilder;

  /// Builder for the send button icon. Receives whether the composer
  /// currently has text (true) or is empty (false), so the consumer can
  /// render different states. When provided, it replaces the circular
  /// background + Icon combo entirely.
  final Widget Function(BuildContext context, bool hasText)? sendIconBuilder;

  /// Builder for the inline composer rendered while the user is actively
  /// holding the microphone (state == VoiceRecordingState.recording). When
  /// null the default minimalist row (red mic / arrow / "slide to cancel"
  /// hint) is used. The callback receives the [VoiceRecordingController] so
  /// custom layouts can read state, plus an `onSend` shortcut for the right
  /// side of the row when relevant.
  final Widget Function(
    BuildContext context,
    VoiceRecordingController controller,
    VoidCallback onSend,
  )? recordingComposerBuilder;

  /// Builder for the floating "slide up to lock" hint that hovers above the
  /// microphone button while recording. When null a default vertical pill
  /// (lock icon + animated upwards arrow) is shown. Return
  /// [SizedBox.shrink] to disable it.
  final Widget Function(BuildContext context)? lockHintBuilder;

  /// Builder for the map preview inside [LocationBubble]. When provided, it
  /// replaces the default static map image. Useful to render a lightweight
  /// map widget (e.g. `GoogleMap` in lite mode) so the consumer can reuse the
  /// SDK that is already authorized in the host app.
  final Widget Function(BuildContext context, double latitude, double longitude)?
      locationMapBuilder;

  final TextStyle? timestampTextStyle;
  final TextStyle? outgoingTimestampTextStyle;
  final TextStyle? incomingTimestampTextStyle;
  final TextStyle? dateSeparatorTextStyle;
  final TextStyle? systemMessageTextStyle;
  final Color? systemMessageBackgroundColor;
  final Color? typingIndicatorDotColor;

  final Color? messageStatusColor;
  final Color? messageStatusReadColor;

  final Color? replyPreviewBackgroundColor;
  final Color? replyPreviewBarColor;

  final Color? reactionBackgroundColor;
  final Color? reactionSelectedColor;
  final Color? reactionSelectedBorderColor;
  final TextStyle? reactionTextStyle;

  final Color? audioPlayButtonColor;
  final Color? audioSeekBarColor;
  final Color? audioSeekBarActiveColor;
  final TextStyle? audioDurationTextStyle;

  final BorderRadius? imageBorderRadius;
  final double? imageMaxHeight;

  final Color? videoPlayIconColor;
  final Color? videoPlayIconBackgroundColor;

  final Color? fileIconColor;
  final TextStyle? fileNameTextStyle;
  final TextStyle? fileSizeTextStyle;

  final Color? linkPreviewBackgroundColor;
  final TextStyle? linkPreviewTitleStyle;
  final TextStyle? linkPreviewDescriptionStyle;
  final BorderRadius? linkPreviewBorderRadius;

  final Color? voiceRecorderActiveColor;
  final TextStyle? voiceRecorderTimerStyle;
  final Color? voiceRecorderOverlayColor;
  final Color? voiceRecorderCancelColor;
  final Color? voiceRecorderLockIconColor;
  final TextStyle? voiceRecorderHintStyle;
  final Color? waveformActiveColor;
  final Color? waveformInactiveColor;
  final Color? waveformRecordingColor;
  final Color? audioSpeedButtonColor;
  final TextStyle? audioSpeedTextStyle;
  final Color? audioListenedIconColor;
  final Color? audioUnlistenedIconColor;

  final Color? backgroundColor;
  final ImageProvider? backgroundImage;
  final ImageRepeat backgroundImageRepeat;
  final double backgroundImageOpacity;
  final ColorFilter? backgroundImageColorFilter;

  final Color? avatarBackgroundColor;
  final TextStyle? avatarInitialsTextStyle;
  final Color? avatarOnlineColor;
  final Color? avatarOfflineColor;

  final Color? connectionBannerColor;
  final TextStyle? connectionBannerTextStyle;

  final TextStyle? editedLabelTextStyle;

  final Color? forwardedLabelColor;
  final TextStyle? forwardedLabelTextStyle;

  final Color? emptyStateIconColor;
  final TextStyle? emptyStateTitleStyle;
  final TextStyle? emptyStateSubtitleStyle;

  final Color? roomTileBackgroundColor;
  final Color? roomTileSelectedColor;
  final TextStyle? roomNameTextStyle;
  final TextStyle? roomPreviewTextStyle;
  final TextStyle? roomPreviewUnreadTextStyle;
  final TextStyle? roomTimestampTextStyle;
  final TextStyle? roomTimestampUnreadTextStyle;
  final Color? unreadBadgeColor;
  final TextStyle? unreadBadgeTextStyle;
  final Color? mutedIconColor;
  final Color? pinnedIconColor;
  final TextStyle? suggestionsBarTitleStyle;
  final TextStyle? suggestionsBarNameStyle;
  final Color? searchBarBackgroundColor;
  final TextStyle? searchBarTextStyle;
  final TextStyle? roomListHeaderTextStyle;

  // Editing banner (MessageInput)
  final Color? editingBackgroundColor;
  final Color? editingBorderColor;
  final TextStyle? editingLabelStyle;
  final TextStyle? editingPreviewStyle;

  // Input field
  final Color? inputFillColor;
  final Color? sendButtonDisabledColor;

  // Date separator
  final Color? dateSeparatorBackgroundColor;

  // Reply preview
  final TextStyle? replyPreviewSenderStyle;
  final TextStyle? replyPreviewTextStyle;

  // Sender name in group chats
  final TextStyle? senderNameStyle;

  // Avatar online indicator
  final Color? avatarOnlineBorderColor;

  // Image bubble
  final TextStyle? imageCaptionStyle;
  final double? imageMaxWidth;

  // Link preview
  final TextStyle? linkPreviewDomainStyle;

  // Video bubble
  final double? videoHeight;
  final Color? videoPlaceholderColor;
  final BorderRadius? videoBorderRadius;

  // Context menus
  final Color? contextMenuHandleColor;
  final Color? contextMenuDestructiveColor;

  // Send button
  final Color? sendButtonIconColor;

  // Scroll to bottom
  final Color? scrollToBottomButtonColor;
  final Color? scrollToBottomIconColor;

  // Attachment picker
  final Color? attachmentPickerCircleColor;
  final Color? attachmentPickerIconColor;
  final TextStyle? attachmentPickerLabelStyle;

  // Image viewer
  final Color? imageViewerBackgroundColor;
  final Color? imageViewerIconColor;

  // Link preview border
  final Color? linkPreviewBorderColor;

  // Connection banner error
  final Color? connectionBannerErrorIconColor;

  // Room list header selection
  final TextStyle? roomListHeaderSelectedStyle;

  // Audio play button icon
  final Color? audioPlayIconColor;

  // Voice recorder idle icon
  final Color? voiceButtonIdleIconColor;

  // Video placeholder icon
  final Color? videoPlaceholderIconColor;

  // Reaction picker
  final double? reactionPickerElevation;
  final BorderRadius? reactionPickerBorderRadius;
  final double? reactionPickerEmojiSize;

  // Reaction detail sheet
  final Color? reactionDetailSheetBackgroundColor;
  final TextStyle? reactionDetailUserNameStyle;
  final Color? reactionDetailRemoveColor;

  // Emoji picker
  final Color? floatingPickerBackgroundColor;
  final Color? fullEmojiPickerBackgroundColor;

  // Failed message
  final Color? failedMessageIconColor;

  // Presence status colors
  final Color? presenceAvailableColor;
  final Color? presenceAwayColor;
  final Color? presenceBusyColor;
  final Color? presenceDndColor;

  // Markdown inline styles
  final TextStyle? markdownBoldStyle;
  final TextStyle? markdownItalicStyle;
  final TextStyle? markdownCodeStyle;
  final TextStyle? markdownStrikethroughStyle;
  final TextStyle? markdownLinkStyle;
  final TextStyle? markdownMentionStyle;
  final TextStyle? typingStatusTextStyle;

  final ChatUiLocalizations l10n;

  static const ChatTheme defaults = ChatTheme();

  static final ChatTheme dark = ChatTheme(
    outgoingBubbleColor: const Color(0xFF1B5E20),
    incomingBubbleColor: const Color(0xFF37474F),
    outgoingTextStyle: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 14),
    incomingTextStyle: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 14),
    inputTextStyle: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 14),
    inputBackgroundColor: const Color(0xFF263238),
    inputFillColor: const Color(0xFF37474F),
    backgroundColor: const Color(0xFF121212),
    sendButtonColor: const Color(0xFF4CAF50),
    timestampTextStyle: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 11),
    dateSeparatorTextStyle: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
    roomTileBackgroundColor: const Color(0xFF1E1E1E),
    roomNameTextStyle: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 16, fontWeight: FontWeight.w600),
    roomPreviewTextStyle: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
    roomPreviewUnreadTextStyle: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 14, fontWeight: FontWeight.w600),
    connectionBannerColor: const Color(0xFF37474F),
    connectionBannerTextStyle: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 13),
  );

  static final ChatTheme highContrast = ChatTheme(
    outgoingBubbleColor: const Color(0xFF000000),
    incomingBubbleColor: const Color(0xFFFFFFFF),
    outgoingTextStyle: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 18, fontWeight: FontWeight.w600),
    incomingTextStyle: const TextStyle(color: Color(0xFF000000), fontSize: 18, fontWeight: FontWeight.w600),
    inputTextStyle: const TextStyle(color: Color(0xFF000000), fontSize: 18),
    inputBackgroundColor: const Color(0xFFFFFFFF),
    backgroundColor: const Color(0xFFF5F5F5),
    sendButtonColor: const Color(0xFF000000),
    timestampTextStyle: const TextStyle(color: Color(0xFF424242), fontSize: 14, fontWeight: FontWeight.w500),
    dateSeparatorTextStyle: const TextStyle(color: Color(0xFF212121), fontSize: 16, fontWeight: FontWeight.bold),
    roomNameTextStyle: const TextStyle(color: Color(0xFF000000), fontSize: 18, fontWeight: FontWeight.bold),
    roomPreviewTextStyle: const TextStyle(color: Color(0xFF424242), fontSize: 16),
    roomPreviewUnreadTextStyle: const TextStyle(color: Color(0xFF000000), fontSize: 16, fontWeight: FontWeight.bold),
    connectionBannerColor: const Color(0xFFFF0000),
    connectionBannerTextStyle: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 16, fontWeight: FontWeight.bold),
  );

  ChatTheme copyWith({
    ChatUiLocalizations? l10n,
    Color? outgoingBubbleColor,
    Color? incomingBubbleColor,
    TextStyle? outgoingTextStyle,
    TextStyle? incomingTextStyle,
    BorderRadius? bubbleBorderRadius,
    Color? inputBackgroundColor,
    TextStyle? inputTextStyle,
    TextStyle? inputHintStyle,
    Color? inputBorderColor,
    double? inputBorderWidth,
    BorderRadius? inputBorderRadius,
    List<BoxShadow>? inputContainerShadow,
    Color? sendButtonColor,
    IconData? sendButtonIcon,
    IconData? attachButtonIcon,
    Color? attachButtonColor,
    IconData? voiceButtonIcon,
    Color? voiceButtonColor,
    IconData? cameraButtonIcon,
    Color? cameraButtonColor,
    Widget Function(BuildContext context)? attachIconBuilder,
    Widget Function(BuildContext context)? cameraIconBuilder,
    Widget Function(BuildContext context)? voiceIconBuilder,
    Widget Function(BuildContext context, bool hasText)? sendIconBuilder,
    Widget Function(
      BuildContext context,
      VoiceRecordingController controller,
      VoidCallback onSend,
    )? recordingComposerBuilder,
    Widget Function(BuildContext context)? lockHintBuilder,
    Widget Function(BuildContext context, double latitude, double longitude)?
        locationMapBuilder,
    TextStyle? timestampTextStyle,
    TextStyle? outgoingTimestampTextStyle,
    TextStyle? incomingTimestampTextStyle,
    TextStyle? dateSeparatorTextStyle,
    TextStyle? systemMessageTextStyle,
    Color? systemMessageBackgroundColor,
    Color? typingIndicatorDotColor,
    Color? messageStatusColor,
    Color? messageStatusReadColor,
    Color? replyPreviewBackgroundColor,
    Color? replyPreviewBarColor,
    Color? reactionBackgroundColor,
    Color? reactionSelectedColor,
    Color? reactionSelectedBorderColor,
    TextStyle? reactionTextStyle,
    Color? audioPlayButtonColor,
    Color? audioSeekBarColor,
    Color? audioSeekBarActiveColor,
    TextStyle? audioDurationTextStyle,
    BorderRadius? imageBorderRadius,
    double? imageMaxHeight,
    Color? videoPlayIconColor,
    Color? videoPlayIconBackgroundColor,
    Color? fileIconColor,
    TextStyle? fileNameTextStyle,
    TextStyle? fileSizeTextStyle,
    Color? linkPreviewBackgroundColor,
    TextStyle? linkPreviewTitleStyle,
    TextStyle? linkPreviewDescriptionStyle,
    BorderRadius? linkPreviewBorderRadius,
    Color? voiceRecorderActiveColor,
    TextStyle? voiceRecorderTimerStyle,
    Color? voiceRecorderOverlayColor,
    Color? voiceRecorderCancelColor,
    Color? voiceRecorderLockIconColor,
    TextStyle? voiceRecorderHintStyle,
    Color? waveformActiveColor,
    Color? waveformInactiveColor,
    Color? waveformRecordingColor,
    Color? audioSpeedButtonColor,
    TextStyle? audioSpeedTextStyle,
    Color? audioListenedIconColor,
    Color? audioUnlistenedIconColor,
    Color? backgroundColor,
    ImageProvider? backgroundImage,
    ImageRepeat? backgroundImageRepeat,
    double? backgroundImageOpacity,
    ColorFilter? backgroundImageColorFilter,
    Color? avatarBackgroundColor,
    TextStyle? avatarInitialsTextStyle,
    Color? avatarOnlineColor,
    Color? avatarOfflineColor,
    Color? connectionBannerColor,
    TextStyle? connectionBannerTextStyle,
    TextStyle? editedLabelTextStyle,
    Color? forwardedLabelColor,
    TextStyle? forwardedLabelTextStyle,
    Color? emptyStateIconColor,
    TextStyle? emptyStateTitleStyle,
    TextStyle? emptyStateSubtitleStyle,
    Color? roomTileBackgroundColor,
    Color? roomTileSelectedColor,
    TextStyle? roomNameTextStyle,
    TextStyle? roomPreviewTextStyle,
    TextStyle? roomPreviewUnreadTextStyle,
    TextStyle? roomTimestampTextStyle,
    TextStyle? roomTimestampUnreadTextStyle,
    Color? unreadBadgeColor,
    TextStyle? unreadBadgeTextStyle,
    Color? mutedIconColor,
    Color? pinnedIconColor,
    TextStyle? suggestionsBarTitleStyle,
    TextStyle? suggestionsBarNameStyle,
    Color? searchBarBackgroundColor,
    TextStyle? searchBarTextStyle,
    TextStyle? roomListHeaderTextStyle,
    Color? editingBackgroundColor,
    Color? editingBorderColor,
    TextStyle? editingLabelStyle,
    TextStyle? editingPreviewStyle,
    Color? inputFillColor,
    Color? sendButtonDisabledColor,
    Color? dateSeparatorBackgroundColor,
    TextStyle? replyPreviewSenderStyle,
    TextStyle? replyPreviewTextStyle,
    TextStyle? senderNameStyle,
    Color? avatarOnlineBorderColor,
    TextStyle? imageCaptionStyle,
    double? imageMaxWidth,
    TextStyle? linkPreviewDomainStyle,
    double? videoHeight,
    Color? videoPlaceholderColor,
    BorderRadius? videoBorderRadius,
    Color? contextMenuHandleColor,
    Color? contextMenuDestructiveColor,
    Color? sendButtonIconColor,
    Color? scrollToBottomButtonColor,
    Color? scrollToBottomIconColor,
    Color? attachmentPickerCircleColor,
    Color? attachmentPickerIconColor,
    TextStyle? attachmentPickerLabelStyle,
    Color? imageViewerBackgroundColor,
    Color? imageViewerIconColor,
    Color? linkPreviewBorderColor,
    Color? connectionBannerErrorIconColor,
    TextStyle? roomListHeaderSelectedStyle,
    Color? audioPlayIconColor,
    Color? voiceButtonIdleIconColor,
    Color? videoPlaceholderIconColor,
    double? reactionPickerElevation,
    BorderRadius? reactionPickerBorderRadius,
    double? reactionPickerEmojiSize,
    Color? reactionDetailSheetBackgroundColor,
    TextStyle? reactionDetailUserNameStyle,
    Color? reactionDetailRemoveColor,
    Color? floatingPickerBackgroundColor,
    Color? fullEmojiPickerBackgroundColor,
    Color? failedMessageIconColor,
    Color? presenceAvailableColor,
    Color? presenceAwayColor,
    Color? presenceBusyColor,
    Color? presenceDndColor,
    TextStyle? markdownBoldStyle,
    TextStyle? markdownItalicStyle,
    TextStyle? markdownCodeStyle,
    TextStyle? markdownStrikethroughStyle,
    TextStyle? markdownLinkStyle,
    TextStyle? markdownMentionStyle,
    TextStyle? typingStatusTextStyle,
  }) {
    return ChatTheme(
      l10n: l10n ?? this.l10n,
      outgoingBubbleColor: outgoingBubbleColor ?? this.outgoingBubbleColor,
      incomingBubbleColor: incomingBubbleColor ?? this.incomingBubbleColor,
      outgoingTextStyle: outgoingTextStyle ?? this.outgoingTextStyle,
      incomingTextStyle: incomingTextStyle ?? this.incomingTextStyle,
      bubbleBorderRadius: bubbleBorderRadius ?? this.bubbleBorderRadius,
      inputBackgroundColor: inputBackgroundColor ?? this.inputBackgroundColor,
      inputTextStyle: inputTextStyle ?? this.inputTextStyle,
      inputHintStyle: inputHintStyle ?? this.inputHintStyle,
      inputBorderColor: inputBorderColor ?? this.inputBorderColor,
      inputBorderWidth: inputBorderWidth ?? this.inputBorderWidth,
      inputBorderRadius: inputBorderRadius ?? this.inputBorderRadius,
      inputContainerShadow: inputContainerShadow ?? this.inputContainerShadow,
      sendButtonColor: sendButtonColor ?? this.sendButtonColor,
      sendButtonIcon: sendButtonIcon ?? this.sendButtonIcon,
      attachButtonIcon: attachButtonIcon ?? this.attachButtonIcon,
      attachButtonColor: attachButtonColor ?? this.attachButtonColor,
      voiceButtonIcon: voiceButtonIcon ?? this.voiceButtonIcon,
      voiceButtonColor: voiceButtonColor ?? this.voiceButtonColor,
      cameraButtonIcon: cameraButtonIcon ?? this.cameraButtonIcon,
      cameraButtonColor: cameraButtonColor ?? this.cameraButtonColor,
      attachIconBuilder: attachIconBuilder ?? this.attachIconBuilder,
      cameraIconBuilder: cameraIconBuilder ?? this.cameraIconBuilder,
      voiceIconBuilder: voiceIconBuilder ?? this.voiceIconBuilder,
      sendIconBuilder: sendIconBuilder ?? this.sendIconBuilder,
      recordingComposerBuilder:
          recordingComposerBuilder ?? this.recordingComposerBuilder,
      lockHintBuilder: lockHintBuilder ?? this.lockHintBuilder,
      locationMapBuilder: locationMapBuilder ?? this.locationMapBuilder,
      timestampTextStyle: timestampTextStyle ?? this.timestampTextStyle,
      outgoingTimestampTextStyle: outgoingTimestampTextStyle ?? this.outgoingTimestampTextStyle,
      incomingTimestampTextStyle: incomingTimestampTextStyle ?? this.incomingTimestampTextStyle,
      dateSeparatorTextStyle: dateSeparatorTextStyle ?? this.dateSeparatorTextStyle,
      systemMessageTextStyle: systemMessageTextStyle ?? this.systemMessageTextStyle,
      systemMessageBackgroundColor: systemMessageBackgroundColor ?? this.systemMessageBackgroundColor,
      typingIndicatorDotColor: typingIndicatorDotColor ?? this.typingIndicatorDotColor,
      messageStatusColor: messageStatusColor ?? this.messageStatusColor,
      messageStatusReadColor: messageStatusReadColor ?? this.messageStatusReadColor,
      replyPreviewBackgroundColor: replyPreviewBackgroundColor ?? this.replyPreviewBackgroundColor,
      replyPreviewBarColor: replyPreviewBarColor ?? this.replyPreviewBarColor,
      reactionBackgroundColor: reactionBackgroundColor ?? this.reactionBackgroundColor,
      reactionSelectedColor: reactionSelectedColor ?? this.reactionSelectedColor,
      reactionSelectedBorderColor: reactionSelectedBorderColor ?? this.reactionSelectedBorderColor,
      reactionTextStyle: reactionTextStyle ?? this.reactionTextStyle,
      audioPlayButtonColor: audioPlayButtonColor ?? this.audioPlayButtonColor,
      audioSeekBarColor: audioSeekBarColor ?? this.audioSeekBarColor,
      audioSeekBarActiveColor: audioSeekBarActiveColor ?? this.audioSeekBarActiveColor,
      audioDurationTextStyle: audioDurationTextStyle ?? this.audioDurationTextStyle,
      imageBorderRadius: imageBorderRadius ?? this.imageBorderRadius,
      imageMaxHeight: imageMaxHeight ?? this.imageMaxHeight,
      videoPlayIconColor: videoPlayIconColor ?? this.videoPlayIconColor,
      videoPlayIconBackgroundColor: videoPlayIconBackgroundColor ?? this.videoPlayIconBackgroundColor,
      fileIconColor: fileIconColor ?? this.fileIconColor,
      fileNameTextStyle: fileNameTextStyle ?? this.fileNameTextStyle,
      fileSizeTextStyle: fileSizeTextStyle ?? this.fileSizeTextStyle,
      linkPreviewBackgroundColor: linkPreviewBackgroundColor ?? this.linkPreviewBackgroundColor,
      linkPreviewTitleStyle: linkPreviewTitleStyle ?? this.linkPreviewTitleStyle,
      linkPreviewDescriptionStyle: linkPreviewDescriptionStyle ?? this.linkPreviewDescriptionStyle,
      linkPreviewBorderRadius: linkPreviewBorderRadius ?? this.linkPreviewBorderRadius,
      voiceRecorderActiveColor: voiceRecorderActiveColor ?? this.voiceRecorderActiveColor,
      voiceRecorderTimerStyle: voiceRecorderTimerStyle ?? this.voiceRecorderTimerStyle,
      voiceRecorderOverlayColor: voiceRecorderOverlayColor ?? this.voiceRecorderOverlayColor,
      voiceRecorderCancelColor: voiceRecorderCancelColor ?? this.voiceRecorderCancelColor,
      voiceRecorderLockIconColor: voiceRecorderLockIconColor ?? this.voiceRecorderLockIconColor,
      voiceRecorderHintStyle: voiceRecorderHintStyle ?? this.voiceRecorderHintStyle,
      waveformActiveColor: waveformActiveColor ?? this.waveformActiveColor,
      waveformInactiveColor: waveformInactiveColor ?? this.waveformInactiveColor,
      waveformRecordingColor: waveformRecordingColor ?? this.waveformRecordingColor,
      audioSpeedButtonColor: audioSpeedButtonColor ?? this.audioSpeedButtonColor,
      audioSpeedTextStyle: audioSpeedTextStyle ?? this.audioSpeedTextStyle,
      audioListenedIconColor: audioListenedIconColor ?? this.audioListenedIconColor,
      audioUnlistenedIconColor: audioUnlistenedIconColor ?? this.audioUnlistenedIconColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundImage: backgroundImage ?? this.backgroundImage,
      backgroundImageRepeat: backgroundImageRepeat ?? this.backgroundImageRepeat,
      backgroundImageOpacity: backgroundImageOpacity ?? this.backgroundImageOpacity,
      backgroundImageColorFilter: backgroundImageColorFilter ?? this.backgroundImageColorFilter,
      avatarBackgroundColor: avatarBackgroundColor ?? this.avatarBackgroundColor,
      avatarInitialsTextStyle: avatarInitialsTextStyle ?? this.avatarInitialsTextStyle,
      avatarOnlineColor: avatarOnlineColor ?? this.avatarOnlineColor,
      avatarOfflineColor: avatarOfflineColor ?? this.avatarOfflineColor,
      connectionBannerColor: connectionBannerColor ?? this.connectionBannerColor,
      connectionBannerTextStyle: connectionBannerTextStyle ?? this.connectionBannerTextStyle,
      editedLabelTextStyle: editedLabelTextStyle ?? this.editedLabelTextStyle,
      forwardedLabelColor: forwardedLabelColor ?? this.forwardedLabelColor,
      forwardedLabelTextStyle: forwardedLabelTextStyle ?? this.forwardedLabelTextStyle,
      emptyStateIconColor: emptyStateIconColor ?? this.emptyStateIconColor,
      emptyStateTitleStyle: emptyStateTitleStyle ?? this.emptyStateTitleStyle,
      emptyStateSubtitleStyle: emptyStateSubtitleStyle ?? this.emptyStateSubtitleStyle,
      roomTileBackgroundColor: roomTileBackgroundColor ?? this.roomTileBackgroundColor,
      roomTileSelectedColor: roomTileSelectedColor ?? this.roomTileSelectedColor,
      roomNameTextStyle: roomNameTextStyle ?? this.roomNameTextStyle,
      roomPreviewTextStyle: roomPreviewTextStyle ?? this.roomPreviewTextStyle,
      roomPreviewUnreadTextStyle: roomPreviewUnreadTextStyle ?? this.roomPreviewUnreadTextStyle,
      roomTimestampTextStyle: roomTimestampTextStyle ?? this.roomTimestampTextStyle,
      roomTimestampUnreadTextStyle: roomTimestampUnreadTextStyle ?? this.roomTimestampUnreadTextStyle,
      unreadBadgeColor: unreadBadgeColor ?? this.unreadBadgeColor,
      unreadBadgeTextStyle: unreadBadgeTextStyle ?? this.unreadBadgeTextStyle,
      mutedIconColor: mutedIconColor ?? this.mutedIconColor,
      pinnedIconColor: pinnedIconColor ?? this.pinnedIconColor,
      suggestionsBarTitleStyle: suggestionsBarTitleStyle ?? this.suggestionsBarTitleStyle,
      suggestionsBarNameStyle: suggestionsBarNameStyle ?? this.suggestionsBarNameStyle,
      searchBarBackgroundColor: searchBarBackgroundColor ?? this.searchBarBackgroundColor,
      searchBarTextStyle: searchBarTextStyle ?? this.searchBarTextStyle,
      roomListHeaderTextStyle: roomListHeaderTextStyle ?? this.roomListHeaderTextStyle,
      editingBackgroundColor: editingBackgroundColor ?? this.editingBackgroundColor,
      editingBorderColor: editingBorderColor ?? this.editingBorderColor,
      editingLabelStyle: editingLabelStyle ?? this.editingLabelStyle,
      editingPreviewStyle: editingPreviewStyle ?? this.editingPreviewStyle,
      inputFillColor: inputFillColor ?? this.inputFillColor,
      sendButtonDisabledColor: sendButtonDisabledColor ?? this.sendButtonDisabledColor,
      dateSeparatorBackgroundColor: dateSeparatorBackgroundColor ?? this.dateSeparatorBackgroundColor,
      replyPreviewSenderStyle: replyPreviewSenderStyle ?? this.replyPreviewSenderStyle,
      replyPreviewTextStyle: replyPreviewTextStyle ?? this.replyPreviewTextStyle,
      senderNameStyle: senderNameStyle ?? this.senderNameStyle,
      avatarOnlineBorderColor: avatarOnlineBorderColor ?? this.avatarOnlineBorderColor,
      imageCaptionStyle: imageCaptionStyle ?? this.imageCaptionStyle,
      imageMaxWidth: imageMaxWidth ?? this.imageMaxWidth,
      linkPreviewDomainStyle: linkPreviewDomainStyle ?? this.linkPreviewDomainStyle,
      videoHeight: videoHeight ?? this.videoHeight,
      videoPlaceholderColor: videoPlaceholderColor ?? this.videoPlaceholderColor,
      videoBorderRadius: videoBorderRadius ?? this.videoBorderRadius,
      contextMenuHandleColor: contextMenuHandleColor ?? this.contextMenuHandleColor,
      contextMenuDestructiveColor: contextMenuDestructiveColor ?? this.contextMenuDestructiveColor,
      sendButtonIconColor: sendButtonIconColor ?? this.sendButtonIconColor,
      scrollToBottomButtonColor: scrollToBottomButtonColor ?? this.scrollToBottomButtonColor,
      scrollToBottomIconColor: scrollToBottomIconColor ?? this.scrollToBottomIconColor,
      attachmentPickerCircleColor: attachmentPickerCircleColor ?? this.attachmentPickerCircleColor,
      attachmentPickerIconColor: attachmentPickerIconColor ?? this.attachmentPickerIconColor,
      attachmentPickerLabelStyle: attachmentPickerLabelStyle ?? this.attachmentPickerLabelStyle,
      imageViewerBackgroundColor: imageViewerBackgroundColor ?? this.imageViewerBackgroundColor,
      imageViewerIconColor: imageViewerIconColor ?? this.imageViewerIconColor,
      linkPreviewBorderColor: linkPreviewBorderColor ?? this.linkPreviewBorderColor,
      connectionBannerErrorIconColor: connectionBannerErrorIconColor ?? this.connectionBannerErrorIconColor,
      roomListHeaderSelectedStyle: roomListHeaderSelectedStyle ?? this.roomListHeaderSelectedStyle,
      audioPlayIconColor: audioPlayIconColor ?? this.audioPlayIconColor,
      voiceButtonIdleIconColor: voiceButtonIdleIconColor ?? this.voiceButtonIdleIconColor,
      videoPlaceholderIconColor: videoPlaceholderIconColor ?? this.videoPlaceholderIconColor,
      reactionPickerElevation: reactionPickerElevation ?? this.reactionPickerElevation,
      reactionPickerBorderRadius: reactionPickerBorderRadius ?? this.reactionPickerBorderRadius,
      reactionPickerEmojiSize: reactionPickerEmojiSize ?? this.reactionPickerEmojiSize,
      reactionDetailSheetBackgroundColor: reactionDetailSheetBackgroundColor ?? this.reactionDetailSheetBackgroundColor,
      reactionDetailUserNameStyle: reactionDetailUserNameStyle ?? this.reactionDetailUserNameStyle,
      reactionDetailRemoveColor: reactionDetailRemoveColor ?? this.reactionDetailRemoveColor,
      floatingPickerBackgroundColor: floatingPickerBackgroundColor ?? this.floatingPickerBackgroundColor,
      fullEmojiPickerBackgroundColor: fullEmojiPickerBackgroundColor ?? this.fullEmojiPickerBackgroundColor,
      failedMessageIconColor: failedMessageIconColor ?? this.failedMessageIconColor,
      presenceAvailableColor: presenceAvailableColor ?? this.presenceAvailableColor,
      presenceAwayColor: presenceAwayColor ?? this.presenceAwayColor,
      presenceBusyColor: presenceBusyColor ?? this.presenceBusyColor,
      presenceDndColor: presenceDndColor ?? this.presenceDndColor,
      markdownBoldStyle: markdownBoldStyle ?? this.markdownBoldStyle,
      markdownItalicStyle: markdownItalicStyle ?? this.markdownItalicStyle,
      markdownCodeStyle: markdownCodeStyle ?? this.markdownCodeStyle,
      markdownStrikethroughStyle: markdownStrikethroughStyle ?? this.markdownStrikethroughStyle,
      markdownLinkStyle: markdownLinkStyle ?? this.markdownLinkStyle,
      markdownMentionStyle: markdownMentionStyle ?? this.markdownMentionStyle,
      typingStatusTextStyle: typingStatusTextStyle ?? this.typingStatusTextStyle,
    );
  }
}
