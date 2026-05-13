// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'reaction.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AggregatedReaction {

 String get emoji; int get count; List<String> get users;
/// Create a copy of AggregatedReaction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AggregatedReactionCopyWith<AggregatedReaction> get copyWith => _$AggregatedReactionCopyWithImpl<AggregatedReaction>(this as AggregatedReaction, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AggregatedReaction&&(identical(other.emoji, emoji) || other.emoji == emoji)&&(identical(other.count, count) || other.count == count)&&const DeepCollectionEquality().equals(other.users, users));
}


@override
int get hashCode => Object.hash(runtimeType,emoji,count,const DeepCollectionEquality().hash(users));

@override
String toString() {
  return 'AggregatedReaction(emoji: $emoji, count: $count, users: $users)';
}


}

/// @nodoc
abstract mixin class $AggregatedReactionCopyWith<$Res>  {
  factory $AggregatedReactionCopyWith(AggregatedReaction value, $Res Function(AggregatedReaction) _then) = _$AggregatedReactionCopyWithImpl;
@useResult
$Res call({
 String emoji, int count, List<String> users
});




}
/// @nodoc
class _$AggregatedReactionCopyWithImpl<$Res>
    implements $AggregatedReactionCopyWith<$Res> {
  _$AggregatedReactionCopyWithImpl(this._self, this._then);

  final AggregatedReaction _self;
  final $Res Function(AggregatedReaction) _then;

/// Create a copy of AggregatedReaction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? emoji = null,Object? count = null,Object? users = null,}) {
  return _then(_self.copyWith(
emoji: null == emoji ? _self.emoji : emoji // ignore: cast_nullable_to_non_nullable
as String,count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,users: null == users ? _self.users : users // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [AggregatedReaction].
extension AggregatedReactionPatterns on AggregatedReaction {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AggregatedReaction value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AggregatedReaction() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AggregatedReaction value)  $default,){
final _that = this;
switch (_that) {
case _AggregatedReaction():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AggregatedReaction value)?  $default,){
final _that = this;
switch (_that) {
case _AggregatedReaction() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String emoji,  int count,  List<String> users)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AggregatedReaction() when $default != null:
return $default(_that.emoji,_that.count,_that.users);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String emoji,  int count,  List<String> users)  $default,) {final _that = this;
switch (_that) {
case _AggregatedReaction():
return $default(_that.emoji,_that.count,_that.users);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String emoji,  int count,  List<String> users)?  $default,) {final _that = this;
switch (_that) {
case _AggregatedReaction() when $default != null:
return $default(_that.emoji,_that.count,_that.users);case _:
  return null;

}
}

}

/// @nodoc


class _AggregatedReaction implements AggregatedReaction {
  const _AggregatedReaction({required this.emoji, required this.count, final  List<String> users = const []}): _users = users;
  

@override final  String emoji;
@override final  int count;
 final  List<String> _users;
@override@JsonKey() List<String> get users {
  if (_users is EqualUnmodifiableListView) return _users;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_users);
}


/// Create a copy of AggregatedReaction
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AggregatedReactionCopyWith<_AggregatedReaction> get copyWith => __$AggregatedReactionCopyWithImpl<_AggregatedReaction>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AggregatedReaction&&(identical(other.emoji, emoji) || other.emoji == emoji)&&(identical(other.count, count) || other.count == count)&&const DeepCollectionEquality().equals(other._users, _users));
}


@override
int get hashCode => Object.hash(runtimeType,emoji,count,const DeepCollectionEquality().hash(_users));

@override
String toString() {
  return 'AggregatedReaction(emoji: $emoji, count: $count, users: $users)';
}


}

/// @nodoc
abstract mixin class _$AggregatedReactionCopyWith<$Res> implements $AggregatedReactionCopyWith<$Res> {
  factory _$AggregatedReactionCopyWith(_AggregatedReaction value, $Res Function(_AggregatedReaction) _then) = __$AggregatedReactionCopyWithImpl;
@override @useResult
$Res call({
 String emoji, int count, List<String> users
});




}
/// @nodoc
class __$AggregatedReactionCopyWithImpl<$Res>
    implements _$AggregatedReactionCopyWith<$Res> {
  __$AggregatedReactionCopyWithImpl(this._self, this._then);

  final _AggregatedReaction _self;
  final $Res Function(_AggregatedReaction) _then;

/// Create a copy of AggregatedReaction
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? emoji = null,Object? count = null,Object? users = null,}) {
  return _then(_AggregatedReaction(
emoji: null == emoji ? _self.emoji : emoji // ignore: cast_nullable_to_non_nullable
as String,count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,users: null == users ? _self._users : users // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

// dart format on
