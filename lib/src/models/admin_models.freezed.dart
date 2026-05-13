// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'admin_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SystemStats {

 Map<String, dynamic> get raw;
/// Create a copy of SystemStats
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SystemStatsCopyWith<SystemStats> get copyWith => _$SystemStatsCopyWithImpl<SystemStats>(this as SystemStats, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SystemStats&&const DeepCollectionEquality().equals(other.raw, raw));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(raw));

@override
String toString() {
  return 'SystemStats(raw: $raw)';
}


}

/// @nodoc
abstract mixin class $SystemStatsCopyWith<$Res>  {
  factory $SystemStatsCopyWith(SystemStats value, $Res Function(SystemStats) _then) = _$SystemStatsCopyWithImpl;
@useResult
$Res call({
 Map<String, dynamic> raw
});




}
/// @nodoc
class _$SystemStatsCopyWithImpl<$Res>
    implements $SystemStatsCopyWith<$Res> {
  _$SystemStatsCopyWithImpl(this._self, this._then);

  final SystemStats _self;
  final $Res Function(SystemStats) _then;

/// Create a copy of SystemStats
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? raw = null,}) {
  return _then(_self.copyWith(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}

}


/// Adds pattern-matching-related methods to [SystemStats].
extension SystemStatsPatterns on SystemStats {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SystemStats value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SystemStats() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SystemStats value)  $default,){
final _that = this;
switch (_that) {
case _SystemStats():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SystemStats value)?  $default,){
final _that = this;
switch (_that) {
case _SystemStats() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Map<String, dynamic> raw)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SystemStats() when $default != null:
return $default(_that.raw);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Map<String, dynamic> raw)  $default,) {final _that = this;
switch (_that) {
case _SystemStats():
return $default(_that.raw);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Map<String, dynamic> raw)?  $default,) {final _that = this;
switch (_that) {
case _SystemStats() when $default != null:
return $default(_that.raw);case _:
  return null;

}
}

}

/// @nodoc


class _SystemStats implements SystemStats {
  const _SystemStats({required final  Map<String, dynamic> raw}): _raw = raw;
  

 final  Map<String, dynamic> _raw;
@override Map<String, dynamic> get raw {
  if (_raw is EqualUnmodifiableMapView) return _raw;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_raw);
}


/// Create a copy of SystemStats
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SystemStatsCopyWith<_SystemStats> get copyWith => __$SystemStatsCopyWithImpl<_SystemStats>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SystemStats&&const DeepCollectionEquality().equals(other._raw, _raw));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_raw));

@override
String toString() {
  return 'SystemStats(raw: $raw)';
}


}

/// @nodoc
abstract mixin class _$SystemStatsCopyWith<$Res> implements $SystemStatsCopyWith<$Res> {
  factory _$SystemStatsCopyWith(_SystemStats value, $Res Function(_SystemStats) _then) = __$SystemStatsCopyWithImpl;
@override @useResult
$Res call({
 Map<String, dynamic> raw
});




}
/// @nodoc
class __$SystemStatsCopyWithImpl<$Res>
    implements _$SystemStatsCopyWith<$Res> {
  __$SystemStatsCopyWithImpl(this._self, this._then);

  final _SystemStats _self;
  final $Res Function(_SystemStats) _then;

/// Create a copy of SystemStats
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? raw = null,}) {
  return _then(_SystemStats(
raw: null == raw ? _self._raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}


}

/// @nodoc
mixin _$AdminSession {

 Map<String, dynamic> get raw;
/// Create a copy of AdminSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AdminSessionCopyWith<AdminSession> get copyWith => _$AdminSessionCopyWithImpl<AdminSession>(this as AdminSession, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AdminSession&&const DeepCollectionEquality().equals(other.raw, raw));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(raw));

@override
String toString() {
  return 'AdminSession(raw: $raw)';
}


}

/// @nodoc
abstract mixin class $AdminSessionCopyWith<$Res>  {
  factory $AdminSessionCopyWith(AdminSession value, $Res Function(AdminSession) _then) = _$AdminSessionCopyWithImpl;
@useResult
$Res call({
 Map<String, dynamic> raw
});




}
/// @nodoc
class _$AdminSessionCopyWithImpl<$Res>
    implements $AdminSessionCopyWith<$Res> {
  _$AdminSessionCopyWithImpl(this._self, this._then);

  final AdminSession _self;
  final $Res Function(AdminSession) _then;

/// Create a copy of AdminSession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? raw = null,}) {
  return _then(_self.copyWith(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}

}


/// Adds pattern-matching-related methods to [AdminSession].
extension AdminSessionPatterns on AdminSession {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AdminSession value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AdminSession() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AdminSession value)  $default,){
final _that = this;
switch (_that) {
case _AdminSession():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AdminSession value)?  $default,){
final _that = this;
switch (_that) {
case _AdminSession() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Map<String, dynamic> raw)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AdminSession() when $default != null:
return $default(_that.raw);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Map<String, dynamic> raw)  $default,) {final _that = this;
switch (_that) {
case _AdminSession():
return $default(_that.raw);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Map<String, dynamic> raw)?  $default,) {final _that = this;
switch (_that) {
case _AdminSession() when $default != null:
return $default(_that.raw);case _:
  return null;

}
}

}

