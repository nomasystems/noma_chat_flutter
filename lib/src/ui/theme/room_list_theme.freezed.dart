// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'room_list_theme.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ChatRoomListTheme {

/// Background of an idle room tile.
 Color? get tileBackgroundColor;/// Background applied when the tile is highlighted (active route in a
/// master-detail layout, or pressed state).
 Color? get tileSelectedColor;/// Style of the room name (top line).
 TextStyle? get nameStyle;/// Style of the last-message preview (bottom line) for rooms with no
/// unread messages.
 TextStyle? get previewStyle;/// Style of the last-message preview when the room has >=1 unread
/// messages. Usually bolder to draw attention.
 TextStyle? get previewUnreadStyle;/// Style of the trailing timestamp (right side) for rooms with no
/// unread messages.
 TextStyle? get timestampStyle;/// Style of the trailing timestamp when the room has >=1 unread.
/// Usually coloured to match the badge.
 TextStyle? get timestampUnreadStyle;/// Background of the unread count badge.
 Color? get unreadBadgeColor;/// Text style inside the unread count badge.
 TextStyle? get unreadBadgeTextStyle;/// Tint of the "muted" icon shown next to muted rooms.
 Color? get mutedIconColor;/// Tint of the "pinned" icon shown next to pinned rooms.
 Color? get pinnedIconColor;/// Style of the title above the contact-suggestions strip.
 TextStyle? get suggestionsTitleStyle;/// Style of the contact name chips inside the suggestions strip.
 TextStyle? get suggestionsNameStyle;/// Background of the search bar at the top of the room list.
 Color? get searchBackgroundColor;/// Style of the search field text.
 TextStyle? get searchTextStyle;/// Style of the section headers ("Chats", "Channels", ...).
 TextStyle? get headerStyle;/// Style of a section header when its tab is selected.
 TextStyle? get headerSelectedStyle;
/// Create a copy of ChatRoomListTheme
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatRoomListThemeCopyWith<ChatRoomListTheme> get copyWith => _$ChatRoomListThemeCopyWithImpl<ChatRoomListTheme>(this as ChatRoomListTheme, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatRoomListTheme&&(identical(other.tileBackgroundColor, tileBackgroundColor) || other.tileBackgroundColor == tileBackgroundColor)&&(identical(other.tileSelectedColor, tileSelectedColor) || other.tileSelectedColor == tileSelectedColor)&&(identical(other.nameStyle, nameStyle) || other.nameStyle == nameStyle)&&(identical(other.previewStyle, previewStyle) || other.previewStyle == previewStyle)&&(identical(other.previewUnreadStyle, previewUnreadStyle) || other.previewUnreadStyle == previewUnreadStyle)&&(identical(other.timestampStyle, timestampStyle) || other.timestampStyle == timestampStyle)&&(identical(other.timestampUnreadStyle, timestampUnreadStyle) || other.timestampUnreadStyle == timestampUnreadStyle)&&(identical(other.unreadBadgeColor, unreadBadgeColor) || other.unreadBadgeColor == unreadBadgeColor)&&(identical(other.unreadBadgeTextStyle, unreadBadgeTextStyle) || other.unreadBadgeTextStyle == unreadBadgeTextStyle)&&(identical(other.mutedIconColor, mutedIconColor) || other.mutedIconColor == mutedIconColor)&&(identical(other.pinnedIconColor, pinnedIconColor) || other.pinnedIconColor == pinnedIconColor)&&(identical(other.suggestionsTitleStyle, suggestionsTitleStyle) || other.suggestionsTitleStyle == suggestionsTitleStyle)&&(identical(other.suggestionsNameStyle, suggestionsNameStyle) || other.suggestionsNameStyle == suggestionsNameStyle)&&(identical(other.searchBackgroundColor, searchBackgroundColor) || other.searchBackgroundColor == searchBackgroundColor)&&(identical(other.searchTextStyle, searchTextStyle) || other.searchTextStyle == searchTextStyle)&&(identical(other.headerStyle, headerStyle) || other.headerStyle == headerStyle)&&(identical(other.headerSelectedStyle, headerSelectedStyle) || other.headerSelectedStyle == headerSelectedStyle));
}


