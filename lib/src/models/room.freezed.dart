// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'room.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ChatRoom {

 String get id; String? get owner; String? get name; String? get subject; RoomAudience get audience; bool get allowInvitations; List<String> get members; String? get publicToken; String? get avatarUrl; Map<String, dynamic>? get custom;
/// Create a copy of ChatRoom
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatRoomCopyWith<ChatRoom> get copyWith => _$ChatRoomCopyWithImpl<ChatRoom>(this as ChatRoom, _$identity);







}

/// @nodoc
abstract mixin class $ChatRoomCopyWith<$Res>  {
  factory $ChatRoomCopyWith(ChatRoom value, $Res Function(ChatRoom) _then) = _$ChatRoomCopyWithImpl;
@useResult
$Res call({
 String id, String? owner, String? name, String? subject, RoomAudience audience, bool allowInvitations, List<String> members, String? publicToken, String? avatarUrl, Map<String, dynamic>? custom
});




}
/// @nodoc
class _$ChatRoomCopyWithImpl<$Res>
    implements $ChatRoomCopyWith<$Res> {
  _$ChatRoomCopyWithImpl(this._self, this._then);

  final ChatRoom _self;
  final $Res Function(ChatRoom) _then;

/// Create a copy of ChatRoom
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? owner = freezed,Object? name = freezed,Object? subject = freezed,Object? audience = null,Object? allowInvitations = null,Object? members = null,Object? publicToken = freezed,Object? avatarUrl = freezed,Object? custom = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,owner: freezed == owner ? _self.owner : owner // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,subject: freezed == subject ? _self.subject : subject // ignore: cast_nullable_to_non_nullable
as String?,audience: null == audience ? _self.audience : audience // ignore: cast_nullable_to_non_nullable
as RoomAudience,allowInvitations: null == allowInvitations ? _self.allowInvitations : allowInvitations // ignore: cast_nullable_to_non_nullable
as bool,members: null == members ? _self.members : members // ignore: cast_nullable_to_non_nullable
as List<String>,publicToken: freezed == publicToken ? _self.publicToken : publicToken // ignore: cast_nullable_to_non_nullable
as String?,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,custom: freezed == custom ? _self.custom : custom // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,
  ));
}

}


/// Adds pattern-matching-related methods to [ChatRoom].
extension ChatRoomPatterns on ChatRoom {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatRoom value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatRoom() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatRoom value)  $default,){
final _that = this;
switch (_that) {
case _ChatRoom():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatRoom value)?  $default,){
final _that = this;
switch (_that) {
case _ChatRoom() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String? owner,  String? name,  String? subject,  RoomAudience audience,  bool allowInvitations,  List<String> members,  String? publicToken,  String? avatarUrl,  Map<String, dynamic>? custom)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatRoom() when $default != null:
return $default(_that.id,_that.owner,_that.name,_that.subject,_that.audience,_that.allowInvitations,_that.members,_that.publicToken,_that.avatarUrl,_that.custom);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String? owner,  String? name,  String? subject,  RoomAudience audience,  bool allowInvitations,  List<String> members,  String? publicToken,  String? avatarUrl,  Map<String, dynamic>? custom)  $default,) {final _that = this;
switch (_that) {
case _ChatRoom():
return $default(_that.id,_that.owner,_that.name,_that.subject,_that.audience,_that.allowInvitations,_that.members,_that.publicToken,_that.avatarUrl,_that.custom);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String? owner,  String? name,  String? subject,  RoomAudience audience,  bool allowInvitations,  List<String> members,  String? publicToken,  String? avatarUrl,  Map<String, dynamic>? custom)?  $default,) {final _that = this;
switch (_that) {
case _ChatRoom() when $default != null:
return $default(_that.id,_that.owner,_that.name,_that.subject,_that.audience,_that.allowInvitations,_that.members,_that.publicToken,_that.avatarUrl,_that.custom);case _:
  return null;

}
}

}

/// @nodoc


class _ChatRoom extends ChatRoom {
  const _ChatRoom({required this.id, this.owner, this.name, this.subject, this.audience = RoomAudience.contacts, this.allowInvitations = false, final  List<String> members = const [], this.publicToken, this.avatarUrl, final  Map<String, dynamic>? custom}): _members = members,_custom = custom,super._();
  

@override final  String id;
@override final  String? owner;
@override final  String? name;
@override final  String? subject;
@override@JsonKey() final  RoomAudience audience;
@override@JsonKey() final  bool allowInvitations;
 final  List<String> _members;
@override@JsonKey() List<String> get members {
  if (_members is EqualUnmodifiableListView) return _members;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_members);
}

