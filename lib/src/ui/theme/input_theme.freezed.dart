// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'input_theme.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ChatInputTheme {

/// Background of the entire composer container (the bar that hosts the
/// text field + side buttons).
 Color? get backgroundColor;/// Fill colour of the text-field surface itself, inset inside the
/// composer container.
 Color? get fillColor;/// Default text style typed into the composer.
 TextStyle? get textStyle;/// Style for the placeholder text shown when the composer is empty.
 TextStyle? get hintStyle;/// Border of the composer text-field. When null, no border is drawn.
 Color? get borderColor;/// Width of [borderColor]. Defaults to 1 px when [borderColor] is set
/// and this is null.
 double? get borderWidth;/// Rounded-corner radius of the composer text-field. Defaults to a
/// pill shape (24) when null.
 BorderRadius? get borderRadius;/// Optional shadow rendered behind the composer container.
 List<BoxShadow>? get containerShadow;/// Background of the round send button.
 Color? get sendButtonColor;/// Icon shown inside the send button. Falls back to a paper-plane.
 IconData? get sendButtonIcon;/// Tint of [sendButtonIcon].
 Color? get sendButtonIconColor;/// Background of the send button when no text is typed.
 Color? get sendButtonDisabledColor;/// Icon shown on the attachment shortcut.
 IconData? get attachButtonIcon;/// Tint of the attachment shortcut.
 Color? get attachButtonColor;/// Icon shown on the voice (microphone) shortcut.
 IconData? get voiceButtonIcon;/// Tint of [voiceButtonIcon] while idle.
 Color? get voiceButtonColor;/// Tint of the voice icon when the composer is empty (idle state),
/// overriding [voiceButtonColor]. Useful for theme tokens that want a
/// brand colour only when recording is available.
 Color? get voiceButtonIdleIconColor;/// Icon shown on the camera shortcut.
 IconData? get cameraButtonIcon;/// Tint of the camera shortcut.
 Color? get cameraButtonColor;/// Custom builder for the attach button — replaces icon + tint.
 Widget Function(BuildContext context)? get attachIconBuilder;/// Custom builder for the camera button.
 Widget Function(BuildContext context)? get cameraIconBuilder;/// Custom builder for the voice button.
 Widget Function(BuildContext context)? get voiceIconBuilder;/// Builder for the send button. Receives whether the composer has text.
 Widget Function(BuildContext context, bool hasText)? get sendIconBuilder;/// Custom layout while voice recording is active (replaces the default
/// red-mic row).
 Widget Function(BuildContext context, VoiceRecordingController controller, VoidCallback onSend)? get recordingComposerBuilder;/// Builder for the floating "slide up to lock" hint.
 Widget Function(BuildContext context)? get lockHintBuilder;/// Background of the "Editing this message" banner above the composer.
 Color? get editingBackgroundColor;/// Border / accent colour of the editing banner.
 Color? get editingBorderColor;/// Style for the "Editing" label.
 TextStyle? get editingLabelStyle;/// Style for the preview of the message being edited.
 TextStyle? get editingPreviewStyle;/// Background of the "Replying to" preview above the composer.
 Color? get replyPreviewBackgroundColor;/// Vertical accent bar shown on the reply preview.
 Color? get replyPreviewBarColor;/// Style for the sender name inside the reply preview.
 TextStyle? get replyPreviewSenderStyle;/// Style for the message snippet inside the reply preview.
 TextStyle? get replyPreviewTextStyle;
/// Create a copy of ChatInputTheme
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatInputThemeCopyWith<ChatInputTheme> get copyWith => _$ChatInputThemeCopyWithImpl<ChatInputTheme>(this as ChatInputTheme, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatInputTheme&&(identical(other.backgroundColor, backgroundColor) || other.backgroundColor == backgroundColor)&&(identical(other.fillColor, fillColor) || other.fillColor == fillColor)&&(identical(other.textStyle, textStyle) || other.textStyle == textStyle)&&(identical(other.hintStyle, hintStyle) || other.hintStyle == hintStyle)&&(identical(other.borderColor, borderColor) || other.borderColor == borderColor)&&(identical(other.borderWidth, borderWidth) || other.borderWidth == borderWidth)&&(identical(other.borderRadius, borderRadius) || other.borderRadius == borderRadius)&&const DeepCollectionEquality().equals(other.containerShadow, containerShadow)&&(identical(other.sendButtonColor, sendButtonColor) || other.sendButtonColor == sendButtonColor)&&(identical(other.sendButtonIcon, sendButtonIcon) || other.sendButtonIcon == sendButtonIcon)&&(identical(other.sendButtonIconColor, sendButtonIconColor) || other.sendButtonIconColor == sendButtonIconColor)&&(identical(other.sendButtonDisabledColor, sendButtonDisabledColor) || other.sendButtonDisabledColor == sendButtonDisabledColor)&&(identical(other.attachButtonIcon, attachButtonIcon) || other.attachButtonIcon == attachButtonIcon)&&(identical(other.attachButtonColor, attachButtonColor) || other.attachButtonColor == attachButtonColor)&&(identical(other.voiceButtonIcon, voiceButtonIcon) || other.voiceButtonIcon == voiceButtonIcon)&&(identical(other.voiceButtonColor, voiceButtonColor) || other.voiceButtonColor == voiceButtonColor)&&(identical(other.voiceButtonIdleIconColor, voiceButtonIdleIconColor) || other.voiceButtonIdleIconColor == voiceButtonIdleIconColor)&&(identical(other.cameraButtonIcon, cameraButtonIcon) || other.cameraButtonIcon == cameraButtonIcon)&&(identical(other.cameraButtonColor, cameraButtonColor) || other.cameraButtonColor == cameraButtonColor)&&(identical(other.attachIconBuilder, attachIconBuilder) || other.attachIconBuilder == attachIconBuilder)&&(identical(other.cameraIconBuilder, cameraIconBuilder) || other.cameraIconBuilder == cameraIconBuilder)&&(identical(other.voiceIconBuilder, voiceIconBuilder) || other.voiceIconBuilder == voiceIconBuilder)&&(identical(other.sendIconBuilder, sendIconBuilder) || other.sendIconBuilder == sendIconBuilder)&&(identical(other.recordingComposerBuilder, recordingComposerBuilder) || other.recordingComposerBuilder == recordingComposerBuilder)&&(identical(other.lockHintBuilder, lockHintBuilder) || other.lockHintBuilder == lockHintBuilder)&&(identical(other.editingBackgroundColor, editingBackgroundColor) || other.editingBackgroundColor == editingBackgroundColor)&&(identical(other.editingBorderColor, editingBorderColor) || other.editingBorderColor == editingBorderColor)&&(identical(other.editingLabelStyle, editingLabelStyle) || other.editingLabelStyle == editingLabelStyle)&&(identical(other.editingPreviewStyle, editingPreviewStyle) || other.editingPreviewStyle == editingPreviewStyle)&&(identical(other.replyPreviewBackgroundColor, replyPreviewBackgroundColor) || other.replyPreviewBackgroundColor == replyPreviewBackgroundColor)&&(identical(other.replyPreviewBarColor, replyPreviewBarColor) || other.replyPreviewBarColor == replyPreviewBarColor)&&(identical(other.replyPreviewSenderStyle, replyPreviewSenderStyle) || other.replyPreviewSenderStyle == replyPreviewSenderStyle)&&(identical(other.replyPreviewTextStyle, replyPreviewTextStyle) || other.replyPreviewTextStyle == replyPreviewTextStyle));
}


