import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../controller/voice_recording_controller.dart';

part 'input_theme.freezed.dart';

/// Theme for the message composer — text field, send / attach / voice /
/// camera buttons, editing banner and reply preview. Captures every visual
/// surface that lives between the conversation and the keyboard.
///
/// Pass an instance to [ChatTheme] to override the matching flat fields;
/// pass nothing and the existing flat fields keep working unchanged
/// (back-compat).
@freezed
abstract class ChatInputTheme with _$ChatInputTheme {
  const factory ChatInputTheme({
    /// Background of the entire composer container (the bar that hosts the
    /// text field + side buttons).
    Color? backgroundColor,

    /// Fill colour of the text-field surface itself, inset inside the
    /// composer container.
    Color? fillColor,

    /// Default text style typed into the composer.
    TextStyle? textStyle,

    /// Style for the placeholder text shown when the composer is empty.
    TextStyle? hintStyle,

    /// Border of the composer text-field. When null, no border is drawn.
    Color? borderColor,

    /// Width of [borderColor]. Defaults to 1 px when [borderColor] is set
    /// and this is null.
    double? borderWidth,

    /// Rounded-corner radius of the composer text-field. Defaults to a
    /// pill shape (24) when null.
    BorderRadius? borderRadius,

    /// Optional shadow rendered behind the composer container.
    List<BoxShadow>? containerShadow,

    /// Background of the round send button.
    Color? sendButtonColor,

    /// Icon shown inside the send button. Falls back to a paper-plane.
    IconData? sendButtonIcon,

    /// Tint of [sendButtonIcon].
    Color? sendButtonIconColor,

    /// Background of the send button when no text is typed.
    Color? sendButtonDisabledColor,

    /// Icon shown on the attachment shortcut.
    IconData? attachButtonIcon,

    /// Tint of the attachment shortcut.
    Color? attachButtonColor,

    /// Icon shown on the voice (microphone) shortcut.
    IconData? voiceButtonIcon,

    /// Tint of [voiceButtonIcon] while idle.
    Color? voiceButtonColor,

    /// Tint of the voice icon when the composer is empty (idle state),
    /// overriding [voiceButtonColor]. Useful for theme tokens that want a
    /// brand colour only when recording is available.
    Color? voiceButtonIdleIconColor,

    /// Icon shown on the camera shortcut.
    IconData? cameraButtonIcon,

    /// Tint of the camera shortcut.
    Color? cameraButtonColor,

    /// Custom builder for the attach button — replaces icon + tint.
    Widget Function(BuildContext context)? attachIconBuilder,

    /// Custom builder for the camera button.
    Widget Function(BuildContext context)? cameraIconBuilder,

    /// Custom builder for the voice button.
    Widget Function(BuildContext context)? voiceIconBuilder,

    /// Builder for the send button. Receives whether the composer has text.
    Widget Function(BuildContext context, bool hasText)? sendIconBuilder,

    /// Custom layout while voice recording is active (replaces the default
    /// red-mic row).
    Widget Function(
      BuildContext context,
      VoiceRecordingController controller,
      VoidCallback onSend,
    )?
    recordingComposerBuilder,

    /// Builder for the floating "slide up to lock" hint.
    Widget Function(BuildContext context)? lockHintBuilder,

    /// Background of the "Editing this message" banner above the composer.
    Color? editingBackgroundColor,

    /// Border / accent colour of the editing banner.
    Color? editingBorderColor,

    /// Style for the "Editing" label.
    TextStyle? editingLabelStyle,

    /// Style for the preview of the message being edited.
    TextStyle? editingPreviewStyle,

    /// Background of the "Replying to" preview above the composer.
    Color? replyPreviewBackgroundColor,

    /// Vertical accent bar shown on the reply preview.
    Color? replyPreviewBarColor,

    /// Style for the sender name inside the reply preview.
    TextStyle? replyPreviewSenderStyle,

    /// Style for the message snippet inside the reply preview.
    TextStyle? replyPreviewTextStyle,
  }) = _ChatInputTheme;
}