@override
int get hashCode => Object.hash(runtimeType,tileBackgroundColor,tileSelectedColor,nameStyle,previewStyle,previewUnreadStyle,timestampStyle,timestampUnreadStyle,unreadBadgeColor,unreadBadgeTextStyle,mutedIconColor,pinnedIconColor,suggestionsTitleStyle,suggestionsNameStyle,searchBackgroundColor,searchTextStyle,headerStyle,headerSelectedStyle);

@override
String toString() {
  return 'ChatRoomListTheme(tileBackgroundColor: $tileBackgroundColor, tileSelectedColor: $tileSelectedColor, nameStyle: $nameStyle, previewStyle: $previewStyle, previewUnreadStyle: $previewUnreadStyle, timestampStyle: $timestampStyle, timestampUnreadStyle: $timestampUnreadStyle, unreadBadgeColor: $unreadBadgeColor, unreadBadgeTextStyle: $unreadBadgeTextStyle, mutedIconColor: $mutedIconColor, pinnedIconColor: $pinnedIconColor, suggestionsTitleStyle: $suggestionsTitleStyle, suggestionsNameStyle: $suggestionsNameStyle, searchBackgroundColor: $searchBackgroundColor, searchTextStyle: $searchTextStyle, headerStyle: $headerStyle, headerSelectedStyle: $headerSelectedStyle)';
}


}

/// @nodoc
abstract mixin class $ChatRoomListThemeCopyWith<$Res>  {
  factory $ChatRoomListThemeCopyWith(ChatRoomListTheme value, $Res Function(ChatRoomListTheme) _then) = _$ChatRoomListThemeCopyWithImpl;
@useResult
$Res call({
 Color? tileBackgroundColor, Color? tileSelectedColor, TextStyle? nameStyle, TextStyle? previewStyle, TextStyle? previewUnreadStyle, TextStyle? timestampStyle, TextStyle? timestampUnreadStyle, Color? unreadBadgeColor, TextStyle? unreadBadgeTextStyle, Color? mutedIconColor, Color? pinnedIconColor, TextStyle? suggestionsTitleStyle, TextStyle? suggestionsNameStyle, Color? searchBackgroundColor, TextStyle? searchTextStyle, TextStyle? headerStyle, TextStyle? headerSelectedStyle
});




}
/// @nodoc
class _$ChatRoomListThemeCopyWithImpl<$Res>
    implements $ChatRoomListThemeCopyWith<$Res> {
  _$ChatRoomListThemeCopyWithImpl(this._self, this._then);

  final ChatRoomListTheme _self;
  final $Res Function(ChatRoomListTheme) _then;

/// Create a copy of ChatRoomListTheme
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? tileBackgroundColor = freezed,Object? tileSelectedColor = freezed,Object? nameStyle = freezed,Object? previewStyle = freezed,Object? previewUnreadStyle = freezed,Object? timestampStyle = freezed,Object? timestampUnreadStyle = freezed,Object? unreadBadgeColor = freezed,Object? unreadBadgeTextStyle = freezed,Object? mutedIconColor = freezed,Object? pinnedIconColor = freezed,Object? suggestionsTitleStyle = freezed,Object? suggestionsNameStyle = freezed,Object? searchBackgroundColor = freezed,Object? searchTextStyle = freezed,Object? headerStyle = freezed,Object? headerSelectedStyle = freezed,}) {
  return _then(_self.copyWith(
tileBackgroundColor: freezed == tileBackgroundColor ? _self.tileBackgroundColor : tileBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,tileSelectedColor: freezed == tileSelectedColor ? _self.tileSelectedColor : tileSelectedColor // ignore: cast_nullable_to_non_nullable
as Color?,nameStyle: freezed == nameStyle ? _self.nameStyle : nameStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,previewStyle: freezed == previewStyle ? _self.previewStyle : previewStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,previewUnreadStyle: freezed == previewUnreadStyle ? _self.previewUnreadStyle : previewUnreadStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,timestampStyle: freezed == timestampStyle ? _self.timestampStyle : timestampStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,timestampUnreadStyle: freezed == timestampUnreadStyle ? _self.timestampUnreadStyle : timestampUnreadStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,unreadBadgeColor: freezed == unreadBadgeColor ? _self.unreadBadgeColor : unreadBadgeColor // ignore: cast_nullable_to_non_nullable
as Color?,unreadBadgeTextStyle: freezed == unreadBadgeTextStyle ? _self.unreadBadgeTextStyle : unreadBadgeTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,mutedIconColor: freezed == mutedIconColor ? _self.mutedIconColor : mutedIconColor // ignore: cast_nullable_to_non_nullable
as Color?,pinnedIconColor: freezed == pinnedIconColor ? _self.pinnedIconColor : pinnedIconColor // ignore: cast_nullable_to_non_nullable
as Color?,suggestionsTitleStyle: freezed == suggestionsTitleStyle ? _self.suggestionsTitleStyle : suggestionsTitleStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,suggestionsNameStyle: freezed == suggestionsNameStyle ? _self.suggestionsNameStyle : suggestionsNameStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,searchBackgroundColor: freezed == searchBackgroundColor ? _self.searchBackgroundColor : searchBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,searchTextStyle: freezed == searchTextStyle ? _self.searchTextStyle : searchTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,headerStyle: freezed == headerStyle ? _self.headerStyle : headerStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,headerSelectedStyle: freezed == headerSelectedStyle ? _self.headerSelectedStyle : headerSelectedStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,
  ));
}

}