@override final  String? publicToken;
@override final  String? avatarUrl;
 final  Map<String, dynamic>? _custom;
@override Map<String, dynamic>? get custom {
  final value = _custom;
  if (value == null) return null;
  if (_custom is EqualUnmodifiableMapView) return _custom;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of ChatRoom
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatRoomCopyWith<_ChatRoom> get copyWith => __$ChatRoomCopyWithImpl<_ChatRoom>(this, _$identity);







}

/// @nodoc
abstract mixin class _$ChatRoomCopyWith<$Res> implements $ChatRoomCopyWith<$Res> {
  factory _$ChatRoomCopyWith(_ChatRoom value, $Res Function(_ChatRoom) _then) = __$ChatRoomCopyWithImpl;
@override @useResult
$Res call({
 String id, String? owner, String? name, String? subject, RoomAudience audience, bool allowInvitations, List<String> members, String? publicToken, String? avatarUrl, Map<String, dynamic>? custom
});




}
/// @nodoc
class __$ChatRoomCopyWithImpl<$Res>
    implements _$ChatRoomCopyWith<$Res> {
  __$ChatRoomCopyWithImpl(this._self, this._then);

  final _ChatRoom _self;
  final $Res Function(_ChatRoom) _then;

/// Create a copy of ChatRoom
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? owner = freezed,Object? name = freezed,Object? subject = freezed,Object? audience = null,Object? allowInvitations = null,Object? members = null,Object? publicToken = freezed,Object? avatarUrl = freezed,Object? custom = freezed,}) {
  return _then(_ChatRoom(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,owner: freezed == owner ? _self.owner : owner // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,subject: freezed == subject ? _self.subject : subject // ignore: cast_nullable_to_non_nullable
as String?,audience: null == audience ? _self.audience : audience // ignore: cast_nullable_to_non_nullable
as RoomAudience,allowInvitations: null == allowInvitations ? _self.allowInvitations : allowInvitations // ignore: cast_nullable_to_non_nullable
as bool,members: null == members ? _self._members : members // ignore: cast_nullable_to_non_nullable
as List<String>,publicToken: freezed == publicToken ? _self.publicToken : publicToken // ignore: cast_nullable_to_non_nullable
as String?,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,custom: freezed == custom ? _self._custom : custom // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,
  ));
}


}

/// @nodoc
mixin _$RoomDetail {

 String get id; String? get name; String? get subject; RoomType get type; int get memberCount; RoomRole get userRole; RoomConfig get config; bool get muted; bool get pinned; DateTime? get createdAt; String? get avatarUrl; Map<String, dynamic>? get custom;
/// Create a copy of RoomDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoomDetailCopyWith<RoomDetail> get copyWith => _$RoomDetailCopyWithImpl<RoomDetail>(this as RoomDetail, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoomDetail&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.subject, subject) || other.subject == subject)&&(identical(other.type, type) || other.type == type)&&(identical(other.memberCount, memberCount) || other.memberCount == memberCount)&&(identical(other.userRole, userRole) || other.userRole == userRole)&&(identical(other.config, config) || other.config == config)&&(identical(other.muted, muted) || other.muted == muted)&&(identical(other.pinned, pinned) || other.pinned == pinned)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.avatarUrl, avatarUrl) || other.avatarUrl == avatarUrl)&&const DeepCollectionEquality().equals(other.custom, custom));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,subject,type,memberCount,userRole,config,muted,pinned,createdAt,avatarUrl,const DeepCollectionEquality().hash(custom));

@override
String toString() {
  return 'RoomDetail(id: $id, name: $name, subject: $subject, type: $type, memberCount: $memberCount, userRole: $userRole, config: $config, muted: $muted, pinned: $pinned, createdAt: $createdAt, avatarUrl: $avatarUrl, custom: $custom)';
}


}

