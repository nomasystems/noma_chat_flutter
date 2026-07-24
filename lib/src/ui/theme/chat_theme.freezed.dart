// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat_theme.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ChatTheme {

 ChatUiLocalizations get l10n; ChatBubbleTheme get bubble; ChatInputTheme get input; ChatRoomListTheme get roomList; ChatMarkdownTheme get markdown;/// Custom builder for the map preview inside `LocationBubble`. When
/// provided, replaces the default static map image — useful for apps
/// that already have a maps SDK authorised and want to render a
/// lightweight interactive map (e.g. `GoogleMap` in lite mode).
 Widget Function(BuildContext, double latitude, double longitude)? get locationMapBuilder;// Date separator + system messages
 TextStyle? get dateSeparatorTextStyle; Color? get dateSeparatorBackgroundColor; TextStyle? get systemMessageTextStyle; Color? get systemMessageBackgroundColor;// Typing indicator (bubble + status text in room tiles)
 Color? get typingIndicatorDotColor; TextStyle? get typingStatusTextStyle;// Reactions (bar + picker + detail sheet + emoji picker)
 Color? get reactionBackgroundColor; Color? get reactionSelectedColor; Color? get reactionSelectedBorderColor; TextStyle? get reactionTextStyle; double? get reactionPickerElevation; BorderRadius? get reactionPickerBorderRadius; double? get reactionPickerEmojiSize; Color? get reactionDetailSheetBackgroundColor; TextStyle? get reactionDetailUserNameStyle; Color? get reactionDetailRemoveColor; Color? get floatingPickerBackgroundColor; Color? get fullEmojiPickerBackgroundColor;// Audio bubble + voice recorder + waveform
 Color? get audioPlayButtonColor; Color? get audioPlayIconColor; Color? get audioSeekBarColor; Color? get audioSeekBarActiveColor; TextStyle? get audioDurationTextStyle; Color? get audioSpeedButtonColor; TextStyle? get audioSpeedTextStyle; Color? get audioListenedIconColor; Color? get audioUnlistenedIconColor; Color? get voiceRecorderActiveColor; TextStyle? get voiceRecorderTimerStyle; Color? get voiceRecorderOverlayColor; Color? get voiceRecorderCancelColor; Color? get voiceRecorderLockIconColor; TextStyle? get voiceRecorderHintStyle; Color? get waveformActiveColor; Color? get waveformInactiveColor; Color? get waveformRecordingColor;// Image / Video / File / Link Preview bubbles
 BorderRadius? get imageBorderRadius; double? get imageMaxHeight; double? get imageMaxWidth; TextStyle? get imageCaptionStyle; Color? get videoPlayIconColor; Color? get videoPlayIconBackgroundColor; Color? get videoPlaceholderIconColor; double? get videoHeight; Color? get videoPlaceholderColor; BorderRadius? get videoBorderRadius; Color? get fileIconColor; TextStyle? get fileNameTextStyle; TextStyle? get fileSizeTextStyle; Color? get linkPreviewBackgroundColor; TextStyle? get linkPreviewTitleStyle; TextStyle? get linkPreviewDescriptionStyle; BorderRadius? get linkPreviewBorderRadius; TextStyle? get linkPreviewDomainStyle; Color? get linkPreviewBorderColor;// Chat background
 Color? get backgroundColor; ImageProvider? get backgroundImage; ImageRepeat get backgroundImageRepeat; double get backgroundImageOpacity; ColorFilter? get backgroundImageColorFilter;// Avatar
 Color? get avatarBackgroundColor; TextStyle? get avatarInitialsTextStyle; Color? get avatarOnlineColor; Color? get avatarOfflineColor; Color? get avatarOnlineBorderColor;// Connection banner + empty state
 Color? get connectionBannerColor; TextStyle? get connectionBannerTextStyle; Color? get connectionBannerErrorIconColor; Color? get emptyStateIconColor; TextStyle? get emptyStateTitleStyle; TextStyle? get emptyStateSubtitleStyle;// Context menus + scroll to bottom + attachment picker + image viewer
 Color? get contextMenuHandleColor; Color? get contextMenuDestructiveColor; Color? get scrollToBottomButtonColor; Color? get scrollToBottomIconColor; Color? get attachmentPickerCircleColor; Color? get attachmentPickerIconColor; TextStyle? get attachmentPickerLabelStyle; Color? get imageViewerBackgroundColor; Color? get imageViewerIconColor;// Presence dots
 Color? get presenceAvailableColor; Color? get presenceAwayColor; Color? get presenceBusyColor; Color? get presenceDndColor;// Media Gallery page (`MediaGalleryPage`'s own Scaffold/AppBar/TabBar
// chrome — everything else in the page already reads `backgroundColor`
// via its child widgets). `null` falls back to the ambient Material
// `Theme`, unchanged from before these fields existed.
 Color? get galleryAppBarBackgroundColor; Color? get galleryAppBarForegroundColor; Color? get galleryTabIndicatorColor;
/// Create a copy of ChatTheme
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatThemeCopyWith<ChatTheme> get copyWith => _$ChatThemeCopyWithImpl<ChatTheme>(this as ChatTheme, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatTheme&&(identical(other.l10n, l10n) || other.l10n == l10n)&&(identical(other.bubble, bubble) || other.bubble == bubble)&&(identical(other.input, input) || other.input == input)&&(identical(other.roomList, roomList) || other.roomList == roomList)&&(identical(other.markdown, markdown) || other.markdown == markdown)&&(identical(other.locationMapBuilder, locationMapBuilder) || other.locationMapBuilder == locationMapBuilder)&&(identical(other.dateSeparatorTextStyle, dateSeparatorTextStyle) || other.dateSeparatorTextStyle == dateSeparatorTextStyle)&&(identical(other.dateSeparatorBackgroundColor, dateSeparatorBackgroundColor) || other.dateSeparatorBackgroundColor == dateSeparatorBackgroundColor)&&(identical(other.systemMessageTextStyle, systemMessageTextStyle) || other.systemMessageTextStyle == systemMessageTextStyle)&&(identical(other.systemMessageBackgroundColor, systemMessageBackgroundColor) || other.systemMessageBackgroundColor == systemMessageBackgroundColor)&&(identical(other.typingIndicatorDotColor, typingIndicatorDotColor) || other.typingIndicatorDotColor == typingIndicatorDotColor)&&(identical(other.typingStatusTextStyle, typingStatusTextStyle) || other.typingStatusTextStyle == typingStatusTextStyle)&&(identical(other.reactionBackgroundColor, reactionBackgroundColor) || other.reactionBackgroundColor == reactionBackgroundColor)&&(identical(other.reactionSelectedColor, reactionSelectedColor) || other.reactionSelectedColor == reactionSelectedColor)&&(identical(other.reactionSelectedBorderColor, reactionSelectedBorderColor) || other.reactionSelectedBorderColor == reactionSelectedBorderColor)&&(identical(other.reactionTextStyle, reactionTextStyle) || other.reactionTextStyle == reactionTextStyle)&&(identical(other.reactionPickerElevation, reactionPickerElevation) || other.reactionPickerElevation == reactionPickerElevation)&&(identical(other.reactionPickerBorderRadius, reactionPickerBorderRadius) || other.reactionPickerBorderRadius == reactionPickerBorderRadius)&&(identical(other.reactionPickerEmojiSize, reactionPickerEmojiSize) || other.reactionPickerEmojiSize == reactionPickerEmojiSize)&&(identical(other.reactionDetailSheetBackgroundColor, reactionDetailSheetBackgroundColor) || other.reactionDetailSheetBackgroundColor == reactionDetailSheetBackgroundColor)&&(identical(other.reactionDetailUserNameStyle, reactionDetailUserNameStyle) || other.reactionDetailUserNameStyle == reactionDetailUserNameStyle)&&(identical(other.reactionDetailRemoveColor, reactionDetailRemoveColor) || other.reactionDetailRemoveColor == reactionDetailRemoveColor)&&(identical(other.floatingPickerBackgroundColor, floatingPickerBackgroundColor) || other.floatingPickerBackgroundColor == floatingPickerBackgroundColor)&&(identical(other.fullEmojiPickerBackgroundColor, fullEmojiPickerBackgroundColor) || other.fullEmojiPickerBackgroundColor == fullEmojiPickerBackgroundColor)&&(identical(other.audioPlayButtonColor, audioPlayButtonColor) || other.audioPlayButtonColor == audioPlayButtonColor)&&(identical(other.audioPlayIconColor, audioPlayIconColor) || other.audioPlayIconColor == audioPlayIconColor)&&(identical(other.audioSeekBarColor, audioSeekBarColor) || other.audioSeekBarColor == audioSeekBarColor)&&(identical(other.audioSeekBarActiveColor, audioSeekBarActiveColor) || other.audioSeekBarActiveColor == audioSeekBarActiveColor)&&(identical(other.audioDurationTextStyle, audioDurationTextStyle) || other.audioDurationTextStyle == audioDurationTextStyle)&&(identical(other.audioSpeedButtonColor, audioSpeedButtonColor) || other.audioSpeedButtonColor == audioSpeedButtonColor)&&(identical(other.audioSpeedTextStyle, audioSpeedTextStyle) || other.audioSpeedTextStyle == audioSpeedTextStyle)&&(identical(other.audioListenedIconColor, audioListenedIconColor) || other.audioListenedIconColor == audioListenedIconColor)&&(identical(other.audioUnlistenedIconColor, audioUnlistenedIconColor) || other.audioUnlistenedIconColor == audioUnlistenedIconColor)&&(identical(other.voiceRecorderActiveColor, voiceRecorderActiveColor) || other.voiceRecorderActiveColor == voiceRecorderActiveColor)&&(identical(other.voiceRecorderTimerStyle, voiceRecorderTimerStyle) || other.voiceRecorderTimerStyle == voiceRecorderTimerStyle)&&(identical(other.voiceRecorderOverlayColor, voiceRecorderOverlayColor) || other.voiceRecorderOverlayColor == voiceRecorderOverlayColor)&&(identical(other.voiceRecorderCancelColor, voiceRecorderCancelColor) || other.voiceRecorderCancelColor == voiceRecorderCancelColor)&&(identical(other.voiceRecorderLockIconColor, voiceRecorderLockIconColor) || other.voiceRecorderLockIconColor == voiceRecorderLockIconColor)&&(identical(other.voiceRecorderHintStyle, voiceRecorderHintStyle) || other.voiceRecorderHintStyle == voiceRecorderHintStyle)&&(identical(other.waveformActiveColor, waveformActiveColor) || other.waveformActiveColor == waveformActiveColor)&&(identical(other.waveformInactiveColor, waveformInactiveColor) || other.waveformInactiveColor == waveformInactiveColor)&&(identical(other.waveformRecordingColor, waveformRecordingColor) || other.waveformRecordingColor == waveformRecordingColor)&&(identical(other.imageBorderRadius, imageBorderRadius) || other.imageBorderRadius == imageBorderRadius)&&(identical(other.imageMaxHeight, imageMaxHeight) || other.imageMaxHeight == imageMaxHeight)&&(identical(other.imageMaxWidth, imageMaxWidth) || other.imageMaxWidth == imageMaxWidth)&&(identical(other.imageCaptionStyle, imageCaptionStyle) || other.imageCaptionStyle == imageCaptionStyle)&&(identical(other.videoPlayIconColor, videoPlayIconColor) || other.videoPlayIconColor == videoPlayIconColor)&&(identical(other.videoPlayIconBackgroundColor, videoPlayIconBackgroundColor) || other.videoPlayIconBackgroundColor == videoPlayIconBackgroundColor)&&(identical(other.videoPlaceholderIconColor, videoPlaceholderIconColor) || other.videoPlaceholderIconColor == videoPlaceholderIconColor)&&(identical(other.videoHeight, videoHeight) || other.videoHeight == videoHeight)&&(identical(other.videoPlaceholderColor, videoPlaceholderColor) || other.videoPlaceholderColor == videoPlaceholderColor)&&(identical(other.videoBorderRadius, videoBorderRadius) || other.videoBorderRadius == videoBorderRadius)&&(identical(other.fileIconColor, fileIconColor) || other.fileIconColor == fileIconColor)&&(identical(other.fileNameTextStyle, fileNameTextStyle) || other.fileNameTextStyle == fileNameTextStyle)&&(identical(other.fileSizeTextStyle, fileSizeTextStyle) || other.fileSizeTextStyle == fileSizeTextStyle)&&(identical(other.linkPreviewBackgroundColor, linkPreviewBackgroundColor) || other.linkPreviewBackgroundColor == linkPreviewBackgroundColor)&&(identical(other.linkPreviewTitleStyle, linkPreviewTitleStyle) || other.linkPreviewTitleStyle == linkPreviewTitleStyle)&&(identical(other.linkPreviewDescriptionStyle, linkPreviewDescriptionStyle) || other.linkPreviewDescriptionStyle == linkPreviewDescriptionStyle)&&(identical(other.linkPreviewBorderRadius, linkPreviewBorderRadius) || other.linkPreviewBorderRadius == linkPreviewBorderRadius)&&(identical(other.linkPreviewDomainStyle, linkPreviewDomainStyle) || other.linkPreviewDomainStyle == linkPreviewDomainStyle)&&(identical(other.linkPreviewBorderColor, linkPreviewBorderColor) || other.linkPreviewBorderColor == linkPreviewBorderColor)&&(identical(other.backgroundColor, backgroundColor) || other.backgroundColor == backgroundColor)&&(identical(other.backgroundImage, backgroundImage) || other.backgroundImage == backgroundImage)&&(identical(other.backgroundImageRepeat, backgroundImageRepeat) || other.backgroundImageRepeat == backgroundImageRepeat)&&(identical(other.backgroundImageOpacity, backgroundImageOpacity) || other.backgroundImageOpacity == backgroundImageOpacity)&&(identical(other.backgroundImageColorFilter, backgroundImageColorFilter) || other.backgroundImageColorFilter == backgroundImageColorFilter)&&(identical(other.avatarBackgroundColor, avatarBackgroundColor) || other.avatarBackgroundColor == avatarBackgroundColor)&&(identical(other.avatarInitialsTextStyle, avatarInitialsTextStyle) || other.avatarInitialsTextStyle == avatarInitialsTextStyle)&&(identical(other.avatarOnlineColor, avatarOnlineColor) || other.avatarOnlineColor == avatarOnlineColor)&&(identical(other.avatarOfflineColor, avatarOfflineColor) || other.avatarOfflineColor == avatarOfflineColor)&&(identical(other.avatarOnlineBorderColor, avatarOnlineBorderColor) || other.avatarOnlineBorderColor == avatarOnlineBorderColor)&&(identical(other.connectionBannerColor, connectionBannerColor) || other.connectionBannerColor == connectionBannerColor)&&(identical(other.connectionBannerTextStyle, connectionBannerTextStyle) || other.connectionBannerTextStyle == connectionBannerTextStyle)&&(identical(other.connectionBannerErrorIconColor, connectionBannerErrorIconColor) || other.connectionBannerErrorIconColor == connectionBannerErrorIconColor)&&(identical(other.emptyStateIconColor, emptyStateIconColor) || other.emptyStateIconColor == emptyStateIconColor)&&(identical(other.emptyStateTitleStyle, emptyStateTitleStyle) || other.emptyStateTitleStyle == emptyStateTitleStyle)&&(identical(other.emptyStateSubtitleStyle, emptyStateSubtitleStyle) || other.emptyStateSubtitleStyle == emptyStateSubtitleStyle)&&(identical(other.contextMenuHandleColor, contextMenuHandleColor) || other.contextMenuHandleColor == contextMenuHandleColor)&&(identical(other.contextMenuDestructiveColor, contextMenuDestructiveColor) || other.contextMenuDestructiveColor == contextMenuDestructiveColor)&&(identical(other.scrollToBottomButtonColor, scrollToBottomButtonColor) || other.scrollToBottomButtonColor == scrollToBottomButtonColor)&&(identical(other.scrollToBottomIconColor, scrollToBottomIconColor) || other.scrollToBottomIconColor == scrollToBottomIconColor)&&(identical(other.attachmentPickerCircleColor, attachmentPickerCircleColor) || other.attachmentPickerCircleColor == attachmentPickerCircleColor)&&(identical(other.attachmentPickerIconColor, attachmentPickerIconColor) || other.attachmentPickerIconColor == attachmentPickerIconColor)&&(identical(other.attachmentPickerLabelStyle, attachmentPickerLabelStyle) || other.attachmentPickerLabelStyle == attachmentPickerLabelStyle)&&(identical(other.imageViewerBackgroundColor, imageViewerBackgroundColor) || other.imageViewerBackgroundColor == imageViewerBackgroundColor)&&(identical(other.imageViewerIconColor, imageViewerIconColor) || other.imageViewerIconColor == imageViewerIconColor)&&(identical(other.presenceAvailableColor, presenceAvailableColor) || other.presenceAvailableColor == presenceAvailableColor)&&(identical(other.presenceAwayColor, presenceAwayColor) || other.presenceAwayColor == presenceAwayColor)&&(identical(other.presenceBusyColor, presenceBusyColor) || other.presenceBusyColor == presenceBusyColor)&&(identical(other.presenceDndColor, presenceDndColor) || other.presenceDndColor == presenceDndColor)&&(identical(other.galleryAppBarBackgroundColor, galleryAppBarBackgroundColor) || other.galleryAppBarBackgroundColor == galleryAppBarBackgroundColor)&&(identical(other.galleryAppBarForegroundColor, galleryAppBarForegroundColor) || other.galleryAppBarForegroundColor == galleryAppBarForegroundColor)&&(identical(other.galleryTabIndicatorColor, galleryTabIndicatorColor) || other.galleryTabIndicatorColor == galleryTabIndicatorColor));
}


