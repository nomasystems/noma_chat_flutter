// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'forward_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ForwardInfo {

 String get forwardedFrom; String get forwardedFromRoom; String get forwardedMessageId;
/// Create a copy of ForwardInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ForwardInfoCopyWith<ForwardInfo> get copyWith => _$ForwardInfoCopyWithImpl<ForwardInfo>(this as ForwardInfo, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ForwardInfo&&(identical(other.forwardedFrom, forwardedFrom) || other.forwardedFrom == forwardedFrom)&&(identical(other.forwardedFromRoom, forwardedFromRoom) || other.forwardedFromRoom == forwardedFromRoom)&&(identical(other.forwardedMessageId, forwardedMessageId) || other.forwardedMessageId == forwardedMessageId));
}


@override
int get hashCode => Object.hash(runtimeType,forwardedFrom,forwardedFromRoom,forwardedMessageId);



}

/// @nodoc
abstract mixin class $ForwardInfoCopyWith<$Res>  {
  factory $ForwardInfoCopyWith(ForwardInfo value, $Res Function(ForwardInfo) _then) = _$ForwardInfoCopyWithImpl;
@useResult
$Res call({
 String forwardedFrom, String forwardedFromRoom, String forwardedMessageId
});




}
/// @nodoc
class _$ForwardInfoCopyWithImpl<$Res>
    implements $ForwardInfoCopyWith<$Res> {
  _$ForwardInfoCopyWithImpl(this._self, this._then);

  final ForwardInfo _self;
  final $Res Function(ForwardInfo) _then;

/// Create a copy of ForwardInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? forwardedFrom = null,Object? forwardedFromRoom = null,Object? forwardedMessageId = null,}) {
  return _then(_self.copyWith(
forwardedFrom: null == forwardedFrom ? _self.forwardedFrom : forwardedFrom // ignore: cast_nullable_to_non_nullable
as String,forwardedFromRoom: null == forwardedFromRoom ? _self.forwardedFromRoom : forwardedFromRoom // ignore: cast_nullable_to_non_nullable
as String,forwardedMessageId: null == forwardedMessageId ? _self.forwardedMessageId : forwardedMessageId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ForwardInfo].
extension ForwardInfoPatterns on ForwardInfo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ForwardInfo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ForwardInfo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ForwardInfo value)  $default,){
final _that = this;
switch (_that) {
case _ForwardInfo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ForwardInfo value)?  $default,){
final _that = this;
switch (_that) {
case _ForwardInfo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String forwardedFrom,  String forwardedFromRoom,  String forwardedMessageId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ForwardInfo() when $default != null:
return $default(_that.forwardedFrom,_that.forwardedFromRoom,_that.forwardedMessageId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String forwardedFrom,  String forwardedFromRoom,  String forwardedMessageId)  $default,) {final _that = this;
switch (_that) {
case _ForwardInfo():
return $default(_that.forwardedFrom,_that.forwardedFromRoom,_that.forwardedMessageId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String forwardedFrom,  String forwardedFromRoom,  String forwardedMessageId)?  $default,) {final _that = this;
switch (_that) {
case _ForwardInfo() when $default != null:
return $default(_that.forwardedFrom,_that.forwardedFromRoom,_that.forwardedMessageId);case _:
  return null;

}
}

}

/// @nodoc


class _ForwardInfo extends ForwardInfo {
  const _ForwardInfo({required this.forwardedFrom, required this.forwardedFromRoom, required this.forwardedMessageId}): super._();
  

@override final  String forwardedFrom;
@override final  String forwardedFromRoom;
@override final  String forwardedMessageId;

/// Create a copy of ForwardInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ForwardInfoCopyWith<_ForwardInfo> get copyWith => __$ForwardInfoCopyWithImpl<_ForwardInfo>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ForwardInfo&&(identical(other.forwardedFrom, forwardedFrom) || other.forwardedFrom == forwardedFrom)&&(identical(other.forwardedFromRoom, forwardedFromRoom) || other.forwardedFromRoom == forwardedFromRoom)&&(identical(other.forwardedMessageId, forwardedMessageId) || other.forwardedMessageId == forwardedMessageId));
}


@override
int get hashCode => Object.hash(runtimeType,forwardedFrom,forwardedFromRoom,forwardedMessageId);



}

/// @nodoc
abstract mixin class _$ForwardInfoCopyWith<$Res> implements $ForwardInfoCopyWith<$Res> {
  factory _$ForwardInfoCopyWith(_ForwardInfo value, $Res Function(_ForwardInfo) _then) = __$ForwardInfoCopyWithImpl;
@override @useResult
$Res call({
 String forwardedFrom, String forwardedFromRoom, String forwardedMessageId
});




}
/// @nodoc
class __$ForwardInfoCopyWithImpl<$Res>
    implements _$ForwardInfoCopyWith<$Res> {
  __$ForwardInfoCopyWithImpl(this._self, this._then);

  final _ForwardInfo _self;
  final $Res Function(_ForwardInfo) _then;

/// Create a copy of ForwardInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? forwardedFrom = null,Object? forwardedFromRoom = null,Object? forwardedMessageId = null,}) {
  return _then(_ForwardInfo(
forwardedFrom: null == forwardedFrom ? _self.forwardedFrom : forwardedFrom // ignore: cast_nullable_to_non_nullable
as String,forwardedFromRoom: null == forwardedFromRoom ? _self.forwardedFromRoom : forwardedFromRoom // ignore: cast_nullable_to_non_nullable
as String,forwardedMessageId: null == forwardedMessageId ? _self.forwardedMessageId : forwardedMessageId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