/// Adds pattern-matching-related methods to [ChatRoomListTheme].
extension ChatRoomListThemePatterns on ChatRoomListTheme {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatRoomListTheme value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatRoomListTheme() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatRoomListTheme value)  $default,){
final _that = this;
switch (_that) {
case _ChatRoomListTheme():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatRoomListTheme value)?  $default,){
final _that = this;
switch (_that) {
case _ChatRoomListTheme() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Color? tileBackgroundColor,  Color? tileSelectedColor,  TextStyle? nameStyle,  TextStyle? previewStyle,  TextStyle? previewUnreadStyle,  TextStyle? timestampStyle,  TextStyle? timestampUnreadStyle,  Color? unreadBadgeColor,  TextStyle? unreadBadgeTextStyle,  Color? mutedIconColor,  Color? pinnedIconColor,  TextStyle? suggestionsTitleStyle,  TextStyle? suggestionsNameStyle,  Color? searchBackgroundColor,  TextStyle? searchTextStyle,  TextStyle? headerStyle,  TextStyle? headerSelectedStyle)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatRoomListTheme() when $default != null:
return $default(_that.tileBackgroundColor,_that.tileSelectedColor,_that.nameStyle,_that.previewStyle,_that.previewUnreadStyle,_that.timestampStyle,_that.timestampUnreadStyle,_that.unreadBadgeColor,_that.unreadBadgeTextStyle,_that.mutedIconColor,_that.pinnedIconColor,_that.suggestionsTitleStyle,_that.suggestionsNameStyle,_that.searchBackgroundColor,_that.searchTextStyle,_that.headerStyle,_that.headerSelectedStyle);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Color? tileBackgroundColor,  Color? tileSelectedColor,  TextStyle? nameStyle,  TextStyle? previewStyle,  TextStyle? previewUnreadStyle,  TextStyle? timestampStyle,  TextStyle? timestampUnreadStyle,  Color? unreadBadgeColor,  TextStyle? unreadBadgeTextStyle,  Color? mutedIconColor,  Color? pinnedIconColor,  TextStyle? suggestionsTitleStyle,  TextStyle? suggestionsNameStyle,  Color? searchBackgroundColor,  TextStyle? searchTextStyle,  TextStyle? headerStyle,  TextStyle? headerSelectedStyle)  $default,) {final _that = this;
switch (_that) {
case _ChatRoomListTheme():
return $default(_that.tileBackgroundColor,_that.tileSelectedColor,_that.nameStyle,_that.previewStyle,_that.previewUnreadStyle,_that.timestampStyle,_that.timestampUnreadStyle,_that.unreadBadgeColor,_that.unreadBadgeTextStyle,_that.mutedIconColor,_that.pinnedIconColor,_that.suggestionsTitleStyle,_that.suggestionsNameStyle,_that.searchBackgroundColor,_that.searchTextStyle,_that.headerStyle,_that.headerSelectedStyle);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Color? tileBackgroundColor,  Color? tileSelectedColor,  TextStyle? nameStyle,  TextStyle? previewStyle,  TextStyle? previewUnreadStyle,  TextStyle? timestampStyle,  TextStyle? timestampUnreadStyle,  Color? unreadBadgeColor,  TextStyle? unreadBadgeTextStyle,  Color? mutedIconColor,  Color? pinnedIconColor,  TextStyle? suggestionsTitleStyle,  TextStyle? suggestionsNameStyle,  Color? searchBackgroundColor,  TextStyle? searchTextStyle,  TextStyle? headerStyle,  TextStyle? headerSelectedStyle)?  $default,) {final _that = this;
switch (_that) {
case _ChatRoomListTheme() when $default != null:
return $default(_that.tileBackgroundColor,_that.tileSelectedColor,_that.nameStyle,_that.previewStyle,_that.previewUnreadStyle,_that.timestampStyle,_that.timestampUnreadStyle,_that.unreadBadgeColor,_that.unreadBadgeTextStyle,_that.mutedIconColor,_that.pinnedIconColor,_that.suggestionsTitleStyle,_that.suggestionsNameStyle,_that.searchBackgroundColor,_that.searchTextStyle,_that.headerStyle,_that.headerSelectedStyle);case _:
  return null;

}
}

}

