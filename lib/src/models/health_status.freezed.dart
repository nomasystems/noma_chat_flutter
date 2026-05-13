// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'health_status.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$HealthStatus {

 ServiceStatus get status; Map<String, String> get checks;
/// Create a copy of HealthStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HealthStatusCopyWith<HealthStatus> get copyWith => _$HealthStatusCopyWithImpl<HealthStatus>(this as HealthStatus, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HealthStatus&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other.checks, checks));
}


@override
int get hashCode => Object.hash(runtimeType,status,const DeepCollectionEquality().hash(checks));

@override
String toString() {
  return 'HealthStatus(status: $status, checks: $checks)';
}


}

/// @nodoc
abstract mixin class $HealthStatusCopyWith<$Res>  {
  factory $HealthStatusCopyWith(HealthStatus value, $Res Function(HealthStatus) _then) = _$HealthStatusCopyWithImpl;
@useResult
$Res call({
 ServiceStatus status, Map<String, String> checks
});




}
/// @nodoc
class _$HealthStatusCopyWithImpl<$Res>
    implements $HealthStatusCopyWith<$Res> {
  _$HealthStatusCopyWithImpl(this._self, this._then);

  final HealthStatus _self;
  final $Res Function(HealthStatus) _then;

/// Create a copy of HealthStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? checks = null,}) {
  return _then(_self.copyWith(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ServiceStatus,checks: null == checks ? _self.checks : checks // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}

}


/// Adds pattern-matching-related methods to [HealthStatus].
extension HealthStatusPatterns on HealthStatus {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _HealthStatus value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _HealthStatus() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _HealthStatus value)  $default,){
final _that = this;
switch (_that) {
case _HealthStatus():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _HealthStatus value)?  $default,){
final _that = this;
switch (_that) {
case _HealthStatus() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ServiceStatus status,  Map<String, String> checks)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _HealthStatus() when $default != null:
return $default(_that.status,_that.checks);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ServiceStatus status,  Map<String, String> checks)  $default,) {final _that = this;
switch (_that) {
case _HealthStatus():
return $default(_that.status,_that.checks);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ServiceStatus status,  Map<String, String> checks)?  $default,) {final _that = this;
switch (_that) {
case _HealthStatus() when $default != null:
return $default(_that.status,_that.checks);case _:
  return null;

}
}

}

/// @nodoc


class _HealthStatus extends HealthStatus {
  const _HealthStatus({required this.status, final  Map<String, String> checks = const {}}): _checks = checks,super._();
  

@override final  ServiceStatus status;
 final  Map<String, String> _checks;
@override@JsonKey() Map<String, String> get checks {
  if (_checks is EqualUnmodifiableMapView) return _checks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_checks);
}


/// Create a copy of HealthStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HealthStatusCopyWith<_HealthStatus> get copyWith => __$HealthStatusCopyWithImpl<_HealthStatus>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _HealthStatus&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other._checks, _checks));
}


@override
int get hashCode => Object.hash(runtimeType,status,const DeepCollectionEquality().hash(_checks));

@override
String toString() {
  return 'HealthStatus(status: $status, checks: $checks)';
}


}

/// @nodoc
abstract mixin class _$HealthStatusCopyWith<$Res> implements $HealthStatusCopyWith<$Res> {
  factory _$HealthStatusCopyWith(_HealthStatus value, $Res Function(_HealthStatus) _then) = __$HealthStatusCopyWithImpl;
@override @useResult
$Res call({
 ServiceStatus status, Map<String, String> checks
});




}
/// @nodoc
class __$HealthStatusCopyWithImpl<$Res>
    implements _$HealthStatusCopyWith<$Res> {
  __$HealthStatusCopyWithImpl(this._self, this._then);

  final _HealthStatus _self;
  final $Res Function(_HealthStatus) _then;

/// Create a copy of HealthStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? checks = null,}) {
  return _then(_HealthStatus(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ServiceStatus,checks: null == checks ? _self._checks : checks // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}


}

// dart format on
