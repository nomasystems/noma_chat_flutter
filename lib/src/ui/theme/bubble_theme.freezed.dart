// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bubble_theme.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ChatBubbleTheme {

/// Background of bubbles authored by the current user.
 Color? get outgoingColor;/// Background of bubbles authored by anyone else.
 Color? get incomingColor;/// Default text style for outgoing bubble payloads.
 TextStyle? get outgoingTextStyle;/// Default text style for incoming bubble payloads.
 TextStyle? get incomingTextStyle;/// Border radius applied to every bubble.
 BorderRadius? get borderRadius;/// Fallback timestamp style applied at the bubble corner.
 TextStyle? get timestampStyle;/// Outgoing-side override for [timestampStyle].
 TextStyle? get outgoingTimestampStyle;/// Incoming-side override for [timestampStyle].
 TextStyle? get incomingTimestampStyle;/// Color of the receipt status icon (sent / delivered).
 Color? get statusColor;/// Color of the double-check when the recipient has read the message.
/// Defaults to a Material-blue (0xFF2196F3) at the [ChatTheme] level.
 Color? get statusReadColor;/// Color used to highlight `@<word>` mention tokens inside a bubble.
 Color? get mentionColor;/// Style for the "edited" / "edited by admin" sublabel.
 TextStyle? get editedLabelStyle;/// Color of the "Forwarded" header on forwarded bubbles.
 Color? get forwardedLabelColor;/// Style of the "Forwarded" header on forwarded bubbles.
 TextStyle? get forwardedLabelStyle;/// Style of the sender name rendered above incoming bubbles in group
/// chats (WhatsApp-style).
 TextStyle? get senderNameStyle;/// Tint for the warning icon attached to messages that failed to send.
 Color? get failedIconColor;
/// Create a copy of ChatBubbleTheme
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatBubbleThemeCopyWith<ChatBubbleTheme> get copyWith => _$ChatBubbleThemeCopyWithImpl<ChatBubbleTheme>(this as ChatBubbleTheme, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatBubbleTheme&&(identical(other.outgoingColor, outgoingColor) || other.outgoingColor == outgoingColor)&&(identical(other.incomingColor, incomingColor) || other.incomingColor == incomingColor)&&(identical(other.outgoingTextStyle, outgoingTextStyle) || other.outgoingTextStyle == outgoingTextStyle)&&(identical(other.incomingTextStyle, incomingTextStyle) || other.incomingTextStyle == incomingTextStyle)&&(identical(other.borderRadius, borderRadius) || other.borderRadius == borderRadius)&&(identical(other.timestampStyle, timestampStyle) || other.timestampStyle == timestampStyle)&&(identical(other.outgoingTimestampStyle, outgoingTimestampStyle) || other.outgoingTimestampStyle == outgoingTimestampStyle)&&(identical(other.incomingTimestampStyle, incomingTimestampStyle) || other.incomingTimestampStyle == incomingTimestampStyle)&&(identical(other.statusColor, statusColor) || other.statusColor == statusColor)&&(identical(other.statusReadColor, statusReadColor) || other.statusReadColor == statusReadColor)&&(identical(other.mentionColor, mentionColor) || other.mentionColor == mentionColor)&&(identical(other.editedLabelStyle, editedLabelStyle) || other.editedLabelStyle == editedLabelStyle)&&(identical(other.forwardedLabelColor, forwardedLabelColor) || other.forwardedLabelColor == forwardedLabelColor)&&(identical(other.forwardedLabelStyle, forwardedLabelStyle) || other.forwardedLabelStyle == forwardedLabelStyle)&&(identical(other.senderNameStyle, senderNameStyle) || other.senderNameStyle == senderNameStyle)&&(identical(other.failedIconColor, failedIconColor) || other.failedIconColor == failedIconColor));
}


@override
int get hashCode => Object.hash(runtimeType,outgoingColor,incomingColor,outgoingTextStyle,incomingTextStyle,borderRadius,timestampStyle,outgoingTimestampStyle,incomingTimestampStyle,statusColor,statusReadColor,mentionColor,editedLabelStyle,forwardedLabelColor,forwardedLabelStyle,senderNameStyle,failedIconColor);