@override
int get hashCode => Object.hashAll([runtimeType,l10n,bubble,input,roomList,markdown,locationMapBuilder,dateSeparatorTextStyle,dateSeparatorBackgroundColor,systemMessageTextStyle,systemMessageBackgroundColor,typingIndicatorDotColor,typingStatusTextStyle,reactionBackgroundColor,reactionSelectedColor,reactionSelectedBorderColor,reactionTextStyle,reactionPickerElevation,reactionPickerBorderRadius,reactionPickerEmojiSize,reactionDetailSheetBackgroundColor,reactionDetailUserNameStyle,reactionDetailRemoveColor,floatingPickerBackgroundColor,fullEmojiPickerBackgroundColor,audioPlayButtonColor,audioPlayIconColor,audioSeekBarColor,audioSeekBarActiveColor,audioDurationTextStyle,audioSpeedButtonColor,audioSpeedTextStyle,audioListenedIconColor,audioUnlistenedIconColor,voiceRecorderActiveColor,voiceRecorderTimerStyle,voiceRecorderOverlayColor,voiceRecorderCancelColor,voiceRecorderLockIconColor,voiceRecorderHintStyle,waveformActiveColor,waveformInactiveColor,waveformRecordingColor,imageBorderRadius,imageMaxHeight,imageMaxWidth,imageCaptionStyle,videoPlayIconColor,videoPlayIconBackgroundColor,videoPlaceholderIconColor,videoHeight,videoPlaceholderColor,videoBorderRadius,fileIconColor,fileNameTextStyle,fileSizeTextStyle,linkPreviewBackgroundColor,linkPreviewTitleStyle,linkPreviewDescriptionStyle,linkPreviewBorderRadius,linkPreviewDomainStyle,linkPreviewBorderColor,backgroundColor,backgroundImage,backgroundImageRepeat,backgroundImageOpacity,backgroundImageColorFilter,avatarBackgroundColor,avatarInitialsTextStyle,avatarOnlineColor,avatarOfflineColor,avatarOnlineBorderColor,connectionBannerColor,connectionBannerTextStyle,connectionBannerErrorIconColor,emptyStateIconColor,emptyStateTitleStyle,emptyStateSubtitleStyle,contextMenuHandleColor,contextMenuDestructiveColor,scrollToBottomButtonColor,scrollToBottomIconColor,attachmentPickerCircleColor,attachmentPickerIconColor,attachmentPickerLabelStyle,imageViewerBackgroundColor,imageViewerIconColor,presenceAvailableColor,presenceAwayColor,presenceBusyColor,presenceDndColor,galleryAppBarBackgroundColor,galleryAppBarForegroundColor,galleryTabIndicatorColor]);

@override
String toString() {
  return 'ChatTheme(l10n: $l10n, bubble: $bubble, input: $input, roomList: $roomList, markdown: $markdown, locationMapBuilder: $locationMapBuilder, dateSeparatorTextStyle: $dateSeparatorTextStyle, dateSeparatorBackgroundColor: $dateSeparatorBackgroundColor, systemMessageTextStyle: $systemMessageTextStyle, systemMessageBackgroundColor: $systemMessageBackgroundColor, typingIndicatorDotColor: $typingIndicatorDotColor, typingStatusTextStyle: $typingStatusTextStyle, reactionBackgroundColor: $reactionBackgroundColor, reactionSelectedColor: $reactionSelectedColor, reactionSelectedBorderColor: $reactionSelectedBorderColor, reactionTextStyle: $reactionTextStyle, reactionPickerElevation: $reactionPickerElevation, reactionPickerBorderRadius: $reactionPickerBorderRadius, reactionPickerEmojiSize: $reactionPickerEmojiSize, reactionDetailSheetBackgroundColor: $reactionDetailSheetBackgroundColor, reactionDetailUserNameStyle: $reactionDetailUserNameStyle, reactionDetailRemoveColor: $reactionDetailRemoveColor, floatingPickerBackgroundColor: $floatingPickerBackgroundColor, fullEmojiPickerBackgroundColor: $fullEmojiPickerBackgroundColor, audioPlayButtonColor: $audioPlayButtonColor, audioPlayIconColor: $audioPlayIconColor, audioSeekBarColor: $audioSeekBarColor, audioSeekBarActiveColor: $audioSeekBarActiveColor, audioDurationTextStyle: $audioDurationTextStyle, audioSpeedButtonColor: $audioSpeedButtonColor, audioSpeedTextStyle: $audioSpeedTextStyle, audioListenedIconColor: $audioListenedIconColor, audioUnlistenedIconColor: $audioUnlistenedIconColor, voiceRecorderActiveColor: $voiceRecorderActiveColor, voiceRecorderTimerStyle: $voiceRecorderTimerStyle, voiceRecorderOverlayColor: $voiceRecorderOverlayColor, voiceRecorderCancelColor: $voiceRecorderCancelColor, voiceRecorderLockIconColor: $voiceRecorderLockIconColor, voiceRecorderHintStyle: $voiceRecorderHintStyle, waveformActiveColor: $waveformActiveColor, waveformInactiveColor: $waveformInactiveColor, waveformRecordingColor: $waveformRecordingColor, imageBorderRadius: $imageBorderRadius, imageMaxHeight: $imageMaxHeight, imageMaxWidth: $imageMaxWidth, imageCaptionStyle: $imageCaptionStyle, videoPlayIconColor: $videoPlayIconColor, videoPlayIconBackgroundColor: $videoPlayIconBackgroundColor, videoPlaceholderIconColor: $videoPlaceholderIconColor, videoHeight: $videoHeight, videoPlaceholderColor: $videoPlaceholderColor, videoBorderRadius: $videoBorderRadius, fileIconColor: $fileIconColor, fileNameTextStyle: $fileNameTextStyle, fileSizeTextStyle: $fileSizeTextStyle, linkPreviewBackgroundColor: $linkPreviewBackgroundColor, linkPreviewTitleStyle: $linkPreviewTitleStyle, linkPreviewDescriptionStyle: $linkPreviewDescriptionStyle, linkPreviewBorderRadius: $linkPreviewBorderRadius, linkPreviewDomainStyle: $linkPreviewDomainStyle, linkPreviewBorderColor: $linkPreviewBorderColor, backgroundColor: $backgroundColor, backgroundImage: $backgroundImage, backgroundImageRepeat: $backgroundImageRepeat, backgroundImageOpacity: $backgroundImageOpacity, backgroundImageColorFilter: $backgroundImageColorFilter, avatarBackgroundColor: $avatarBackgroundColor, avatarInitialsTextStyle: $avatarInitialsTextStyle, avatarOnlineColor: $avatarOnlineColor, avatarOfflineColor: $avatarOfflineColor, avatarOnlineBorderColor: $avatarOnlineBorderColor, connectionBannerColor: $connectionBannerColor, connectionBannerTextStyle: $connectionBannerTextStyle, connectionBannerErrorIconColor: $connectionBannerErrorIconColor, emptyStateIconColor: $emptyStateIconColor, emptyStateTitleStyle: $emptyStateTitleStyle, emptyStateSubtitleStyle: $emptyStateSubtitleStyle, contextMenuHandleColor: $contextMenuHandleColor, contextMenuDestructiveColor: $contextMenuDestructiveColor, scrollToBottomButtonColor: $scrollToBottomButtonColor, scrollToBottomIconColor: $scrollToBottomIconColor, attachmentPickerCircleColor: $attachmentPickerCircleColor, attachmentPickerIconColor: $attachmentPickerIconColor, attachmentPickerLabelStyle: $attachmentPickerLabelStyle, imageViewerBackgroundColor: $imageViewerBackgroundColor, imageViewerIconColor: $imageViewerIconColor, presenceAvailableColor: $presenceAvailableColor, presenceAwayColor: $presenceAwayColor, presenceBusyColor: $presenceBusyColor, presenceDndColor: $presenceDndColor, galleryAppBarBackgroundColor: $galleryAppBarBackgroundColor, galleryAppBarForegroundColor: $galleryAppBarForegroundColor, galleryTabIndicatorColor: $galleryTabIndicatorColor)';
}


}