/// @nodoc
abstract mixin class $RoomDetailCopyWith<$Res>  {
  factory $RoomDetailCopyWith(RoomDetail value, $Res Function(RoomDetail) _then) = _$RoomDetailCopyWithImpl;
@useResult
$Res call({
 String id, String? name, String? subject, RoomType type, int memberCount, RoomRole userRole, RoomConfig config, bool muted, bool pinned, DateTime? createdAt, String? avatarUrl, Map<String, dynamic>? custom
});


$RoomConfigCopyWith<$Res> get config;

}
/// @nodoc
class _$RoomDetailCopyWithImpl<$Res>
    implements $RoomDetailCopyWith<$Res> {
  _$RoomDetailCopyWithImpl(this._self, this._then);

  final RoomDetail _self;
  final $Res Function(RoomDetail) _then;

/// Create a copy of RoomDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = freezed,Object? subject = freezed,Object? type = null,Object? memberCount = null,Object? userRole = null,Object? config = null,Object? muted = null,Object? pinned = null,Object? createdAt = freezed,Object? avatarUrl = freezed,Object? custom = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,subject: freezed == subject ? _self.subject : subject // ignore: cast_nullable_to_non_nullable
as String?,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as RoomType,memberCount: null == memberCount ? _self.memberCount : memberCount // ignore: cast_nullable_to_non_nullable
as int,userRole: null == userRole ? _self.userRole : userRole // ignore: cast_nullable_to_non_nullable
as RoomRole,config: null == config ? _self.config : config // ignore: cast_nullable_to_non_nullable
as RoomConfig,muted: null == muted ? _self.muted : muted // ignore: cast_nullable_to_non_nullable
as bool,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,custom: freezed == custom ? _self.custom : custom // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,
  ));
}
/// Create a copy of RoomDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RoomConfigCopyWith<$Res> get config {
  
  return $RoomConfigCopyWith<$Res>(_self.config, (value) {
    return _then(_self.copyWith(config: value));
  });
}
}


/// Adds pattern-matching-related methods to [RoomDetail].
extension RoomDetailPatterns on RoomDetail {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoomDetail value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoomDetail() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoomDetail value)  $default,){
final _that = this;
switch (_that) {
case _RoomDetail():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoomDetail value)?  $default,){
final _that = this;
switch (_that) {
case _RoomDetail() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String? name,  String? subject,  RoomType type,  int memberCount,  RoomRole userRole,  RoomConfig config,  bool muted,  bool pinned,  DateTime? createdAt,  String? avatarUrl,  Map<String, dynamic>? custom)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoomDetail() when $default != null:
return $default(_that.id,_that.name,_that.subject,_that.type,_that.memberCount,_that.userRole,_that.config,_that.muted,_that.pinned,_that.createdAt,_that.avatarUrl,_that.custom);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String? name,  String? subject,  RoomType type,  int memberCount,  RoomRole userRole,  RoomConfig config,  bool muted,  bool pinned,  DateTime? createdAt,  String? avatarUrl,  Map<String, dynamic>? custom)  $default,) {final _that = this;
switch (_that) {
case _RoomDetail():
return $default(_that.id,_that.name,_that.subject,_that.type,_that.memberCount,_that.userRole,_that.config,_that.muted,_that.pinned,_that.createdAt,_that.avatarUrl,_that.custom);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String? name,  String? subject,  RoomType type,  int memberCount,  RoomRole userRole,  RoomConfig config,  bool muted,  bool pinned,  DateTime? createdAt,  String? avatarUrl,  Map<String, dynamic>? custom)?  $default,) {final _that = this;
switch (_that) {
case _RoomDetail() when $default != null:
return $default(_that.id,_that.name,_that.subject,_that.type,_that.memberCount,_that.userRole,_that.config,_that.muted,_that.pinned,_that.createdAt,_that.avatarUrl,_that.custom);case _:
  return null;

}
}

}

/// @nodoc


class _RoomDetail implements RoomDetail {
  const _RoomDetail({required this.id, this.name, this.subject, required this.type, required this.memberCount, required this.userRole, required this.config, this.muted = false, this.pinned = false, this.createdAt, this.avatarUrl, final  Map<String, dynamic>? custom}): _custom = custom;
  

@override final  String id;
@override final  String? name;
@override final  String? subject;
@override final  RoomType type;
@override final  int memberCount;
@override final  RoomRole userRole;
@override final  RoomConfig config;
@override@JsonKey() final  bool muted;
@override@JsonKey() final  bool pinned;
@override final  DateTime? createdAt;
@override final  String? avatarUrl;
 final  Map<String, dynamic>? _custom;
@override Map<String, dynamic>? get custom {
  final value = _custom;
  if (value == null) return null;
  if (_custom is EqualUnmodifiableMapView) return _custom;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of RoomDetail
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoomDetailCopyWith<_RoomDetail> get copyWith => __$RoomDetailCopyWithImpl<_RoomDetail>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoomDetail&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.subject, subject) || other.subject == subject)&&(identical(other.type, type) || other.type == type)&&(identical(other.memberCount, memberCount) || other.memberCount == memberCount)&&(identical(other.userRole, userRole) || other.userRole == userRole)&&(identical(other.config, config) || other.config == config)&&(identical(other.muted, muted) || other.muted == muted)&&(identical(other.pinned, pinned) || other.pinned == pinned)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.avatarUrl, avatarUrl) || other.avatarUrl == avatarUrl)&&const DeepCollectionEquality().equals(other._custom, _custom));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,subject,type,memberCount,userRole,config,muted,pinned,createdAt,avatarUrl,const DeepCollectionEquality().hash(_custom));