@override
int get hashCode => Object.hashAll([runtimeType,backgroundColor,fillColor,textStyle,hintStyle,borderColor,borderWidth,borderRadius,const DeepCollectionEquality().hash(containerShadow),sendButtonColor,sendButtonIcon,sendButtonIconColor,sendButtonDisabledColor,attachButtonIcon,attachButtonColor,voiceButtonIcon,voiceButtonColor,voiceButtonIdleIconColor,cameraButtonIcon,cameraButtonColor,attachIconBuilder,cameraIconBuilder,voiceIconBuilder,sendIconBuilder,recordingComposerBuilder,lockHintBuilder,editingBackgroundColor,editingBorderColor,editingLabelStyle,editingPreviewStyle,replyPreviewBackgroundColor,replyPreviewBarColor,replyPreviewSenderStyle,replyPreviewTextStyle]);

@override
String toString() {
  return 'ChatInputTheme(backgroundColor: $backgroundColor, fillColor: $fillColor, textStyle: $textStyle, hintStyle: $hintStyle, borderColor: $borderColor, borderWidth: $borderWidth, borderRadius: $borderRadius, containerShadow: $containerShadow, sendButtonColor: $sendButtonColor, sendButtonIcon: $sendButtonIcon, sendButtonIconColor: $sendButtonIconColor, sendButtonDisabledColor: $sendButtonDisabledColor, attachButtonIcon: $attachButtonIcon, attachButtonColor: $attachButtonColor, voiceButtonIcon: $voiceButtonIcon, voiceButtonColor: $voiceButtonColor, voiceButtonIdleIconColor: $voiceButtonIdleIconColor, cameraButtonIcon: $cameraButtonIcon, cameraButtonColor: $cameraButtonColor, attachIconBuilder: $attachIconBuilder, cameraIconBuilder: $cameraIconBuilder, voiceIconBuilder: $voiceIconBuilder, sendIconBuilder: $sendIconBuilder, recordingComposerBuilder: $recordingComposerBuilder, lockHintBuilder: $lockHintBuilder, editingBackgroundColor: $editingBackgroundColor, editingBorderColor: $editingBorderColor, editingLabelStyle: $editingLabelStyle, editingPreviewStyle: $editingPreviewStyle, replyPreviewBackgroundColor: $replyPreviewBackgroundColor, replyPreviewBarColor: $replyPreviewBarColor, replyPreviewSenderStyle: $replyPreviewSenderStyle, replyPreviewTextStyle: $replyPreviewTextStyle)';
}


}

