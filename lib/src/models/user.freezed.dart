// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'user.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ChatUser {

 String get id; String? get displayName; String? get avatarUrl; String? get bio; String? get email; UserRole get role; bool get active; Map<String, dynamic>? get custom; UserConfiguration? get configuration;
/// Create a copy of ChatUser
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatUserCopyWith<ChatUser> get copyWith => _$ChatUserCopyWithImpl<ChatUser>(this as ChatUser, _$identity);







}

/// @nodoc
abstract mixin class $ChatUserCopyWith<$Res>  {
  factory $ChatUserCopyWith(ChatUser value, $Res Function(ChatUser) _then) = _$ChatUserCopyWithImpl;
@useResult
$Res call({
 String id, String? displayName, String? avatarUrl, String? bio, String? email, UserRole role, bool active, Map<String, dynamic>? custom, UserConfiguration? configuration
});


$UserConfigurationCopyWith<$Res>? get configuration;

}
/// @nodoc
class _$ChatUserCopyWithImpl<$Res>
    implements $ChatUserCopyWith<$Res> {
  _$ChatUserCopyWithImpl(this._self, this._then);

  final ChatUser _self;
  final $Res Function(ChatUser) _then;

/// Create a copy of ChatUser
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? displayName = freezed,Object? avatarUrl = freezed,Object? bio = freezed,Object? email = freezed,Object? role = null,Object? active = null,Object? custom = freezed,Object? configuration = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: freezed == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String?,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,bio: freezed == bio ? _self.bio : bio // ignore: cast_nullable_to_non_nullable
as String?,email: freezed == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String?,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as UserRole,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,custom: freezed == custom ? _self.custom : custom // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,configuration: freezed == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as UserConfiguration?,
  ));
}
/// Create a copy of ChatUser
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UserConfigurationCopyWith<$Res>? get configuration {
    if (_self.configuration == null) {
    return null;
  }

  return $UserConfigurationCopyWith<$Res>(_self.configuration!, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}
}


/// Adds pattern-matching-related methods to [ChatUser].
extension ChatUserPatterns on ChatUser {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatUser value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatUser() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatUser value)  $default,){
final _that = this;
switch (_that) {
case _ChatUser():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatUser value)?  $default,){
final _that = this;
switch (_that) {
case _ChatUser() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String? displayName,  String? avatarUrl,  String? bio,  String? email,  UserRole role,  bool active,  Map<String, dynamic>? custom,  UserConfiguration? configuration)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatUser() when $default != null:
return $default(_that.id,_that.displayName,_that.avatarUrl,_that.bio,_that.email,_that.role,_that.active,_that.custom,_that.configuration);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String? displayName,  String? avatarUrl,  String? bio,  String? email,  UserRole role,  bool active,  Map<String, dynamic>? custom,  UserConfiguration? configuration)  $default,) {final _that = this;
switch (_that) {
case _ChatUser():
return $default(_that.id,_that.displayName,_that.avatarUrl,_that.bio,_that.email,_that.role,_that.active,_that.custom,_that.configuration);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String? displayName,  String? avatarUrl,  String? bio,  String? email,  UserRole role,  bool active,  Map<String, dynamic>? custom,  UserConfiguration? configuration)?  $default,) {final _that = this;
switch (_that) {
case _ChatUser() when $default != null:
return $default(_that.id,_that.displayName,_that.avatarUrl,_that.bio,_that.email,_that.role,_that.active,_that.custom,_that.configuration);case _:
  return null;

}
}

}

/// @nodoc


