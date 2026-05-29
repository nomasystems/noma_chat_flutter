// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'report.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$MessageReport {

 String get reporterId; String get messageId; String get roomId; String get reason; DateTime get reportedAt;
/// Create a copy of MessageReport
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MessageReportCopyWith<MessageReport> get copyWith => _$MessageReportCopyWithImpl<MessageReport>(this as MessageReport, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MessageReport&&(identical(other.reporterId, reporterId) || other.reporterId == reporterId)&&(identical(other.messageId, messageId) || other.messageId == messageId)&&(identical(other.roomId, roomId) || other.roomId == roomId)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.reportedAt, reportedAt) || other.reportedAt == reportedAt));
}


@override
int get hashCode => Object.hash(runtimeType,reporterId,messageId,roomId,reason,reportedAt);

@override
String toString() {
  return 'MessageReport(reporterId: $reporterId, messageId: $messageId, roomId: $roomId, reason: $reason, reportedAt: $reportedAt)';
}


}

/// @nodoc
abstract mixin class $MessageReportCopyWith<$Res>  {
  factory $MessageReportCopyWith(MessageReport value, $Res Function(MessageReport) _then) = _$MessageReportCopyWithImpl;
@useResult
$Res call({
 String reporterId, String messageId, String roomId, String reason, DateTime reportedAt
});




}
/// @nodoc
class _$MessageReportCopyWithImpl<$Res>
    implements $MessageReportCopyWith<$Res> {
  _$MessageReportCopyWithImpl(this._self, this._then);

  final MessageReport _self;
  final $Res Function(MessageReport) _then;

/// Create a copy of MessageReport
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reporterId = null,Object? messageId = null,Object? roomId = null,Object? reason = null,Object? reportedAt = null,}) {
  return _then(_self.copyWith(
reporterId: null == reporterId ? _self.reporterId : reporterId // ignore: cast_nullable_to_non_nullable
as String,messageId: null == messageId ? _self.messageId : messageId // ignore: cast_nullable_to_non_nullable
as String,roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,reportedAt: null == reportedAt ? _self.reportedAt : reportedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [MessageReport].
extension MessageReportPatterns on MessageReport {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MessageReport value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MessageReport() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MessageReport value)  $default,){
final _that = this;
switch (_that) {
case _MessageReport():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MessageReport value)?  $default,){
final _that = this;
switch (_that) {
case _MessageReport() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String reporterId,  String messageId,  String roomId,  String reason,  DateTime reportedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MessageReport() when $default != null:
return $default(_that.reporterId,_that.messageId,_that.roomId,_that.reason,_that.reportedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String reporterId,  String messageId,  String roomId,  String reason,  DateTime reportedAt)  $default,) {final _that = this;
switch (_that) {
case _MessageReport():
return $default(_that.reporterId,_that.messageId,_that.roomId,_that.reason,_that.reportedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String reporterId,  String messageId,  String roomId,  String reason,  DateTime reportedAt)?  $default,) {final _that = this;
switch (_that) {
case _MessageReport() when $default != null:
return $default(_that.reporterId,_that.messageId,_that.roomId,_that.reason,_that.reportedAt);case _:
  return null;

}
}

}

/// @nodoc


class _MessageReport implements MessageReport {
  const _MessageReport({required this.reporterId, required this.messageId, required this.roomId, required this.reason, required this.reportedAt});
  

@override final  String reporterId;
@override final  String messageId;
@override final  String roomId;
@override final  String reason;
@override final  DateTime reportedAt;

/// Create a copy of MessageReport
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MessageReportCopyWith<_MessageReport> get copyWith => __$MessageReportCopyWithImpl<_MessageReport>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MessageReport&&(identical(other.reporterId, reporterId) || other.reporterId == reporterId)&&(identical(other.messageId, messageId) || other.messageId == messageId)&&(identical(other.roomId, roomId) || other.roomId == roomId)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.reportedAt, reportedAt) || other.reportedAt == reportedAt));
}


@override
int get hashCode => Object.hash(runtimeType,reporterId,messageId,roomId,reason,reportedAt);

@override
String toString() {
  return 'MessageReport(reporterId: $reporterId, messageId: $messageId, roomId: $roomId, reason: $reason, reportedAt: $reportedAt)';
}


}

/// @nodoc
abstract mixin class _$MessageReportCopyWith<$Res> implements $MessageReportCopyWith<$Res> {
  factory _$MessageReportCopyWith(_MessageReport value, $Res Function(_MessageReport) _then) = __$MessageReportCopyWithImpl;
@override @useResult
$Res call({
 String reporterId, String messageId, String roomId, String reason, DateTime reportedAt
});




}
/// @nodoc
class __$MessageReportCopyWithImpl<$Res>
    implements _$MessageReportCopyWith<$Res> {
  __$MessageReportCopyWithImpl(this._self, this._then);

  final _MessageReport _self;
  final $Res Function(_MessageReport) _then;

/// Create a copy of MessageReport
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reporterId = null,Object? messageId = null,Object? roomId = null,Object? reason = null,Object? reportedAt = null,}) {
  return _then(_MessageReport(
reporterId: null == reporterId ? _self.reporterId : reporterId // ignore: cast_nullable_to_non_nullable
as String,messageId: null == messageId ? _self.messageId : messageId // ignore: cast_nullable_to_non_nullable
as String,roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,reportedAt: null == reportedAt ? _self.reportedAt : reportedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