@override
String toString() {
  return 'ChatBubbleTheme(outgoingColor: $outgoingColor, incomingColor: $incomingColor, outgoingTextStyle: $outgoingTextStyle, incomingTextStyle: $incomingTextStyle, borderRadius: $borderRadius, timestampStyle: $timestampStyle, outgoingTimestampStyle: $outgoingTimestampStyle, incomingTimestampStyle: $incomingTimestampStyle, statusColor: $statusColor, statusReadColor: $statusReadColor, mentionColor: $mentionColor, editedLabelStyle: $editedLabelStyle, forwardedLabelColor: $forwardedLabelColor, forwardedLabelStyle: $forwardedLabelStyle, senderNameStyle: $senderNameStyle, failedIconColor: $failedIconColor)';
}


}

/// @nodoc
abstract mixin class $ChatBubbleThemeCopyWith<$Res>  {
  factory $ChatBubbleThemeCopyWith(ChatBubbleTheme value, $Res Function(ChatBubbleTheme) _then) = _$ChatBubbleThemeCopyWithImpl;
@useResult
$Res call({
 Color? outgoingColor, Color? incomingColor, TextStyle? outgoingTextStyle, TextStyle? incomingTextStyle, BorderRadius? borderRadius, TextStyle? timestampStyle, TextStyle? outgoingTimestampStyle, TextStyle? incomingTimestampStyle, Color? statusColor, Color? statusReadColor, Color? mentionColor, TextStyle? editedLabelStyle, Color? forwardedLabelColor, TextStyle? forwardedLabelStyle, TextStyle? senderNameStyle, Color? failedIconColor
});




}
/// @nodoc
class _$ChatBubbleThemeCopyWithImpl<$Res>
    implements $ChatBubbleThemeCopyWith<$Res> {
  _$ChatBubbleThemeCopyWithImpl(this._self, this._then);

  final ChatBubbleTheme _self;
  final $Res Function(ChatBubbleTheme) _then;

/// Create a copy of ChatBubbleTheme
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? outgoingColor = freezed,Object? incomingColor = freezed,Object? outgoingTextStyle = freezed,Object? incomingTextStyle = freezed,Object? borderRadius = freezed,Object? timestampStyle = freezed,Object? outgoingTimestampStyle = freezed,Object? incomingTimestampStyle = freezed,Object? statusColor = freezed,Object? statusReadColor = freezed,Object? mentionColor = freezed,Object? editedLabelStyle = freezed,Object? forwardedLabelColor = freezed,Object? forwardedLabelStyle = freezed,Object? senderNameStyle = freezed,Object? failedIconColor = freezed,}) {
  return _then(_self.copyWith(
outgoingColor: freezed == outgoingColor ? _self.outgoingColor : outgoingColor // ignore: cast_nullable_to_non_nullable
as Color?,incomingColor: freezed == incomingColor ? _self.incomingColor : incomingColor // ignore: cast_nullable_to_non_nullable
as Color?,outgoingTextStyle: freezed == outgoingTextStyle ? _self.outgoingTextStyle : outgoingTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,incomingTextStyle: freezed == incomingTextStyle ? _self.incomingTextStyle : incomingTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,borderRadius: freezed == borderRadius ? _self.borderRadius : borderRadius // ignore: cast_nullable_to_non_nullable
as BorderRadius?,timestampStyle: freezed == timestampStyle ? _self.timestampStyle : timestampStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,outgoingTimestampStyle: freezed == outgoingTimestampStyle ? _self.outgoingTimestampStyle : outgoingTimestampStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,incomingTimestampStyle: freezed == incomingTimestampStyle ? _self.incomingTimestampStyle : incomingTimestampStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,statusColor: freezed == statusColor ? _self.statusColor : statusColor // ignore: cast_nullable_to_non_nullable
as Color?,statusReadColor: freezed == statusReadColor ? _self.statusReadColor : statusReadColor // ignore: cast_nullable_to_non_nullable
as Color?,mentionColor: freezed == mentionColor ? _self.mentionColor : mentionColor // ignore: cast_nullable_to_non_nullable
as Color?,editedLabelStyle: freezed == editedLabelStyle ? _self.editedLabelStyle : editedLabelStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,forwardedLabelColor: freezed == forwardedLabelColor ? _self.forwardedLabelColor : forwardedLabelColor // ignore: cast_nullable_to_non_nullable
as Color?,forwardedLabelStyle: freezed == forwardedLabelStyle ? _self.forwardedLabelStyle : forwardedLabelStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,senderNameStyle: freezed == senderNameStyle ? _self.senderNameStyle : senderNameStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,failedIconColor: freezed == failedIconColor ? _self.failedIconColor : failedIconColor // ignore: cast_nullable_to_non_nullable
as Color?,
  ));
}

}