class _ChatUser extends ChatUser {
  const _ChatUser({required this.id, this.displayName, this.avatarUrl, this.bio, this.email, this.role = UserRole.user, this.active = true, final  Map<String, dynamic>? custom, this.configuration}): _custom = custom,super._();
  

@override final  String id;
@override final  String? displayName;
@override final  String? avatarUrl;
@override final  String? bio;
@override final  String? email;
@override@JsonKey() final  UserRole role;
@override@JsonKey() final  bool active;
 final  Map<String, dynamic>? _custom;
@override Map<String, dynamic>? get custom {
  final value = _custom;
  if (value == null) return null;
  if (_custom is EqualUnmodifiableMapView) return _custom;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

@override final  UserConfiguration? configuration;

/// Create a copy of ChatUser
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatUserCopyWith<_ChatUser> get copyWith => __$ChatUserCopyWithImpl<_ChatUser>(this, _$identity);







}

/// @nodoc
abstract mixin class _$ChatUserCopyWith<$Res> implements $ChatUserCopyWith<$Res> {
  factory _$ChatUserCopyWith(_ChatUser value, $Res Function(_ChatUser) _then) = __$ChatUserCopyWithImpl;
@override @useResult
$Res call({
 String id, String? displayName, String? avatarUrl, String? bio, String? email, UserRole role, bool active, Map<String, dynamic>? custom, UserConfiguration? configuration
});


@override $UserConfigurationCopyWith<$Res>? get configuration;

}
/// @nodoc
class __$ChatUserCopyWithImpl<$Res>
    implements _$ChatUserCopyWith<$Res> {
  __$ChatUserCopyWithImpl(this._self, this._then);

  final _ChatUser _self;
  final $Res Function(_ChatUser) _then;

/// Create a copy of ChatUser
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? displayName = freezed,Object? avatarUrl = freezed,Object? bio = freezed,Object? email = freezed,Object? role = null,Object? active = null,Object? custom = freezed,Object? configuration = freezed,}) {
  return _then(_ChatUser(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: freezed == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String?,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,bio: freezed == bio ? _self.bio : bio // ignore: cast_nullable_to_non_nullable
as String?,email: freezed == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String?,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as UserRole,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,custom: freezed == custom ? _self._custom : custom // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,configuration: freezed == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as UserConfiguration?,
  ));
}

/// Create a copy of ChatUser
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UserConfigurationCopyWith<$Res>? get configuration {
    if (_self.configuration == null) {
    return null;
  }

  return $UserConfigurationCopyWith<$Res>(_self.configuration!, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}
}

/// @nodoc
mixin _$UserConfiguration {

 Map<String, dynamic>? get metadata; WebhookConfig? get webhook;
/// Create a copy of UserConfiguration
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserConfigurationCopyWith<UserConfiguration> get copyWith => _$UserConfigurationCopyWithImpl<UserConfiguration>(this as UserConfiguration, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UserConfiguration&&const DeepCollectionEquality().equals(other.metadata, metadata)&&(identical(other.webhook, webhook) || other.webhook == webhook));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(metadata),webhook);

@override
String toString() {
  return 'UserConfiguration(metadata: $metadata, webhook: $webhook)';
}


}

/// @nodoc
abstract mixin class $UserConfigurationCopyWith<$Res>  {
  factory $UserConfigurationCopyWith(UserConfiguration value, $Res Function(UserConfiguration) _then) = _$UserConfigurationCopyWithImpl;
@useResult
$Res call({
 Map<String, dynamic>? metadata, WebhookConfig? webhook
});


$WebhookConfigCopyWith<$Res>? get webhook;

}
/// @nodoc
class _$UserConfigurationCopyWithImpl<$Res>
    implements $UserConfigurationCopyWith<$Res> {
  _$UserConfigurationCopyWithImpl(this._self, this._then);

  final UserConfiguration _self;
  final $Res Function(UserConfiguration) _then;

/// Create a copy of UserConfiguration
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? metadata = freezed,Object? webhook = freezed,}) {
  return _then(_self.copyWith(
metadata: freezed == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,webhook: freezed == webhook ? _self.webhook : webhook // ignore: cast_nullable_to_non_nullable
as WebhookConfig?,
  ));
}
/// Create a copy of UserConfiguration
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WebhookConfigCopyWith<$Res>? get webhook {
    if (_self.webhook == null) {
    return null;
  }

  return $WebhookConfigCopyWith<$Res>(_self.webhook!, (value) {
    return _then(_self.copyWith(webhook: value));
  });
}
}