/// @nodoc
abstract mixin class $ChatThemeCopyWith<$Res>  {
  factory $ChatThemeCopyWith(ChatTheme value, $Res Function(ChatTheme) _then) = _$ChatThemeCopyWithImpl;
@useResult
$Res call({
 ChatUiLocalizations l10n, ChatBubbleTheme bubble, ChatInputTheme input, ChatRoomListTheme roomList, ChatMarkdownTheme markdown, Widget Function(BuildContext, double latitude, double longitude)? locationMapBuilder, TextStyle? dateSeparatorTextStyle, Color? dateSeparatorBackgroundColor, TextStyle? systemMessageTextStyle, Color? systemMessageBackgroundColor, Color? typingIndicatorDotColor, TextStyle? typingStatusTextStyle, Color? reactionBackgroundColor, Color? reactionSelectedColor, Color? reactionSelectedBorderColor, TextStyle? reactionTextStyle, double? reactionPickerElevation, BorderRadius? reactionPickerBorderRadius, double? reactionPickerEmojiSize, Color? reactionDetailSheetBackgroundColor, TextStyle? reactionDetailUserNameStyle, Color? reactionDetailRemoveColor, Color? floatingPickerBackgroundColor, Color? fullEmojiPickerBackgroundColor, Color? audioPlayButtonColor, Color? audioPlayIconColor, Color? audioSeekBarColor, Color? audioSeekBarActiveColor, TextStyle? audioDurationTextStyle, Color? audioSpeedButtonColor, TextStyle? audioSpeedTextStyle, Color? audioListenedIconColor, Color? audioUnlistenedIconColor, Color? voiceRecorderActiveColor, TextStyle? voiceRecorderTimerStyle, Color? voiceRecorderOverlayColor, Color? voiceRecorderCancelColor, Color? voiceRecorderLockIconColor, TextStyle? voiceRecorderHintStyle, Color? waveformActiveColor, Color? waveformInactiveColor, Color? waveformRecordingColor, BorderRadius? imageBorderRadius, double? imageMaxHeight, double? imageMaxWidth, TextStyle? imageCaptionStyle, Color? videoPlayIconColor, Color? videoPlayIconBackgroundColor, Color? videoPlaceholderIconColor, double? videoHeight, Color? videoPlaceholderColor, BorderRadius? videoBorderRadius, Color? fileIconColor, TextStyle? fileNameTextStyle, TextStyle? fileSizeTextStyle, Color? linkPreviewBackgroundColor, TextStyle? linkPreviewTitleStyle, TextStyle? linkPreviewDescriptionStyle, BorderRadius? linkPreviewBorderRadius, TextStyle? linkPreviewDomainStyle, Color? linkPreviewBorderColor, Color? backgroundColor, ImageProvider? backgroundImage, ImageRepeat backgroundImageRepeat, double backgroundImageOpacity, ColorFilter? backgroundImageColorFilter, Color? avatarBackgroundColor, TextStyle? avatarInitialsTextStyle, Color? avatarOnlineColor, Color? avatarOfflineColor, Color? avatarOnlineBorderColor, Color? connectionBannerColor, TextStyle? connectionBannerTextStyle, Color? connectionBannerErrorIconColor, Color? emptyStateIconColor, TextStyle? emptyStateTitleStyle, TextStyle? emptyStateSubtitleStyle, Color? contextMenuHandleColor, Color? contextMenuDestructiveColor, Color? scrollToBottomButtonColor, Color? scrollToBottomIconColor, Color? attachmentPickerCircleColor, Color? attachmentPickerIconColor, TextStyle? attachmentPickerLabelStyle, Color? imageViewerBackgroundColor, Color? imageViewerIconColor, Color? presenceAvailableColor, Color? presenceAwayColor, Color? presenceBusyColor, Color? presenceDndColor, Color? galleryAppBarBackgroundColor, Color? galleryAppBarForegroundColor, Color? galleryTabIndicatorColor
});


$ChatBubbleThemeCopyWith<$Res> get bubble;$ChatInputThemeCopyWith<$Res> get input;$ChatRoomListThemeCopyWith<$Res> get roomList;$ChatMarkdownThemeCopyWith<$Res> get markdown;

}
/// @nodoc
class _$ChatThemeCopyWithImpl<$Res>
    implements $ChatThemeCopyWith<$Res> {
  _$ChatThemeCopyWithImpl(this._self, this._then);

  final ChatTheme _self;
  final $Res Function(ChatTheme) _then;

/// Create a copy of ChatTheme
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? l10n = null,Object? bubble = null,Object? input = null,Object? roomList = null,Object? markdown = null,Object? locationMapBuilder = freezed,Object? dateSeparatorTextStyle = freezed,Object? dateSeparatorBackgroundColor = freezed,Object? systemMessageTextStyle = freezed,Object? systemMessageBackgroundColor = freezed,Object? typingIndicatorDotColor = freezed,Object? typingStatusTextStyle = freezed,Object? reactionBackgroundColor = freezed,Object? reactionSelectedColor = freezed,Object? reactionSelectedBorderColor = freezed,Object? reactionTextStyle = freezed,Object? reactionPickerElevation = freezed,Object? reactionPickerBorderRadius = freezed,Object? reactionPickerEmojiSize = freezed,Object? reactionDetailSheetBackgroundColor = freezed,Object? reactionDetailUserNameStyle = freezed,Object? reactionDetailRemoveColor = freezed,Object? floatingPickerBackgroundColor = freezed,Object? fullEmojiPickerBackgroundColor = freezed,Object? audioPlayButtonColor = freezed,Object? audioPlayIconColor = freezed,Object? audioSeekBarColor = freezed,Object? audioSeekBarActiveColor = freezed,Object? audioDurationTextStyle = freezed,Object? audioSpeedButtonColor = freezed,Object? audioSpeedTextStyle = freezed,Object? audioListenedIconColor = freezed,Object? audioUnlistenedIconColor = freezed,Object? voiceRecorderActiveColor = freezed,Object? voiceRecorderTimerStyle = freezed,Object? voiceRecorderOverlayColor = freezed,Object? voiceRecorderCancelColor = freezed,Object? voiceRecorderLockIconColor = freezed,Object? voiceRecorderHintStyle = freezed,Object? waveformActiveColor = freezed,Object? waveformInactiveColor = freezed,Object? waveformRecordingColor = freezed,Object? imageBorderRadius = freezed,Object? imageMaxHeight = freezed,Object? imageMaxWidth = freezed,Object? imageCaptionStyle = freezed,Object? videoPlayIconColor = freezed,Object? videoPlayIconBackgroundColor = freezed,Object? videoPlaceholderIconColor = freezed,Object? videoHeight = freezed,Object? videoPlaceholderColor = freezed,Object? videoBorderRadius = freezed,Object? fileIconColor = freezed,Object? fileNameTextStyle = freezed,Object? fileSizeTextStyle = freezed,Object? linkPreviewBackgroundColor = freezed,Object? linkPreviewTitleStyle = freezed,Object? linkPreviewDescriptionStyle = freezed,Object? linkPreviewBorderRadius = freezed,Object? linkPreviewDomainStyle = freezed,Object? linkPreviewBorderColor = freezed,Object? backgroundColor = freezed,Object? backgroundImage = freezed,Object? backgroundImageRepeat = null,Object? backgroundImageOpacity = null,Object? backgroundImageColorFilter = freezed,Object? avatarBackgroundColor = freezed,Object? avatarInitialsTextStyle = freezed,Object? avatarOnlineColor = freezed,Object? avatarOfflineColor = freezed,Object? avatarOnlineBorderColor = freezed,Object? connectionBannerColor = freezed,Object? connectionBannerTextStyle = freezed,Object? connectionBannerErrorIconColor = freezed,Object? emptyStateIconColor = freezed,Object? emptyStateTitleStyle = freezed,Object? emptyStateSubtitleStyle = freezed,Object? contextMenuHandleColor = freezed,Object? contextMenuDestructiveColor = freezed,Object? scrollToBottomButtonColor = freezed,Object? scrollToBottomIconColor = freezed,Object? attachmentPickerCircleColor = freezed,Object? attachmentPickerIconColor = freezed,Object? attachmentPickerLabelStyle = freezed,Object? imageViewerBackgroundColor = freezed,Object? imageViewerIconColor = freezed,Object? presenceAvailableColor = freezed,Object? presenceAwayColor = freezed,Object? presenceBusyColor = freezed,Object? presenceDndColor = freezed,Object? galleryAppBarBackgroundColor = freezed,Object? galleryAppBarForegroundColor = freezed,Object? galleryTabIndicatorColor = freezed,}) {
  return _then(_self.copyWith(
l10n: null == l10n ? _self.l10n : l10n // ignore: cast_nullable_to_non_nullable
as ChatUiLocalizations,bubble: null == bubble ? _self.bubble : bubble // ignore: cast_nullable_to_non_nullable
as ChatBubbleTheme,input: null == input ? _self.input : input // ignore: cast_nullable_to_non_nullable
as ChatInputTheme,roomList: null == roomList ? _self.roomList : roomList // ignore: cast_nullable_to_non_nullable
as ChatRoomListTheme,markdown: null == markdown ? _self.markdown : markdown // ignore: cast_nullable_to_non_nullable
as ChatMarkdownTheme,locationMapBuilder: freezed == locationMapBuilder ? _self.locationMapBuilder : locationMapBuilder // ignore: cast_nullable_to_non_nullable
as Widget Function(BuildContext, double latitude, double longitude)?,dateSeparatorTextStyle: freezed == dateSeparatorTextStyle ? _self.dateSeparatorTextStyle : dateSeparatorTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,dateSeparatorBackgroundColor: freezed == dateSeparatorBackgroundColor ? _self.dateSeparatorBackgroundColor : dateSeparatorBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,systemMessageTextStyle: freezed == systemMessageTextStyle ? _self.systemMessageTextStyle : systemMessageTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,systemMessageBackgroundColor: freezed == systemMessageBackgroundColor ? _self.systemMessageBackgroundColor : systemMessageBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,typingIndicatorDotColor: freezed == typingIndicatorDotColor ? _self.typingIndicatorDotColor : typingIndicatorDotColor // ignore: cast_nullable_to_non_nullable
as Color?,typingStatusTextStyle: freezed == typingStatusTextStyle ? _self.typingStatusTextStyle : typingStatusTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,reactionBackgroundColor: freezed == reactionBackgroundColor ? _self.reactionBackgroundColor : reactionBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,reactionSelectedColor: freezed == reactionSelectedColor ? _self.reactionSelectedColor : reactionSelectedColor // ignore: cast_nullable_to_non_nullable
as Color?,reactionSelectedBorderColor: freezed == reactionSelectedBorderColor ? _self.reactionSelectedBorderColor : reactionSelectedBorderColor // ignore: cast_nullable_to_non_nullable
as Color?,reactionTextStyle: freezed == reactionTextStyle ? _self.reactionTextStyle : reactionTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,reactionPickerElevation: freezed == reactionPickerElevation ? _self.reactionPickerElevation : reactionPickerElevation // ignore: cast_nullable_to_non_nullable
as double?,reactionPickerBorderRadius: freezed == reactionPickerBorderRadius ? _self.reactionPickerBorderRadius : reactionPickerBorderRadius // ignore: cast_nullable_to_non_nullable
as BorderRadius?,reactionPickerEmojiSize: freezed == reactionPickerEmojiSize ? _self.reactionPickerEmojiSize : reactionPickerEmojiSize // ignore: cast_nullable_to_non_nullable
as double?,reactionDetailSheetBackgroundColor: freezed == reactionDetailSheetBackgroundColor ? _self.reactionDetailSheetBackgroundColor : reactionDetailSheetBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,reactionDetailUserNameStyle: freezed == reactionDetailUserNameStyle ? _self.reactionDetailUserNameStyle : reactionDetailUserNameStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,reactionDetailRemoveColor: freezed == reactionDetailRemoveColor ? _self.reactionDetailRemoveColor : reactionDetailRemoveColor // ignore: cast_nullable_to_non_nullable
as Color?,floatingPickerBackgroundColor: freezed == floatingPickerBackgroundColor ? _self.floatingPickerBackgroundColor : floatingPickerBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,fullEmojiPickerBackgroundColor: freezed == fullEmojiPickerBackgroundColor ? _self.fullEmojiPickerBackgroundColor : fullEmojiPickerBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,audioPlayButtonColor: freezed == audioPlayButtonColor ? _self.audioPlayButtonColor : audioPlayButtonColor // ignore: cast_nullable_to_non_nullable
as Color?,audioPlayIconColor: freezed == audioPlayIconColor ? _self.audioPlayIconColor : audioPlayIconColor // ignore: cast_nullable_to_non_nullable
as Color?,audioSeekBarColor: freezed == audioSeekBarColor ? _self.audioSeekBarColor : audioSeekBarColor // ignore: cast_nullable_to_non_nullable
as Color?,audioSeekBarActiveColor: freezed == audioSeekBarActiveColor ? _self.audioSeekBarActiveColor : audioSeekBarActiveColor // ignore: cast_nullable_to_non_nullable
as Color?,audioDurationTextStyle: freezed == audioDurationTextStyle ? _self.audioDurationTextStyle : audioDurationTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,audioSpeedButtonColor: freezed == audioSpeedButtonColor ? _self.audioSpeedButtonColor : audioSpeedButtonColor // ignore: cast_nullable_to_non_nullable
as Color?,audioSpeedTextStyle: freezed == audioSpeedTextStyle ? _self.audioSpeedTextStyle : audioSpeedTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,audioListenedIconColor: freezed == audioListenedIconColor ? _self.audioListenedIconColor : audioListenedIconColor // ignore: cast_nullable_to_non_nullable
as Color?,audioUnlistenedIconColor: freezed == audioUnlistenedIconColor ? _self.audioUnlistenedIconColor : audioUnlistenedIconColor // ignore: cast_nullable_to_non_nullable
as Color?,voiceRecorderActiveColor: freezed == voiceRecorderActiveColor ? _self.voiceRecorderActiveColor : voiceRecorderActiveColor // ignore: cast_nullable_to_non_nullable
as Color?,voiceRecorderTimerStyle: freezed == voiceRecorderTimerStyle ? _self.voiceRecorderTimerStyle : voiceRecorderTimerStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,voiceRecorderOverlayColor: freezed == voiceRecorderOverlayColor ? _self.voiceRecorderOverlayColor : voiceRecorderOverlayColor // ignore: cast_nullable_to_non_nullable
as Color?,voiceRecorderCancelColor: freezed == voiceRecorderCancelColor ? _self.voiceRecorderCancelColor : voiceRecorderCancelColor // ignore: cast_nullable_to_non_nullable
as Color?,voiceRecorderLockIconColor: freezed == voiceRecorderLockIconColor ? _self.voiceRecorderLockIconColor : voiceRecorderLockIconColor // ignore: cast_nullable_to_non_nullable
as Color?,voiceRecorderHintStyle: freezed == voiceRecorderHintStyle ? _self.voiceRecorderHintStyle : voiceRecorderHintStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,waveformActiveColor: freezed == waveformActiveColor ? _self.waveformActiveColor : waveformActiveColor // ignore: cast_nullable_to_non_nullable
as Color?,waveformInactiveColor: freezed == waveformInactiveColor ? _self.waveformInactiveColor : waveformInactiveColor // ignore: cast_nullable_to_non_nullable
as Color?,waveformRecordingColor: freezed == waveformRecordingColor ? _self.waveformRecordingColor : waveformRecordingColor // ignore: cast_nullable_to_non_nullable
as Color?,imageBorderRadius: freezed == imageBorderRadius ? _self.imageBorderRadius : imageBorderRadius // ignore: cast_nullable_to_non_nullable
as BorderRadius?,imageMaxHeight: freezed == imageMaxHeight ? _self.imageMaxHeight : imageMaxHeight // ignore: cast_nullable_to_non_nullable
as double?,imageMaxWidth: freezed == imageMaxWidth ? _self.imageMaxWidth : imageMaxWidth // ignore: cast_nullable_to_non_nullable
as double?,imageCaptionStyle: freezed == imageCaptionStyle ? _self.imageCaptionStyle : imageCaptionStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,videoPlayIconColor: freezed == videoPlayIconColor ? _self.videoPlayIconColor : videoPlayIconColor // ignore: cast_nullable_to_non_nullable
as Color?,videoPlayIconBackgroundColor: freezed == videoPlayIconBackgroundColor ? _self.videoPlayIconBackgroundColor : videoPlayIconBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,videoPlaceholderIconColor: freezed == videoPlaceholderIconColor ? _self.videoPlaceholderIconColor : videoPlaceholderIconColor // ignore: cast_nullable_to_non_nullable
as Color?,videoHeight: freezed == videoHeight ? _self.videoHeight : videoHeight // ignore: cast_nullable_to_non_nullable
as double?,videoPlaceholderColor: freezed == videoPlaceholderColor ? _self.videoPlaceholderColor : videoPlaceholderColor // ignore: cast_nullable_to_non_nullable
as Color?,videoBorderRadius: freezed == videoBorderRadius ? _self.videoBorderRadius : videoBorderRadius // ignore: cast_nullable_to_non_nullable
as BorderRadius?,fileIconColor: freezed == fileIconColor ? _self.fileIconColor : fileIconColor // ignore: cast_nullable_to_non_nullable
as Color?,fileNameTextStyle: freezed == fileNameTextStyle ? _self.fileNameTextStyle : fileNameTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,fileSizeTextStyle: freezed == fileSizeTextStyle ? _self.fileSizeTextStyle : fileSizeTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,linkPreviewBackgroundColor: freezed == linkPreviewBackgroundColor ? _self.linkPreviewBackgroundColor : linkPreviewBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,linkPreviewTitleStyle: freezed == linkPreviewTitleStyle ? _self.linkPreviewTitleStyle : linkPreviewTitleStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,linkPreviewDescriptionStyle: freezed == linkPreviewDescriptionStyle ? _self.linkPreviewDescriptionStyle : linkPreviewDescriptionStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,linkPreviewBorderRadius: freezed == linkPreviewBorderRadius ? _self.linkPreviewBorderRadius : linkPreviewBorderRadius // ignore: cast_nullable_to_non_nullable
as BorderRadius?,linkPreviewDomainStyle: freezed == linkPreviewDomainStyle ? _self.linkPreviewDomainStyle : linkPreviewDomainStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,linkPreviewBorderColor: freezed == linkPreviewBorderColor ? _self.linkPreviewBorderColor : linkPreviewBorderColor // ignore: cast_nullable_to_non_nullable
as Color?,backgroundColor: freezed == backgroundColor ? _self.backgroundColor : backgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,backgroundImage: freezed == backgroundImage ? _self.backgroundImage : backgroundImage // ignore: cast_nullable_to_non_nullable
as ImageProvider?,backgroundImageRepeat: null == backgroundImageRepeat ? _self.backgroundImageRepeat : backgroundImageRepeat // ignore: cast_nullable_to_non_nullable
as ImageRepeat,backgroundImageOpacity: null == backgroundImageOpacity ? _self.backgroundImageOpacity : backgroundImageOpacity // ignore: cast_nullable_to_non_nullable
as double,backgroundImageColorFilter: freezed == backgroundImageColorFilter ? _self.backgroundImageColorFilter : backgroundImageColorFilter // ignore: cast_nullable_to_non_nullable
as ColorFilter?,avatarBackgroundColor: freezed == avatarBackgroundColor ? _self.avatarBackgroundColor : avatarBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,avatarInitialsTextStyle: freezed == avatarInitialsTextStyle ? _self.avatarInitialsTextStyle : avatarInitialsTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,avatarOnlineColor: freezed == avatarOnlineColor ? _self.avatarOnlineColor : avatarOnlineColor // ignore: cast_nullable_to_non_nullable
as Color?,avatarOfflineColor: freezed == avatarOfflineColor ? _self.avatarOfflineColor : avatarOfflineColor // ignore: cast_nullable_to_non_nullable
as Color?,avatarOnlineBorderColor: freezed == avatarOnlineBorderColor ? _self.avatarOnlineBorderColor : avatarOnlineBorderColor // ignore: cast_nullable_to_non_nullable
as Color?,connectionBannerColor: freezed == connectionBannerColor ? _self.connectionBannerColor : connectionBannerColor // ignore: cast_nullable_to_non_nullable
as Color?,connectionBannerTextStyle: freezed == connectionBannerTextStyle ? _self.connectionBannerTextStyle : connectionBannerTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,connectionBannerErrorIconColor: freezed == connectionBannerErrorIconColor ? _self.connectionBannerErrorIconColor : connectionBannerErrorIconColor // ignore: cast_nullable_to_non_nullable
as Color?,emptyStateIconColor: freezed == emptyStateIconColor ? _self.emptyStateIconColor : emptyStateIconColor // ignore: cast_nullable_to_non_nullable
as Color?,emptyStateTitleStyle: freezed == emptyStateTitleStyle ? _self.emptyStateTitleStyle : emptyStateTitleStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,emptyStateSubtitleStyle: freezed == emptyStateSubtitleStyle ? _self.emptyStateSubtitleStyle : emptyStateSubtitleStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,contextMenuHandleColor: freezed == contextMenuHandleColor ? _self.contextMenuHandleColor : contextMenuHandleColor // ignore: cast_nullable_to_non_nullable
as Color?,contextMenuDestructiveColor: freezed == contextMenuDestructiveColor ? _self.contextMenuDestructiveColor : contextMenuDestructiveColor // ignore: cast_nullable_to_non_nullable
as Color?,scrollToBottomButtonColor: freezed == scrollToBottomButtonColor ? _self.scrollToBottomButtonColor : scrollToBottomButtonColor // ignore: cast_nullable_to_non_nullable
as Color?,scrollToBottomIconColor: freezed == scrollToBottomIconColor ? _self.scrollToBottomIconColor : scrollToBottomIconColor // ignore: cast_nullable_to_non_nullable
as Color?,attachmentPickerCircleColor: freezed == attachmentPickerCircleColor ? _self.attachmentPickerCircleColor : attachmentPickerCircleColor // ignore: cast_nullable_to_non_nullable
as Color?,attachmentPickerIconColor: freezed == attachmentPickerIconColor ? _self.attachmentPickerIconColor : attachmentPickerIconColor // ignore: cast_nullable_to_non_nullable
as Color?,attachmentPickerLabelStyle: freezed == attachmentPickerLabelStyle ? _self.attachmentPickerLabelStyle : attachmentPickerLabelStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,imageViewerBackgroundColor: freezed == imageViewerBackgroundColor ? _self.imageViewerBackgroundColor : imageViewerBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,imageViewerIconColor: freezed == imageViewerIconColor ? _self.imageViewerIconColor : imageViewerIconColor // ignore: cast_nullable_to_non_nullable
as Color?,presenceAvailableColor: freezed == presenceAvailableColor ? _self.presenceAvailableColor : presenceAvailableColor // ignore: cast_nullable_to_non_nullable
as Color?,presenceAwayColor: freezed == presenceAwayColor ? _self.presenceAwayColor : presenceAwayColor // ignore: cast_nullable_to_non_nullable
as Color?,presenceBusyColor: freezed == presenceBusyColor ? _self.presenceBusyColor : presenceBusyColor // ignore: cast_nullable_to_non_nullable
as Color?,presenceDndColor: freezed == presenceDndColor ? _self.presenceDndColor : presenceDndColor // ignore: cast_nullable_to_non_nullable
as Color?,galleryAppBarBackgroundColor: freezed == galleryAppBarBackgroundColor ? _self.galleryAppBarBackgroundColor : galleryAppBarBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,galleryAppBarForegroundColor: freezed == galleryAppBarForegroundColor ? _self.galleryAppBarForegroundColor : galleryAppBarForegroundColor // ignore: cast_nullable_to_non_nullable
as Color?,galleryTabIndicatorColor: freezed == galleryTabIndicatorColor ? _self.galleryTabIndicatorColor : galleryTabIndicatorColor // ignore: cast_nullable_to_non_nullable
as Color?,
  ));
}
/// Create a copy of ChatTheme
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ChatBubbleThemeCopyWith<$Res> get bubble {
  
  return $ChatBubbleThemeCopyWith<$Res>(_self.bubble, (value) {
    return _then(_self.copyWith(bubble: value));
  });
}/// Create a copy of ChatTheme
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ChatInputThemeCopyWith<$Res> get input {
  
  return $ChatInputThemeCopyWith<$Res>(_self.input, (value) {
    return _then(_self.copyWith(input: value));
  });
}/// Create a copy of ChatTheme
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ChatRoomListThemeCopyWith<$Res> get roomList {
  
  return $ChatRoomListThemeCopyWith<$Res>(_self.roomList, (value) {
    return _then(_self.copyWith(roomList: value));
  });
}/// Create a copy of ChatTheme
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ChatMarkdownThemeCopyWith<$Res> get markdown {
  
  return $ChatMarkdownThemeCopyWith<$Res>(_self.markdown, (value) {
    return _then(_self.copyWith(markdown: value));
  });
}
}