@override
String toString() {
  return 'RoomDetail(id: $id, name: $name, subject: $subject, type: $type, memberCount: $memberCount, userRole: $userRole, config: $config, muted: $muted, pinned: $pinned, createdAt: $createdAt, avatarUrl: $avatarUrl, custom: $custom)';
}


}

/// @nodoc
abstract mixin class _$RoomDetailCopyWith<$Res> implements $RoomDetailCopyWith<$Res> {
  factory _$RoomDetailCopyWith(_RoomDetail value, $Res Function(_RoomDetail) _then) = __$RoomDetailCopyWithImpl;
@override @useResult
$Res call({
 String id, String? name, String? subject, RoomType type, int memberCount, RoomRole userRole, RoomConfig config, bool muted, bool pinned, DateTime? createdAt, String? avatarUrl, Map<String, dynamic>? custom
});


@override $RoomConfigCopyWith<$Res> get config;

}
/// @nodoc
class __$RoomDetailCopyWithImpl<$Res>
    implements _$RoomDetailCopyWith<$Res> {
  __$RoomDetailCopyWithImpl(this._self, this._then);

  final _RoomDetail _self;
  final $Res Function(_RoomDetail) _then;

/// Create a copy of RoomDetail
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = freezed,Object? subject = freezed,Object? type = null,Object? memberCount = null,Object? userRole = null,Object? config = null,Object? muted = null,Object? pinned = null,Object? createdAt = freezed,Object? avatarUrl = freezed,Object? custom = freezed,}) {
  return _then(_RoomDetail(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,subject: freezed == subject ? _self.subject : subject // ignore: cast_nullable_to_non_nullable
as String?,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as RoomType,memberCount: null == memberCount ? _self.memberCount : memberCount // ignore: cast_nullable_to_non_nullable
as int,userRole: null == userRole ? _self.userRole : userRole // ignore: cast_nullable_to_non_nullable
as RoomRole,config: null == config ? _self.config : config // ignore: cast_nullable_to_non_nullable
as RoomConfig,muted: null == muted ? _self.muted : muted // ignore: cast_nullable_to_non_nullable
as bool,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,custom: freezed == custom ? _self._custom : custom // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,
  ));
}

/// Create a copy of RoomDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RoomConfigCopyWith<$Res> get config {
  
  return $RoomConfigCopyWith<$Res>(_self.config, (value) {
    return _then(_self.copyWith(config: value));
  });
}
}

/// @nodoc
mixin _$RoomConfig {

 bool get allowInvitations;
/// Create a copy of RoomConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoomConfigCopyWith<RoomConfig> get copyWith => _$RoomConfigCopyWithImpl<RoomConfig>(this as RoomConfig, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoomConfig&&(identical(other.allowInvitations, allowInvitations) || other.allowInvitations == allowInvitations));
}


@override
int get hashCode => Object.hash(runtimeType,allowInvitations);

@override
String toString() {
  return 'RoomConfig(allowInvitations: $allowInvitations)';
}


}

/// @nodoc
abstract mixin class $RoomConfigCopyWith<$Res>  {
  factory $RoomConfigCopyWith(RoomConfig value, $Res Function(RoomConfig) _then) = _$RoomConfigCopyWithImpl;
@useResult
$Res call({
 bool allowInvitations
});




}
/// @nodoc
class _$RoomConfigCopyWithImpl<$Res>
    implements $RoomConfigCopyWith<$Res> {
  _$RoomConfigCopyWithImpl(this._self, this._then);

  final RoomConfig _self;
  final $Res Function(RoomConfig) _then;

/// Create a copy of RoomConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? allowInvitations = null,}) {
  return _then(_self.copyWith(
allowInvitations: null == allowInvitations ? _self.allowInvitations : allowInvitations // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [RoomConfig].
extension RoomConfigPatterns on RoomConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoomConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoomConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoomConfig value)  $default,){
final _that = this;
switch (_that) {
case _RoomConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoomConfig value)?  $default,){
final _that = this;
switch (_that) {
case _RoomConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool allowInvitations)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoomConfig() when $default != null:
return $default(_that.allowInvitations);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool allowInvitations)  $default,) {final _that = this;
switch (_that) {
case _RoomConfig():
return $default(_that.allowInvitations);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool allowInvitations)?  $default,) {final _that = this;
switch (_that) {
case _RoomConfig() when $default != null:
return $default(_that.allowInvitations);case _:
  return null;

}
}

}