/// Adds pattern-matching-related methods to [ChatBubbleTheme].
extension ChatBubbleThemePatterns on ChatBubbleTheme {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatBubbleTheme value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatBubbleTheme() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatBubbleTheme value)  $default,){
final _that = this;
switch (_that) {
case _ChatBubbleTheme():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatBubbleTheme value)?  $default,){
final _that = this;
switch (_that) {
case _ChatBubbleTheme() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Color? outgoingColor,  Color? incomingColor,  TextStyle? outgoingTextStyle,  TextStyle? incomingTextStyle,  BorderRadius? borderRadius,  TextStyle? timestampStyle,  TextStyle? outgoingTimestampStyle,  TextStyle? incomingTimestampStyle,  Color? statusColor,  Color? statusReadColor,  Color? mentionColor,  TextStyle? editedLabelStyle,  Color? forwardedLabelColor,  TextStyle? forwardedLabelStyle,  TextStyle? senderNameStyle,  Color? failedIconColor)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatBubbleTheme() when $default != null:
return $default(_that.outgoingColor,_that.incomingColor,_that.outgoingTextStyle,_that.incomingTextStyle,_that.borderRadius,_that.timestampStyle,_that.outgoingTimestampStyle,_that.incomingTimestampStyle,_that.statusColor,_that.statusReadColor,_that.mentionColor,_that.editedLabelStyle,_that.forwardedLabelColor,_that.forwardedLabelStyle,_that.senderNameStyle,_that.failedIconColor);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Color? outgoingColor,  Color? incomingColor,  TextStyle? outgoingTextStyle,  TextStyle? incomingTextStyle,  BorderRadius? borderRadius,  TextStyle? timestampStyle,  TextStyle? outgoingTimestampStyle,  TextStyle? incomingTimestampStyle,  Color? statusColor,  Color? statusReadColor,  Color? mentionColor,  TextStyle? editedLabelStyle,  Color? forwardedLabelColor,  TextStyle? forwardedLabelStyle,  TextStyle? senderNameStyle,  Color? failedIconColor)  $default,) {final _that = this;
switch (_that) {
case _ChatBubbleTheme():
return $default(_that.outgoingColor,_that.incomingColor,_that.outgoingTextStyle,_that.incomingTextStyle,_that.borderRadius,_that.timestampStyle,_that.outgoingTimestampStyle,_that.incomingTimestampStyle,_that.statusColor,_that.statusReadColor,_that.mentionColor,_that.editedLabelStyle,_that.forwardedLabelColor,_that.forwardedLabelStyle,_that.senderNameStyle,_that.failedIconColor);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Color? outgoingColor,  Color? incomingColor,  TextStyle? outgoingTextStyle,  TextStyle? incomingTextStyle,  BorderRadius? borderRadius,  TextStyle? timestampStyle,  TextStyle? outgoingTimestampStyle,  TextStyle? incomingTimestampStyle,  Color? statusColor,  Color? statusReadColor,  Color? mentionColor,  TextStyle? editedLabelStyle,  Color? forwardedLabelColor,  TextStyle? forwardedLabelStyle,  TextStyle? senderNameStyle,  Color? failedIconColor)?  $default,) {final _that = this;
switch (_that) {
case _ChatBubbleTheme() when $default != null:
return $default(_that.outgoingColor,_that.incomingColor,_that.outgoingTextStyle,_that.incomingTextStyle,_that.borderRadius,_that.timestampStyle,_that.outgoingTimestampStyle,_that.incomingTimestampStyle,_that.statusColor,_that.statusReadColor,_that.mentionColor,_that.editedLabelStyle,_that.forwardedLabelColor,_that.forwardedLabelStyle,_that.senderNameStyle,_that.failedIconColor);case _:
  return null;

}
}

}

/// @nodoc


