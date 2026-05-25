// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'scheduled_message.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ScheduledMessage {

 String get id; String get userId; String get roomId; DateTime get sendAt; DateTime get createdAt; String? get text; Map<String, dynamic>? get metadata;
/// Create a copy of ScheduledMessage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ScheduledMessageCopyWith<ScheduledMessage> get copyWith => _$ScheduledMessageCopyWithImpl<ScheduledMessage>(this as ScheduledMessage, _$identity);





@override
String toString() {
  return 'ScheduledMessage(id: $id, userId: $userId, roomId: $roomId, sendAt: $sendAt, createdAt: $createdAt, text: $text, metadata: $metadata)';
}


}

/// @nodoc
abstract mixin class $ScheduledMessageCopyWith<$Res>  {
  factory $ScheduledMessageCopyWith(ScheduledMessage value, $Res Function(ScheduledMessage) _then) = _$ScheduledMessageCopyWithImpl;
@useResult
$Res call({
 String id, String userId, String roomId, DateTime sendAt, DateTime createdAt, String? text, Map<String, dynamic>? metadata
});




}
/// @nodoc
class _$ScheduledMessageCopyWithImpl<$Res>
    implements $ScheduledMessageCopyWith<$Res> {
  _$ScheduledMessageCopyWithImpl(this._self, this._then);

  final ScheduledMessage _self;
  final $Res Function(ScheduledMessage) _then;

/// Create a copy of ScheduledMessage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? userId = null,Object? roomId = null,Object? sendAt = null,Object? createdAt = null,Object? text = freezed,Object? metadata = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,sendAt: null == sendAt ? _self.sendAt : sendAt // ignore: cast_nullable_to_non_nullable
as DateTime,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,text: freezed == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String?,metadata: freezed == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,
  ));
}

}


/// Adds pattern-matching-related methods to [ScheduledMessage].
extension ScheduledMessagePatterns on ScheduledMessage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ScheduledMessage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ScheduledMessage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ScheduledMessage value)  $default,){
final _that = this;
switch (_that) {
case _ScheduledMessage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ScheduledMessage value)?  $default,){
final _that = this;
switch (_that) {
case _ScheduledMessage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String userId,  String roomId,  DateTime sendAt,  DateTime createdAt,  String? text,  Map<String, dynamic>? metadata)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ScheduledMessage() when $default != null:
return $default(_that.id,_that.userId,_that.roomId,_that.sendAt,_that.createdAt,_that.text,_that.metadata);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String userId,  String roomId,  DateTime sendAt,  DateTime createdAt,  String? text,  Map<String, dynamic>? metadata)  $default,) {final _that = this;
switch (_that) {
case _ScheduledMessage():
return $default(_that.id,_that.userId,_that.roomId,_that.sendAt,_that.createdAt,_that.text,_that.metadata);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String userId,  String roomId,  DateTime sendAt,  DateTime createdAt,  String? text,  Map<String, dynamic>? metadata)?  $default,) {final _that = this;
switch (_that) {
case _ScheduledMessage() when $default != null:
return $default(_that.id,_that.userId,_that.roomId,_that.sendAt,_that.createdAt,_that.text,_that.metadata);case _:
  return null;

}
}

}

/// @nodoc


class _ScheduledMessage extends ScheduledMessage {
  const _ScheduledMessage({required this.id, required this.userId, required this.roomId, required this.sendAt, required this.createdAt, this.text, final  Map<String, dynamic>? metadata}): _metadata = metadata,super._();
  

@override final  String id;
@override final  String userId;
@override final  String roomId;
@override final  DateTime sendAt;
@override final  DateTime createdAt;
@override final  String? text;
 final  Map<String, dynamic>? _metadata;
@override Map<String, dynamic>? get metadata {
  final value = _metadata;
  if (value == null) return null;
  if (_metadata is EqualUnmodifiableMapView) return _metadata;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of ScheduledMessage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ScheduledMessageCopyWith<_ScheduledMessage> get copyWith => __$ScheduledMessageCopyWithImpl<_ScheduledMessage>(this, _$identity);





@override
String toString() {
  return 'ScheduledMessage(id: $id, userId: $userId, roomId: $roomId, sendAt: $sendAt, createdAt: $createdAt, text: $text, metadata: $metadata)';
}


}

/// @nodoc
abstract mixin class _$ScheduledMessageCopyWith<$Res> implements $ScheduledMessageCopyWith<$Res> {
  factory _$ScheduledMessageCopyWith(_ScheduledMessage value, $Res Function(_ScheduledMessage) _then) = __$ScheduledMessageCopyWithImpl;
@override @useResult
$Res call({
 String id, String userId, String roomId, DateTime sendAt, DateTime createdAt, String? text, Map<String, dynamic>? metadata
});




}
/// @nodoc
class __$ScheduledMessageCopyWithImpl<$Res>
    implements _$ScheduledMessageCopyWith<$Res> {
  __$ScheduledMessageCopyWithImpl(this._self, this._then);

  final _ScheduledMessage _self;
  final $Res Function(_ScheduledMessage) _then;

/// Create a copy of ScheduledMessage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? userId = null,Object? roomId = null,Object? sendAt = null,Object? createdAt = null,Object? text = freezed,Object? metadata = freezed,}) {
  return _then(_ScheduledMessage(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,sendAt: null == sendAt ? _self.sendAt : sendAt // ignore: cast_nullable_to_non_nullable
as DateTime,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,text: freezed == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String?,metadata: freezed == metadata ? _self._metadata : metadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,
  ));
}


}

// dart format on