/// @nodoc


class _ChatRoomListTheme implements ChatRoomListTheme {
  const _ChatRoomListTheme({this.tileBackgroundColor, this.tileSelectedColor, this.nameStyle, this.previewStyle, this.previewUnreadStyle, this.timestampStyle, this.timestampUnreadStyle, this.unreadBadgeColor, this.unreadBadgeTextStyle, this.mutedIconColor, this.pinnedIconColor, this.suggestionsTitleStyle, this.suggestionsNameStyle, this.searchBackgroundColor, this.searchTextStyle, this.headerStyle, this.headerSelectedStyle});
  

/// Background of an idle room tile.
@override final  Color? tileBackgroundColor;
/// Background applied when the tile is highlighted (active route in a
/// master-detail layout, or pressed state).
@override final  Color? tileSelectedColor;
/// Style of the room name (top line).
@override final  TextStyle? nameStyle;
/// Style of the last-message preview (bottom line) for rooms with no
/// unread messages.
@override final  TextStyle? previewStyle;
/// Style of the last-message preview when the room has >=1 unread
/// messages. Usually bolder to draw attention.
@override final  TextStyle? previewUnreadStyle;
/// Style of the trailing timestamp (right side) for rooms with no
/// unread messages.
@override final  TextStyle? timestampStyle;
/// Style of the trailing timestamp when the room has >=1 unread.
/// Usually coloured to match the badge.
@override final  TextStyle? timestampUnreadStyle;
/// Background of the unread count badge.
@override final  Color? unreadBadgeColor;
/// Text style inside the unread count badge.
@override final  TextStyle? unreadBadgeTextStyle;
/// Tint of the "muted" icon shown next to muted rooms.
@override final  Color? mutedIconColor;
/// Tint of the "pinned" icon shown next to pinned rooms.
@override final  Color? pinnedIconColor;
/// Style of the title above the contact-suggestions strip.
@override final  TextStyle? suggestionsTitleStyle;
/// Style of the contact name chips inside the suggestions strip.
@override final  TextStyle? suggestionsNameStyle;
/// Background of the search bar at the top of the room list.
@override final  Color? searchBackgroundColor;
/// Style of the search field text.
@override final  TextStyle? searchTextStyle;
/// Style of the section headers ("Chats", "Channels", ...).
@override final  TextStyle? headerStyle;
/// Style of a section header when its tab is selected.
@override final  TextStyle? headerSelectedStyle;

/// Create a copy of ChatRoomListTheme
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatRoomListThemeCopyWith<_ChatRoomListTheme> get copyWith => __$ChatRoomListThemeCopyWithImpl<_ChatRoomListTheme>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatRoomListTheme&&(identical(other.tileBackgroundColor, tileBackgroundColor) || other.tileBackgroundColor == tileBackgroundColor)&&(identical(other.tileSelectedColor, tileSelectedColor) || other.tileSelectedColor == tileSelectedColor)&&(identical(other.nameStyle, nameStyle) || other.nameStyle == nameStyle)&&(identical(other.previewStyle, previewStyle) || other.previewStyle == previewStyle)&&(identical(other.previewUnreadStyle, previewUnreadStyle) || other.previewUnreadStyle == previewUnreadStyle)&&(identical(other.timestampStyle, timestampStyle) || other.timestampStyle == timestampStyle)&&(identical(other.timestampUnreadStyle, timestampUnreadStyle) || other.timestampUnreadStyle == timestampUnreadStyle)&&(identical(other.unreadBadgeColor, unreadBadgeColor) || other.unreadBadgeColor == unreadBadgeColor)&&(identical(other.unreadBadgeTextStyle, unreadBadgeTextStyle) || other.unreadBadgeTextStyle == unreadBadgeTextStyle)&&(identical(other.mutedIconColor, mutedIconColor) || other.mutedIconColor == mutedIconColor)&&(identical(other.pinnedIconColor, pinnedIconColor) || other.pinnedIconColor == pinnedIconColor)&&(identical(other.suggestionsTitleStyle, suggestionsTitleStyle) || other.suggestionsTitleStyle == suggestionsTitleStyle)&&(identical(other.suggestionsNameStyle, suggestionsNameStyle) || other.suggestionsNameStyle == suggestionsNameStyle)&&(identical(other.searchBackgroundColor, searchBackgroundColor) || other.searchBackgroundColor == searchBackgroundColor)&&(identical(other.searchTextStyle, searchTextStyle) || other.searchTextStyle == searchTextStyle)&&(identical(other.headerStyle, headerStyle) || other.headerStyle == headerStyle)&&(identical(other.headerSelectedStyle, headerSelectedStyle) || other.headerSelectedStyle == headerSelectedStyle));
}