/// Adds pattern-matching-related methods to [UserConfiguration].
extension UserConfigurationPatterns on UserConfiguration {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UserConfiguration value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UserConfiguration() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UserConfiguration value)  $default,){
final _that = this;
switch (_that) {
case _UserConfiguration():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UserConfiguration value)?  $default,){
final _that = this;
switch (_that) {
case _UserConfiguration() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Map<String, dynamic>? metadata,  WebhookConfig? webhook)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UserConfiguration() when $default != null:
return $default(_that.metadata,_that.webhook);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Map<String, dynamic>? metadata,  WebhookConfig? webhook)  $default,) {final _that = this;
switch (_that) {
case _UserConfiguration():
return $default(_that.metadata,_that.webhook);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Map<String, dynamic>? metadata,  WebhookConfig? webhook)?  $default,) {final _that = this;
switch (_that) {
case _UserConfiguration() when $default != null:
return $default(_that.metadata,_that.webhook);case _:
  return null;

}
}

}

/// @nodoc


class _UserConfiguration implements UserConfiguration {
  const _UserConfiguration({final  Map<String, dynamic>? metadata, this.webhook}): _metadata = metadata;
  

 final  Map<String, dynamic>? _metadata;
@override Map<String, dynamic>? get metadata {
  final value = _metadata;
  if (value == null) return null;
  if (_metadata is EqualUnmodifiableMapView) return _metadata;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

@override final  WebhookConfig? webhook;

/// Create a copy of UserConfiguration
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UserConfigurationCopyWith<_UserConfiguration> get copyWith => __$UserConfigurationCopyWithImpl<_UserConfiguration>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UserConfiguration&&const DeepCollectionEquality().equals(other._metadata, _metadata)&&(identical(other.webhook, webhook) || other.webhook == webhook));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_metadata),webhook);

@override
String toString() {
  return 'UserConfiguration(metadata: $metadata, webhook: $webhook)';
}


}

/// @nodoc
abstract mixin class _$UserConfigurationCopyWith<$Res> implements $UserConfigurationCopyWith<$Res> {
  factory _$UserConfigurationCopyWith(_UserConfiguration value, $Res Function(_UserConfiguration) _then) = __$UserConfigurationCopyWithImpl;
@override @useResult
$Res call({
 Map<String, dynamic>? metadata, WebhookConfig? webhook
});


@override $WebhookConfigCopyWith<$Res>? get webhook;

}
/// @nodoc
class __$UserConfigurationCopyWithImpl<$Res>
    implements _$UserConfigurationCopyWith<$Res> {
  __$UserConfigurationCopyWithImpl(this._self, this._then);

  final _UserConfiguration _self;
  final $Res Function(_UserConfiguration) _then;

/// Create a copy of UserConfiguration
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? metadata = freezed,Object? webhook = freezed,}) {
  return _then(_UserConfiguration(
metadata: freezed == metadata ? _self._metadata : metadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,webhook: freezed == webhook ? _self.webhook : webhook // ignore: cast_nullable_to_non_nullable
as WebhookConfig?,
  ));
}

/// Create a copy of UserConfiguration
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WebhookConfigCopyWith<$Res>? get webhook {
    if (_self.webhook == null) {
    return null;
  }

  return $WebhookConfigCopyWith<$Res>(_self.webhook!, (value) {
    return _then(_self.copyWith(webhook: value));
  });
}
}

/// @nodoc
mixin _$WebhookConfig {

 String get url; WebhookAuthType get authType; String? get token; String? get username; String? get password;
/// Create a copy of WebhookConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WebhookConfigCopyWith<WebhookConfig> get copyWith => _$WebhookConfigCopyWithImpl<WebhookConfig>(this as WebhookConfig, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WebhookConfig&&(identical(other.url, url) || other.url == url)&&(identical(other.authType, authType) || other.authType == authType)&&(identical(other.token, token) || other.token == token)&&(identical(other.username, username) || other.username == username)&&(identical(other.password, password) || other.password == password));
}


@override
int get hashCode => Object.hash(runtimeType,url,authType,token,username,password);

@override
String toString() {
  return 'WebhookConfig(url: $url, authType: $authType, token: $token, username: $username, password: $password)';
}


}