/// @nodoc


class _RoomConfig implements RoomConfig {
  const _RoomConfig({this.allowInvitations = false});
  

@override@JsonKey() final  bool allowInvitations;

/// Create a copy of RoomConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoomConfigCopyWith<_RoomConfig> get copyWith => __$RoomConfigCopyWithImpl<_RoomConfig>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoomConfig&&(identical(other.allowInvitations, allowInvitations) || other.allowInvitations == allowInvitations));
}


@override
int get hashCode => Object.hash(runtimeType,allowInvitations);

@override
String toString() {
  return 'RoomConfig(allowInvitations: $allowInvitations)';
}


}

/// @nodoc
abstract mixin class _$RoomConfigCopyWith<$Res> implements $RoomConfigCopyWith<$Res> {
  factory _$RoomConfigCopyWith(_RoomConfig value, $Res Function(_RoomConfig) _then) = __$RoomConfigCopyWithImpl;
@override @useResult
$Res call({
 bool allowInvitations
});




}
/// @nodoc
class __$RoomConfigCopyWithImpl<$Res>
    implements _$RoomConfigCopyWith<$Res> {
  __$RoomConfigCopyWithImpl(this._self, this._then);

  final _RoomConfig _self;
  final $Res Function(_RoomConfig) _then;

/// Create a copy of RoomConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? allowInvitations = null,}) {
  return _then(_RoomConfig(
allowInvitations: null == allowInvitations ? _self.allowInvitations : allowInvitations // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$DiscoveredRoom {

 String get id; String? get name; String? get subject; String? get owner; int? get memberCount; String? get avatarUrl; Map<String, dynamic>? get custom;
/// Create a copy of DiscoveredRoom
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiscoveredRoomCopyWith<DiscoveredRoom> get copyWith => _$DiscoveredRoomCopyWithImpl<DiscoveredRoom>(this as DiscoveredRoom, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiscoveredRoom&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.subject, subject) || other.subject == subject)&&(identical(other.owner, owner) || other.owner == owner)&&(identical(other.memberCount, memberCount) || other.memberCount == memberCount)&&(identical(other.avatarUrl, avatarUrl) || other.avatarUrl == avatarUrl)&&const DeepCollectionEquality().equals(other.custom, custom));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,subject,owner,memberCount,avatarUrl,const DeepCollectionEquality().hash(custom));

@override
String toString() {
  return 'DiscoveredRoom(id: $id, name: $name, subject: $subject, owner: $owner, memberCount: $memberCount, avatarUrl: $avatarUrl, custom: $custom)';
}


}

/// @nodoc
abstract mixin class $DiscoveredRoomCopyWith<$Res>  {
  factory $DiscoveredRoomCopyWith(DiscoveredRoom value, $Res Function(DiscoveredRoom) _then) = _$DiscoveredRoomCopyWithImpl;
@useResult
$Res call({
 String id, String? name, String? subject, String? owner, int? memberCount, String? avatarUrl, Map<String, dynamic>? custom
});




}
/// @nodoc
class _$DiscoveredRoomCopyWithImpl<$Res>
    implements $DiscoveredRoomCopyWith<$Res> {
  _$DiscoveredRoomCopyWithImpl(this._self, this._then);

  final DiscoveredRoom _self;
  final $Res Function(DiscoveredRoom) _then;

/// Create a copy of DiscoveredRoom
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = freezed,Object? subject = freezed,Object? owner = freezed,Object? memberCount = freezed,Object? avatarUrl = freezed,Object? custom = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,subject: freezed == subject ? _self.subject : subject // ignore: cast_nullable_to_non_nullable
as String?,owner: freezed == owner ? _self.owner : owner // ignore: cast_nullable_to_non_nullable
as String?,memberCount: freezed == memberCount ? _self.memberCount : memberCount // ignore: cast_nullable_to_non_nullable
as int?,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,custom: freezed == custom ? _self.custom : custom // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,
  ));
}

}


