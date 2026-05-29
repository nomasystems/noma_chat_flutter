// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'markdown_theme.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ChatMarkdownTheme {

/// Style applied to `*bold*` / `**bold**` tokens.
 TextStyle? get boldStyle;/// Style applied to `_italic_` tokens.
 TextStyle? get italicStyle;/// Style applied to inline `` `code` `` tokens. The default sets a
/// monospace family and a subtle background.
 TextStyle? get codeStyle;/// Style applied to `~~strikethrough~~` tokens.
 TextStyle? get strikethroughStyle;/// Style applied to bare URLs (`http://...` / `https://...`).
 TextStyle? get linkStyle;/// Style applied to `@mentions`. Falls back to [ChatBubbleTheme.mentionColor]
/// when null.
 TextStyle? get mentionStyle;
/// Create a copy of ChatMarkdownTheme
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatMarkdownThemeCopyWith<ChatMarkdownTheme> get copyWith => _$ChatMarkdownThemeCopyWithImpl<ChatMarkdownTheme>(this as ChatMarkdownTheme, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatMarkdownTheme&&(identical(other.boldStyle, boldStyle) || other.boldStyle == boldStyle)&&(identical(other.italicStyle, italicStyle) || other.italicStyle == italicStyle)&&(identical(other.codeStyle, codeStyle) || other.codeStyle == codeStyle)&&(identical(other.strikethroughStyle, strikethroughStyle) || other.strikethroughStyle == strikethroughStyle)&&(identical(other.linkStyle, linkStyle) || other.linkStyle == linkStyle)&&(identical(other.mentionStyle, mentionStyle) || other.mentionStyle == mentionStyle));
}


@override
int get hashCode => Object.hash(runtimeType,boldStyle,italicStyle,codeStyle,strikethroughStyle,linkStyle,mentionStyle);

@override
String toString() {
  return 'ChatMarkdownTheme(boldStyle: $boldStyle, italicStyle: $italicStyle, codeStyle: $codeStyle, strikethroughStyle: $strikethroughStyle, linkStyle: $linkStyle, mentionStyle: $mentionStyle)';
}


}

/// @nodoc
abstract mixin class $ChatMarkdownThemeCopyWith<$Res>  {
  factory $ChatMarkdownThemeCopyWith(ChatMarkdownTheme value, $Res Function(ChatMarkdownTheme) _then) = _$ChatMarkdownThemeCopyWithImpl;
@useResult
$Res call({
 TextStyle? boldStyle, TextStyle? italicStyle, TextStyle? codeStyle, TextStyle? strikethroughStyle, TextStyle? linkStyle, TextStyle? mentionStyle
});




}
/// @nodoc
class _$ChatMarkdownThemeCopyWithImpl<$Res>
    implements $ChatMarkdownThemeCopyWith<$Res> {
  _$ChatMarkdownThemeCopyWithImpl(this._self, this._then);

  final ChatMarkdownTheme _self;
  final $Res Function(ChatMarkdownTheme) _then;

/// Create a copy of ChatMarkdownTheme
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? boldStyle = freezed,Object? italicStyle = freezed,Object? codeStyle = freezed,Object? strikethroughStyle = freezed,Object? linkStyle = freezed,Object? mentionStyle = freezed,}) {
  return _then(_self.copyWith(
boldStyle: freezed == boldStyle ? _self.boldStyle : boldStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,italicStyle: freezed == italicStyle ? _self.italicStyle : italicStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,codeStyle: freezed == codeStyle ? _self.codeStyle : codeStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,strikethroughStyle: freezed == strikethroughStyle ? _self.strikethroughStyle : strikethroughStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,linkStyle: freezed == linkStyle ? _self.linkStyle : linkStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,mentionStyle: freezed == mentionStyle ? _self.mentionStyle : mentionStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,
  ));
}

}


/// Adds pattern-matching-related methods to [ChatMarkdownTheme].
extension ChatMarkdownThemePatterns on ChatMarkdownTheme {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatMarkdownTheme value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatMarkdownTheme() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatMarkdownTheme value)  $default,){
final _that = this;
switch (_that) {
case _ChatMarkdownTheme():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatMarkdownTheme value)?  $default,){
final _that = this;
switch (_that) {
case _ChatMarkdownTheme() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TextStyle? boldStyle,  TextStyle? italicStyle,  TextStyle? codeStyle,  TextStyle? strikethroughStyle,  TextStyle? linkStyle,  TextStyle? mentionStyle)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatMarkdownTheme() when $default != null:
return $default(_that.boldStyle,_that.italicStyle,_that.codeStyle,_that.strikethroughStyle,_that.linkStyle,_that.mentionStyle);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TextStyle? boldStyle,  TextStyle? italicStyle,  TextStyle? codeStyle,  TextStyle? strikethroughStyle,  TextStyle? linkStyle,  TextStyle? mentionStyle)  $default,) {final _that = this;
switch (_that) {
case _ChatMarkdownTheme():
return $default(_that.boldStyle,_that.italicStyle,_that.codeStyle,_that.strikethroughStyle,_that.linkStyle,_that.mentionStyle);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TextStyle? boldStyle,  TextStyle? italicStyle,  TextStyle? codeStyle,  TextStyle? strikethroughStyle,  TextStyle? linkStyle,  TextStyle? mentionStyle)?  $default,) {final _that = this;
switch (_that) {
case _ChatMarkdownTheme() when $default != null:
return $default(_that.boldStyle,_that.italicStyle,_that.codeStyle,_that.strikethroughStyle,_that.linkStyle,_that.mentionStyle);case _:
  return null;

}
}

}

