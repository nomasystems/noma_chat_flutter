// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'unread_room.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UnreadRoom {

 String get roomId; int get unreadMessages; String? get lastMessage; DateTime? get lastMessageTime; String? get lastMessageUserId; String? get lastMessageId; String? get name; String? get avatarUrl; String? get type; int? get memberCount; RoomRole? get userRole; bool get muted; bool get pinned;
/// Create a copy of UnreadRoom
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnreadRoomCopyWith<UnreadRoom> get copyWith => _$UnreadRoomCopyWithImpl<UnreadRoom>(this as UnreadRoom, _$identity);





@override
String toString() {
  return 'UnreadRoom(roomId: $roomId, unreadMessages: $unreadMessages, lastMessage: $lastMessage, lastMessageTime: $lastMessageTime, lastMessageUserId: $lastMessageUserId, lastMessageId: $lastMessageId, name: $name, avatarUrl: $avatarUrl, type: $type, memberCount: $memberCount, userRole: $userRole, muted: $muted, pinned: $pinned)';
}


}

/// @nodoc
abstract mixin class $UnreadRoomCopyWith<$Res>  {
  factory $UnreadRoomCopyWith(UnreadRoom value, $Res Function(UnreadRoom) _then) = _$UnreadRoomCopyWithImpl;
@useResult
$Res call({
 String roomId, int unreadMessages, String? lastMessage, DateTime? lastMessageTime, String? lastMessageUserId, String? lastMessageId, String? name, String? avatarUrl, String? type, int? memberCount, RoomRole? userRole, bool muted, bool pinned
});




}
/// @nodoc
class _$UnreadRoomCopyWithImpl<$Res>
    implements $UnreadRoomCopyWith<$Res> {
  _$UnreadRoomCopyWithImpl(this._self, this._then);

  final UnreadRoom _self;
  final $Res Function(UnreadRoom) _then;

/// Create a copy of UnreadRoom
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? roomId = null,Object? unreadMessages = null,Object? lastMessage = freezed,Object? lastMessageTime = freezed,Object? lastMessageUserId = freezed,Object? lastMessageId = freezed,Object? name = freezed,Object? avatarUrl = freezed,Object? type = freezed,Object? memberCount = freezed,Object? userRole = freezed,Object? muted = null,Object? pinned = null,}) {
  return _then(_self.copyWith(
roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,unreadMessages: null == unreadMessages ? _self.unreadMessages : unreadMessages // ignore: cast_nullable_to_non_nullable
as int,lastMessage: freezed == lastMessage ? _self.lastMessage : lastMessage // ignore: cast_nullable_to_non_nullable
as String?,lastMessageTime: freezed == lastMessageTime ? _self.lastMessageTime : lastMessageTime // ignore: cast_nullable_to_non_nullable
as DateTime?,lastMessageUserId: freezed == lastMessageUserId ? _self.lastMessageUserId : lastMessageUserId // ignore: cast_nullable_to_non_nullable
as String?,lastMessageId: freezed == lastMessageId ? _self.lastMessageId : lastMessageId // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,type: freezed == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String?,memberCount: freezed == memberCount ? _self.memberCount : memberCount // ignore: cast_nullable_to_non_nullable
as int?,userRole: freezed == userRole ? _self.userRole : userRole // ignore: cast_nullable_to_non_nullable
as RoomRole?,muted: null == muted ? _self.muted : muted // ignore: cast_nullable_to_non_nullable
as bool,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [UnreadRoom].
extension UnreadRoomPatterns on UnreadRoom {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UnreadRoom value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UnreadRoom() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UnreadRoom value)  $default,){
final _that = this;
switch (_that) {
case _UnreadRoom():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UnreadRoom value)?  $default,){
final _that = this;
switch (_that) {
case _UnreadRoom() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String roomId,  int unreadMessages,  String? lastMessage,  DateTime? lastMessageTime,  String? lastMessageUserId,  String? lastMessageId,  String? name,  String? avatarUrl,  String? type,  int? memberCount,  RoomRole? userRole,  bool muted,  bool pinned)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UnreadRoom() when $default != null:
return $default(_that.roomId,_that.unreadMessages,_that.lastMessage,_that.lastMessageTime,_that.lastMessageUserId,_that.lastMessageId,_that.name,_that.avatarUrl,_that.type,_that.memberCount,_that.userRole,_that.muted,_that.pinned);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String roomId,  int unreadMessages,  String? lastMessage,  DateTime? lastMessageTime,  String? lastMessageUserId,  String? lastMessageId,  String? name,  String? avatarUrl,  String? type,  int? memberCount,  RoomRole? userRole,  bool muted,  bool pinned)  $default,) {final _that = this;
switch (_that) {
case _UnreadRoom():
return $default(_that.roomId,_that.unreadMessages,_that.lastMessage,_that.lastMessageTime,_that.lastMessageUserId,_that.lastMessageId,_that.name,_that.avatarUrl,_that.type,_that.memberCount,_that.userRole,_that.muted,_that.pinned);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String roomId,  int unreadMessages,  String? lastMessage,  DateTime? lastMessageTime,  String? lastMessageUserId,  String? lastMessageId,  String? name,  String? avatarUrl,  String? type,  int? memberCount,  RoomRole? userRole,  bool muted,  bool pinned)?  $default,) {final _that = this;
switch (_that) {
case _UnreadRoom() when $default != null:
return $default(_that.roomId,_that.unreadMessages,_that.lastMessage,_that.lastMessageTime,_that.lastMessageUserId,_that.lastMessageId,_that.name,_that.avatarUrl,_that.type,_that.memberCount,_that.userRole,_that.muted,_that.pinned);case _:
  return null;

}
}

}