@override
int get hashCode => Object.hash(runtimeType,tileBackgroundColor,tileSelectedColor,nameStyle,previewStyle,previewUnreadStyle,timestampStyle,timestampUnreadStyle,unreadBadgeColor,unreadBadgeTextStyle,mutedIconColor,pinnedIconColor,suggestionsTitleStyle,suggestionsNameStyle,searchBackgroundColor,searchTextStyle,headerStyle,headerSelectedStyle);

@override
String toString() {
  return 'ChatRoomListTheme(tileBackgroundColor: $tileBackgroundColor, tileSelectedColor: $tileSelectedColor, nameStyle: $nameStyle, previewStyle: $previewStyle, previewUnreadStyle: $previewUnreadStyle, timestampStyle: $timestampStyle, timestampUnreadStyle: $timestampUnreadStyle, unreadBadgeColor: $unreadBadgeColor, unreadBadgeTextStyle: $unreadBadgeTextStyle, mutedIconColor: $mutedIconColor, pinnedIconColor: $pinnedIconColor, suggestionsTitleStyle: $suggestionsTitleStyle, suggestionsNameStyle: $suggestionsNameStyle, searchBackgroundColor: $searchBackgroundColor, searchTextStyle: $searchTextStyle, headerStyle: $headerStyle, headerSelectedStyle: $headerSelectedStyle)';
}


}

