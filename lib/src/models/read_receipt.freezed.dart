// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'read_receipt.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ReadReceipt {

 String get userId; String? get lastReadMessageId; DateTime? get lastReadAt;
/// Create a copy of ReadReceipt
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadReceiptCopyWith<ReadReceipt> get copyWith => _$ReadReceiptCopyWithImpl<ReadReceipt>(this as ReadReceipt, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadReceipt&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.lastReadMessageId, lastReadMessageId) || other.lastReadMessageId == lastReadMessageId)&&(identical(other.lastReadAt, lastReadAt) || other.lastReadAt == lastReadAt));
}


@override
int get hashCode => Object.hash(runtimeType,userId,lastReadMessageId,lastReadAt);

@override
String toString() {
  return 'ReadReceipt(userId: $userId, lastReadMessageId: $lastReadMessageId, lastReadAt: $lastReadAt)';
}


}

/// @nodoc
abstract mixin class $ReadReceiptCopyWith<$Res>  {
  factory $ReadReceiptCopyWith(ReadReceipt value, $Res Function(ReadReceipt) _then) = _$ReadReceiptCopyWithImpl;
@useResult
$Res call({
 String userId, String? lastReadMessageId, DateTime? lastReadAt
});




}
/// @nodoc
class _$ReadReceiptCopyWithImpl<$Res>
    implements $ReadReceiptCopyWith<$Res> {
  _$ReadReceiptCopyWithImpl(this._self, this._then);

  final ReadReceipt _self;
  final $Res Function(ReadReceipt) _then;

/// Create a copy of ReadReceipt
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? userId = null,Object? lastReadMessageId = freezed,Object? lastReadAt = freezed,}) {
  return _then(_self.copyWith(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,lastReadMessageId: freezed == lastReadMessageId ? _self.lastReadMessageId : lastReadMessageId // ignore: cast_nullable_to_non_nullable
as String?,lastReadAt: freezed == lastReadAt ? _self.lastReadAt : lastReadAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [ReadReceipt].
extension ReadReceiptPatterns on ReadReceipt {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ReadReceipt value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ReadReceipt() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ReadReceipt value)  $default,){
final _that = this;
switch (_that) {
case _ReadReceipt():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ReadReceipt value)?  $default,){
final _that = this;
switch (_that) {
case _ReadReceipt() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String userId,  String? lastReadMessageId,  DateTime? lastReadAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ReadReceipt() when $default != null:
return $default(_that.userId,_that.lastReadMessageId,_that.lastReadAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String userId,  String? lastReadMessageId,  DateTime? lastReadAt)  $default,) {final _that = this;
switch (_that) {
case _ReadReceipt():
return $default(_that.userId,_that.lastReadMessageId,_that.lastReadAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String userId,  String? lastReadMessageId,  DateTime? lastReadAt)?  $default,) {final _that = this;
switch (_that) {
case _ReadReceipt() when $default != null:
return $default(_that.userId,_that.lastReadMessageId,_that.lastReadAt);case _:
  return null;

}
}

}

/// @nodoc


class _ReadReceipt implements ReadReceipt {
  const _ReadReceipt({required this.userId, this.lastReadMessageId, this.lastReadAt});
  

@override final  String userId;
@override final  String? lastReadMessageId;
@override final  DateTime? lastReadAt;

/// Create a copy of ReadReceipt
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ReadReceiptCopyWith<_ReadReceipt> get copyWith => __$ReadReceiptCopyWithImpl<_ReadReceipt>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ReadReceipt&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.lastReadMessageId, lastReadMessageId) || other.lastReadMessageId == lastReadMessageId)&&(identical(other.lastReadAt, lastReadAt) || other.lastReadAt == lastReadAt));
}


@override
int get hashCode => Object.hash(runtimeType,userId,lastReadMessageId,lastReadAt);

@override
String toString() {
  return 'ReadReceipt(userId: $userId, lastReadMessageId: $lastReadMessageId, lastReadAt: $lastReadAt)';
}


}

/// @nodoc
abstract mixin class _$ReadReceiptCopyWith<$Res> implements $ReadReceiptCopyWith<$Res> {
  factory _$ReadReceiptCopyWith(_ReadReceipt value, $Res Function(_ReadReceipt) _then) = __$ReadReceiptCopyWithImpl;
@override @useResult
$Res call({
 String userId, String? lastReadMessageId, DateTime? lastReadAt
});




}
/// @nodoc
class __$ReadReceiptCopyWithImpl<$Res>
    implements _$ReadReceiptCopyWith<$Res> {
  __$ReadReceiptCopyWithImpl(this._self, this._then);

  final _ReadReceipt _self;
  final $Res Function(_ReadReceipt) _then;

/// Create a copy of ReadReceipt
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? userId = null,Object? lastReadMessageId = freezed,Object? lastReadAt = freezed,}) {
  return _then(_ReadReceipt(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,lastReadMessageId: freezed == lastReadMessageId ? _self.lastReadMessageId : lastReadMessageId // ignore: cast_nullable_to_non_nullable
as String?,lastReadAt: freezed == lastReadAt ? _self.lastReadAt : lastReadAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