/// @nodoc
abstract mixin class $WebhookConfigCopyWith<$Res>  {
  factory $WebhookConfigCopyWith(WebhookConfig value, $Res Function(WebhookConfig) _then) = _$WebhookConfigCopyWithImpl;
@useResult
$Res call({
 String url, WebhookAuthType authType, String? token, String? username, String? password
});




}
/// @nodoc
class _$WebhookConfigCopyWithImpl<$Res>
    implements $WebhookConfigCopyWith<$Res> {
  _$WebhookConfigCopyWithImpl(this._self, this._then);

  final WebhookConfig _self;
  final $Res Function(WebhookConfig) _then;

/// Create a copy of WebhookConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? url = null,Object? authType = null,Object? token = freezed,Object? username = freezed,Object? password = freezed,}) {
  return _then(_self.copyWith(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,authType: null == authType ? _self.authType : authType // ignore: cast_nullable_to_non_nullable
as WebhookAuthType,token: freezed == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String?,username: freezed == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String?,password: freezed == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [WebhookConfig].
extension WebhookConfigPatterns on WebhookConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WebhookConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WebhookConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WebhookConfig value)  $default,){
final _that = this;
switch (_that) {
case _WebhookConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WebhookConfig value)?  $default,){
final _that = this;
switch (_that) {
case _WebhookConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String url,  WebhookAuthType authType,  String? token,  String? username,  String? password)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WebhookConfig() when $default != null:
return $default(_that.url,_that.authType,_that.token,_that.username,_that.password);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String url,  WebhookAuthType authType,  String? token,  String? username,  String? password)  $default,) {final _that = this;
switch (_that) {
case _WebhookConfig():
return $default(_that.url,_that.authType,_that.token,_that.username,_that.password);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String url,  WebhookAuthType authType,  String? token,  String? username,  String? password)?  $default,) {final _that = this;
switch (_that) {
case _WebhookConfig() when $default != null:
return $default(_that.url,_that.authType,_that.token,_that.username,_that.password);case _:
  return null;

}
}

}

/// @nodoc


class _WebhookConfig implements WebhookConfig {
  const _WebhookConfig({required this.url, required this.authType, this.token, this.username, this.password});
  

@override final  String url;
@override final  WebhookAuthType authType;
@override final  String? token;
@override final  String? username;
@override final  String? password;

/// Create a copy of WebhookConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WebhookConfigCopyWith<_WebhookConfig> get copyWith => __$WebhookConfigCopyWithImpl<_WebhookConfig>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WebhookConfig&&(identical(other.url, url) || other.url == url)&&(identical(other.authType, authType) || other.authType == authType)&&(identical(other.token, token) || other.token == token)&&(identical(other.username, username) || other.username == username)&&(identical(other.password, password) || other.password == password));
}


@override
int get hashCode => Object.hash(runtimeType,url,authType,token,username,password);

@override
String toString() {
  return 'WebhookConfig(url: $url, authType: $authType, token: $token, username: $username, password: $password)';
}


}

/// @nodoc
abstract mixin class _$WebhookConfigCopyWith<$Res> implements $WebhookConfigCopyWith<$Res> {
  factory _$WebhookConfigCopyWith(_WebhookConfig value, $Res Function(_WebhookConfig) _then) = __$WebhookConfigCopyWithImpl;
@override @useResult
$Res call({
 String url, WebhookAuthType authType, String? token, String? username, String? password
});




}
/// @nodoc
class __$WebhookConfigCopyWithImpl<$Res>
    implements _$WebhookConfigCopyWith<$Res> {
  __$WebhookConfigCopyWithImpl(this._self, this._then);

  final _WebhookConfig _self;
  final $Res Function(_WebhookConfig) _then;

/// Create a copy of WebhookConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? url = null,Object? authType = null,Object? token = freezed,Object? username = freezed,Object? password = freezed,}) {
  return _then(_WebhookConfig(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,authType: null == authType ? _self.authType : authType // ignore: cast_nullable_to_non_nullable
as WebhookAuthType,token: freezed == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String?,username: freezed == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String?,password: freezed == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