/// @nodoc
abstract mixin class _$ChatRoomListThemeCopyWith<$Res> implements $ChatRoomListThemeCopyWith<$Res> {
  factory _$ChatRoomListThemeCopyWith(_ChatRoomListTheme value, $Res Function(_ChatRoomListTheme) _then) = __$ChatRoomListThemeCopyWithImpl;
@override @useResult
$Res call({
 Color? tileBackgroundColor, Color? tileSelectedColor, TextStyle? nameStyle, TextStyle? previewStyle, TextStyle? previewUnreadStyle, TextStyle? timestampStyle, TextStyle? timestampUnreadStyle, Color? unreadBadgeColor, TextStyle? unreadBadgeTextStyle, Color? mutedIconColor, Color? pinnedIconColor, TextStyle? suggestionsTitleStyle, TextStyle? suggestionsNameStyle, Color? searchBackgroundColor, TextStyle? searchTextStyle, TextStyle? headerStyle, TextStyle? headerSelectedStyle
});




}
/// @nodoc
class __$ChatRoomListThemeCopyWithImpl<$Res>
    implements _$ChatRoomListThemeCopyWith<$Res> {
  __$ChatRoomListThemeCopyWithImpl(this._self, this._then);

  final _ChatRoomListTheme _self;
  final $Res Function(_ChatRoomListTheme) _then;

/// Create a copy of ChatRoomListTheme
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? tileBackgroundColor = freezed,Object? tileSelectedColor = freezed,Object? nameStyle = freezed,Object? previewStyle = freezed,Object? previewUnreadStyle = freezed,Object? timestampStyle = freezed,Object? timestampUnreadStyle = freezed,Object? unreadBadgeColor = freezed,Object? unreadBadgeTextStyle = freezed,Object? mutedIconColor = freezed,Object? pinnedIconColor = freezed,Object? suggestionsTitleStyle = freezed,Object? suggestionsNameStyle = freezed,Object? searchBackgroundColor = freezed,Object? searchTextStyle = freezed,Object? headerStyle = freezed,Object? headerSelectedStyle = freezed,}) {
  return _then(_ChatRoomListTheme(
tileBackgroundColor: freezed == tileBackgroundColor ? _self.tileBackgroundColor : tileBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,tileSelectedColor: freezed == tileSelectedColor ? _self.tileSelectedColor : tileSelectedColor // ignore: cast_nullable_to_non_nullable
as Color?,nameStyle: freezed == nameStyle ? _self.nameStyle : nameStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,previewStyle: freezed == previewStyle ? _self.previewStyle : previewStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,previewUnreadStyle: freezed == previewUnreadStyle ? _self.previewUnreadStyle : previewUnreadStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,timestampStyle: freezed == timestampStyle ? _self.timestampStyle : timestampStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,timestampUnreadStyle: freezed == timestampUnreadStyle ? _self.timestampUnreadStyle : timestampUnreadStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,unreadBadgeColor: freezed == unreadBadgeColor ? _self.unreadBadgeColor : unreadBadgeColor // ignore: cast_nullable_to_non_nullable
as Color?,unreadBadgeTextStyle: freezed == unreadBadgeTextStyle ? _self.unreadBadgeTextStyle : unreadBadgeTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,mutedIconColor: freezed == mutedIconColor ? _self.mutedIconColor : mutedIconColor // ignore: cast_nullable_to_non_nullable
as Color?,pinnedIconColor: freezed == pinnedIconColor ? _self.pinnedIconColor : pinnedIconColor // ignore: cast_nullable_to_non_nullable
as Color?,suggestionsTitleStyle: freezed == suggestionsTitleStyle ? _self.suggestionsTitleStyle : suggestionsTitleStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,suggestionsNameStyle: freezed == suggestionsNameStyle ? _self.suggestionsNameStyle : suggestionsNameStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,searchBackgroundColor: freezed == searchBackgroundColor ? _self.searchBackgroundColor : searchBackgroundColor // ignore: cast_nullable_to_non_nullable
as Color?,searchTextStyle: freezed == searchTextStyle ? _self.searchTextStyle : searchTextStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,headerStyle: freezed == headerStyle ? _self.headerStyle : headerStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,headerSelectedStyle: freezed == headerSelectedStyle ? _self.headerSelectedStyle : headerSelectedStyle // ignore: cast_nullable_to_non_nullable
as TextStyle?,
  ));
}


}

// dart format on