/// @nodoc
abstract mixin class $ChatInputThemeCopyWith<$Res>  {
  factory $ChatInputThemeCopyWith(ChatInputTheme value, $Res Function(ChatInputTheme) _then) = _$ChatInputThemeCopyWithImpl;
@useResult
$Res call({
 Color? backgroundColor, Color? fillColor, TextStyle? textStyle, TextStyle? hintStyle, Color? borderColor, double? borderWidth, BorderRadius? borderRadius, List<BoxShadow>? containerShadow, Color? sendButtonColor, IconData? sendButtonIcon, Color? sendButtonIconColor, Color? sendButtonDisabledColor, IconData? attachButtonIcon, Color? attachButtonColor, IconData? voiceButtonIcon, Color? voiceButtonColor, Color? voiceButtonIdleIconColor, IconData? cameraButtonIcon, Color? cameraButtonColor, Widget Function(BuildContext context)? attachIconBuilder, Widget Function(BuildContext context)? cameraIconBuilder, Widget Function(BuildContext context)? voiceIconBuilder, Widget Function(BuildContext context, bool hasText)? sendIconBuilder, Widget Function(BuildContext context, VoiceRecordingController controller, VoidCallback onSend)? recordingComposerBuilder, Widget Function(BuildContext context)? lockHintBuilder, Color? editingBackgroundColor, Color? editingBorderColor, TextStyle? editingLabelStyle, TextStyle? editingPreviewStyle, Color? replyPreviewBackgroundColor, Color? replyPreviewBarColor, TextStyle? replyPreviewSenderStyle, TextStyle? replyPreviewTextStyle
});




}
/// @nodoc
class _$ChatInputThemeCopyWithImpl<$Res>
    implements $ChatInputThemeCopyWith<$Res> {
  _$ChatInputThemeCopyWithImpl(this._self, this._then);

  final ChatInputTheme _self;
  final $Res Function(ChatInputTheme) _then;

/// Create a copy of ChatInputTheme
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? backgroundColor = freezed,Object? fillColor = freezed,Object? textStyle = freezed,Object? hintStyle = freezed,Object? borderColor = freezed,Object? borderWidth = freezed,Object? borderRadius = freezed,Object? containerShadow = freezed,Object? sendButtonColor = freezed,Object? sendButtonIcon = freezed,Object? sendButtonIconColor = freezed,Object? sendButtonDisabledColor = freezed,Object? attachButtonIcon = freezed,Object? attachButtonColor = freezed,Object? voiceButtonIcon = freezed,Object? voiceButtonColor = freezed,Object? voiceButtonIdleIconColor = freezed,Object? cameraButtonIcon = freezed,Object? cameraButtonColor = freezed,Object? attachIconBuilder = freezed,Object? cameraIconBuilder = freezed,Object? voiceIconBuilder = freezed,Object? sendIconBuilder = freezed,Object? recordingComposerBuilder = freezed,Object? lockHintBuilder = freezed,Object? editingBackgroundColor = freezed,Object? editingBorderColor = freezed,Object? editingLabelStyle = freezed,Object? editingPreviewStyle = freezed,Object? replyPreviewBackgroundColor = freezed,Object? replyPreviewBarColor = freezed,Object? replyPreviewSenderStyle = freezed,Object? replyPreviewTextStyle = freezed,}) {
  return _then(_self.copyWith(
backgroundColor: freezed == backgroundColor ? _self.backgroundColor : backgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,fillColor: freezed == fillColor ? _self.fillColor : fillColor // ignore: cast_nullable_to_non_nullable
as Color?,textStyle: freezed == textStyle ? _self.textStyle : textStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,hintStyle: freezed == hintStyle ? _self.hintStyle : hintStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,borderColor: freezed == borderColor ? _self.borderColor : borderColor // ignore: cast_nullable_to_non_nullable
as Color?,borderWidth: freezed == borderWidth ? _self.borderWidth : borderWidth // ignore: cast_nullable_to_non_nullable
as double?,borderRadius: freezed == borderRadius ? _self.borderRadius : borderRadius // ignore: cast_nullable_to_non_nullable
as BorderRadius?,containerShadow: freezed == containerShadow ? _self.containerShadow : containerShadow // ignore: cast_nullable_to_non_nullable
as List<BoxShadow>?,sendButtonColor: freezed == sendButtonColor ? _self.sendButtonColor : sendButtonColor // ignore: cast_nullable_to_non_nullable
as Color?,sendButtonIcon: freezed == sendButtonIcon ? _self.sendButtonIcon : sendButtonIcon // ignore: cast_nullable_to_non_nullable
as IconData?,sendButtonIconColor: freezed == sendButtonIconColor ? _self.sendButtonIconColor : sendButtonIconColor // ignore: cast_nullable_to_non_nullable
as Color?,sendButtonDisabledColor: freezed == sendButtonDisabledColor ? _self.sendButtonDisabledColor : sendButtonDisabledColor // ignore: cast_nullable_to_non_nullable
as Color?,attachButtonIcon: freezed == attachButtonIcon ? _self.attachButtonIcon : attachButtonIcon // ignore: cast_nullable_to_non_nullable
as IconData?,attachButtonColor: freezed == attachButtonColor ? _self.attachButtonColor : attachButtonColor // ignore: cast_nullable_to_non_nullable
as Color?,voiceButtonIcon: freezed == voiceButtonIcon ? _self.voiceButtonIcon : voiceButtonIcon // ignore: cast_nullable_to_non_nullable
as IconData?,voiceButtonColor: freezed == voiceButtonColor ? _self.voiceButtonColor : voiceButtonColor // ignore: cast_nullable_to_non_nullable
as Color?,voiceButtonIdleIconColor: freezed == voiceButtonIdleIconColor ? _self.voiceButtonIdleIconColor : voiceButtonIdleIconColor // ignore: cast_nullable_to_non_nullable
as Color?,cameraButtonIcon: freezed == cameraButtonIcon ? _self.cameraButtonIcon : cameraButtonIcon // ignore: cast_nullable_to_non_nullable
as IconData?,cameraButtonColor: freezed == cameraButtonColor ? _self.cameraButtonColor : cameraButtonColor // ignore: cast_nullable_to_non_nullable
as Color?,attachIconBuilder: freezed == attachIconBuilder ? _self.attachIconBuilder : attachIconBuilder // ignore: cast_nullable_to_non_nullable
as Widget Function(BuildContext context)?,cameraIconBuilder: freezed == cameraIconBuilder ? _self.cameraIconBuilder : cameraIconBuilder // ignore: cast_nullable_to_non_nullable
as Widget Function(BuildContext context)?,voiceIconBuilder: freezed == voiceIconBuilder ? _self.voiceIconBuilder : voiceIconBuilder // ignore: cast_nullable_to_non_nullable
as Widget Function(BuildContext context)?,sendIconBuilder: freezed == sendIconBuilder ? _self.sendIconBuilder : sendIconBuilder // ignore: cast_nullable_to_non_nullable
as Widget Function(BuildContext context, bool hasText)?,recordingComposerBuilder: freezed == recordingComposerBuilder ? _self.recordingComposerBuilder : recordingComposerBuilder // ignore: cast_nullable_to_non_nullable
as Widget Function(BuildContext context, VoiceRecordingController controller, VoidCallback onSend)?,lockHintBuilder: freezed == lockHintBuilder ? _self.lockHintBuilder : lockHintBuilder // ignore: cast_nullable_to_non_nullable
as Widget Function(BuildContext context)?,editingBackgroundColor: freezed == editingBackgroundColor ? _self.editingBackgroundColor : editingBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,editingBorderColor: freezed == editingBorderColor ? _self.editingBorderColor : editingBorderColor // ignore: cast_nullable_to_non_nullable
as Color?,editingLabelStyle: freezed == editingLabelStyle ? _self.editingLabelStyle : editingLabelStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,editingPreviewStyle: freezed == editingPreviewStyle ? _self.editingPreviewStyle : editingPreviewStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,replyPreviewBackgroundColor: freezed == replyPreviewBackgroundColor ? _self.replyPreviewBackgroundColor : replyPreviewBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,replyPreviewBarColor: freezed == replyPreviewBarColor ? _self.replyPreviewBarColor : replyPreviewBarColor // ignore: cast_nullable_to_non_nullable
as Color?,replyPreviewSenderStyle: freezed == replyPreviewSenderStyle ? _self.replyPreviewSenderStyle : replyPreviewSenderStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,replyPreviewTextStyle: freezed == replyPreviewTextStyle ? _self.replyPreviewTextStyle : replyPreviewTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,
  ));
}

}