/// @nodoc


class _AdminSession implements AdminSession {
  const _AdminSession({required final  Map<String, dynamic> raw}): _raw = raw;
  

 final  Map<String, dynamic> _raw;
@override Map<String, dynamic> get raw {
  if (_raw is EqualUnmodifiableMapView) return _raw;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_raw);
}


/// Create a copy of AdminSession
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AdminSessionCopyWith<_AdminSession> get copyWith => __$AdminSessionCopyWithImpl<_AdminSession>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AdminSession&&const DeepCollectionEquality().equals(other._raw, _raw));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_raw));

@override
String toString() {
  return 'AdminSession(raw: $raw)';
}


}

/// @nodoc
abstract mixin class _$AdminSessionCopyWith<$Res> implements $AdminSessionCopyWith<$Res> {
  factory _$AdminSessionCopyWith(_AdminSession value, $Res Function(_AdminSession) _then) = __$AdminSessionCopyWithImpl;
@override @useResult
$Res call({
 Map<String, dynamic> raw
});




}
/// @nodoc
class __$AdminSessionCopyWithImpl<$Res>
    implements _$AdminSessionCopyWith<$Res> {
  __$AdminSessionCopyWithImpl(this._self, this._then);

  final _AdminSession _self;
  final $Res Function(_AdminSession) _then;

/// Create a copy of AdminSession
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? raw = null,}) {
  return _then(_AdminSession(
raw: null == raw ? _self._raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}


}

/// @nodoc
mixin _$ContentFilter {

 String get id; String get pattern; String? get createdAt;
/// Create a copy of ContentFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ContentFilterCopyWith<ContentFilter> get copyWith => _$ContentFilterCopyWithImpl<ContentFilter>(this as ContentFilter, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ContentFilter&&(identical(other.id, id) || other.id == id)&&(identical(other.pattern, pattern) || other.pattern == pattern)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,pattern,createdAt);

@override
String toString() {
  return 'ContentFilter(id: $id, pattern: $pattern, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $ContentFilterCopyWith<$Res>  {
  factory $ContentFilterCopyWith(ContentFilter value, $Res Function(ContentFilter) _then) = _$ContentFilterCopyWithImpl;
@useResult
$Res call({
 String id, String pattern, String? createdAt
});




}
/// @nodoc
class _$ContentFilterCopyWithImpl<$Res>
    implements $ContentFilterCopyWith<$Res> {
  _$ContentFilterCopyWithImpl(this._self, this._then);

  final ContentFilter _self;
  final $Res Function(ContentFilter) _then;

/// Create a copy of ContentFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? pattern = null,Object? createdAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,pattern: null == pattern ? _self.pattern : pattern // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ContentFilter].
extension ContentFilterPatterns on ContentFilter {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ContentFilter value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ContentFilter() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ContentFilter value)  $default,){
final _that = this;
switch (_that) {
case _ContentFilter():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ContentFilter value)?  $default,){
final _that = this;
switch (_that) {
case _ContentFilter() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String pattern,  String? createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ContentFilter() when $default != null:
return $default(_that.id,_that.pattern,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String pattern,  String? createdAt)  $default,) {final _that = this;
switch (_that) {
case _ContentFilter():
return $default(_that.id,_that.pattern,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String pattern,  String? createdAt)?  $default,) {final _that = this;
switch (_that) {
case _ContentFilter() when $default != null:
return $default(_that.id,_that.pattern,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc


class _ContentFilter implements ContentFilter {
  const _ContentFilter({required this.id, required this.pattern, this.createdAt});
  

@override final  String id;
@override final  String pattern;
@override final  String? createdAt;

/// Create a copy of ContentFilter
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ContentFilterCopyWith<_ContentFilter> get copyWith => __$ContentFilterCopyWithImpl<_ContentFilter>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ContentFilter&&(identical(other.id, id) || other.id == id)&&(identical(other.pattern, pattern) || other.pattern == pattern)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,pattern,createdAt);

@override
String toString() {
  return 'ContentFilter(id: $id, pattern: $pattern, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$ContentFilterCopyWith<$Res> implements $ContentFilterCopyWith<$Res> {
  factory _$ContentFilterCopyWith(_ContentFilter value, $Res Function(_ContentFilter) _then) = __$ContentFilterCopyWithImpl;
@override @useResult
$Res call({
 String id, String pattern, String? createdAt
});




}
/// @nodoc
class __$ContentFilterCopyWithImpl<$Res>
    implements _$ContentFilterCopyWith<$Res> {
  __$ContentFilterCopyWithImpl(this._self, this._then);

  final _ContentFilter _self;
  final $Res Function(_ContentFilter) _then;

/// Create a copy of ContentFilter
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? pattern = null,Object? createdAt = freezed,}) {
  return _then(_ContentFilter(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,pattern: null == pattern ? _self.pattern : pattern // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
