// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'attachment.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AttachmentUploadResult {

 String get attachmentId; String? get url; String? get metadata; Map<String, dynamic> get raw;
/// Create a copy of AttachmentUploadResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AttachmentUploadResultCopyWith<AttachmentUploadResult> get copyWith => _$AttachmentUploadResultCopyWithImpl<AttachmentUploadResult>(this as AttachmentUploadResult, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AttachmentUploadResult&&(identical(other.attachmentId, attachmentId) || other.attachmentId == attachmentId)&&(identical(other.url, url) || other.url == url)&&(identical(other.metadata, metadata) || other.metadata == metadata)&&const DeepCollectionEquality().equals(other.raw, raw));
}


@override
int get hashCode => Object.hash(runtimeType,attachmentId,url,metadata,const DeepCollectionEquality().hash(raw));



}

/// @nodoc
abstract mixin class $AttachmentUploadResultCopyWith<$Res>  {
  factory $AttachmentUploadResultCopyWith(AttachmentUploadResult value, $Res Function(AttachmentUploadResult) _then) = _$AttachmentUploadResultCopyWithImpl;
@useResult
$Res call({
 String attachmentId, String? url, String? metadata, Map<String, dynamic> raw
});




}
/// @nodoc
class _$AttachmentUploadResultCopyWithImpl<$Res>
    implements $AttachmentUploadResultCopyWith<$Res> {
  _$AttachmentUploadResultCopyWithImpl(this._self, this._then);

  final AttachmentUploadResult _self;
  final $Res Function(AttachmentUploadResult) _then;

/// Create a copy of AttachmentUploadResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? attachmentId = null,Object? url = freezed,Object? metadata = freezed,Object? raw = null,}) {
  return _then(_self.copyWith(
attachmentId: null == attachmentId ? _self.attachmentId : attachmentId // ignore: cast_nullable_to_non_nullable
as String,url: freezed == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String?,metadata: freezed == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as String?,raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}

}


/// Adds pattern-matching-related methods to [AttachmentUploadResult].
extension AttachmentUploadResultPatterns on AttachmentUploadResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AttachmentUploadResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AttachmentUploadResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AttachmentUploadResult value)  $default,){
final _that = this;
switch (_that) {
case _AttachmentUploadResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AttachmentUploadResult value)?  $default,){
final _that = this;
switch (_that) {
case _AttachmentUploadResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String attachmentId,  String? url,  String? metadata,  Map<String, dynamic> raw)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AttachmentUploadResult() when $default != null:
return $default(_that.attachmentId,_that.url,_that.metadata,_that.raw);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String attachmentId,  String? url,  String? metadata,  Map<String, dynamic> raw)  $default,) {final _that = this;
switch (_that) {
case _AttachmentUploadResult():
return $default(_that.attachmentId,_that.url,_that.metadata,_that.raw);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String attachmentId,  String? url,  String? metadata,  Map<String, dynamic> raw)?  $default,) {final _that = this;
switch (_that) {
case _AttachmentUploadResult() when $default != null:
return $default(_that.attachmentId,_that.url,_that.metadata,_that.raw);case _:
  return null;

}
}

}

/// @nodoc


class _AttachmentUploadResult extends AttachmentUploadResult {
  const _AttachmentUploadResult({required this.attachmentId, this.url, this.metadata, required final  Map<String, dynamic> raw}): _raw = raw,super._();
  

@override final  String attachmentId;
@override final  String? url;
@override final  String? metadata;
 final  Map<String, dynamic> _raw;
@override Map<String, dynamic> get raw {
  if (_raw is EqualUnmodifiableMapView) return _raw;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_raw);
}


/// Create a copy of AttachmentUploadResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AttachmentUploadResultCopyWith<_AttachmentUploadResult> get copyWith => __$AttachmentUploadResultCopyWithImpl<_AttachmentUploadResult>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AttachmentUploadResult&&(identical(other.attachmentId, attachmentId) || other.attachmentId == attachmentId)&&(identical(other.url, url) || other.url == url)&&(identical(other.metadata, metadata) || other.metadata == metadata)&&const DeepCollectionEquality().equals(other._raw, _raw));
}


@override
int get hashCode => Object.hash(runtimeType,attachmentId,url,metadata,const DeepCollectionEquality().hash(_raw));



}

/// @nodoc
abstract mixin class _$AttachmentUploadResultCopyWith<$Res> implements $AttachmentUploadResultCopyWith<$Res> {
  factory _$AttachmentUploadResultCopyWith(_AttachmentUploadResult value, $Res Function(_AttachmentUploadResult) _then) = __$AttachmentUploadResultCopyWithImpl;
@override @useResult
$Res call({
 String attachmentId, String? url, String? metadata, Map<String, dynamic> raw
});




}
/// @nodoc
class __$AttachmentUploadResultCopyWithImpl<$Res>
    implements _$AttachmentUploadResultCopyWith<$Res> {
  __$AttachmentUploadResultCopyWithImpl(this._self, this._then);

  final _AttachmentUploadResult _self;
  final $Res Function(_AttachmentUploadResult) _then;

/// Create a copy of AttachmentUploadResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? attachmentId = null,Object? url = freezed,Object? metadata = freezed,Object? raw = null,}) {
  return _then(_AttachmentUploadResult(
attachmentId: null == attachmentId ? _self.attachmentId : attachmentId // ignore: cast_nullable_to_non_nullable
as String,url: freezed == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String?,metadata: freezed == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as String?,raw: null == raw ? _self._raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}


}

// dart format on