class _ChatBubbleTheme implements ChatBubbleTheme {
  const _ChatBubbleTheme({this.outgoingColor, this.incomingColor, this.outgoingTextStyle, this.incomingTextStyle, this.borderRadius, this.timestampStyle, this.outgoingTimestampStyle, this.incomingTimestampStyle, this.statusColor, this.statusReadColor, this.mentionColor, this.editedLabelStyle, this.forwardedLabelColor, this.forwardedLabelStyle, this.senderNameStyle, this.failedIconColor});
  

/// Background of bubbles authored by the current user.
@override final  Color? outgoingColor;
/// Background of bubbles authored by anyone else.
@override final  Color? incomingColor;
/// Default text style for outgoing bubble payloads.
@override final  TextStyle? outgoingTextStyle;
/// Default text style for incoming bubble payloads.
@override final  TextStyle? incomingTextStyle;
/// Border radius applied to every bubble.
@override final  BorderRadius? borderRadius;
/// Fallback timestamp style applied at the bubble corner.
@override final  TextStyle? timestampStyle;
/// Outgoing-side override for [timestampStyle].
@override final  TextStyle? outgoingTimestampStyle;
/// Incoming-side override for [timestampStyle].
@override final  TextStyle? incomingTimestampStyle;
/// Color of the receipt status icon (sent / delivered).
@override final  Color? statusColor;
/// Color of the double-check when the recipient has read the message.
/// Defaults to a Material-blue (0xFF2196F3) at the [ChatTheme] level.
@override final  Color? statusReadColor;
/// Color used to highlight `@<word>` mention tokens inside a bubble.
@override final  Color? mentionColor;
/// Style for the "edited" / "edited by admin" sublabel.
@override final  TextStyle? editedLabelStyle;
/// Color of the "Forwarded" header on forwarded bubbles.
@override final  Color? forwardedLabelColor;
/// Style of the "Forwarded" header on forwarded bubbles.
@override final  TextStyle? forwardedLabelStyle;
/// Style of the sender name rendered above incoming bubbles in group
/// chats (WhatsApp-style).
@override final  TextStyle? senderNameStyle;
/// Tint for the warning icon attached to messages that failed to send.
@override final  Color? failedIconColor;

/// Create a copy of ChatBubbleTheme
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatBubbleThemeCopyWith<_ChatBubbleTheme> get copyWith => __$ChatBubbleThemeCopyWithImpl<_ChatBubbleTheme>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatBubbleTheme&&(identical(other.outgoingColor, outgoingColor) || other.outgoingColor == outgoingColor)&&(identical(other.incomingColor, incomingColor) || other.incomingColor == incomingColor)&&(identical(other.outgoingTextStyle, outgoingTextStyle) || other.outgoingTextStyle == outgoingTextStyle)&&(identical(other.incomingTextStyle, incomingTextStyle) || other.incomingTextStyle == incomingTextStyle)&&(identical(other.borderRadius, borderRadius) || other.borderRadius == borderRadius)&&(identical(other.timestampStyle, timestampStyle) || other.timestampStyle == timestampStyle)&&(identical(other.outgoingTimestampStyle, outgoingTimestampStyle) || other.outgoingTimestampStyle == outgoingTimestampStyle)&&(identical(other.incomingTimestampStyle, incomingTimestampStyle) || other.incomingTimestampStyle == incomingTimestampStyle)&&(identical(other.statusColor, statusColor) || other.statusColor == statusColor)&&(identical(other.statusReadColor, statusReadColor) || other.statusReadColor == statusReadColor)&&(identical(other.mentionColor, mentionColor) || other.mentionColor == mentionColor)&&(identical(other.editedLabelStyle, editedLabelStyle) || other.editedLabelStyle == editedLabelStyle)&&(identical(other.forwardedLabelColor, forwardedLabelColor) || other.forwardedLabelColor == forwardedLabelColor)&&(identical(other.forwardedLabelStyle, forwardedLabelStyle) || other.forwardedLabelStyle == forwardedLabelStyle)&&(identical(other.senderNameStyle, senderNameStyle) || other.senderNameStyle == senderNameStyle)&&(identical(other.failedIconColor, failedIconColor) || other.failedIconColor == failedIconColor));
}


@override
int get hashCode => Object.hash(runtimeType,outgoingColor,incomingColor,outgoingTextStyle,incomingTextStyle,borderRadius,timestampStyle,outgoingTimestampStyle,incomingTimestampStyle,statusColor,statusReadColor,mentionColor,editedLabelStyle,forwardedLabelColor,forwardedLabelStyle,senderNameStyle,failedIconColor);

@override
String toString() {
  return 'ChatBubbleTheme(outgoingColor: $outgoingColor, incomingColor: $incomingColor, outgoingTextStyle: $outgoingTextStyle, incomingTextStyle: $incomingTextStyle, borderRadius: $borderRadius, timestampStyle: $timestampStyle, outgoingTimestampStyle: $outgoingTimestampStyle, incomingTimestampStyle: $incomingTimestampStyle, statusColor: $statusColor, statusReadColor: $statusReadColor, mentionColor: $mentionColor, editedLabelStyle: $editedLabelStyle, forwardedLabelColor: $forwardedLabelColor, forwardedLabelStyle: $forwardedLabelStyle, senderNameStyle: $senderNameStyle, failedIconColor: $failedIconColor)';
}


}