/// Adds pattern-matching-related methods to [ChatTheme].
extension ChatThemePatterns on ChatTheme {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatTheme value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatTheme() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatTheme value)  $default,){
final _that = this;
switch (_that) {
case _ChatTheme():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatTheme value)?  $default,){
final _that = this;
switch (_that) {
case _ChatTheme() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ChatUiLocalizations l10n,  ChatBubbleTheme bubble,  ChatInputTheme input,  ChatRoomListTheme roomList,  ChatMarkdownTheme markdown,  Widget Function(BuildContext, double latitude, double longitude)? locationMapBuilder,  TextStyle? dateSeparatorTextStyle,  Color? dateSeparatorBackgroundColor,  TextStyle? systemMessageTextStyle,  Color? systemMessageBackgroundColor,  Color? typingIndicatorDotColor,  TextStyle? typingStatusTextStyle,  Color? reactionBackgroundColor,  Color? reactionSelectedColor,  Color? reactionSelectedBorderColor,  TextStyle? reactionTextStyle,  double? reactionPickerElevation,  BorderRadius? reactionPickerBorderRadius,  double? reactionPickerEmojiSize,  Color? reactionDetailSheetBackgroundColor,  TextStyle? reactionDetailUserNameStyle,  Color? reactionDetailRemoveColor,  Color? floatingPickerBackgroundColor,  Color? fullEmojiPickerBackgroundColor,  Color? audioPlayButtonColor,  Color? audioPlayIconColor,  Color? audioSeekBarColor,  Color? audioSeekBarActiveColor,  TextStyle? audioDurationTextStyle,  Color? audioSpeedButtonColor,  TextStyle? audioSpeedTextStyle,  Color? audioListenedIconColor,  Color? audioUnlistenedIconColor,  Color? voiceRecorderActiveColor,  TextStyle? voiceRecorderTimerStyle,  Color? voiceRecorderOverlayColor,  Color? voiceRecorderCancelColor,  Color? voiceRecorderLockIconColor,  TextStyle? voiceRecorderHintStyle,  Color? waveformActiveColor,  Color? waveformInactiveColor,  Color? waveformRecordingColor,  BorderRadius? imageBorderRadius,  double? imageMaxHeight,  double? imageMaxWidth,  TextStyle? imageCaptionStyle,  Color? videoPlayIconColor,  Color? videoPlayIconBackgroundColor,  Color? videoPlaceholderIconColor,  double? videoHeight,  Color? videoPlaceholderColor,  BorderRadius? videoBorderRadius,  Color? fileIconColor,  TextStyle? fileNameTextStyle,  TextStyle? fileSizeTextStyle,  Color? linkPreviewBackgroundColor,  TextStyle? linkPreviewTitleStyle,  TextStyle? linkPreviewDescriptionStyle,  BorderRadius? linkPreviewBorderRadius,  TextStyle? linkPreviewDomainStyle,  Color? linkPreviewBorderColor,  Color? backgroundColor,  ImageProvider? backgroundImage,  ImageRepeat backgroundImageRepeat,  double backgroundImageOpacity,  ColorFilter? backgroundImageColorFilter,  Color? avatarBackgroundColor,  TextStyle? avatarInitialsTextStyle,  Color? avatarOnlineColor,  Color? avatarOfflineColor,  Color? avatarOnlineBorderColor,  Color? connectionBannerColor,  TextStyle? connectionBannerTextStyle,  Color? connectionBannerErrorIconColor,  Color? emptyStateIconColor,  TextStyle? emptyStateTitleStyle,  TextStyle? emptyStateSubtitleStyle,  Color? contextMenuHandleColor,  Color? contextMenuDestructiveColor,  Color? scrollToBottomButtonColor,  Color? scrollToBottomIconColor,  Color? attachmentPickerCircleColor,  Color? attachmentPickerIconColor,  TextStyle? attachmentPickerLabelStyle,  Color? imageViewerBackgroundColor,  Color? imageViewerIconColor,  Color? presenceAvailableColor,  Color? presenceAwayColor,  Color? presenceBusyColor,  Color? presenceDndColor,  Color? galleryAppBarBackgroundColor,  Color? galleryAppBarForegroundColor,  Color? galleryTabIndicatorColor)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatTheme() when $default != null:
return $default(_that.l10n,_that.bubble,_that.input,_that.roomList,_that.markdown,_that.locationMapBuilder,_that.dateSeparatorTextStyle,_that.dateSeparatorBackgroundColor,_that.systemMessageTextStyle,_that.systemMessageBackgroundColor,_that.typingIndicatorDotColor,_that.typingStatusTextStyle,_that.reactionBackgroundColor,_that.reactionSelectedColor,_that.reactionSelectedBorderColor,_that.reactionTextStyle,_that.reactionPickerElevation,_that.reactionPickerBorderRadius,_that.reactionPickerEmojiSize,_that.reactionDetailSheetBackgroundColor,_that.reactionDetailUserNameStyle,_that.reactionDetailRemoveColor,_that.floatingPickerBackgroundColor,_that.fullEmojiPickerBackgroundColor,_that.audioPlayButtonColor,_that.audioPlayIconColor,_that.audioSeekBarColor,_that.audioSeekBarActiveColor,_that.audioDurationTextStyle,_that.audioSpeedButtonColor,_that.audioSpeedTextStyle,_that.audioListenedIconColor,_that.audioUnlistenedIconColor,_that.voiceRecorderActiveColor,_that.voiceRecorderTimerStyle,_that.voiceRecorderOverlayColor,_that.voiceRecorderCancelColor,_that.voiceRecorderLockIconColor,_that.voiceRecorderHintStyle,_that.waveformActiveColor,_that.waveformInactiveColor,_that.waveformRecordingColor,_that.imageBorderRadius,_that.imageMaxHeight,_that.imageMaxWidth,_that.imageCaptionStyle,_that.videoPlayIconColor,_that.videoPlayIconBackgroundColor,_that.videoPlaceholderIconColor,_that.videoHeight,_that.videoPlaceholderColor,_that.videoBorderRadius,_that.fileIconColor,_that.fileNameTextStyle,_that.fileSizeTextStyle,_that.linkPreviewBackgroundColor,_that.linkPreviewTitleStyle,_that.linkPreviewDescriptionStyle,_that.linkPreviewBorderRadius,_that.linkPreviewDomainStyle,_that.linkPreviewBorderColor,_that.backgroundColor,_that.backgroundImage,_that.backgroundImageRepeat,_that.backgroundImageOpacity,_that.backgroundImageColorFilter,_that.avatarBackgroundColor,_that.avatarInitialsTextStyle,_that.avatarOnlineColor,_that.avatarOfflineColor,_that.avatarOnlineBorderColor,_that.connectionBannerColor,_that.connectionBannerTextStyle,_that.connectionBannerErrorIconColor,_that.emptyStateIconColor,_that.emptyStateTitleStyle,_that.emptyStateSubtitleStyle,_that.contextMenuHandleColor,_that.contextMenuDestructiveColor,_that.scrollToBottomButtonColor,_that.scrollToBottomIconColor,_that.attachmentPickerCircleColor,_that.attachmentPickerIconColor,_that.attachmentPickerLabelStyle,_that.imageViewerBackgroundColor,_that.imageViewerIconColor,_that.presenceAvailableColor,_that.presenceAwayColor,_that.presenceBusyColor,_that.presenceDndColor,_that.galleryAppBarBackgroundColor,_that.galleryAppBarForegroundColor,_that.galleryTabIndicatorColor);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ChatUiLocalizations l10n,  ChatBubbleTheme bubble,  ChatInputTheme input,  ChatRoomListTheme roomList,  ChatMarkdownTheme markdown,  Widget Function(BuildContext, double latitude, double longitude)? locationMapBuilder,  TextStyle? dateSeparatorTextStyle,  Color? dateSeparatorBackgroundColor,  TextStyle? systemMessageTextStyle,  Color? systemMessageBackgroundColor,  Color? typingIndicatorDotColor,  TextStyle? typingStatusTextStyle,  Color? reactionBackgroundColor,  Color? reactionSelectedColor,  Color? reactionSelectedBorderColor,  TextStyle? reactionTextStyle,  double? reactionPickerElevation,  BorderRadius? reactionPickerBorderRadius,  double? reactionPickerEmojiSize,  Color? reactionDetailSheetBackgroundColor,  TextStyle? reactionDetailUserNameStyle,  Color? reactionDetailRemoveColor,  Color? floatingPickerBackgroundColor,  Color? fullEmojiPickerBackgroundColor,  Color? audioPlayButtonColor,  Color? audioPlayIconColor,  Color? audioSeekBarColor,  Color? audioSeekBarActiveColor,  TextStyle? audioDurationTextStyle,  Color? audioSpeedButtonColor,  TextStyle? audioSpeedTextStyle,  Color? audioListenedIconColor,  Color? audioUnlistenedIconColor,  Color? voiceRecorderActiveColor,  TextStyle? voiceRecorderTimerStyle,  Color? voiceRecorderOverlayColor,  Color? voiceRecorderCancelColor,  Color? voiceRecorderLockIconColor,  TextStyle? voiceRecorderHintStyle,  Color? waveformActiveColor,  Color? waveformInactiveColor,  Color? waveformRecordingColor,  BorderRadius? imageBorderRadius,  double? imageMaxHeight,  double? imageMaxWidth,  TextStyle? imageCaptionStyle,  Color? videoPlayIconColor,  Color? videoPlayIconBackgroundColor,  Color? videoPlaceholderIconColor,  double? videoHeight,  Color? videoPlaceholderColor,  BorderRadius? videoBorderRadius,  Color? fileIconColor,  TextStyle? fileNameTextStyle,  TextStyle? fileSizeTextStyle,  Color? linkPreviewBackgroundColor,  TextStyle? linkPreviewTitleStyle,  TextStyle? linkPreviewDescriptionStyle,  BorderRadius? linkPreviewBorderRadius,  TextStyle? linkPreviewDomainStyle,  Color? linkPreviewBorderColor,  Color? backgroundColor,  ImageProvider? backgroundImage,  ImageRepeat backgroundImageRepeat,  double backgroundImageOpacity,  ColorFilter? backgroundImageColorFilter,  Color? avatarBackgroundColor,  TextStyle? avatarInitialsTextStyle,  Color? avatarOnlineColor,  Color? avatarOfflineColor,  Color? avatarOnlineBorderColor,  Color? connectionBannerColor,  TextStyle? connectionBannerTextStyle,  Color? connectionBannerErrorIconColor,  Color? emptyStateIconColor,  TextStyle? emptyStateTitleStyle,  TextStyle? emptyStateSubtitleStyle,  Color? contextMenuHandleColor,  Color? contextMenuDestructiveColor,  Color? scrollToBottomButtonColor,  Color? scrollToBottomIconColor,  Color? attachmentPickerCircleColor,  Color? attachmentPickerIconColor,  TextStyle? attachmentPickerLabelStyle,  Color? imageViewerBackgroundColor,  Color? imageViewerIconColor,  Color? presenceAvailableColor,  Color? presenceAwayColor,  Color? presenceBusyColor,  Color? presenceDndColor,  Color? galleryAppBarBackgroundColor,  Color? galleryAppBarForegroundColor,  Color? galleryTabIndicatorColor)  $default,) {final _that = this;
switch (_that) {
case _ChatTheme():
return $default(_that.l10n,_that.bubble,_that.input,_that.roomList,_that.markdown,_that.locationMapBuilder,_that.dateSeparatorTextStyle,_that.dateSeparatorBackgroundColor,_that.systemMessageTextStyle,_that.systemMessageBackgroundColor,_that.typingIndicatorDotColor,_that.typingStatusTextStyle,_that.reactionBackgroundColor,_that.reactionSelectedColor,_that.reactionSelectedBorderColor,_that.reactionTextStyle,_that.reactionPickerElevation,_that.reactionPickerBorderRadius,_that.reactionPickerEmojiSize,_that.reactionDetailSheetBackgroundColor,_that.reactionDetailUserNameStyle,_that.reactionDetailRemoveColor,_that.floatingPickerBackgroundColor,_that.fullEmojiPickerBackgroundColor,_that.audioPlayButtonColor,_that.audioPlayIconColor,_that.audioSeekBarColor,_that.audioSeekBarActiveColor,_that.audioDurationTextStyle,_that.audioSpeedButtonColor,_that.audioSpeedTextStyle,_that.audioListenedIconColor,_that.audioUnlistenedIconColor,_that.voiceRecorderActiveColor,_that.voiceRecorderTimerStyle,_that.voiceRecorderOverlayColor,_that.voiceRecorderCancelColor,_that.voiceRecorderLockIconColor,_that.voiceRecorderHintStyle,_that.waveformActiveColor,_that.waveformInactiveColor,_that.waveformRecordingColor,_that.imageBorderRadius,_that.imageMaxHeight,_that.imageMaxWidth,_that.imageCaptionStyle,_that.videoPlayIconColor,_that.videoPlayIconBackgroundColor,_that.videoPlaceholderIconColor,_that.videoHeight,_that.videoPlaceholderColor,_that.videoBorderRadius,_that.fileIconColor,_that.fileNameTextStyle,_that.fileSizeTextStyle,_that.linkPreviewBackgroundColor,_that.linkPreviewTitleStyle,_that.linkPreviewDescriptionStyle,_that.linkPreviewBorderRadius,_that.linkPreviewDomainStyle,_that.linkPreviewBorderColor,_that.backgroundColor,_that.backgroundImage,_that.backgroundImageRepeat,_that.backgroundImageOpacity,_that.backgroundImageColorFilter,_that.avatarBackgroundColor,_that.avatarInitialsTextStyle,_that.avatarOnlineColor,_that.avatarOfflineColor,_that.avatarOnlineBorderColor,_that.connectionBannerColor,_that.connectionBannerTextStyle,_that.connectionBannerErrorIconColor,_that.emptyStateIconColor,_that.emptyStateTitleStyle,_that.emptyStateSubtitleStyle,_that.contextMenuHandleColor,_that.contextMenuDestructiveColor,_that.scrollToBottomButtonColor,_that.scrollToBottomIconColor,_that.attachmentPickerCircleColor,_that.attachmentPickerIconColor,_that.attachmentPickerLabelStyle,_that.imageViewerBackgroundColor,_that.imageViewerIconColor,_that.presenceAvailableColor,_that.presenceAwayColor,_that.presenceBusyColor,_that.presenceDndColor,_that.galleryAppBarBackgroundColor,_that.galleryAppBarForegroundColor,_that.galleryTabIndicatorColor);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ChatUiLocalizations l10n,  ChatBubbleTheme bubble,  ChatInputTheme input,  ChatRoomListTheme roomList,  ChatMarkdownTheme markdown,  Widget Function(BuildContext, double latitude, double longitude)? locationMapBuilder,  TextStyle? dateSeparatorTextStyle,  Color? dateSeparatorBackgroundColor,  TextStyle? systemMessageTextStyle,  Color? systemMessageBackgroundColor,  Color? typingIndicatorDotColor,  TextStyle? typingStatusTextStyle,  Color? reactionBackgroundColor,  Color? reactionSelectedColor,  Color? reactionSelectedBorderColor,  TextStyle? reactionTextStyle,  double? reactionPickerElevation,  BorderRadius? reactionPickerBorderRadius,  double? reactionPickerEmojiSize,  Color? reactionDetailSheetBackgroundColor,  TextStyle? reactionDetailUserNameStyle,  Color? reactionDetailRemoveColor,  Color? floatingPickerBackgroundColor,  Color? fullEmojiPickerBackgroundColor,  Color? audioPlayButtonColor,  Color? audioPlayIconColor,  Color? audioSeekBarColor,  Color? audioSeekBarActiveColor,  TextStyle? audioDurationTextStyle,  Color? audioSpeedButtonColor,  TextStyle? audioSpeedTextStyle,  Color? audioListenedIconColor,  Color? audioUnlistenedIconColor,  Color? voiceRecorderActiveColor,  TextStyle? voiceRecorderTimerStyle,  Color? voiceRecorderOverlayColor,  Color? voiceRecorderCancelColor,  Color? voiceRecorderLockIconColor,  TextStyle? voiceRecorderHintStyle,  Color? waveformActiveColor,  Color? waveformInactiveColor,  Color? waveformRecordingColor,  BorderRadius? imageBorderRadius,  double? imageMaxHeight,  double? imageMaxWidth,  TextStyle? imageCaptionStyle,  Color? videoPlayIconColor,  Color? videoPlayIconBackgroundColor,  Color? videoPlaceholderIconColor,  double? videoHeight,  Color? videoPlaceholderColor,  BorderRadius? videoBorderRadius,  Color? fileIconColor,  TextStyle? fileNameTextStyle,  TextStyle? fileSizeTextStyle,  Color? linkPreviewBackgroundColor,  TextStyle? linkPreviewTitleStyle,  TextStyle? linkPreviewDescriptionStyle,  BorderRadius? linkPreviewBorderRadius,  TextStyle? linkPreviewDomainStyle,  Color? linkPreviewBorderColor,  Color? backgroundColor,  ImageProvider? backgroundImage,  ImageRepeat backgroundImageRepeat,  double backgroundImageOpacity,  ColorFilter? backgroundImageColorFilter,  Color? avatarBackgroundColor,  TextStyle? avatarInitialsTextStyle,  Color? avatarOnlineColor,  Color? avatarOfflineColor,  Color? avatarOnlineBorderColor,  Color? connectionBannerColor,  TextStyle? connectionBannerTextStyle,  Color? connectionBannerErrorIconColor,  Color? emptyStateIconColor,  TextStyle? emptyStateTitleStyle,  TextStyle? emptyStateSubtitleStyle,  Color? contextMenuHandleColor,  Color? contextMenuDestructiveColor,  Color? scrollToBottomButtonColor,  Color? scrollToBottomIconColor,  Color? attachmentPickerCircleColor,  Color? attachmentPickerIconColor,  TextStyle? attachmentPickerLabelStyle,  Color? imageViewerBackgroundColor,  Color? imageViewerIconColor,  Color? presenceAvailableColor,  Color? presenceAwayColor,  Color? presenceBusyColor,  Color? presenceDndColor,  Color? galleryAppBarBackgroundColor,  Color? galleryAppBarForegroundColor,  Color? galleryTabIndicatorColor)?  $default,) {final _that = this;
switch (_that) {
case _ChatTheme() when $default != null:
return $default(_that.l10n,_that.bubble,_that.input,_that.roomList,_that.markdown,_that.locationMapBuilder,_that.dateSeparatorTextStyle,_that.dateSeparatorBackgroundColor,_that.systemMessageTextStyle,_that.systemMessageBackgroundColor,_that.typingIndicatorDotColor,_that.typingStatusTextStyle,_that.reactionBackgroundColor,_that.reactionSelectedColor,_that.reactionSelectedBorderColor,_that.reactionTextStyle,_that.reactionPickerElevation,_that.reactionPickerBorderRadius,_that.reactionPickerEmojiSize,_that.reactionDetailSheetBackgroundColor,_that.reactionDetailUserNameStyle,_that.reactionDetailRemoveColor,_that.floatingPickerBackgroundColor,_that.fullEmojiPickerBackgroundColor,_that.audioPlayButtonColor,_that.audioPlayIconColor,_that.audioSeekBarColor,_that.audioSeekBarActiveColor,_that.audioDurationTextStyle,_that.audioSpeedButtonColor,_that.audioSpeedTextStyle,_that.audioListenedIconColor,_that.audioUnlistenedIconColor,_that.voiceRecorderActiveColor,_that.voiceRecorderTimerStyle,_that.voiceRecorderOverlayColor,_that.voiceRecorderCancelColor,_that.voiceRecorderLockIconColor,_that.voiceRecorderHintStyle,_that.waveformActiveColor,_that.waveformInactiveColor,_that.waveformRecordingColor,_that.imageBorderRadius,_that.imageMaxHeight,_that.imageMaxWidth,_that.imageCaptionStyle,_that.videoPlayIconColor,_that.videoPlayIconBackgroundColor,_that.videoPlaceholderIconColor,_that.videoHeight,_that.videoPlaceholderColor,_that.videoBorderRadius,_that.fileIconColor,_that.fileNameTextStyle,_that.fileSizeTextStyle,_that.linkPreviewBackgroundColor,_that.linkPreviewTitleStyle,_that.linkPreviewDescriptionStyle,_that.linkPreviewBorderRadius,_that.linkPreviewDomainStyle,_that.linkPreviewBorderColor,_that.backgroundColor,_that.backgroundImage,_that.backgroundImageRepeat,_that.backgroundImageOpacity,_that.backgroundImageColorFilter,_that.avatarBackgroundColor,_that.avatarInitialsTextStyle,_that.avatarOnlineColor,_that.avatarOfflineColor,_that.avatarOnlineBorderColor,_that.connectionBannerColor,_that.connectionBannerTextStyle,_that.connectionBannerErrorIconColor,_that.emptyStateIconColor,_that.emptyStateTitleStyle,_that.emptyStateSubtitleStyle,_that.contextMenuHandleColor,_that.contextMenuDestructiveColor,_that.scrollToBottomButtonColor,_that.scrollToBottomIconColor,_that.attachmentPickerCircleColor,_that.attachmentPickerIconColor,_that.attachmentPickerLabelStyle,_that.imageViewerBackgroundColor,_that.imageViewerIconColor,_that.presenceAvailableColor,_that.presenceAwayColor,_that.presenceBusyColor,_that.presenceDndColor,_that.galleryAppBarBackgroundColor,_that.galleryAppBarForegroundColor,_that.galleryTabIndicatorColor);case _:
  return null;

}
}

}

