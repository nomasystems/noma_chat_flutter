// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'invited_room.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$InvitedRoom {

 String get roomId; String get invitedBy; String? get roomName; String? get subject; String? get roomType;
/// Create a copy of InvitedRoom
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InvitedRoomCopyWith<InvitedRoom> get copyWith => _$InvitedRoomCopyWithImpl<InvitedRoom>(this as InvitedRoom, _$identity);





@override
String toString() {
  return 'InvitedRoom(roomId: $roomId, invitedBy: $invitedBy, roomName: $roomName, subject: $subject, roomType: $roomType)';
}


}

/// @nodoc
abstract mixin class $InvitedRoomCopyWith<$Res>  {
  factory $InvitedRoomCopyWith(InvitedRoom value, $Res Function(InvitedRoom) _then) = _$InvitedRoomCopyWithImpl;
@useResult
$Res call({
 String roomId, String invitedBy, String? roomName, String? subject, String? roomType
});




}
/// @nodoc
class _$InvitedRoomCopyWithImpl<$Res>
    implements $InvitedRoomCopyWith<$Res> {
  _$InvitedRoomCopyWithImpl(this._self, this._then);

  final InvitedRoom _self;
  final $Res Function(InvitedRoom) _then;

/// Create a copy of InvitedRoom
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? roomId = null,Object? invitedBy = null,Object? roomName = freezed,Object? subject = freezed,Object? roomType = freezed,}) {
  return _then(_self.copyWith(
roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,invitedBy: null == invitedBy ? _self.invitedBy : invitedBy // ignore: cast_nullable_to_non_nullable
as String,roomName: freezed == roomName ? _self.roomName : roomName // ignore: cast_nullable_to_non_nullable
as String?,subject: freezed == subject ? _self.subject : subject // ignore: cast_nullable_to_non_nullable
as String?,roomType: freezed == roomType ? _self.roomType : roomType // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [InvitedRoom].
extension InvitedRoomPatterns on InvitedRoom {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InvitedRoom value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InvitedRoom() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InvitedRoom value)  $default,){
final _that = this;
switch (_that) {
case _InvitedRoom():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InvitedRoom value)?  $default,){
final _that = this;
switch (_that) {
case _InvitedRoom() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String roomId,  String invitedBy,  String? roomName,  String? subject,  String? roomType)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InvitedRoom() when $default != null:
return $default(_that.roomId,_that.invitedBy,_that.roomName,_that.subject,_that.roomType);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String roomId,  String invitedBy,  String? roomName,  String? subject,  String? roomType)  $default,) {final _that = this;
switch (_that) {
case _InvitedRoom():
return $default(_that.roomId,_that.invitedBy,_that.roomName,_that.subject,_that.roomType);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String roomId,  String invitedBy,  String? roomName,  String? subject,  String? roomType)?  $default,) {final _that = this;
switch (_that) {
case _InvitedRoom() when $default != null:
return $default(_that.roomId,_that.invitedBy,_that.roomName,_that.subject,_that.roomType);case _:
  return null;

}
}

}

/// @nodoc


class _InvitedRoom extends InvitedRoom {
  const _InvitedRoom({required this.roomId, required this.invitedBy, this.roomName, this.subject, this.roomType}): super._();
  

@override final  String roomId;
@override final  String invitedBy;
@override final  String? roomName;
@override final  String? subject;
@override final  String? roomType;

/// Create a copy of InvitedRoom
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InvitedRoomCopyWith<_InvitedRoom> get copyWith => __$InvitedRoomCopyWithImpl<_InvitedRoom>(this, _$identity);





@override
String toString() {
  return 'InvitedRoom(roomId: $roomId, invitedBy: $invitedBy, roomName: $roomName, subject: $subject, roomType: $roomType)';
}


}

/// @nodoc
abstract mixin class _$InvitedRoomCopyWith<$Res> implements $InvitedRoomCopyWith<$Res> {
  factory _$InvitedRoomCopyWith(_InvitedRoom value, $Res Function(_InvitedRoom) _then) = __$InvitedRoomCopyWithImpl;
@override @useResult
$Res call({
 String roomId, String invitedBy, String? roomName, String? subject, String? roomType
});




}
/// @nodoc
class __$InvitedRoomCopyWithImpl<$Res>
    implements _$InvitedRoomCopyWith<$Res> {
  __$InvitedRoomCopyWithImpl(this._self, this._then);

  final _InvitedRoom _self;
  final $Res Function(_InvitedRoom) _then;

/// Create a copy of InvitedRoom
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? roomId = null,Object? invitedBy = null,Object? roomName = freezed,Object? subject = freezed,Object? roomType = freezed,}) {
  return _then(_InvitedRoom(
roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,invitedBy: null == invitedBy ? _self.invitedBy : invitedBy // ignore: cast_nullable_to_non_nullable
as String,roomName: freezed == roomName ? _self.roomName : roomName // ignore: cast_nullable_to_non_nullable
as String?,subject: freezed == subject ? _self.subject : subject // ignore: cast_nullable_to_non_nullable
as String?,roomType: freezed == roomType ? _self.roomType : roomType // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