/// @nodoc
abstract mixin class _$ChatBubbleThemeCopyWith<$Res> implements $ChatBubbleThemeCopyWith<$Res> {
  factory _$ChatBubbleThemeCopyWith(_ChatBubbleTheme value, $Res Function(_ChatBubbleTheme) _then) = __$ChatBubbleThemeCopyWithImpl;
@override @useResult
$Res call({
 Color? outgoingColor, Color? incomingColor, TextStyle? outgoingTextStyle, TextStyle? incomingTextStyle, BorderRadius? borderRadius, TextStyle? timestampStyle, TextStyle? outgoingTimestampStyle, TextStyle? incomingTimestampStyle, Color? statusColor, Color? statusReadColor, Color? mentionColor, TextStyle? editedLabelStyle, Color? forwardedLabelColor, TextStyle? forwardedLabelStyle, TextStyle? senderNameStyle, Color? failedIconColor
});




}
/// @nodoc
class __$ChatBubbleThemeCopyWithImpl<$Res>
    implements _$ChatBubbleThemeCopyWith<$Res> {
  __$ChatBubbleThemeCopyWithImpl(this._self, this._then);

  final _ChatBubbleTheme _self;
  final $Res Function(_ChatBubbleTheme) _then;

/// Create a copy of ChatBubbleTheme
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? outgoingColor = freezed,Object? incomingColor = freezed,Object? outgoingTextStyle = freezed,Object? incomingTextStyle = freezed,Object? borderRadius = freezed,Object? timestampStyle = freezed,Object? outgoingTimestampStyle = freezed,Object? incomingTimestampStyle = freezed,Object? statusColor = freezed,Object? statusReadColor = freezed,Object? mentionColor = freezed,Object? editedLabelStyle = freezed,Object? forwardedLabelColor = freezed,Object? forwardedLabelStyle = freezed,Object? senderNameStyle = freezed,Object? failedIconColor = freezed,}) {
  return _then(_ChatBubbleTheme(
outgoingColor: freezed == outgoingColor ? _self.outgoingColor : outgoingColor // ignore: cast_nullable_to_non_nullable
as Color?,incomingColor: freezed == incomingColor ? _self.incomingColor : incomingColor // ignore: cast_nullable_to_non_nullable
as Color?,outgoingTextStyle: freezed == outgoingTextStyle ? _self.outgoingTextStyle : outgoingTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,incomingTextStyle: freezed == incomingTextStyle ? _self.incomingTextStyle : incomingTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,borderRadius: freezed == borderRadius ? _self.borderRadius : borderRadius // ignore: cast_nullable_to_non_nullable
as BorderRadius?,timestampStyle: freezed == timestampStyle ? _self.timestampStyle : timestampStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,outgoingTimestampStyle: freezed == outgoingTimestampStyle ? _self.outgoingTimestampStyle : outgoingTimestampStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,incomingTimestampStyle: freezed == incomingTimestampStyle ? _self.incomingTimestampStyle : incomingTimestampStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,statusColor: freezed == statusColor ? _self.statusColor : statusColor // ignore: cast_nullable_to_non_nullable
as Color?,statusReadColor: freezed == statusReadColor ? _self.statusReadColor : statusReadColor // ignore: cast_nullable_to_non_nullable
as Color?,mentionColor: freezed == mentionColor ? _self.mentionColor : mentionColor // ignore: cast_nullable_to_non_nullable
as Color?,editedLabelStyle: freezed == editedLabelStyle ? _self.editedLabelStyle : editedLabelStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,forwardedLabelColor: freezed == forwardedLabelColor ? _self.forwardedLabelColor : forwardedLabelColor // ignore: cast_nullable_to_non_nullable
as Color?,forwardedLabelStyle: freezed == forwardedLabelStyle ? _self.forwardedLabelStyle : forwardedLabelStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,senderNameStyle: freezed == senderNameStyle ? _self.senderNameStyle : senderNameStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,failedIconColor: freezed == failedIconColor ? _self.failedIconColor : failedIconColor // ignore: cast_nullable_to_non_nullable
as Color?,
  ));
}


}

// dart format on