/// Adds pattern-matching-related methods to [ChatInputTheme].
extension ChatInputThemePatterns on ChatInputTheme {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatInputTheme value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatInputTheme() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatInputTheme value)  $default,){
final _that = this;
switch (_that) {
case _ChatInputTheme():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatInputTheme value)?  $default,){
final _that = this;
switch (_that) {
case _ChatInputTheme() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Color? backgroundColor,  Color? fillColor,  TextStyle? textStyle,  TextStyle? hintStyle,  Color? borderColor,  double? borderWidth,  BorderRadius? borderRadius,  List<BoxShadow>? containerShadow,  Color? sendButtonColor,  IconData? sendButtonIcon,  Color? sendButtonIconColor,  Color? sendButtonDisabledColor,  IconData? attachButtonIcon,  Color? attachButtonColor,  IconData? voiceButtonIcon,  Color? voiceButtonColor,  Color? voiceButtonIdleIconColor,  IconData? cameraButtonIcon,  Color? cameraButtonColor,  Widget Function(BuildContext context)? attachIconBuilder,  Widget Function(BuildContext context)? cameraIconBuilder,  Widget Function(BuildContext context)? voiceIconBuilder,  Widget Function(BuildContext context, bool hasText)? sendIconBuilder,  Widget Function(BuildContext context, VoiceRecordingController controller, VoidCallback onSend)? recordingComposerBuilder,  Widget Function(BuildContext context)? lockHintBuilder,  Color? editingBackgroundColor,  Color? editingBorderColor,  TextStyle? editingLabelStyle,  TextStyle? editingPreviewStyle,  Color? replyPreviewBackgroundColor,  Color? replyPreviewBarColor,  TextStyle? replyPreviewSenderStyle,  TextStyle? replyPreviewTextStyle)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatInputTheme() when $default != null:
return $default(_that.backgroundColor,_that.fillColor,_that.textStyle,_that.hintStyle,_that.borderColor,_that.borderWidth,_that.borderRadius,_that.containerShadow,_that.sendButtonColor,_that.sendButtonIcon,_that.sendButtonIconColor,_that.sendButtonDisabledColor,_that.attachButtonIcon,_that.attachButtonColor,_that.voiceButtonIcon,_that.voiceButtonColor,_that.voiceButtonIdleIconColor,_that.cameraButtonIcon,_that.cameraButtonColor,_that.attachIconBuilder,_that.cameraIconBuilder,_that.voiceIconBuilder,_that.sendIconBuilder,_that.recordingComposerBuilder,_that.lockHintBuilder,_that.editingBackgroundColor,_that.editingBorderColor,_that.editingLabelStyle,_that.editingPreviewStyle,_that.replyPreviewBackgroundColor,_that.replyPreviewBarColor,_that.replyPreviewSenderStyle,_that.replyPreviewTextStyle);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Color? backgroundColor,  Color? fillColor,  TextStyle? textStyle,  TextStyle? hintStyle,  Color? borderColor,  double? borderWidth,  BorderRadius? borderRadius,  List<BoxShadow>? containerShadow,  Color? sendButtonColor,  IconData? sendButtonIcon,  Color? sendButtonIconColor,  Color? sendButtonDisabledColor,  IconData? attachButtonIcon,  Color? attachButtonColor,  IconData? voiceButtonIcon,  Color? voiceButtonColor,  Color? voiceButtonIdleIconColor,  IconData? cameraButtonIcon,  Color? cameraButtonColor,  Widget Function(BuildContext context)? attachIconBuilder,  Widget Function(BuildContext context)? cameraIconBuilder,  Widget Function(BuildContext context)? voiceIconBuilder,  Widget Function(BuildContext context, bool hasText)? sendIconBuilder,  Widget Function(BuildContext context, VoiceRecordingController controller, VoidCallback onSend)? recordingComposerBuilder,  Widget Function(BuildContext context)? lockHintBuilder,  Color? editingBackgroundColor,  Color? editingBorderColor,  TextStyle? editingLabelStyle,  TextStyle? editingPreviewStyle,  Color? replyPreviewBackgroundColor,  Color? replyPreviewBarColor,  TextStyle? replyPreviewSenderStyle,  TextStyle? replyPreviewTextStyle)  $default,) {final _that = this;
switch (_that) {
case _ChatInputTheme():
return $default(_that.backgroundColor,_that.fillColor,_that.textStyle,_that.hintStyle,_that.borderColor,_that.borderWidth,_that.borderRadius,_that.containerShadow,_that.sendButtonColor,_that.sendButtonIcon,_that.sendButtonIconColor,_that.sendButtonDisabledColor,_that.attachButtonIcon,_that.attachButtonColor,_that.voiceButtonIcon,_that.voiceButtonColor,_that.voiceButtonIdleIconColor,_that.cameraButtonIcon,_that.cameraButtonColor,_that.attachIconBuilder,_that.cameraIconBuilder,_that.voiceIconBuilder,_that.sendIconBuilder,_that.recordingComposerBuilder,_that.lockHintBuilder,_that.editingBackgroundColor,_that.editingBorderColor,_that.editingLabelStyle,_that.editingPreviewStyle,_that.replyPreviewBackgroundColor,_that.replyPreviewBarColor,_that.replyPreviewSenderStyle,_that.replyPreviewTextStyle);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Color? backgroundColor,  Color? fillColor,  TextStyle? textStyle,  TextStyle? hintStyle,  Color? borderColor,  double? borderWidth,  BorderRadius? borderRadius,  List<BoxShadow>? containerShadow,  Color? sendButtonColor,  IconData? sendButtonIcon,  Color? sendButtonIconColor,  Color? sendButtonDisabledColor,  IconData? attachButtonIcon,  Color? attachButtonColor,  IconData? voiceButtonIcon,  Color? voiceButtonColor,  Color? voiceButtonIdleIconColor,  IconData? cameraButtonIcon,  Color? cameraButtonColor,  Widget Function(BuildContext context)? attachIconBuilder,  Widget Function(BuildContext context)? cameraIconBuilder,  Widget Function(BuildContext context)? voiceIconBuilder,  Widget Function(BuildContext context, bool hasText)? sendIconBuilder,  Widget Function(BuildContext context, VoiceRecordingController controller, VoidCallback onSend)? recordingComposerBuilder,  Widget Function(BuildContext context)? lockHintBuilder,  Color? editingBackgroundColor,  Color? editingBorderColor,  TextStyle? editingLabelStyle,  TextStyle? editingPreviewStyle,  Color? replyPreviewBackgroundColor,  Color? replyPreviewBarColor,  TextStyle? replyPreviewSenderStyle,  TextStyle? replyPreviewTextStyle)?  $default,) {final _that = this;
switch (_that) {
case _ChatInputTheme() when $default != null:
return $default(_that.backgroundColor,_that.fillColor,_that.textStyle,_that.hintStyle,_that.borderColor,_that.borderWidth,_that.borderRadius,_that.containerShadow,_that.sendButtonColor,_that.sendButtonIcon,_that.sendButtonIconColor,_that.sendButtonDisabledColor,_that.attachButtonIcon,_that.attachButtonColor,_that.voiceButtonIcon,_that.voiceButtonColor,_that.voiceButtonIdleIconColor,_that.cameraButtonIcon,_that.cameraButtonColor,_that.attachIconBuilder,_that.cameraIconBuilder,_that.voiceIconBuilder,_that.sendIconBuilder,_that.recordingComposerBuilder,_that.lockHintBuilder,_that.editingBackgroundColor,_that.editingBorderColor,_that.editingLabelStyle,_that.editingPreviewStyle,_that.replyPreviewBackgroundColor,_that.replyPreviewBarColor,_that.replyPreviewSenderStyle,_that.replyPreviewTextStyle);case _:
  return null;

}
}

}