/// @nodoc


class _UnreadRoom extends UnreadRoom {
  const _UnreadRoom({required this.roomId, required this.unreadMessages, this.lastMessage, this.lastMessageTime, this.lastMessageUserId, this.lastMessageId, this.name, this.avatarUrl, this.type, this.memberCount, this.userRole, this.muted = false, this.pinned = false}): super._();
  

@override final  String roomId;
@override final  int unreadMessages;
@override final  String? lastMessage;
@override final  DateTime? lastMessageTime;
@override final  String? lastMessageUserId;
@override final  String? lastMessageId;
@override final  String? name;
@override final  String? avatarUrl;
@override final  String? type;
@override final  int? memberCount;
@override final  RoomRole? userRole;
@override@JsonKey() final  bool muted;
@override@JsonKey() final  bool pinned;

/// Create a copy of UnreadRoom
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UnreadRoomCopyWith<_UnreadRoom> get copyWith => __$UnreadRoomCopyWithImpl<_UnreadRoom>(this, _$identity);





@override
String toString() {
  return 'UnreadRoom(roomId: $roomId, unreadMessages: $unreadMessages, lastMessage: $lastMessage, lastMessageTime: $lastMessageTime, lastMessageUserId: $lastMessageUserId, lastMessageId: $lastMessageId, name: $name, avatarUrl: $avatarUrl, type: $type, memberCount: $memberCount, userRole: $userRole, muted: $muted, pinned: $pinned)';
}


}

/// @nodoc
abstract mixin class _$UnreadRoomCopyWith<$Res> implements $UnreadRoomCopyWith<$Res> {
  factory _$UnreadRoomCopyWith(_UnreadRoom value, $Res Function(_UnreadRoom) _then) = __$UnreadRoomCopyWithImpl;
@override @useResult
$Res call({
 String roomId, int unreadMessages, String? lastMessage, DateTime? lastMessageTime, String? lastMessageUserId, String? lastMessageId, String? name, String? avatarUrl, String? type, int? memberCount, RoomRole? userRole, bool muted, bool pinned
});




}
/// @nodoc
class __$UnreadRoomCopyWithImpl<$Res>
    implements _$UnreadRoomCopyWith<$Res> {
  __$UnreadRoomCopyWithImpl(this._self, this._then);

  final _UnreadRoom _self;
  final $Res Function(_UnreadRoom) _then;

/// Create a copy of UnreadRoom
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? roomId = null,Object? unreadMessages = null,Object? lastMessage = freezed,Object? lastMessageTime = freezed,Object? lastMessageUserId = freezed,Object? lastMessageId = freezed,Object? name = freezed,Object? avatarUrl = freezed,Object? type = freezed,Object? memberCount = freezed,Object? userRole = freezed,Object? muted = null,Object? pinned = null,}) {
  return _then(_UnreadRoom(
roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,unreadMessages: null == unreadMessages ? _self.unreadMessages : unreadMessages // ignore: cast_nullable_to_non_nullable
as int,lastMessage: freezed == lastMessage ? _self.lastMessage : lastMessage // ignore: cast_nullable_to_non_nullable
as String?,lastMessageTime: freezed == lastMessageTime ? _self.lastMessageTime : lastMessageTime // ignore: cast_nullable_to_non_nullable
as DateTime?,lastMessageUserId: freezed == lastMessageUserId ? _self.lastMessageUserId : lastMessageUserId // ignore: cast_nullable_to_non_nullable
as String?,lastMessageId: freezed == lastMessageId ? _self.lastMessageId : lastMessageId // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,type: freezed == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String?,memberCount: freezed == memberCount ? _self.memberCount : memberCount // ignore: cast_nullable_to_non_nullable
as int?,userRole: freezed == userRole ? _self.userRole : userRole // ignore: cast_nullable_to_non_nullable
as RoomRole?,muted: null == muted ? _self.muted : muted // ignore: cast_nullable_to_non_nullable
as bool,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
