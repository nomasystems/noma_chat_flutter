// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'contact.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ChatContact {

 String get userId;
/// Create a copy of ChatContact
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatContactCopyWith<ChatContact> get copyWith => _$ChatContactCopyWithImpl<ChatContact>(this as ChatContact, _$identity);







}

/// @nodoc
abstract mixin class $ChatContactCopyWith<$Res>  {
  factory $ChatContactCopyWith(ChatContact value, $Res Function(ChatContact) _then) = _$ChatContactCopyWithImpl;
@useResult
$Res call({
 String userId
});




}
/// @nodoc
class _$ChatContactCopyWithImpl<$Res>
    implements $ChatContactCopyWith<$Res> {
  _$ChatContactCopyWithImpl(this._self, this._then);

  final ChatContact _self;
  final $Res Function(ChatContact) _then;

/// Create a copy of ChatContact
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? userId = null,}) {
  return _then(_self.copyWith(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ChatContact].
extension ChatContactPatterns on ChatContact {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatContact value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatContact() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatContact value)  $default,){
final _that = this;
switch (_that) {
case _ChatContact():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatContact value)?  $default,){
final _that = this;
switch (_that) {
case _ChatContact() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String userId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatContact() when $default != null:
return $default(_that.userId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String userId)  $default,) {final _that = this;
switch (_that) {
case _ChatContact():
return $default(_that.userId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String userId)?  $default,) {final _that = this;
switch (_that) {
case _ChatContact() when $default != null:
return $default(_that.userId);case _:
  return null;

}
}

}

/// @nodoc


class _ChatContact extends ChatContact {
  const _ChatContact({required this.userId}): super._();
  

@override final  String userId;

/// Create a copy of ChatContact
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatContactCopyWith<_ChatContact> get copyWith => __$ChatContactCopyWithImpl<_ChatContact>(this, _$identity);







}

/// @nodoc
abstract mixin class _$ChatContactCopyWith<$Res> implements $ChatContactCopyWith<$Res> {
  factory _$ChatContactCopyWith(_ChatContact value, $Res Function(_ChatContact) _then) = __$ChatContactCopyWithImpl;
@override @useResult
$Res call({
 String userId
});




}
/// @nodoc
class __$ChatContactCopyWithImpl<$Res>
    implements _$ChatContactCopyWith<$Res> {
  __$ChatContactCopyWithImpl(this._self, this._then);

  final _ChatContact _self;
  final $Res Function(_ChatContact) _then;

/// Create a copy of ChatContact
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? userId = null,}) {
  return _then(_ChatContact(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