/// @nodoc


class _ChatInputTheme implements ChatInputTheme {
  const _ChatInputTheme({this.backgroundColor, this.fillColor, this.textStyle, this.hintStyle, this.borderColor, this.borderWidth, this.borderRadius, final  List<BoxShadow>? containerShadow, this.sendButtonColor, this.sendButtonIcon, this.sendButtonIconColor, this.sendButtonDisabledColor, this.attachButtonIcon, this.attachButtonColor, this.voiceButtonIcon, this.voiceButtonColor, this.voiceButtonIdleIconColor, this.cameraButtonIcon, this.cameraButtonColor, this.attachIconBuilder, this.cameraIconBuilder, this.voiceIconBuilder, this.sendIconBuilder, this.recordingComposerBuilder, this.lockHintBuilder, this.editingBackgroundColor, this.editingBorderColor, this.editingLabelStyle, this.editingPreviewStyle, this.replyPreviewBackgroundColor, this.replyPreviewBarColor, this.replyPreviewSenderStyle, this.replyPreviewTextStyle}): _containerShadow = containerShadow;
  

/// Background of the entire composer container (the bar that hosts the
/// text field + side buttons).
@override final  Color? backgroundColor;
/// Fill colour of the text-field surface itself, inset inside the
/// composer container.
@override final  Color? fillColor;
/// Default text style typed into the composer.
@override final  TextStyle? textStyle;
/// Style for the placeholder text shown when the composer is empty.
@override final  TextStyle? hintStyle;
/// Border of the composer text-field. When null, no border is drawn.
@override final  Color? borderColor;
/// Width of [borderColor]. Defaults to 1 px when [borderColor] is set
/// and this is null.
@override final  double? borderWidth;
/// Rounded-corner radius of the composer text-field. Defaults to a
/// pill shape (24) when null.
@override final  BorderRadius? borderRadius;
/// Optional shadow rendered behind the composer container.
 final  List<BoxShadow>? _containerShadow;
/// Optional shadow rendered behind the composer container.
@override List<BoxShadow>? get containerShadow {
  final value = _containerShadow;
  if (value == null) return null;
  if (_containerShadow is EqualUnmodifiableListView) return _containerShadow;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

/// Background of the round send button.
@override final  Color? sendButtonColor;
/// Icon shown inside the send button. Falls back to a paper-plane.
@override final  IconData? sendButtonIcon;
/// Tint of [sendButtonIcon].
@override final  Color? sendButtonIconColor;
/// Background of the send button when no text is typed.
@override final  Color? sendButtonDisabledColor;
/// Icon shown on the attachment shortcut.
@override final  IconData? attachButtonIcon;
/// Tint of the attachment shortcut.
@override final  Color? attachButtonColor;
/// Icon shown on the voice (microphone) shortcut.
@override final  IconData? voiceButtonIcon;
/// Tint of [voiceButtonIcon] while idle.
@override final  Color? voiceButtonColor;
/// Tint of the voice icon when the composer is empty (idle state),
/// overriding [voiceButtonColor]. Useful for theme tokens that want a
/// brand colour only when recording is available.
@override final  Color? voiceButtonIdleIconColor;
/// Icon shown on the camera shortcut.
@override final  IconData? cameraButtonIcon;
/// Tint of the camera shortcut.
@override final  Color? cameraButtonColor;
/// Custom builder for the attach button — replaces icon + tint.
@override final  Widget Function(BuildContext context)? attachIconBuilder;
/// Custom builder for the camera button.
@override final  Widget Function(BuildContext context)? cameraIconBuilder;
/// Custom builder for the voice button.
@override final  Widget Function(BuildContext context)? voiceIconBuilder;
/// Builder for the send button. Receives whether the composer has text.
@override final  Widget Function(BuildContext context, bool hasText)? sendIconBuilder;
/// Custom layout while voice recording is active (replaces the default
/// red-mic row).
@override final  Widget Function(BuildContext context, VoiceRecordingController controller, VoidCallback onSend)? recordingComposerBuilder;
/// Builder for the floating "slide up to lock" hint.
@override final  Widget Function(BuildContext context)? lockHintBuilder;
/// Background of the "Editing this message" banner above the composer.
@override final  Color? editingBackgroundColor;
/// Border / accent colour of the editing banner.
@override final  Color? editingBorderColor;
/// Style for the "Editing" label.
@override final  TextStyle? editingLabelStyle;
/// Style for the preview of the message being edited.
@override final  TextStyle? editingPreviewStyle;
/// Background of the "Replying to" preview above the composer.
@override final  Color? replyPreviewBackgroundColor;
/// Vertical accent bar shown on the reply preview.
@override final  Color? replyPreviewBarColor;
/// Style for the sender name inside the reply preview.
@override final  TextStyle? replyPreviewSenderStyle;
/// Style for the message snippet inside the reply preview.
@override final  TextStyle? replyPreviewTextStyle;

/// Create a copy of ChatInputTheme
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatInputThemeCopyWith<_ChatInputTheme> get copyWith => __$ChatInputThemeCopyWithImpl<_ChatInputTheme>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatInputTheme&&(identical(other.backgroundColor, backgroundColor) || other.backgroundColor == backgroundColor)&&(identical(other.fillColor, fillColor) || other.fillColor == fillColor)&&(identical(other.textStyle, textStyle) || other.textStyle == textStyle)&&(identical(other.hintStyle, hintStyle) || other.hintStyle == hintStyle)&&(identical(other.borderColor, borderColor) || other.borderColor == borderColor)&&(identical(other.borderWidth, borderWidth) || other.borderWidth == borderWidth)&&(identical(other.borderRadius, borderRadius) || other.borderRadius == borderRadius)&&const DeepCollectionEquality().equals(other._containerShadow, _containerShadow)&&(identical(other.sendButtonColor, sendButtonColor) || other.sendButtonColor == sendButtonColor)&&(identical(other.sendButtonIcon, sendButtonIcon) || other.sendButtonIcon == sendButtonIcon)&&(identical(other.sendButtonIconColor, sendButtonIconColor) || other.sendButtonIconColor == sendButtonIconColor)&&(identical(other.sendButtonDisabledColor, sendButtonDisabledColor) || other.sendButtonDisabledColor == sendButtonDisabledColor)&&(identical(other.attachButtonIcon, attachButtonIcon) || other.attachButtonIcon == attachButtonIcon)&&(identical(other.attachButtonColor, attachButtonColor) || other.attachButtonColor == attachButtonColor)&&(identical(other.voiceButtonIcon, voiceButtonIcon) || other.voiceButtonIcon == voiceButtonIcon)&&(identical(other.voiceButtonColor, voiceButtonColor) || other.voiceButtonColor == voiceButtonColor)&&(identical(other.voiceButtonIdleIconColor, voiceButtonIdleIconColor) || other.voiceButtonIdleIconColor == voiceButtonIdleIconColor)&&(identical(other.cameraButtonIcon, cameraButtonIcon) || other.cameraButtonIcon == cameraButtonIcon)&&(identical(other.cameraButtonColor, cameraButtonColor) || other.cameraButtonColor == cameraButtonColor)&&(identical(other.attachIconBuilder, attachIconBuilder) || other.attachIconBuilder == attachIconBuilder)&&(identical(other.cameraIconBuilder, cameraIconBuilder) || other.cameraIconBuilder == cameraIconBuilder)&&(identical(other.voiceIconBuilder, voiceIconBuilder) || other.voiceIconBuilder == voiceIconBuilder)&&(identical(other.sendIconBuilder, sendIconBuilder) || other.sendIconBuilder == sendIconBuilder)&&(identical(other.recordingComposerBuilder, recordingComposerBuilder) || other.recordingComposerBuilder == recordingComposerBuilder)&&(identical(other.lockHintBuilder, lockHintBuilder) || other.lockHintBuilder == lockHintBuilder)&&(identical(other.editingBackgroundColor, editingBackgroundColor) || other.editingBackgroundColor == editingBackgroundColor)&&(identical(other.editingBorderColor, editingBorderColor) || other.editingBorderColor == editingBorderColor)&&(identical(other.editingLabelStyle, editingLabelStyle) || other.editingLabelStyle == editingLabelStyle)&&(identical(other.editingPreviewStyle, editingPreviewStyle) || other.editingPreviewStyle == editingPreviewStyle)&&(identical(other.replyPreviewBackgroundColor, replyPreviewBackgroundColor) || other.replyPreviewBackgroundColor == replyPreviewBackgroundColor)&&(identical(other.replyPreviewBarColor, replyPreviewBarColor) || other.replyPreviewBarColor == replyPreviewBarColor)&&(identical(other.replyPreviewSenderStyle, replyPreviewSenderStyle) || other.replyPreviewSenderStyle == replyPreviewSenderStyle)&&(identical(other.replyPreviewTextStyle, replyPreviewTextStyle) || other.replyPreviewTextStyle == replyPreviewTextStyle));
}