/// @nodoc


class _ChatTheme implements ChatTheme {
  const _ChatTheme({this.l10n = ChatUiLocalizations.en, this.bubble = const ChatBubbleTheme(), this.input = const ChatInputTheme(), this.roomList = const ChatRoomListTheme(), this.markdown = const ChatMarkdownTheme(), this.locationMapBuilder, this.dateSeparatorTextStyle, this.dateSeparatorBackgroundColor, this.systemMessageTextStyle, this.systemMessageBackgroundColor, this.typingIndicatorDotColor, this.typingStatusTextStyle, this.reactionBackgroundColor, this.reactionSelectedColor, this.reactionSelectedBorderColor, this.reactionTextStyle, this.reactionPickerElevation, this.reactionPickerBorderRadius, this.reactionPickerEmojiSize, this.reactionDetailSheetBackgroundColor, this.reactionDetailUserNameStyle, this.reactionDetailRemoveColor, this.floatingPickerBackgroundColor, this.fullEmojiPickerBackgroundColor, this.audioPlayButtonColor, this.audioPlayIconColor, this.audioSeekBarColor, this.audioSeekBarActiveColor, this.audioDurationTextStyle, this.audioSpeedButtonColor, this.audioSpeedTextStyle, this.audioListenedIconColor, this.audioUnlistenedIconColor, this.voiceRecorderActiveColor, this.voiceRecorderTimerStyle, this.voiceRecorderOverlayColor, this.voiceRecorderCancelColor, this.voiceRecorderLockIconColor, this.voiceRecorderHintStyle, this.waveformActiveColor, this.waveformInactiveColor, this.waveformRecordingColor, this.imageBorderRadius, this.imageMaxHeight, this.imageMaxWidth, this.imageCaptionStyle, this.videoPlayIconColor, this.videoPlayIconBackgroundColor, this.videoPlaceholderIconColor, this.videoHeight, this.videoPlaceholderColor, this.videoBorderRadius, this.fileIconColor, this.fileNameTextStyle, this.fileSizeTextStyle, this.linkPreviewBackgroundColor, this.linkPreviewTitleStyle, this.linkPreviewDescriptionStyle, this.linkPreviewBorderRadius, this.linkPreviewDomainStyle, this.linkPreviewBorderColor, this.backgroundColor, this.backgroundImage, this.backgroundImageRepeat = ImageRepeat.noRepeat, this.backgroundImageOpacity = 1.0, this.backgroundImageColorFilter, this.avatarBackgroundColor, this.avatarInitialsTextStyle, this.avatarOnlineColor, this.avatarOfflineColor, this.avatarOnlineBorderColor, this.connectionBannerColor, this.connectionBannerTextStyle, this.connectionBannerErrorIconColor, this.emptyStateIconColor, this.emptyStateTitleStyle, this.emptyStateSubtitleStyle, this.contextMenuHandleColor, this.contextMenuDestructiveColor, this.scrollToBottomButtonColor, this.scrollToBottomIconColor, this.attachmentPickerCircleColor, this.attachmentPickerIconColor, this.attachmentPickerLabelStyle, this.imageViewerBackgroundColor, this.imageViewerIconColor, this.presenceAvailableColor, this.presenceAwayColor, this.presenceBusyColor, this.presenceDndColor, this.galleryAppBarBackgroundColor, this.galleryAppBarForegroundColor, this.galleryTabIndicatorColor});
  

@override@JsonKey() final  ChatUiLocalizations l10n;
@override@JsonKey() final  ChatBubbleTheme bubble;
@override@JsonKey() final  ChatInputTheme input;
@override@JsonKey() final  ChatRoomListTheme roomList;
@override@JsonKey() final  ChatMarkdownTheme markdown;
/// Custom builder for the map preview inside `LocationBubble`. When
/// provided, replaces the default static map image — useful for apps
/// that already have a maps SDK authorised and want to render a
/// lightweight interactive map (e.g. `GoogleMap` in lite mode).
@override final  Widget Function(BuildContext, double latitude, double longitude)? locationMapBuilder;
// Date separator + system messages
@override final  TextStyle? dateSeparatorTextStyle;
@override final  Color? dateSeparatorBackgroundColor;
@override final  TextStyle? systemMessageTextStyle;
@override final  Color? systemMessageBackgroundColor;
// Typing indicator (bubble + status text in room tiles)
@override final  Color? typingIndicatorDotColor;
@override final  TextStyle? typingStatusTextStyle;
// Reactions (bar + picker + detail sheet + emoji picker)
@override final  Color? reactionBackgroundColor;
@override final  Color? reactionSelectedColor;
@override final  Color? reactionSelectedBorderColor;
@override final  TextStyle? reactionTextStyle;
@override final  double? reactionPickerElevation;
@override final  BorderRadius? reactionPickerBorderRadius;
@override final  double? reactionPickerEmojiSize;
@override final  Color? reactionDetailSheetBackgroundColor;
@override final  TextStyle? reactionDetailUserNameStyle;
@override final  Color? reactionDetailRemoveColor;
@override final  Color? floatingPickerBackgroundColor;
@override final  Color? fullEmojiPickerBackgroundColor;
// Audio bubble + voice recorder + waveform
@override final  Color? audioPlayButtonColor;
@override final  Color? audioPlayIconColor;
@override final  Color? audioSeekBarColor;
@override final  Color? audioSeekBarActiveColor;
@override final  TextStyle? audioDurationTextStyle;
@override final  Color? audioSpeedButtonColor;
@override final  TextStyle? audioSpeedTextStyle;
@override final  Color? audioListenedIconColor;
@override final  Color? audioUnlistenedIconColor;
@override final  Color? voiceRecorderActiveColor;
@override final  TextStyle? voiceRecorderTimerStyle;
@override final  Color? voiceRecorderOverlayColor;
@override final  Color? voiceRecorderCancelColor;
@override final  Color? voiceRecorderLockIconColor;
@override final  TextStyle? voiceRecorderHintStyle;
@override final  Color? waveformActiveColor;
@override final  Color? waveformInactiveColor;
@override final  Color? waveformRecordingColor;
// Image / Video / File / Link Preview bubbles
@override final  BorderRadius? imageBorderRadius;
@override final  double? imageMaxHeight;
@override final  double? imageMaxWidth;
@override final  TextStyle? imageCaptionStyle;
@override final  Color? videoPlayIconColor;
@override final  Color? videoPlayIconBackgroundColor;
@override final  Color? videoPlaceholderIconColor;
@override final  double? videoHeight;
@override final  Color? videoPlaceholderColor;
@override final  BorderRadius? videoBorderRadius;
@override final  Color? fileIconColor;
@override final  TextStyle? fileNameTextStyle;
@override final  TextStyle? fileSizeTextStyle;
@override final  Color? linkPreviewBackgroundColor;
@override final  TextStyle? linkPreviewTitleStyle;
@override final  TextStyle? linkPreviewDescriptionStyle;
@override final  BorderRadius? linkPreviewBorderRadius;
@override final  TextStyle? linkPreviewDomainStyle;
@override final  Color? linkPreviewBorderColor;
// Chat background
@override final  Color? backgroundColor;
@override final  ImageProvider? backgroundImage;
@override@JsonKey() final  ImageRepeat backgroundImageRepeat;
@override@JsonKey() final  double backgroundImageOpacity;
@override final  ColorFilter? backgroundImageColorFilter;
// Avatar
@override final  Color? avatarBackgroundColor;
@override final  TextStyle? avatarInitialsTextStyle;
@override final  Color? avatarOnlineColor;
@override final  Color? avatarOfflineColor;
@override final  Color? avatarOnlineBorderColor;
// Connection banner + empty state
@override final  Color? connectionBannerColor;
@override final  TextStyle? connectionBannerTextStyle;
@override final  Color? connectionBannerErrorIconColor;
@override final  Color? emptyStateIconColor;
@override final  TextStyle? emptyStateTitleStyle;
@override final  TextStyle? emptyStateSubtitleStyle;
// Context menus + scroll to bottom + attachment picker + image viewer
@override final  Color? contextMenuHandleColor;
@override final  Color? contextMenuDestructiveColor;
@override final  Color? scrollToBottomButtonColor;
@override final  Color? scrollToBottomIconColor;
@override final  Color? attachmentPickerCircleColor;
@override final  Color? attachmentPickerIconColor;
@override final  TextStyle? attachmentPickerLabelStyle;
@override final  Color? imageViewerBackgroundColor;
@override final  Color? imageViewerIconColor;
// Presence dots
@override final  Color? presenceAvailableColor;
@override final  Color? presenceAwayColor;
@override final  Color? presenceBusyColor;
@override final  Color? presenceDndColor;
// Media Gallery page (`MediaGalleryPage`'s own Scaffold/AppBar/TabBar
// chrome — everything else in the page already reads `backgroundColor`
// via its child widgets). `null` falls back to the ambient Material
// `Theme`, unchanged from before these fields existed.
@override final  Color? galleryAppBarBackgroundColor;
@override final  Color? galleryAppBarForegroundColor;
@override final  Color? galleryTabIndicatorColor;

/// Create a copy of ChatTheme
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatThemeCopyWith<_ChatTheme> get copyWith => __$ChatThemeCopyWithImpl<_ChatTheme>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatTheme&&(identical(other.l10n, l10n) || other.l10n == l10n)&&(identical(other.bubble, bubble) || other.bubble == bubble)&&(identical(other.input, input) || other.input == input)&&(identical(other.roomList, roomList) || other.roomList == roomList)&&(identical(other.markdown, markdown) || other.markdown == markdown)&&(identical(other.locationMapBuilder, locationMapBuilder) || other.locationMapBuilder == locationMapBuilder)&&(identical(other.dateSeparatorTextStyle, dateSeparatorTextStyle) || other.dateSeparatorTextStyle == dateSeparatorTextStyle)&&(identical(other.dateSeparatorBackgroundColor, dateSeparatorBackgroundColor) || other.dateSeparatorBackgroundColor == dateSeparatorBackgroundColor)&&(identical(other.systemMessageTextStyle, systemMessageTextStyle) || other.systemMessageTextStyle == systemMessageTextStyle)&&(identical(other.systemMessageBackgroundColor, systemMessageBackgroundColor) || other.systemMessageBackgroundColor == systemMessageBackgroundColor)&&(identical(other.typingIndicatorDotColor, typingIndicatorDotColor) || other.typingIndicatorDotColor == typingIndicatorDotColor)&&(identical(other.typingStatusTextStyle, typingStatusTextStyle) || other.typingStatusTextStyle == typingStatusTextStyle)&&(identical(other.reactionBackgroundColor, reactionBackgroundColor) || other.reactionBackgroundColor == reactionBackgroundColor)&&(identical(other.reactionSelectedColor, reactionSelectedColor) || other.reactionSelectedColor == reactionSelectedColor)&&(identical(other.reactionSelectedBorderColor, reactionSelectedBorderColor) || other.reactionSelectedBorderColor == reactionSelectedBorderColor)&&(identical(other.reactionTextStyle, reactionTextStyle) || other.reactionTextStyle == reactionTextStyle)&&(identical(other.reactionPickerElevation, reactionPickerElevation) || other.reactionPickerElevation == reactionPickerElevation)&&(identical(other.reactionPickerBorderRadius, reactionPickerBorderRadius) || other.reactionPickerBorderRadius == reactionPickerBorderRadius)&&(identical(other.reactionPickerEmojiSize, reactionPickerEmojiSize) || other.reactionPickerEmojiSize == reactionPickerEmojiSize)&&(identical(other.reactionDetailSheetBackgroundColor, reactionDetailSheetBackgroundColor) || other.reactionDetailSheetBackgroundColor == reactionDetailSheetBackgroundColor)&&(identical(other.reactionDetailUserNameStyle, reactionDetailUserNameStyle) || other.reactionDetailUserNameStyle == reactionDetailUserNameStyle)&&(identical(other.reactionDetailRemoveColor, reactionDetailRemoveColor) || other.reactionDetailRemoveColor == reactionDetailRemoveColor)&&(identical(other.floatingPickerBackgroundColor, floatingPickerBackgroundColor) || other.floatingPickerBackgroundColor == floatingPickerBackgroundColor)&&(identical(other.fullEmojiPickerBackgroundColor, fullEmojiPickerBackgroundColor) || other.fullEmojiPickerBackgroundColor == fullEmojiPickerBackgroundColor)&&(identical(other.audioPlayButtonColor, audioPlayButtonColor) || other.audioPlayButtonColor == audioPlayButtonColor)&&(identical(other.audioPlayIconColor, audioPlayIconColor) || other.audioPlayIconColor == audioPlayIconColor)&&(identical(other.audioSeekBarColor, audioSeekBarColor) || other.audioSeekBarColor == audioSeekBarColor)&&(identical(other.audioSeekBarActiveColor, audioSeekBarActiveColor) || other.audioSeekBarActiveColor == audioSeekBarActiveColor)&&(identical(other.audioDurationTextStyle, audioDurationTextStyle) || other.audioDurationTextStyle == audioDurationTextStyle)&&(identical(other.audioSpeedButtonColor, audioSpeedButtonColor) || other.audioSpeedButtonColor == audioSpeedButtonColor)&&(identical(other.audioSpeedTextStyle, audioSpeedTextStyle) || other.audioSpeedTextStyle == audioSpeedTextStyle)&&(identical(other.audioListenedIconColor, audioListenedIconColor) || other.audioListenedIconColor == audioListenedIconColor)&&(identical(other.audioUnlistenedIconColor, audioUnlistenedIconColor) || other.audioUnlistenedIconColor == audioUnlistenedIconColor)&&(identical(other.voiceRecorderActiveColor, voiceRecorderActiveColor) || other.voiceRecorderActiveColor == voiceRecorderActiveColor)&&(identical(other.voiceRecorderTimerStyle, voiceRecorderTimerStyle) || other.voiceRecorderTimerStyle == voiceRecorderTimerStyle)&&(identical(other.voiceRecorderOverlayColor, voiceRecorderOverlayColor) || other.voiceRecorderOverlayColor == voiceRecorderOverlayColor)&&(identical(other.voiceRecorderCancelColor, voiceRecorderCancelColor) || other.voiceRecorderCancelColor == voiceRecorderCancelColor)&&(identical(other.voiceRecorderLockIconColor, voiceRecorderLockIconColor) || other.voiceRecorderLockIconColor == voiceRecorderLockIconColor)&&(identical(other.voiceRecorderHintStyle, voiceRecorderHintStyle) || other.voiceRecorderHintStyle == voiceRecorderHintStyle)&&(identical(other.waveformActiveColor, waveformActiveColor) || other.waveformActiveColor == waveformActiveColor)&&(identical(other.waveformInactiveColor, waveformInactiveColor) || other.waveformInactiveColor == waveformInactiveColor)&&(identical(other.waveformRecordingColor, waveformRecordingColor) || other.waveformRecordingColor == waveformRecordingColor)&&(identical(other.imageBorderRadius, imageBorderRadius) || other.imageBorderRadius == imageBorderRadius)&&(identical(other.imageMaxHeight, imageMaxHeight) || other.imageMaxHeight == imageMaxHeight)&&(identical(other.imageMaxWidth, imageMaxWidth) || other.imageMaxWidth == imageMaxWidth)&&(identical(other.imageCaptionStyle, imageCaptionStyle) || other.imageCaptionStyle == imageCaptionStyle)&&(identical(other.videoPlayIconColor, videoPlayIconColor) || other.videoPlayIconColor == videoPlayIconColor)&&(identical(other.videoPlayIconBackgroundColor, videoPlayIconBackgroundColor) || other.videoPlayIconBackgroundColor == videoPlayIconBackgroundColor)&&(identical(other.videoPlaceholderIconColor, videoPlaceholderIconColor) || other.videoPlaceholderIconColor == videoPlaceholderIconColor)&&(identical(other.videoHeight, videoHeight) || other.videoHeight == videoHeight)&&(identical(other.videoPlaceholderColor, videoPlaceholderColor) || other.videoPlaceholderColor == videoPlaceholderColor)&&(identical(other.videoBorderRadius, videoBorderRadius) || other.videoBorderRadius == videoBorderRadius)&&(identical(other.fileIconColor, fileIconColor) || other.fileIconColor == fileIconColor)&&(identical(other.fileNameTextStyle, fileNameTextStyle) || other.fileNameTextStyle == fileNameTextStyle)&&(identical(other.fileSizeTextStyle, fileSizeTextStyle) || other.fileSizeTextStyle == fileSizeTextStyle)&&(identical(other.linkPreviewBackgroundColor, linkPreviewBackgroundColor) || other.linkPreviewBackgroundColor == linkPreviewBackgroundColor)&&(identical(other.linkPreviewTitleStyle, linkPreviewTitleStyle) || other.linkPreviewTitleStyle == linkPreviewTitleStyle)&&(identical(other.linkPreviewDescriptionStyle, linkPreviewDescriptionStyle) || other.linkPreviewDescriptionStyle == linkPreviewDescriptionStyle)&&(identical(other.linkPreviewBorderRadius, linkPreviewBorderRadius) || other.linkPreviewBorderRadius == linkPreviewBorderRadius)&&(identical(other.linkPreviewDomainStyle, linkPreviewDomainStyle) || other.linkPreviewDomainStyle == linkPreviewDomainStyle)&&(identical(other.linkPreviewBorderColor, linkPreviewBorderColor) || other.linkPreviewBorderColor == linkPreviewBorderColor)&&(identical(other.backgroundColor, backgroundColor) || other.backgroundColor == backgroundColor)&&(identical(other.backgroundImage, backgroundImage) || other.backgroundImage == backgroundImage)&&(identical(other.backgroundImageRepeat, backgroundImageRepeat) || other.backgroundImageRepeat == backgroundImageRepeat)&&(identical(other.backgroundImageOpacity, backgroundImageOpacity) || other.backgroundImageOpacity == backgroundImageOpacity)&&(identical(other.backgroundImageColorFilter, backgroundImageColorFilter) || other.backgroundImageColorFilter == backgroundImageColorFilter)&&(identical(other.avatarBackgroundColor, avatarBackgroundColor) || other.avatarBackgroundColor == avatarBackgroundColor)&&(identical(other.avatarInitialsTextStyle, avatarInitialsTextStyle) || other.avatarInitialsTextStyle == avatarInitialsTextStyle)&&(identical(other.avatarOnlineColor, avatarOnlineColor) || other.avatarOnlineColor == avatarOnlineColor)&&(identical(other.avatarOfflineColor, avatarOfflineColor) || other.avatarOfflineColor == avatarOfflineColor)&&(identical(other.avatarOnlineBorderColor, avatarOnlineBorderColor) || other.avatarOnlineBorderColor == avatarOnlineBorderColor)&&(identical(other.connectionBannerColor, connectionBannerColor) || other.connectionBannerColor == connectionBannerColor)&&(identical(other.connectionBannerTextStyle, connectionBannerTextStyle) || other.connectionBannerTextStyle == connectionBannerTextStyle)&&(identical(other.connectionBannerErrorIconColor, connectionBannerErrorIconColor) || other.connectionBannerErrorIconColor == connectionBannerErrorIconColor)&&(identical(other.emptyStateIconColor, emptyStateIconColor) || other.emptyStateIconColor == emptyStateIconColor)&&(identical(other.emptyStateTitleStyle, emptyStateTitleStyle) || other.emptyStateTitleStyle == emptyStateTitleStyle)&&(identical(other.emptyStateSubtitleStyle, emptyStateSubtitleStyle) || other.emptyStateSubtitleStyle == emptyStateSubtitleStyle)&&(identical(other.contextMenuHandleColor, contextMenuHandleColor) || other.contextMenuHandleColor == contextMenuHandleColor)&&(identical(other.contextMenuDestructiveColor, contextMenuDestructiveColor) || other.contextMenuDestructiveColor == contextMenuDestructiveColor)&&(identical(other.scrollToBottomButtonColor, scrollToBottomButtonColor) || other.scrollToBottomButtonColor == scrollToBottomButtonColor)&&(identical(other.scrollToBottomIconColor, scrollToBottomIconColor) || other.scrollToBottomIconColor == scrollToBottomIconColor)&&(identical(other.attachmentPickerCircleColor, attachmentPickerCircleColor) || other.attachmentPickerCircleColor == attachmentPickerCircleColor)&&(identical(other.attachmentPickerIconColor, attachmentPickerIconColor) || other.attachmentPickerIconColor == attachmentPickerIconColor)&&(identical(other.attachmentPickerLabelStyle, attachmentPickerLabelStyle) || other.attachmentPickerLabelStyle == attachmentPickerLabelStyle)&&(identical(other.imageViewerBackgroundColor, imageViewerBackgroundColor) || other.imageViewerBackgroundColor == imageViewerBackgroundColor)&&(identical(other.imageViewerIconColor, imageViewerIconColor) || other.imageViewerIconColor == imageViewerIconColor)&&(identical(other.presenceAvailableColor, presenceAvailableColor) || other.presenceAvailableColor == presenceAvailableColor)&&(identical(other.presenceAwayColor, presenceAwayColor) || other.presenceAwayColor == presenceAwayColor)&&(identical(other.presenceBusyColor, presenceBusyColor) || other.presenceBusyColor == presenceBusyColor)&&(identical(other.presenceDndColor, presenceDndColor) || other.presenceDndColor == presenceDndColor)&&(identical(other.galleryAppBarBackgroundColor, galleryAppBarBackgroundColor) || other.galleryAppBarBackgroundColor == galleryAppBarBackgroundColor)&&(identical(other.galleryAppBarForegroundColor, galleryAppBarForegroundColor) || other.galleryAppBarForegroundColor == galleryAppBarForegroundColor)&&(identical(other.galleryTabIndicatorColor, galleryTabIndicatorColor) || other.galleryTabIndicatorColor == galleryTabIndicatorColor));
}


