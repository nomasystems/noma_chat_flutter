// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'presence.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ChatPresence {

 String get userId; PresenceStatus get status; bool get online; String? get statusText; DateTime? get lastSeen;
/// Create a copy of ChatPresence
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatPresenceCopyWith<ChatPresence> get copyWith => _$ChatPresenceCopyWithImpl<ChatPresence>(this as ChatPresence, _$identity);







}

/// @nodoc
abstract mixin class $ChatPresenceCopyWith<$Res>  {
  factory $ChatPresenceCopyWith(ChatPresence value, $Res Function(ChatPresence) _then) = _$ChatPresenceCopyWithImpl;
@useResult
$Res call({
 String userId, PresenceStatus status, bool online, String? statusText, DateTime? lastSeen
});




}
/// @nodoc
class _$ChatPresenceCopyWithImpl<$Res>
    implements $ChatPresenceCopyWith<$Res> {
  _$ChatPresenceCopyWithImpl(this._self, this._then);

  final ChatPresence _self;
  final $Res Function(ChatPresence) _then;

/// Create a copy of ChatPresence
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? userId = null,Object? status = null,Object? online = null,Object? statusText = freezed,Object? lastSeen = freezed,}) {
  return _then(_self.copyWith(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as PresenceStatus,online: null == online ? _self.online : online // ignore: cast_nullable_to_non_nullable
as bool,statusText: freezed == statusText ? _self.statusText : statusText // ignore: cast_nullable_to_non_nullable
as String?,lastSeen: freezed == lastSeen ? _self.lastSeen : lastSeen // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [ChatPresence].
extension ChatPresencePatterns on ChatPresence {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatPresence value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatPresence() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatPresence value)  $default,){
final _that = this;
switch (_that) {
case _ChatPresence():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatPresence value)?  $default,){
final _that = this;
switch (_that) {
case _ChatPresence() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String userId,  PresenceStatus status,  bool online,  String? statusText,  DateTime? lastSeen)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatPresence() when $default != null:
return $default(_that.userId,_that.status,_that.online,_that.statusText,_that.lastSeen);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String userId,  PresenceStatus status,  bool online,  String? statusText,  DateTime? lastSeen)  $default,) {final _that = this;
switch (_that) {
case _ChatPresence():
return $default(_that.userId,_that.status,_that.online,_that.statusText,_that.lastSeen);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String userId,  PresenceStatus status,  bool online,  String? statusText,  DateTime? lastSeen)?  $default,) {final _that = this;
switch (_that) {
case _ChatPresence() when $default != null:
return $default(_that.userId,_that.status,_that.online,_that.statusText,_that.lastSeen);case _:
  return null;

}
}

}

/// @nodoc


class _ChatPresence extends ChatPresence {
  const _ChatPresence({required this.userId, required this.status, required this.online, this.statusText, this.lastSeen}): super._();
  

@override final  String userId;
@override final  PresenceStatus status;
@override final  bool online;
@override final  String? statusText;
@override final  DateTime? lastSeen;

/// Create a copy of ChatPresence
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatPresenceCopyWith<_ChatPresence> get copyWith => __$ChatPresenceCopyWithImpl<_ChatPresence>(this, _$identity);







}

