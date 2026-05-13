// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'pin.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$MessagePin {

 String get roomId; String get messageId; String get pinnedBy; DateTime get pinnedAt;
/// Create a copy of MessagePin
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MessagePinCopyWith<MessagePin> get copyWith => _$MessagePinCopyWithImpl<MessagePin>(this as MessagePin, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MessagePin&&(identical(other.roomId, roomId) || other.roomId == roomId)&&(identical(other.messageId, messageId) || other.messageId == messageId)&&(identical(other.pinnedBy, pinnedBy) || other.pinnedBy == pinnedBy)&&(identical(other.pinnedAt, pinnedAt) || other.pinnedAt == pinnedAt));
}


@override
int get hashCode => Object.hash(runtimeType,roomId,messageId,pinnedBy,pinnedAt);

@override
String toString() {
  return 'MessagePin(roomId: $roomId, messageId: $messageId, pinnedBy: $pinnedBy, pinnedAt: $pinnedAt)';
}


}

/// @nodoc
abstract mixin class $MessagePinCopyWith<$Res>  {
  factory $MessagePinCopyWith(MessagePin value, $Res Function(MessagePin) _then) = _$MessagePinCopyWithImpl;
@useResult
$Res call({
 String roomId, String messageId, String pinnedBy, DateTime pinnedAt
});




}
/// @nodoc
class _$MessagePinCopyWithImpl<$Res>
    implements $MessagePinCopyWith<$Res> {
  _$MessagePinCopyWithImpl(this._self, this._then);

  final MessagePin _self;
  final $Res Function(MessagePin) _then;

/// Create a copy of MessagePin
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? roomId = null,Object? messageId = null,Object? pinnedBy = null,Object? pinnedAt = null,}) {
  return _then(_self.copyWith(
roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,messageId: null == messageId ? _self.messageId : messageId // ignore: cast_nullable_to_non_nullable
as String,pinnedBy: null == pinnedBy ? _self.pinnedBy : pinnedBy // ignore: cast_nullable_to_non_nullable
as String,pinnedAt: null == pinnedAt ? _self.pinnedAt : pinnedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [MessagePin].
extension MessagePinPatterns on MessagePin {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MessagePin value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MessagePin() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MessagePin value)  $default,){
final _that = this;
switch (_that) {
case _MessagePin():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MessagePin value)?  $default,){
final _that = this;
switch (_that) {
case _MessagePin() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String roomId,  String messageId,  String pinnedBy,  DateTime pinnedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MessagePin() when $default != null:
return $default(_that.roomId,_that.messageId,_that.pinnedBy,_that.pinnedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String roomId,  String messageId,  String pinnedBy,  DateTime pinnedAt)  $default,) {final _that = this;
switch (_that) {
case _MessagePin():
return $default(_that.roomId,_that.messageId,_that.pinnedBy,_that.pinnedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String roomId,  String messageId,  String pinnedBy,  DateTime pinnedAt)?  $default,) {final _that = this;
switch (_that) {
case _MessagePin() when $default != null:
return $default(_that.roomId,_that.messageId,_that.pinnedBy,_that.pinnedAt);case _:
  return null;

}
}

}

/// @nodoc


class _MessagePin implements MessagePin {
  const _MessagePin({required this.roomId, required this.messageId, required this.pinnedBy, required this.pinnedAt});
  

@override final  String roomId;
@override final  String messageId;
@override final  String pinnedBy;
@override final  DateTime pinnedAt;

/// Create a copy of MessagePin
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MessagePinCopyWith<_MessagePin> get copyWith => __$MessagePinCopyWithImpl<_MessagePin>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MessagePin&&(identical(other.roomId, roomId) || other.roomId == roomId)&&(identical(other.messageId, messageId) || other.messageId == messageId)&&(identical(other.pinnedBy, pinnedBy) || other.pinnedBy == pinnedBy)&&(identical(other.pinnedAt, pinnedAt) || other.pinnedAt == pinnedAt));
}


@override
int get hashCode => Object.hash(runtimeType,roomId,messageId,pinnedBy,pinnedAt);

@override
String toString() {
  return 'MessagePin(roomId: $roomId, messageId: $messageId, pinnedBy: $pinnedBy, pinnedAt: $pinnedAt)';
}


}

/// @nodoc
abstract mixin class _$MessagePinCopyWith<$Res> implements $MessagePinCopyWith<$Res> {
  factory _$MessagePinCopyWith(_MessagePin value, $Res Function(_MessagePin) _then) = __$MessagePinCopyWithImpl;
@override @useResult
$Res call({
 String roomId, String messageId, String pinnedBy, DateTime pinnedAt
});




}
/// @nodoc
class __$MessagePinCopyWithImpl<$Res>
    implements _$MessagePinCopyWith<$Res> {
  __$MessagePinCopyWithImpl(this._self, this._then);

  final _MessagePin _self;
  final $Res Function(_MessagePin) _then;

/// Create a copy of MessagePin
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? roomId = null,Object? messageId = null,Object? pinnedBy = null,Object? pinnedAt = null,}) {
  return _then(_MessagePin(
roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,messageId: null == messageId ? _self.messageId : messageId // ignore: cast_nullable_to_non_nullable
as String,pinnedBy: null == pinnedBy ? _self.pinnedBy : pinnedBy // ignore: cast_nullable_to_non_nullable
as String,pinnedAt: null == pinnedAt ? _self.pinnedAt : pinnedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