@override
int get hashCode => Object.hashAll([runtimeType,l10n,bubble,input,roomList,markdown,locationMapBuilder,dateSeparatorTextStyle,dateSeparatorBackgroundColor,systemMessageTextStyle,systemMessageBackgroundColor,typingIndicatorDotColor,typingStatusTextStyle,reactionBackgroundColor,reactionSelectedColor,reactionSelectedBorderColor,reactionTextStyle,reactionPickerElevation,reactionPickerBorderRadius,reactionPickerEmojiSize,reactionDetailSheetBackgroundColor,reactionDetailUserNameStyle,reactionDetailRemoveColor,floatingPickerBackgroundColor,fullEmojiPickerBackgroundColor,audioPlayButtonColor,audioPlayIconColor,audioSeekBarColor,audioSeekBarActiveColor,audioDurationTextStyle,audioSpeedButtonColor,audioSpeedTextStyle,audioListenedIconColor,audioUnlistenedIconColor,voiceRecorderActiveColor,voiceRecorderTimerStyle,voiceRecorderOverlayColor,voiceRecorderCancelColor,voiceRecorderLockIconColor,voiceRecorderHintStyle,waveformActiveColor,waveformInactiveColor,waveformRecordingColor,imageBorderRadius,imageMaxHeight,imageMaxWidth,imageCaptionStyle,videoPlayIconColor,videoPlayIconBackgroundColor,videoPlaceholderIconColor,videoHeight,videoPlaceholderColor,videoBorderRadius,fileIconColor,fileNameTextStyle,fileSizeTextStyle,linkPreviewBackgroundColor,linkPreviewTitleStyle,linkPreviewDescriptionStyle,linkPreviewBorderRadius,linkPreviewDomainStyle,linkPreviewBorderColor,backgroundColor,backgroundImage,backgroundImageRepeat,backgroundImageOpacity,backgroundImageColorFilter,avatarBackgroundColor,avatarInitialsTextStyle,avatarOnlineColor,avatarOfflineColor,avatarOnlineBorderColor,connectionBannerColor,connectionBannerTextStyle,connectionBannerErrorIconColor,emptyStateIconColor,emptyStateTitleStyle,emptyStateSubtitleStyle,contextMenuHandleColor,contextMenuDestructiveColor,scrollToBottomButtonColor,scrollToBottomIconColor,attachmentPickerCircleColor,attachmentPickerIconColor,attachmentPickerLabelStyle,imageViewerBackgroundColor,imageViewerIconColor,presenceAvailableColor,presenceAwayColor,presenceBusyColor,presenceDndColor,galleryAppBarBackgroundColor,galleryAppBarForegroundColor,galleryTabIndicatorColor]);

