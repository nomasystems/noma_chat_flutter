// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'user_rooms.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UserRooms {

 List<UnreadRoom> get rooms; List<InvitedRoom> get invitedRooms; bool get hasMore;
/// Create a copy of UserRooms
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserRoomsCopyWith<UserRooms> get copyWith => _$UserRoomsCopyWithImpl<UserRooms>(this as UserRooms, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UserRooms&&const DeepCollectionEquality().equals(other.rooms, rooms)&&const DeepCollectionEquality().equals(other.invitedRooms, invitedRooms)&&(identical(other.hasMore, hasMore) || other.hasMore == hasMore));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(rooms),const DeepCollectionEquality().hash(invitedRooms),hasMore);

@override
String toString() {
  return 'UserRooms(rooms: $rooms, invitedRooms: $invitedRooms, hasMore: $hasMore)';
}


}

/// @nodoc
abstract mixin class $UserRoomsCopyWith<$Res>  {
  factory $UserRoomsCopyWith(UserRooms value, $Res Function(UserRooms) _then) = _$UserRoomsCopyWithImpl;
@useResult
$Res call({
 List<UnreadRoom> rooms, List<InvitedRoom> invitedRooms, bool hasMore
});




}
/// @nodoc
class _$UserRoomsCopyWithImpl<$Res>
    implements $UserRoomsCopyWith<$Res> {
  _$UserRoomsCopyWithImpl(this._self, this._then);

  final UserRooms _self;
  final $Res Function(UserRooms) _then;

/// Create a copy of UserRooms
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? rooms = null,Object? invitedRooms = null,Object? hasMore = null,}) {
  return _then(_self.copyWith(
rooms: null == rooms ? _self.rooms : rooms // ignore: cast_nullable_to_non_nullable
as List<UnreadRoom>,invitedRooms: null == invitedRooms ? _self.invitedRooms : invitedRooms // ignore: cast_nullable_to_non_nullable
as List<InvitedRoom>,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [UserRooms].
extension UserRoomsPatterns on UserRooms {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UserRooms value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UserRooms() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UserRooms value)  $default,){
final _that = this;
switch (_that) {
case _UserRooms():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UserRooms value)?  $default,){
final _that = this;
switch (_that) {
case _UserRooms() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<UnreadRoom> rooms,  List<InvitedRoom> invitedRooms,  bool hasMore)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UserRooms() when $default != null:
return $default(_that.rooms,_that.invitedRooms,_that.hasMore);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<UnreadRoom> rooms,  List<InvitedRoom> invitedRooms,  bool hasMore)  $default,) {final _that = this;
switch (_that) {
case _UserRooms():
return $default(_that.rooms,_that.invitedRooms,_that.hasMore);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<UnreadRoom> rooms,  List<InvitedRoom> invitedRooms,  bool hasMore)?  $default,) {final _that = this;
switch (_that) {
case _UserRooms() when $default != null:
return $default(_that.rooms,_that.invitedRooms,_that.hasMore);case _:
  return null;

}
}

}

/// @nodoc


class _UserRooms implements UserRooms {
  const _UserRooms({required final  List<UnreadRoom> rooms, final  List<InvitedRoom> invitedRooms = const [], this.hasMore = false}): _rooms = rooms,_invitedRooms = invitedRooms;
  

 final  List<UnreadRoom> _rooms;
@override List<UnreadRoom> get rooms {
  if (_rooms is EqualUnmodifiableListView) return _rooms;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_rooms);
}

 final  List<InvitedRoom> _invitedRooms;
@override@JsonKey() List<InvitedRoom> get invitedRooms {
  if (_invitedRooms is EqualUnmodifiableListView) return _invitedRooms;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_invitedRooms);
}

@override@JsonKey() final  bool hasMore;

/// Create a copy of UserRooms
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UserRoomsCopyWith<_UserRooms> get copyWith => __$UserRoomsCopyWithImpl<_UserRooms>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UserRooms&&const DeepCollectionEquality().equals(other._rooms, _rooms)&&const DeepCollectionEquality().equals(other._invitedRooms, _invitedRooms)&&(identical(other.hasMore, hasMore) || other.hasMore == hasMore));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_rooms),const DeepCollectionEquality().hash(_invitedRooms),hasMore);

@override
String toString() {
  return 'UserRooms(rooms: $rooms, invitedRooms: $invitedRooms, hasMore: $hasMore)';
}


}

/// @nodoc
abstract mixin class _$UserRoomsCopyWith<$Res> implements $UserRoomsCopyWith<$Res> {
  factory _$UserRoomsCopyWith(_UserRooms value, $Res Function(_UserRooms) _then) = __$UserRoomsCopyWithImpl;
@override @useResult
$Res call({
 List<UnreadRoom> rooms, List<InvitedRoom> invitedRooms, bool hasMore
});




}
/// @nodoc
class __$UserRoomsCopyWithImpl<$Res>
    implements _$UserRoomsCopyWith<$Res> {
  __$UserRoomsCopyWithImpl(this._self, this._then);

  final _UserRooms _self;
  final $Res Function(_UserRooms) _then;

/// Create a copy of UserRooms
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? rooms = null,Object? invitedRooms = null,Object? hasMore = null,}) {
  return _then(_UserRooms(
rooms: null == rooms ? _self._rooms : rooms // ignore: cast_nullable_to_non_nullable
as List<UnreadRoom>,invitedRooms: null == invitedRooms ? _self._invitedRooms : invitedRooms // ignore: cast_nullable_to_non_nullable
as List<InvitedRoom>,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