/// Adds pattern-matching-related methods to [DiscoveredRoom].
extension DiscoveredRoomPatterns on DiscoveredRoom {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DiscoveredRoom value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DiscoveredRoom() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DiscoveredRoom value)  $default,){
final _that = this;
switch (_that) {
case _DiscoveredRoom():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DiscoveredRoom value)?  $default,){
final _that = this;
switch (_that) {
case _DiscoveredRoom() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String? name,  String? subject,  String? owner,  int? memberCount,  String? avatarUrl,  Map<String, dynamic>? custom)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DiscoveredRoom() when $default != null:
return $default(_that.id,_that.name,_that.subject,_that.owner,_that.memberCount,_that.avatarUrl,_that.custom);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String? name,  String? subject,  String? owner,  int? memberCount,  String? avatarUrl,  Map<String, dynamic>? custom)  $default,) {final _that = this;
switch (_that) {
case _DiscoveredRoom():
return $default(_that.id,_that.name,_that.subject,_that.owner,_that.memberCount,_that.avatarUrl,_that.custom);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String? name,  String? subject,  String? owner,  int? memberCount,  String? avatarUrl,  Map<String, dynamic>? custom)?  $default,) {final _that = this;
switch (_that) {
case _DiscoveredRoom() when $default != null:
return $default(_that.id,_that.name,_that.subject,_that.owner,_that.memberCount,_that.avatarUrl,_that.custom);case _:
  return null;

}
}

}

/// @nodoc


class _DiscoveredRoom implements DiscoveredRoom {
  const _DiscoveredRoom({required this.id, this.name, this.subject, this.owner, this.memberCount, this.avatarUrl, final  Map<String, dynamic>? custom}): _custom = custom;
  

@override final  String id;
@override final  String? name;
@override final  String? subject;
@override final  String? owner;
@override final  int? memberCount;
@override final  String? avatarUrl;
 final  Map<String, dynamic>? _custom;
@override Map<String, dynamic>? get custom {
  final value = _custom;
  if (value == null) return null;
  if (_custom is EqualUnmodifiableMapView) return _custom;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of DiscoveredRoom
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DiscoveredRoomCopyWith<_DiscoveredRoom> get copyWith => __$DiscoveredRoomCopyWithImpl<_DiscoveredRoom>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DiscoveredRoom&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.subject, subject) || other.subject == subject)&&(identical(other.owner, owner) || other.owner == owner)&&(identical(other.memberCount, memberCount) || other.memberCount == memberCount)&&(identical(other.avatarUrl, avatarUrl) || other.avatarUrl == avatarUrl)&&const DeepCollectionEquality().equals(other._custom, _custom));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,subject,owner,memberCount,avatarUrl,const DeepCollectionEquality().hash(_custom));

@override
String toString() {
  return 'DiscoveredRoom(id: $id, name: $name, subject: $subject, owner: $owner, memberCount: $memberCount, avatarUrl: $avatarUrl, custom: $custom)';
}


}

/// @nodoc
abstract mixin class _$DiscoveredRoomCopyWith<$Res> implements $DiscoveredRoomCopyWith<$Res> {
  factory _$DiscoveredRoomCopyWith(_DiscoveredRoom value, $Res Function(_DiscoveredRoom) _then) = __$DiscoveredRoomCopyWithImpl;
@override @useResult
$Res call({
 String id, String? name, String? subject, String? owner, int? memberCount, String? avatarUrl, Map<String, dynamic>? custom
});




}
/// @nodoc
class __$DiscoveredRoomCopyWithImpl<$Res>
    implements _$DiscoveredRoomCopyWith<$Res> {
  __$DiscoveredRoomCopyWithImpl(this._self, this._then);

  final _DiscoveredRoom _self;
  final $Res Function(_DiscoveredRoom) _then;

/// Create a copy of DiscoveredRoom
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = freezed,Object? subject = freezed,Object? owner = freezed,Object? memberCount = freezed,Object? avatarUrl = freezed,Object? custom = freezed,}) {
  return _then(_DiscoveredRoom(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,subject: freezed == subject ? _self.subject : subject // ignore: cast_nullable_to_non_nullable
as String?,owner: freezed == owner ? _self.owner : owner // ignore: cast_nullable_to_non_nullable
as String?,memberCount: freezed == memberCount ? _self.memberCount : memberCount // ignore: cast_nullable_to_non_nullable
as int?,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,custom: freezed == custom ? _self._custom : custom // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,
  ));
}


}

// dart format on