@override
String toString() {
  return 'ChatTheme(l10n: $l10n, bubble: $bubble, input: $input, roomList: $roomList, markdown: $markdown, locationMapBuilder: $locationMapBuilder, dateSeparatorTextStyle: $dateSeparatorTextStyle, dateSeparatorBackgroundColor: $dateSeparatorBackgroundColor, systemMessageTextStyle: $systemMessageTextStyle, systemMessageBackgroundColor: $systemMessageBackgroundColor, typingIndicatorDotColor: $typingIndicatorDotColor, typingStatusTextStyle: $typingStatusTextStyle, reactionBackgroundColor: $reactionBackgroundColor, reactionSelectedColor: $reactionSelectedColor, reactionSelectedBorderColor: $reactionSelectedBorderColor, reactionTextStyle: $reactionTextStyle, reactionPickerElevation: $reactionPickerElevation, reactionPickerBorderRadius: $reactionPickerBorderRadius, reactionPickerEmojiSize: $reactionPickerEmojiSize, reactionDetailSheetBackgroundColor: $reactionDetailSheetBackgroundColor, reactionDetailUserNameStyle: $reactionDetailUserNameStyle, reactionDetailRemoveColor: $reactionDetailRemoveColor, floatingPickerBackgroundColor: $floatingPickerBackgroundColor, fullEmojiPickerBackgroundColor: $fullEmojiPickerBackgroundColor, audioPlayButtonColor: $audioPlayButtonColor, audioPlayIconColor: $audioPlayIconColor, audioSeekBarColor: $audioSeekBarColor, audioSeekBarActiveColor: $audioSeekBarActiveColor, audioDurationTextStyle: $audioDurationTextStyle, audioSpeedButtonColor: $audioSpeedButtonColor, audioSpeedTextStyle: $audioSpeedTextStyle, audioListenedIconColor: $audioListenedIconColor, audioUnlistenedIconColor: $audioUnlistenedIconColor, voiceRecorderActiveColor: $voiceRecorderActiveColor, voiceRecorderTimerStyle: $voiceRecorderTimerStyle, voiceRecorderOverlayColor: $voiceRecorderOverlayColor, voiceRecorderCancelColor: $voiceRecorderCancelColor, voiceRecorderLockIconColor: $voiceRecorderLockIconColor, voiceRecorderHintStyle: $voiceRecorderHintStyle, waveformActiveColor: $waveformActiveColor, waveformInactiveColor: $waveformInactiveColor, waveformRecordingColor: $waveformRecordingColor, imageBorderRadius: $imageBorderRadius, imageMaxHeight: $imageMaxHeight, imageMaxWidth: $imageMaxWidth, imageCaptionStyle: $imageCaptionStyle, videoPlayIconColor: $videoPlayIconColor, videoPlayIconBackgroundColor: $videoPlayIconBackgroundColor, videoPlaceholderIconColor: $videoPlaceholderIconColor, videoHeight: $videoHeight, videoPlaceholderColor: $videoPlaceholderColor, videoBorderRadius: $videoBorderRadius, fileIconColor: $fileIconColor, fileNameTextStyle: $fileNameTextStyle, fileSizeTextStyle: $fileSizeTextStyle, linkPreviewBackgroundColor: $linkPreviewBackgroundColor, linkPreviewTitleStyle: $linkPreviewTitleStyle, linkPreviewDescriptionStyle: $linkPreviewDescriptionStyle, linkPreviewBorderRadius: $linkPreviewBorderRadius, linkPreviewDomainStyle: $linkPreviewDomainStyle, linkPreviewBorderColor: $linkPreviewBorderColor, backgroundColor: $backgroundColor, backgroundImage: $backgroundImage, backgroundImageRepeat: $backgroundImageRepeat, backgroundImageOpacity: $backgroundImageOpacity, backgroundImageColorFilter: $backgroundImageColorFilter, avatarBackgroundColor: $avatarBackgroundColor, avatarInitialsTextStyle: $avatarInitialsTextStyle, avatarOnlineColor: $avatarOnlineColor, avatarOfflineColor: $avatarOfflineColor, avatarOnlineBorderColor: $avatarOnlineBorderColor, connectionBannerColor: $connectionBannerColor, connectionBannerTextStyle: $connectionBannerTextStyle, connectionBannerErrorIconColor: $connectionBannerErrorIconColor, emptyStateIconColor: $emptyStateIconColor, emptyStateTitleStyle: $emptyStateTitleStyle, emptyStateSubtitleStyle: $emptyStateSubtitleStyle, contextMenuHandleColor: $contextMenuHandleColor, contextMenuDestructiveColor: $contextMenuDestructiveColor, scrollToBottomButtonColor: $scrollToBottomButtonColor, scrollToBottomIconColor: $scrollToBottomIconColor, attachmentPickerCircleColor: $attachmentPickerCircleColor, attachmentPickerIconColor: $attachmentPickerIconColor, attachmentPickerLabelStyle: $attachmentPickerLabelStyle, imageViewerBackgroundColor: $imageViewerBackgroundColor, imageViewerIconColor: $imageViewerIconColor, presenceAvailableColor: $presenceAvailableColor, presenceAwayColor: $presenceAwayColor, presenceBusyColor: $presenceBusyColor, presenceDndColor: $presenceDndColor, galleryAppBarBackgroundColor: $galleryAppBarBackgroundColor, galleryAppBarForegroundColor: $galleryAppBarForegroundColor, galleryTabIndicatorColor: $galleryTabIndicatorColor)';
}


}