/// @nodoc


class _ChatMarkdownTheme implements ChatMarkdownTheme {
  const _ChatMarkdownTheme({this.boldStyle, this.italicStyle, this.codeStyle, this.strikethroughStyle, this.linkStyle, this.mentionStyle});
  

/// Style applied to `*bold*` / `**bold**` tokens.
@override final  TextStyle? boldStyle;
/// Style applied to `_italic_` tokens.
@override final  TextStyle? italicStyle;
/// Style applied to inline `` `code` `` tokens. The default sets a
/// monospace family and a subtle background.
@override final  TextStyle? codeStyle;
/// Style applied to `~~strikethrough~~` tokens.
@override final  TextStyle? strikethroughStyle;
/// Style applied to bare URLs (`http://...` / `https://...`).
@override final  TextStyle? linkStyle;
/// Style applied to `@mentions`. Falls back to [ChatBubbleTheme.mentionColor]
/// when null.
@override final  TextStyle? mentionStyle;

/// Create a copy of ChatMarkdownTheme
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatMarkdownThemeCopyWith<_ChatMarkdownTheme> get copyWith => __$ChatMarkdownThemeCopyWithImpl<_ChatMarkdownTheme>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatMarkdownTheme&&(identical(other.boldStyle, boldStyle) || other.boldStyle == boldStyle)&&(identical(other.italicStyle, italicStyle) || other.italicStyle == italicStyle)&&(identical(other.codeStyle, codeStyle) || other.codeStyle == codeStyle)&&(identical(other.strikethroughStyle, strikethroughStyle) || other.strikethroughStyle == strikethroughStyle)&&(identical(other.linkStyle, linkStyle) || other.linkStyle == linkStyle)&&(identical(other.mentionStyle, mentionStyle) || other.mentionStyle == mentionStyle));
}


@override
int get hashCode => Object.hash(runtimeType,boldStyle,italicStyle,codeStyle,strikethroughStyle,linkStyle,mentionStyle);

@override
String toString() {
  return 'ChatMarkdownTheme(boldStyle: $boldStyle, italicStyle: $italicStyle, codeStyle: $codeStyle, strikethroughStyle: $strikethroughStyle, linkStyle: $linkStyle, mentionStyle: $mentionStyle)';
}


}

/// @nodoc
abstract mixin class _$ChatMarkdownThemeCopyWith<$Res> implements $ChatMarkdownThemeCopyWith<$Res> {
  factory _$ChatMarkdownThemeCopyWith(_ChatMarkdownTheme value, $Res Function(_ChatMarkdownTheme) _then) = __$ChatMarkdownThemeCopyWithImpl;
@override @useResult
$Res call({
 TextStyle? boldStyle, TextStyle? italicStyle, TextStyle? codeStyle, TextStyle? strikethroughStyle, TextStyle? linkStyle, TextStyle? mentionStyle
});




}
/// @nodoc
class __$ChatMarkdownThemeCopyWithImpl<$Res>
    implements _$ChatMarkdownThemeCopyWith<$Res> {
  __$ChatMarkdownThemeCopyWithImpl(this._self, this._then);

  final _ChatMarkdownTheme _self;
  final $Res Function(_ChatMarkdownTheme) _then;

/// Create a copy of ChatMarkdownTheme
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? boldStyle = freezed,Object? italicStyle = freezed,Object? codeStyle = freezed,Object? strikethroughStyle = freezed,Object? linkStyle = freezed,Object? mentionStyle = freezed,}) {
  return _then(_ChatMarkdownTheme(
boldStyle: freezed == boldStyle ? _self.boldStyle : boldStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,italicStyle: freezed == italicStyle ? _self.italicStyle : italicStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,codeStyle: freezed == codeStyle ? _self.codeStyle : codeStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,strikethroughStyle: freezed == strikethroughStyle ? _self.strikethroughStyle : strikethroughStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,linkStyle: freezed == linkStyle ? _self.linkStyle : linkStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,mentionStyle: freezed == mentionStyle ? _self.mentionStyle : mentionStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,
  ));
}


}

// dart format on