@override
int get hashCode => Object.hashAll([runtimeType,backgroundColor,fillColor,textStyle,hintStyle,borderColor,borderWidth,borderRadius,const DeepCollectionEquality().hash(_containerShadow),sendButtonColor,sendButtonIcon,sendButtonIconColor,sendButtonDisabledColor,attachButtonIcon,attachButtonColor,voiceButtonIcon,voiceButtonColor,voiceButtonIdleIconColor,cameraButtonIcon,cameraButtonColor,attachIconBuilder,cameraIconBuilder,voiceIconBuilder,sendIconBuilder,recordingComposerBuilder,lockHintBuilder,editingBackgroundColor,editingBorderColor,editingLabelStyle,editingPreviewStyle,replyPreviewBackgroundColor,replyPreviewBarColor,replyPreviewSenderStyle,replyPreviewTextStyle]);

@override
String toString() {
  return 'ChatInputTheme(backgroundColor: $backgroundColor, fillColor: $fillColor, textStyle: $textStyle, hintStyle: $hintStyle, borderColor: $borderColor, borderWidth: $borderWidth, borderRadius: $borderRadius, containerShadow: $containerShadow, sendButtonColor: $sendButtonColor, sendButtonIcon: $sendButtonIcon, sendButtonIconColor: $sendButtonIconColor, sendButtonDisabledColor: $sendButtonDisabledColor, attachButtonIcon: $attachButtonIcon, attachButtonColor: $attachButtonColor, voiceButtonIcon: $voiceButtonIcon, voiceButtonColor: $voiceButtonColor, voiceButtonIdleIconColor: $voiceButtonIdleIconColor, cameraButtonIcon: $cameraButtonIcon, cameraButtonColor: $cameraButtonColor, attachIconBuilder: $attachIconBuilder, cameraIconBuilder: $cameraIconBuilder, voiceIconBuilder: $voiceIconBuilder, sendIconBuilder: $sendIconBuilder, recordingComposerBuilder: $recordingComposerBuilder, lockHintBuilder: $lockHintBuilder, editingBackgroundColor: $editingBackgroundColor, editingBorderColor: $editingBorderColor, editingLabelStyle: $editingLabelStyle, editingPreviewStyle: $editingPreviewStyle, replyPreviewBackgroundColor: $replyPreviewBackgroundColor, replyPreviewBarColor: $replyPreviewBarColor, replyPreviewSenderStyle: $replyPreviewSenderStyle, replyPreviewTextStyle: $replyPreviewTextStyle)';
}


}