/// @nodoc
abstract mixin class _$ChatThemeCopyWith<$Res> implements $ChatThemeCopyWith<$Res> {
  factory _$ChatThemeCopyWith(_ChatTheme value, $Res Function(_ChatTheme) _then) = __$ChatThemeCopyWithImpl;
@override @useResult
$Res call({
 ChatUiLocalizations l10n, ChatBubbleTheme bubble, ChatInputTheme input, ChatRoomListTheme roomList, ChatMarkdownTheme markdown, Widget Function(BuildContext, double latitude, double longitude)? locationMapBuilder, TextStyle? dateSeparatorTextStyle, Color? dateSeparatorBackgroundColor, TextStyle? systemMessageTextStyle, Color? systemMessageBackgroundColor, Color? typingIndicatorDotColor, TextStyle? typingStatusTextStyle, Color? reactionBackgroundColor, Color? reactionSelectedColor, Color? reactionSelectedBorderColor, TextStyle? reactionTextStyle, double? reactionPickerElevation, BorderRadius? reactionPickerBorderRadius, double? reactionPickerEmojiSize, Color? reactionDetailSheetBackgroundColor, TextStyle? reactionDetailUserNameStyle, Color? reactionDetailRemoveColor, Color? floatingPickerBackgroundColor, Color? fullEmojiPickerBackgroundColor, Color? audioPlayButtonColor, Color? audioPlayIconColor, Color? audioSeekBarColor, Color? audioSeekBarActiveColor, TextStyle? audioDurationTextStyle, Color? audioSpeedButtonColor, TextStyle? audioSpeedTextStyle, Color? audioListenedIconColor, Color? audioUnlistenedIconColor, Color? voiceRecorderActiveColor, TextStyle? voiceRecorderTimerStyle, Color? voiceRecorderOverlayColor, Color? voiceRecorderCancelColor, Color? voiceRecorderLockIconColor, TextStyle? voiceRecorderHintStyle, Color? waveformActiveColor, Color? waveformInactiveColor, Color? waveformRecordingColor, BorderRadius? imageBorderRadius, double? imageMaxHeight, double? imageMaxWidth, TextStyle? imageCaptionStyle, Color? videoPlayIconColor, Color? videoPlayIconBackgroundColor, Color? videoPlaceholderIconColor, double? videoHeight, Color? videoPlaceholderColor, BorderRadius? videoBorderRadius, Color? fileIconColor, TextStyle? fileNameTextStyle, TextStyle? fileSizeTextStyle, Color? linkPreviewBackgroundColor, TextStyle? linkPreviewTitleStyle, TextStyle? linkPreviewDescriptionStyle, BorderRadius? linkPreviewBorderRadius, TextStyle? linkPreviewDomainStyle, Color? linkPreviewBorderColor, Color? backgroundColor, ImageProvider? backgroundImage, ImageRepeat backgroundImageRepeat, double backgroundImageOpacity, ColorFilter? backgroundImageColorFilter, Color? avatarBackgroundColor, TextStyle? avatarInitialsTextStyle, Color? avatarOnlineColor, Color? avatarOfflineColor, Color? avatarOnlineBorderColor, Color? connectionBannerColor, TextStyle? connectionBannerTextStyle, Color? connectionBannerErrorIconColor, Color? emptyStateIconColor, TextStyle? emptyStateTitleStyle, TextStyle? emptyStateSubtitleStyle, Color? contextMenuHandleColor, Color? contextMenuDestructiveColor, Color? scrollToBottomButtonColor, Color? scrollToBottomIconColor, Color? attachmentPickerCircleColor, Color? attachmentPickerIconColor, TextStyle? attachmentPickerLabelStyle, Color? imageViewerBackgroundColor, Color? imageViewerIconColor, Color? presenceAvailableColor, Color? presenceAwayColor, Color? presenceBusyColor, Color? presenceDndColor, Color? galleryAppBarBackgroundColor, Color? galleryAppBarForegroundColor, Color? galleryTabIndicatorColor
});


@override $ChatBubbleThemeCopyWith<$Res> get bubble;@override $ChatInputThemeCopyWith<$Res> get input;@override $ChatRoomListThemeCopyWith<$Res> get roomList;@override $ChatMarkdownThemeCopyWith<$Res> get markdown;

}
/// @nodoc
class __$ChatThemeCopyWithImpl<$Res>
    implements _$ChatThemeCopyWith<$Res> {
  __$ChatThemeCopyWithImpl(this._self, this._then);

  final _ChatTheme _self;
  final $Res Function(_ChatTheme) _then;

/// Create a copy of ChatTheme
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? l10n = null,Object? bubble = null,Object? input = null,Object? roomList = null,Object? markdown = null,Object? locationMapBuilder = freezed,Object? dateSeparatorTextStyle = freezed,Object? dateSeparatorBackgroundColor = freezed,Object? systemMessageTextStyle = freezed,Object? systemMessageBackgroundColor = freezed,Object? typingIndicatorDotColor = freezed,Object? typingStatusTextStyle = freezed,Object? reactionBackgroundColor = freezed,Object? reactionSelectedColor = freezed,Object? reactionSelectedBorderColor = freezed,Object? reactionTextStyle = freezed,Object? reactionPickerElevation = freezed,Object? reactionPickerBorderRadius = freezed,Object? reactionPickerEmojiSize = freezed,Object? reactionDetailSheetBackgroundColor = freezed,Object? reactionDetailUserNameStyle = freezed,Object? reactionDetailRemoveColor = freezed,Object? floatingPickerBackgroundColor = freezed,Object? fullEmojiPickerBackgroundColor = freezed,Object? audioPlayButtonColor = freezed,Object? audioPlayIconColor = freezed,Object? audioSeekBarColor = freezed,Object? audioSeekBarActiveColor = freezed,Object? audioDurationTextStyle = freezed,Object? audioSpeedButtonColor = freezed,Object? audioSpeedTextStyle = freezed,Object? audioListenedIconColor = freezed,Object? audioUnlistenedIconColor = freezed,Object? voiceRecorderActiveColor = freezed,Object? voiceRecorderTimerStyle = freezed,Object? voiceRecorderOverlayColor = freezed,Object? voiceRecorderCancelColor = freezed,Object? voiceRecorderLockIconColor = freezed,Object? voiceRecorderHintStyle = freezed,Object? waveformActiveColor = freezed,Object? waveformInactiveColor = freezed,Object? waveformRecordingColor = freezed,Object? imageBorderRadius = freezed,Object? imageMaxHeight = freezed,Object? imageMaxWidth = freezed,Object? imageCaptionStyle = freezed,Object? videoPlayIconColor = freezed,Object? videoPlayIconBackgroundColor = freezed,Object? videoPlaceholderIconColor = freezed,Object? videoHeight = freezed,Object? videoPlaceholderColor = freezed,Object? videoBorderRadius = freezed,Object? fileIconColor = freezed,Object? fileNameTextStyle = freezed,Object? fileSizeTextStyle = freezed,Object? linkPreviewBackgroundColor = freezed,Object? linkPreviewTitleStyle = freezed,Object? linkPreviewDescriptionStyle = freezed,Object? linkPreviewBorderRadius = freezed,Object? linkPreviewDomainStyle = freezed,Object? linkPreviewBorderColor = freezed,Object? backgroundColor = freezed,Object? backgroundImage = freezed,Object? backgroundImageRepeat = null,Object? backgroundImageOpacity = null,Object? backgroundImageColorFilter = freezed,Object? avatarBackgroundColor = freezed,Object? avatarInitialsTextStyle = freezed,Object? avatarOnlineColor = freezed,Object? avatarOfflineColor = freezed,Object? avatarOnlineBorderColor = freezed,Object? connectionBannerColor = freezed,Object? connectionBannerTextStyle = freezed,Object? connectionBannerErrorIconColor = freezed,Object? emptyStateIconColor = freezed,Object? emptyStateTitleStyle = freezed,Object? emptyStateSubtitleStyle = freezed,Object? contextMenuHandleColor = freezed,Object? contextMenuDestructiveColor = freezed,Object? scrollToBottomButtonColor = freezed,Object? scrollToBottomIconColor = freezed,Object? attachmentPickerCircleColor = freezed,Object? attachmentPickerIconColor = freezed,Object? attachmentPickerLabelStyle = freezed,Object? imageViewerBackgroundColor = freezed,Object? imageViewerIconColor = freezed,Object? presenceAvailableColor = freezed,Object? presenceAwayColor = freezed,Object? presenceBusyColor = freezed,Object? presenceDndColor = freezed,Object? galleryAppBarBackgroundColor = freezed,Object? galleryAppBarForegroundColor = freezed,Object? galleryTabIndicatorColor = freezed,}) {
  return _then(_ChatTheme(
l10n: null == l10n ? _self.l10n : l10n // ignore: cast_nullable_to_non_nullable
as ChatUiLocalizations,bubble: null == bubble ? _self.bubble : bubble // ignore: cast_nullable_to_non_nullable
as ChatBubbleTheme,input: null == input ? _self.input : input // ignore: cast_nullable_to_non_nullable
as ChatInputTheme,roomList: null == roomList ? _self.roomList : roomList // ignore: cast_nullable_to_non_nullable
as ChatRoomListTheme,markdown: null == markdown ? _self.markdown : markdown // ignore: cast_nullable_to_non_nullable
as ChatMarkdownTheme,locationMapBuilder: freezed == locationMapBuilder ? _self.locationMapBuilder : locationMapBuilder // ignore: cast_nullable_to_non_nullable
as Widget Function(BuildContext, double latitude, double longitude)?,dateSeparatorTextStyle: freezed == dateSeparatorTextStyle ? _self.dateSeparatorTextStyle : dateSeparatorTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,dateSeparatorBackgroundColor: freezed == dateSeparatorBackgroundColor ? _self.dateSeparatorBackgroundColor : dateSeparatorBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,systemMessageTextStyle: freezed == systemMessageTextStyle ? _self.systemMessageTextStyle : systemMessageTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,systemMessageBackgroundColor: freezed == systemMessageBackgroundColor ? _self.systemMessageBackgroundColor : systemMessageBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,typingIndicatorDotColor: freezed == typingIndicatorDotColor ? _self.typingIndicatorDotColor : typingIndicatorDotColor // ignore: cast_nullable_to_non_nullable
as Color?,typingStatusTextStyle: freezed == typingStatusTextStyle ? _self.typingStatusTextStyle : typingStatusTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,reactionBackgroundColor: freezed == reactionBackgroundColor ? _self.reactionBackgroundColor : reactionBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,reactionSelectedColor: freezed == reactionSelectedColor ? _self.reactionSelectedColor : reactionSelectedColor // ignore: cast_nullable_to_non_nullable
as Color?,reactionSelectedBorderColor: freezed == reactionSelectedBorderColor ? _self.reactionSelectedBorderColor : reactionSelectedBorderColor // ignore: cast_nullable_to_non_nullable
as Color?,reactionTextStyle: freezed == reactionTextStyle ? _self.reactionTextStyle : reactionTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,reactionPickerElevation: freezed == reactionPickerElevation ? _self.reactionPickerElevation : reactionPickerElevation // ignore: cast_nullable_to_non_nullable
as double?,reactionPickerBorderRadius: freezed == reactionPickerBorderRadius ? _self.reactionPickerBorderRadius : reactionPickerBorderRadius // ignore: cast_nullable_to_non_nullable
as BorderRadius?,reactionPickerEmojiSize: freezed == reactionPickerEmojiSize ? _self.reactionPickerEmojiSize : reactionPickerEmojiSize // ignore: cast_nullable_to_non_nullable
as double?,reactionDetailSheetBackgroundColor: freezed == reactionDetailSheetBackgroundColor ? _self.reactionDetailSheetBackgroundColor : reactionDetailSheetBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,reactionDetailUserNameStyle: freezed == reactionDetailUserNameStyle ? _self.reactionDetailUserNameStyle : reactionDetailUserNameStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,reactionDetailRemoveColor: freezed == reactionDetailRemoveColor ? _self.reactionDetailRemoveColor : reactionDetailRemoveColor // ignore: cast_nullable_to_non_nullable
as Color?,floatingPickerBackgroundColor: freezed == floatingPickerBackgroundColor ? _self.floatingPickerBackgroundColor : floatingPickerBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,fullEmojiPickerBackgroundColor: freezed == fullEmojiPickerBackgroundColor ? _self.fullEmojiPickerBackgroundColor : fullEmojiPickerBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,audioPlayButtonColor: freezed == audioPlayButtonColor ? _self.audioPlayButtonColor : audioPlayButtonColor // ignore: cast_nullable_to_non_nullable
as Color?,audioPlayIconColor: freezed == audioPlayIconColor ? _self.audioPlayIconColor : audioPlayIconColor // ignore: cast_nullable_to_non_nullable
as Color?,audioSeekBarColor: freezed == audioSeekBarColor ? _self.audioSeekBarColor : audioSeekBarColor // ignore: cast_nullable_to_non_nullable
as Color?,audioSeekBarActiveColor: freezed == audioSeekBarActiveColor ? _self.audioSeekBarActiveColor : audioSeekBarActiveColor // ignore: cast_nullable_to_non_nullable
as Color?,audioDurationTextStyle: freezed == audioDurationTextStyle ? _self.audioDurationTextStyle : audioDurationTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,audioSpeedButtonColor: freezed == audioSpeedButtonColor ? _self.audioSpeedButtonColor : audioSpeedButtonColor // ignore: cast_nullable_to_non_nullable
as Color?,audioSpeedTextStyle: freezed == audioSpeedTextStyle ? _self.audioSpeedTextStyle : audioSpeedTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,audioListenedIconColor: freezed == audioListenedIconColor ? _self.audioListenedIconColor : audioListenedIconColor // ignore: cast_nullable_to_non_nullable
as Color?,audioUnlistenedIconColor: freezed == audioUnlistenedIconColor ? _self.audioUnlistenedIconColor : audioUnlistenedIconColor // ignore: cast_nullable_to_non_nullable
as Color?,voiceRecorderActiveColor: freezed == voiceRecorderActiveColor ? _self.voiceRecorderActiveColor : voiceRecorderActiveColor // ignore: cast_nullable_to_non_nullable
as Color?,voiceRecorderTimerStyle: freezed == voiceRecorderTimerStyle ? _self.voiceRecorderTimerStyle : voiceRecorderTimerStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,voiceRecorderOverlayColor: freezed == voiceRecorderOverlayColor ? _self.voiceRecorderOverlayColor : voiceRecorderOverlayColor // ignore: cast_nullable_to_non_nullable
as Color?,voiceRecorderCancelColor: freezed == voiceRecorderCancelColor ? _self.voiceRecorderCancelColor : voiceRecorderCancelColor // ignore: cast_nullable_to_non_nullable
as Color?,voiceRecorderLockIconColor: freezed == voiceRecorderLockIconColor ? _self.voiceRecorderLockIconColor : voiceRecorderLockIconColor // ignore: cast_nullable_to_non_nullable
as Color?,voiceRecorderHintStyle: freezed == voiceRecorderHintStyle ? _self.voiceRecorderHintStyle : voiceRecorderHintStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,waveformActiveColor: freezed == waveformActiveColor ? _self.waveformActiveColor : waveformActiveColor // ignore: cast_nullable_to_non_nullable
as Color?,waveformInactiveColor: freezed == waveformInactiveColor ? _self.waveformInactiveColor : waveformInactiveColor // ignore: cast_nullable_to_non_nullable
as Color?,waveformRecordingColor: freezed == waveformRecordingColor ? _self.waveformRecordingColor : waveformRecordingColor // ignore: cast_nullable_to_non_nullable
as Color?,imageBorderRadius: freezed == imageBorderRadius ? _self.imageBorderRadius : imageBorderRadius // ignore: cast_nullable_to_non_nullable
as BorderRadius?,imageMaxHeight: freezed == imageMaxHeight ? _self.imageMaxHeight : imageMaxHeight // ignore: cast_nullable_to_non_nullable
as double?,imageMaxWidth: freezed == imageMaxWidth ? _self.imageMaxWidth : imageMaxWidth // ignore: cast_nullable_to_non_nullable
as double?,imageCaptionStyle: freezed == imageCaptionStyle ? _self.imageCaptionStyle : imageCaptionStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,videoPlayIconColor: freezed == videoPlayIconColor ? _self.videoPlayIconColor : videoPlayIconColor // ignore: cast_nullable_to_non_nullable
as Color?,videoPlayIconBackgroundColor: freezed == videoPlayIconBackgroundColor ? _self.videoPlayIconBackgroundColor : videoPlayIconBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,videoPlaceholderIconColor: freezed == videoPlaceholderIconColor ? _self.videoPlaceholderIconColor : videoPlaceholderIconColor // ignore: cast_nullable_to_non_nullable
as Color?,videoHeight: freezed == videoHeight ? _self.videoHeight : videoHeight // ignore: cast_nullable_to_non_nullable
as double?,videoPlaceholderColor: freezed == videoPlaceholderColor ? _self.videoPlaceholderColor : videoPlaceholderColor // ignore: cast_nullable_to_non_nullable
as Color?,videoBorderRadius: freezed == videoBorderRadius ? _self.videoBorderRadius : videoBorderRadius // ignore: cast_nullable_to_non_nullable
as BorderRadius?,fileIconColor: freezed == fileIconColor ? _self.fileIconColor : fileIconColor // ignore: cast_nullable_to_non_nullable
as Color?,fileNameTextStyle: freezed == fileNameTextStyle ? _self.fileNameTextStyle : fileNameTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,fileSizeTextStyle: freezed == fileSizeTextStyle ? _self.fileSizeTextStyle : fileSizeTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,linkPreviewBackgroundColor: freezed == linkPreviewBackgroundColor ? _self.linkPreviewBackgroundColor : linkPreviewBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,linkPreviewTitleStyle: freezed == linkPreviewTitleStyle ? _self.linkPreviewTitleStyle : linkPreviewTitleStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,linkPreviewDescriptionStyle: freezed == linkPreviewDescriptionStyle ? _self.linkPreviewDescriptionStyle : linkPreviewDescriptionStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,linkPreviewBorderRadius: freezed == linkPreviewBorderRadius ? _self.linkPreviewBorderRadius : linkPreviewBorderRadius // ignore: cast_nullable_to_non_nullable
as BorderRadius?,linkPreviewDomainStyle: freezed == linkPreviewDomainStyle ? _self.linkPreviewDomainStyle : linkPreviewDomainStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,linkPreviewBorderColor: freezed == linkPreviewBorderColor ? _self.linkPreviewBorderColor : linkPreviewBorderColor // ignore: cast_nullable_to_non_nullable
as Color?,backgroundColor: freezed == backgroundColor ? _self.backgroundColor : backgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,backgroundImage: freezed == backgroundImage ? _self.backgroundImage : backgroundImage // ignore: cast_nullable_to_non_nullable
as ImageProvider?,backgroundImageRepeat: null == backgroundImageRepeat ? _self.backgroundImageRepeat : backgroundImageRepeat // ignore: cast_nullable_to_non_nullable
as ImageRepeat,backgroundImageOpacity: null == backgroundImageOpacity ? _self.backgroundImageOpacity : backgroundImageOpacity // ignore: cast_nullable_to_non_nullable
as double,backgroundImageColorFilter: freezed == backgroundImageColorFilter ? _self.backgroundImageColorFilter : backgroundImageColorFilter // ignore: cast_nullable_to_non_nullable
as ColorFilter?,avatarBackgroundColor: freezed == avatarBackgroundColor ? _self.avatarBackgroundColor : avatarBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,avatarInitialsTextStyle: freezed == avatarInitialsTextStyle ? _self.avatarInitialsTextStyle : avatarInitialsTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,avatarOnlineColor: freezed == avatarOnlineColor ? _self.avatarOnlineColor : avatarOnlineColor // ignore: cast_nullable_to_non_nullable
as Color?,avatarOfflineColor: freezed == avatarOfflineColor ? _self.avatarOfflineColor : avatarOfflineColor // ignore: cast_nullable_to_non_nullable
as Color?,avatarOnlineBorderColor: freezed == avatarOnlineBorderColor ? _self.avatarOnlineBorderColor : avatarOnlineBorderColor // ignore: cast_nullable_to_non_nullable
as Color?,connectionBannerColor: freezed == connectionBannerColor ? _self.connectionBannerColor : connectionBannerColor // ignore: cast_nullable_to_non_nullable
as Color?,connectionBannerTextStyle: freezed == connectionBannerTextStyle ? _self.connectionBannerTextStyle : connectionBannerTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,connectionBannerErrorIconColor: freezed == connectionBannerErrorIconColor ? _self.connectionBannerErrorIconColor : connectionBannerErrorIconColor // ignore: cast_nullable_to_non_nullable
as Color?,emptyStateIconColor: freezed == emptyStateIconColor ? _self.emptyStateIconColor : emptyStateIconColor // ignore: cast_nullable_to_non_nullable
as Color?,emptyStateTitleStyle: freezed == emptyStateTitleStyle ? _self.emptyStateTitleStyle : emptyStateTitleStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,emptyStateSubtitleStyle: freezed == emptyStateSubtitleStyle ? _self.emptyStateSubtitleStyle : emptyStateSubtitleStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,contextMenuHandleColor: freezed == contextMenuHandleColor ? _self.contextMenuHandleColor : contextMenuHandleColor // ignore: cast_nullable_to_non_nullable
as Color?,contextMenuDestructiveColor: freezed == contextMenuDestructiveColor ? _self.contextMenuDestructiveColor : contextMenuDestructiveColor // ignore: cast_nullable_to_non_nullable
as Color?,scrollToBottomButtonColor: freezed == scrollToBottomButtonColor ? _self.scrollToBottomButtonColor : scrollToBottomButtonColor // ignore: cast_nullable_to_non_nullable
as Color?,scrollToBottomIconColor: freezed == scrollToBottomIconColor ? _self.scrollToBottomIconColor : scrollToBottomIconColor // ignore: cast_nullable_to_non_nullable
as Color?,attachmentPickerCircleColor: freezed == attachmentPickerCircleColor ? _self.attachmentPickerCircleColor : attachmentPickerCircleColor // ignore: cast_nullable_to_non_nullable
as Color?,attachmentPickerIconColor: freezed == attachmentPickerIconColor ? _self.attachmentPickerIconColor : attachmentPickerIconColor // ignore: cast_nullable_to_non_nullable
as Color?,attachmentPickerLabelStyle: freezed == attachmentPickerLabelStyle ? _self.attachmentPickerLabelStyle : attachmentPickerLabelStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,imageViewerBackgroundColor: freezed == imageViewerBackgroundColor ? _self.imageViewerBackgroundColor : imageViewerBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,imageViewerIconColor: freezed == imageViewerIconColor ? _self.imageViewerIconColor : imageViewerIconColor // ignore: cast_nullable_to_non_nullable
as Color?,presenceAvailableColor: freezed == presenceAvailableColor ? _self.presenceAvailableColor : presenceAvailableColor // ignore: cast_nullable_to_non_nullable
as Color?,presenceAwayColor: freezed == presenceAwayColor ? _self.presenceAwayColor : presenceAwayColor // ignore: cast_nullable_to_non_nullable
as Color?,presenceBusyColor: freezed == presenceBusyColor ? _self.presenceBusyColor : presenceBusyColor // ignore: cast_nullable_to_non_nullable
as Color?,presenceDndColor: freezed == presenceDndColor ? _self.presenceDndColor : presenceDndColor // ignore: cast_nullable_to_non_nullable
as Color?,galleryAppBarBackgroundColor: freezed == galleryAppBarBackgroundColor ? _self.galleryAppBarBackgroundColor : galleryAppBarBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,galleryAppBarForegroundColor: freezed == galleryAppBarForegroundColor ? _self.galleryAppBarForegroundColor : galleryAppBarForegroundColor // ignore: cast_nullable_to_non_nullable
as Color?,galleryTabIndicatorColor: freezed == galleryTabIndicatorColor ? _self.galleryTabIndicatorColor : galleryTabIndicatorColor // ignore: cast_nullable_to_non_nullable
as Color?,
  ));
}

/// Create a copy of ChatTheme
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ChatBubbleThemeCopyWith<$Res> get bubble {
  
  return $ChatBubbleThemeCopyWith<$Res>(_self.bubble, (value) {
    return _then(_self.copyWith(bubble: value));
  });
}/// Create a copy of ChatTheme
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ChatInputThemeCopyWith<$Res> get input {
  
  return $ChatInputThemeCopyWith<$Res>(_self.input, (value) {
    return _then(_self.copyWith(input: value));
  });
}/// Create a copy of ChatTheme
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ChatRoomListThemeCopyWith<$Res> get roomList {
  
  return $ChatRoomListThemeCopyWith<$Res>(_self.roomList, (value) {
    return _then(_self.copyWith(roomList: value));
  });
}/// Create a copy of ChatTheme
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ChatMarkdownThemeCopyWith<$Res> get markdown {
  
  return $ChatMarkdownThemeCopyWith<$Res>(_self.markdown, (value) {
    return _then(_self.copyWith(markdown: value));
  });
}
}

// dart format on