/// @nodoc
abstract mixin class _$ChatPresenceCopyWith<$Res> implements $ChatPresenceCopyWith<$Res> {
  factory _$ChatPresenceCopyWith(_ChatPresence value, $Res Function(_ChatPresence) _then) = __$ChatPresenceCopyWithImpl;
@override @useResult
$Res call({
 String userId, PresenceStatus status, bool online, String? statusText, DateTime? lastSeen
});




}
/// @nodoc
class __$ChatPresenceCopyWithImpl<$Res>
    implements _$ChatPresenceCopyWith<$Res> {
  __$ChatPresenceCopyWithImpl(this._self, this._then);

  final _ChatPresence _self;
  final $Res Function(_ChatPresence) _then;

/// Create a copy of ChatPresence
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? userId = null,Object? status = null,Object? online = null,Object? statusText = freezed,Object? lastSeen = freezed,}) {
  return _then(_ChatPresence(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as PresenceStatus,online: null == online ? _self.online : online // ignore: cast_nullable_to_non_nullable
as bool,statusText: freezed == statusText ? _self.statusText : statusText // ignore: cast_nullable_to_non_nullable
as String?,lastSeen: freezed == lastSeen ? _self.lastSeen : lastSeen // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

/// @nodoc
mixin _$BulkPresenceResponse {

 ChatPresence get own; List<ChatPresence> get contacts;
/// Create a copy of BulkPresenceResponse
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BulkPresenceResponseCopyWith<BulkPresenceResponse> get copyWith => _$BulkPresenceResponseCopyWithImpl<BulkPresenceResponse>(this as BulkPresenceResponse, _$identity);







}

/// @nodoc
abstract mixin class $BulkPresenceResponseCopyWith<$Res>  {
  factory $BulkPresenceResponseCopyWith(BulkPresenceResponse value, $Res Function(BulkPresenceResponse) _then) = _$BulkPresenceResponseCopyWithImpl;
@useResult
$Res call({
 ChatPresence own, List<ChatPresence> contacts
});


$ChatPresenceCopyWith<$Res> get own;

}
/// @nodoc
class _$BulkPresenceResponseCopyWithImpl<$Res>
    implements $BulkPresenceResponseCopyWith<$Res> {
  _$BulkPresenceResponseCopyWithImpl(this._self, this._then);

  final BulkPresenceResponse _self;
  final $Res Function(BulkPresenceResponse) _then;

/// Create a copy of BulkPresenceResponse
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? own = null,Object? contacts = null,}) {
  return _then(_self.copyWith(
own: null == own ? _self.own : own // ignore: cast_nullable_to_non_nullable
as ChatPresence,contacts: null == contacts ? _self.contacts : contacts // ignore: cast_nullable_to_non_nullable
as List<ChatPresence>,
  ));
}
/// Create a copy of BulkPresenceResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ChatPresenceCopyWith<$Res> get own {
  
  return $ChatPresenceCopyWith<$Res>(_self.own, (value) {
    return _then(_self.copyWith(own: value));
  });
}
}


/// Adds pattern-matching-related methods to [BulkPresenceResponse].
extension BulkPresenceResponsePatterns on BulkPresenceResponse {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BulkPresenceResponse value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BulkPresenceResponse() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BulkPresenceResponse value)  $default,){
final _that = this;
switch (_that) {
case _BulkPresenceResponse():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BulkPresenceResponse value)?  $default,){
final _that = this;
switch (_that) {
case _BulkPresenceResponse() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ChatPresence own,  List<ChatPresence> contacts)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BulkPresenceResponse() when $default != null:
return $default(_that.own,_that.contacts);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ChatPresence own,  List<ChatPresence> contacts)  $default,) {final _that = this;
switch (_that) {
case _BulkPresenceResponse():
return $default(_that.own,_that.contacts);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ChatPresence own,  List<ChatPresence> contacts)?  $default,) {final _that = this;
switch (_that) {
case _BulkPresenceResponse() when $default != null:
return $default(_that.own,_that.contacts);case _:
  return null;

}
}

}

/// @nodoc


class _BulkPresenceResponse extends BulkPresenceResponse {
  const _BulkPresenceResponse({required this.own, required final  List<ChatPresence> contacts}): _contacts = contacts,super._();
  

@override final  ChatPresence own;
 final  List<ChatPresence> _contacts;
@override List<ChatPresence> get contacts {
  if (_contacts is EqualUnmodifiableListView) return _contacts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_contacts);
}


/// Create a copy of BulkPresenceResponse
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BulkPresenceResponseCopyWith<_BulkPresenceResponse> get copyWith => __$BulkPresenceResponseCopyWithImpl<_BulkPresenceResponse>(this, _$identity);







}

/// @nodoc
abstract mixin class _$BulkPresenceResponseCopyWith<$Res> implements $BulkPresenceResponseCopyWith<$Res> {
  factory _$BulkPresenceResponseCopyWith(_BulkPresenceResponse value, $Res Function(_BulkPresenceResponse) _then) = __$BulkPresenceResponseCopyWithImpl;
@override @useResult
$Res call({
 ChatPresence own, List<ChatPresence> contacts
});


@override $ChatPresenceCopyWith<$Res> get own;

}
/// @nodoc
class __$BulkPresenceResponseCopyWithImpl<$Res>
    implements _$BulkPresenceResponseCopyWith<$Res> {
  __$BulkPresenceResponseCopyWithImpl(this._self, this._then);

  final _BulkPresenceResponse _self;
  final $Res Function(_BulkPresenceResponse) _then;

/// Create a copy of BulkPresenceResponse
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? own = null,Object? contacts = null,}) {
  return _then(_BulkPresenceResponse(
own: null == own ? _self.own : own // ignore: cast_nullable_to_non_nullable
as ChatPresence,contacts: null == contacts ? _self._contacts : contacts // ignore: cast_nullable_to_non_nullable
as List<ChatPresence>,
  ));
}

/// Create a copy of BulkPresenceResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ChatPresenceCopyWith<$Res> get own {
  
  return $ChatPresenceCopyWith<$Res>(_self.own, (value) {
    return _then(_self.copyWith(own: value));
  });
}
}

// dart format on