/// @nodoc
abstract mixin class _$ChatInputThemeCopyWith<$Res> implements $ChatInputThemeCopyWith<$Res> {
  factory _$ChatInputThemeCopyWith(_ChatInputTheme value, $Res Function(_ChatInputTheme) _then) = __$ChatInputThemeCopyWithImpl;
@override @useResult
$Res call({
 Color? backgroundColor, Color? fillColor, TextStyle? textStyle, TextStyle? hintStyle, Color? borderColor, double? borderWidth, BorderRadius? borderRadius, List<BoxShadow>? containerShadow, Color? sendButtonColor, IconData? sendButtonIcon, Color? sendButtonIconColor, Color? sendButtonDisabledColor, IconData? attachButtonIcon, Color? attachButtonColor, IconData? voiceButtonIcon, Color? voiceButtonColor, Color? voiceButtonIdleIconColor, IconData? cameraButtonIcon, Color? cameraButtonColor, Widget Function(BuildContext context)? attachIconBuilder, Widget Function(BuildContext context)? cameraIconBuilder, Widget Function(BuildContext context)? voiceIconBuilder, Widget Function(BuildContext context, bool hasText)? sendIconBuilder, Widget Function(BuildContext context, VoiceRecordingController controller, VoidCallback onSend)? recordingComposerBuilder, Widget Function(BuildContext context)? lockHintBuilder, Color? editingBackgroundColor, Color? editingBorderColor, TextStyle? editingLabelStyle, TextStyle? editingPreviewStyle, Color? replyPreviewBackgroundColor, Color? replyPreviewBarColor, TextStyle? replyPreviewSenderStyle, TextStyle? replyPreviewTextStyle
});




}
/// @nodoc
class __$ChatInputThemeCopyWithImpl<$Res>
    implements _$ChatInputThemeCopyWith<$Res> {
  __$ChatInputThemeCopyWithImpl(this._self, this._then);

  final _ChatInputTheme _self;
  final $Res Function(_ChatInputTheme) _then;

/// Create a copy of ChatInputTheme
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? backgroundColor = freezed,Object? fillColor = freezed,Object? textStyle = freezed,Object? hintStyle = freezed,Object? borderColor = freezed,Object? borderWidth = freezed,Object? borderRadius = freezed,Object? containerShadow = freezed,Object? sendButtonColor = freezed,Object? sendButtonIcon = freezed,Object? sendButtonIconColor = freezed,Object? sendButtonDisabledColor = freezed,Object? attachButtonIcon = freezed,Object? attachButtonColor = freezed,Object? voiceButtonIcon = freezed,Object? voiceButtonColor = freezed,Object? voiceButtonIdleIconColor = freezed,Object? cameraButtonIcon = freezed,Object? cameraButtonColor = freezed,Object? attachIconBuilder = freezed,Object? cameraIconBuilder = freezed,Object? voiceIconBuilder = freezed,Object? sendIconBuilder = freezed,Object? recordingComposerBuilder = freezed,Object? lockHintBuilder = freezed,Object? editingBackgroundColor = freezed,Object? editingBorderColor = freezed,Object? editingLabelStyle = freezed,Object? editingPreviewStyle = freezed,Object? replyPreviewBackgroundColor = freezed,Object? replyPreviewBarColor = freezed,Object? replyPreviewSenderStyle = freezed,Object? replyPreviewTextStyle = freezed,}) {
  return _then(_ChatInputTheme(
backgroundColor: freezed == backgroundColor ? _self.backgroundColor : backgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,fillColor: freezed == fillColor ? _self.fillColor : fillColor // ignore: cast_nullable_to_non_nullable
as Color?,textStyle: freezed == textStyle ? _self.textStyle : textStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,hintStyle: freezed == hintStyle ? _self.hintStyle : hintStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,borderColor: freezed == borderColor ? _self.borderColor : borderColor // ignore: cast_nullable_to_non_nullable
as Color?,borderWidth: freezed == borderWidth ? _self.borderWidth : borderWidth // ignore: cast_nullable_to_non_nullable
as double?,borderRadius: freezed == borderRadius ? _self.borderRadius : borderRadius // ignore: cast_nullable_to_non_nullable
as BorderRadius?,containerShadow: freezed == containerShadow ? _self._containerShadow : containerShadow // ignore: cast_nullable_to_non_nullable
as List<BoxShadow>?,sendButtonColor: freezed == sendButtonColor ? _self.sendButtonColor : sendButtonColor // ignore: cast_nullable_to_non_nullable
as Color?,sendButtonIcon: freezed == sendButtonIcon ? _self.sendButtonIcon : sendButtonIcon // ignore: cast_nullable_to_non_nullable
as IconData?,sendButtonIconColor: freezed == sendButtonIconColor ? _self.sendButtonIconColor : sendButtonIconColor // ignore: cast_nullable_to_non_nullable
as Color?,sendButtonDisabledColor: freezed == sendButtonDisabledColor ? _self.sendButtonDisabledColor : sendButtonDisabledColor // ignore: cast_nullable_to_non_nullable
as Color?,attachButtonIcon: freezed == attachButtonIcon ? _self.attachButtonIcon : attachButtonIcon // ignore: cast_nullable_to_non_nullable
as IconData?,attachButtonColor: freezed == attachButtonColor ? _self.attachButtonColor : attachButtonColor // ignore: cast_nullable_to_non_nullable
as Color?,voiceButtonIcon: freezed == voiceButtonIcon ? _self.voiceButtonIcon : voiceButtonIcon // ignore: cast_nullable_to_non_nullable
as IconData?,voiceButtonColor: freezed == voiceButtonColor ? _self.voiceButtonColor : voiceButtonColor // ignore: cast_nullable_to_non_nullable
as Color?,voiceButtonIdleIconColor: freezed == voiceButtonIdleIconColor ? _self.voiceButtonIdleIconColor : voiceButtonIdleIconColor // ignore: cast_nullable_to_non_nullable
as Color?,cameraButtonIcon: freezed == cameraButtonIcon ? _self.cameraButtonIcon : cameraButtonIcon // ignore: cast_nullable_to_non_nullable
as IconData?,cameraButtonColor: freezed == cameraButtonColor ? _self.cameraButtonColor : cameraButtonColor // ignore: cast_nullable_to_non_nullable
as Color?,attachIconBuilder: freezed == attachIconBuilder ? _self.attachIconBuilder : attachIconBuilder // ignore: cast_nullable_to_non_nullable
as Widget Function(BuildContext context)?,cameraIconBuilder: freezed == cameraIconBuilder ? _self.cameraIconBuilder : cameraIconBuilder // ignore: cast_nullable_to_non_nullable
as Widget Function(BuildContext context)?,voiceIconBuilder: freezed == voiceIconBuilder ? _self.voiceIconBuilder : voiceIconBuilder // ignore: cast_nullable_to_non_nullable
as Widget Function(BuildContext context)?,sendIconBuilder: freezed == sendIconBuilder ? _self.sendIconBuilder : sendIconBuilder // ignore: cast_nullable_to_non_nullable
as Widget Function(BuildContext context, bool hasText)?,recordingComposerBuilder: freezed == recordingComposerBuilder ? _self.recordingComposerBuilder : recordingComposerBuilder // ignore: cast_nullable_to_non_nullable
as Widget Function(BuildContext context, VoiceRecordingController controller, VoidCallback onSend)?,lockHintBuilder: freezed == lockHintBuilder ? _self.lockHintBuilder : lockHintBuilder // ignore: cast_nullable_to_non_nullable
as Widget Function(BuildContext context)?,editingBackgroundColor: freezed == editingBackgroundColor ? _self.editingBackgroundColor : editingBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,editingBorderColor: freezed == editingBorderColor ? _self.editingBorderColor : editingBorderColor // ignore: cast_nullable_to_non_nullable
as Color?,editingLabelStyle: freezed == editingLabelStyle ? _self.editingLabelStyle : editingLabelStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,editingPreviewStyle: freezed == editingPreviewStyle ? _self.editingPreviewStyle : editingPreviewStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,replyPreviewBackgroundColor: freezed == replyPreviewBackgroundColor ? _self.replyPreviewBackgroundColor : replyPreviewBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,replyPreviewBarColor: freezed == replyPreviewBarColor ? _self.replyPreviewBarColor : replyPreviewBarColor // ignore: cast_nullable_to_non_nullable
as Color?,replyPreviewSenderStyle: freezed == replyPreviewSenderStyle ? _self.replyPreviewSenderStyle : replyPreviewSenderStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,replyPreviewTextStyle: freezed == replyPreviewTextStyle ? _self.replyPreviewTextStyle : replyPreviewTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,
  ));
}


}

// dart format on
