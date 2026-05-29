// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'room_user.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RoomUser {

 String get userId; RoomRole get role;
/// Create a copy of RoomUser
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoomUserCopyWith<RoomUser> get copyWith => _$RoomUserCopyWithImpl<RoomUser>(this as RoomUser, _$identity);





@override
String toString() {
  return 'RoomUser(userId: $userId, role: $role)';
}


}

/// @nodoc
abstract mixin class $RoomUserCopyWith<$Res>  {
  factory $RoomUserCopyWith(RoomUser value, $Res Function(RoomUser) _then) = _$RoomUserCopyWithImpl;
@useResult
$Res call({
 String userId, RoomRole role
});




}
/// @nodoc
class _$RoomUserCopyWithImpl<$Res>
    implements $RoomUserCopyWith<$Res> {
  _$RoomUserCopyWithImpl(this._self, this._then);

  final RoomUser _self;
  final $Res Function(RoomUser) _then;

/// Create a copy of RoomUser
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? userId = null,Object? role = null,}) {
  return _then(_self.copyWith(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as RoomRole,
  ));
}

}


/// Adds pattern-matching-related methods to [RoomUser].
extension RoomUserPatterns on RoomUser {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoomUser value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoomUser() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoomUser value)  $default,){
final _that = this;
switch (_that) {
case _RoomUser():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoomUser value)?  $default,){
final _that = this;
switch (_that) {
case _RoomUser() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String userId,  RoomRole role)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoomUser() when $default != null:
return $default(_that.userId,_that.role);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String userId,  RoomRole role)  $default,) {final _that = this;
switch (_that) {
case _RoomUser():
return $default(_that.userId,_that.role);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String userId,  RoomRole role)?  $default,) {final _that = this;
switch (_that) {
case _RoomUser() when $default != null:
return $default(_that.userId,_that.role);case _:
  return null;

}
}

}

/// @nodoc


class _RoomUser extends RoomUser {
  const _RoomUser({required this.userId, this.role = RoomRole.member}): super._();
  

@override final  String userId;
@override@JsonKey() final  RoomRole role;

/// Create a copy of RoomUser
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoomUserCopyWith<_RoomUser> get copyWith => __$RoomUserCopyWithImpl<_RoomUser>(this, _$identity);





@override
String toString() {
  return 'RoomUser(userId: $userId, role: $role)';
}


}

/// @nodoc
abstract mixin class _$RoomUserCopyWith<$Res> implements $RoomUserCopyWith<$Res> {
  factory _$RoomUserCopyWith(_RoomUser value, $Res Function(_RoomUser) _then) = __$RoomUserCopyWithImpl;
@override @useResult
$Res call({
 String userId, RoomRole role
});




}
/// @nodoc
class __$RoomUserCopyWithImpl<$Res>
    implements _$RoomUserCopyWith<$Res> {
  __$RoomUserCopyWithImpl(this._self, this._then);

  final _RoomUser _self;
  final $Res Function(_RoomUser) _then;

/// Create a copy of RoomUser
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? userId = null,Object? role = null,}) {
  return _then(_RoomUser(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as RoomRole,
  ));
}


}

// dart format on
