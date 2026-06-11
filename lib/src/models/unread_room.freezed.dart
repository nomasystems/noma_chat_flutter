// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'unread_room.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UnreadRoom {

 String get roomId; int get unreadMessages;/// Count of unread messages in this room that mention the current user.
/// `0` when there are none. Drives the "@" badge on the room tile
/// without fetching message bodies.
 int get unreadMentions; String? get lastMessage; DateTime? get lastMessageTime; String? get lastMessageUserId; String? get lastMessageId; MessageType? get lastMessageType; String? get lastMessageMimeType; String? get lastMessageFileName; int? get lastMessageDurationMs; bool get lastMessageIsDeleted; String? get lastMessageReactionEmoji; ReceiptStatus? get lastMessageReceipt; String? get name; String? get avatarUrl; String? get type; int? get memberCount; RoomRole? get userRole; bool get muted;/// When the notification mute expires (UTC). `null` means a permanent
/// mute (or not muted at all — check [muted]). Lets the UI show "muted
/// until 14:00" and the consumer re-derive [muted] after expiry.
 DateTime? get muteUntil; bool get pinned; bool get hidden; bool get selfMuted;
/// Create a copy of UnreadRoom
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnreadRoomCopyWith<UnreadRoom> get copyWith => _$UnreadRoomCopyWithImpl<UnreadRoom>(this as UnreadRoom, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UnreadRoom&&(identical(other.roomId, roomId) || other.roomId == roomId)&&(identical(other.unreadMessages, unreadMessages) || other.unreadMessages == unreadMessages)&&(identical(other.unreadMentions, unreadMentions) || other.unreadMentions == unreadMentions)&&(identical(other.lastMessage, lastMessage) || other.lastMessage == lastMessage)&&(identical(other.lastMessageTime, lastMessageTime) || other.lastMessageTime == lastMessageTime)&&(identical(other.lastMessageUserId, lastMessageUserId) || other.lastMessageUserId == lastMessageUserId)&&(identical(other.lastMessageId, lastMessageId) || other.lastMessageId == lastMessageId)&&(identical(other.lastMessageType, lastMessageType) || other.lastMessageType == lastMessageType)&&(identical(other.lastMessageMimeType, lastMessageMimeType) || other.lastMessageMimeType == lastMessageMimeType)&&(identical(other.lastMessageFileName, lastMessageFileName) || other.lastMessageFileName == lastMessageFileName)&&(identical(other.lastMessageDurationMs, lastMessageDurationMs) || other.lastMessageDurationMs == lastMessageDurationMs)&&(identical(other.lastMessageIsDeleted, lastMessageIsDeleted) || other.lastMessageIsDeleted == lastMessageIsDeleted)&&(identical(other.lastMessageReactionEmoji, lastMessageReactionEmoji) || other.lastMessageReactionEmoji == lastMessageReactionEmoji)&&(identical(other.lastMessageReceipt, lastMessageReceipt) || other.lastMessageReceipt == lastMessageReceipt)&&(identical(other.name, name) || other.name == name)&&(identical(other.avatarUrl, avatarUrl) || other.avatarUrl == avatarUrl)&&(identical(other.type, type) || other.type == type)&&(identical(other.memberCount, memberCount) || other.memberCount == memberCount)&&(identical(other.userRole, userRole) || other.userRole == userRole)&&(identical(other.muted, muted) || other.muted == muted)&&(identical(other.muteUntil, muteUntil) || other.muteUntil == muteUntil)&&(identical(other.pinned, pinned) || other.pinned == pinned)&&(identical(other.hidden, hidden) || other.hidden == hidden)&&(identical(other.selfMuted, selfMuted) || other.selfMuted == selfMuted));
}


@override
int get hashCode => Object.hashAll([runtimeType,roomId,unreadMessages,unreadMentions,lastMessage,lastMessageTime,lastMessageUserId,lastMessageId,lastMessageType,lastMessageMimeType,lastMessageFileName,lastMessageDurationMs,lastMessageIsDeleted,lastMessageReactionEmoji,lastMessageReceipt,name,avatarUrl,type,memberCount,userRole,muted,muteUntil,pinned,hidden,selfMuted]);

@override
String toString() {
  return 'UnreadRoom(roomId: $roomId, unreadMessages: $unreadMessages, unreadMentions: $unreadMentions, lastMessage: $lastMessage, lastMessageTime: $lastMessageTime, lastMessageUserId: $lastMessageUserId, lastMessageId: $lastMessageId, lastMessageType: $lastMessageType, lastMessageMimeType: $lastMessageMimeType, lastMessageFileName: $lastMessageFileName, lastMessageDurationMs: $lastMessageDurationMs, lastMessageIsDeleted: $lastMessageIsDeleted, lastMessageReactionEmoji: $lastMessageReactionEmoji, lastMessageReceipt: $lastMessageReceipt, name: $name, avatarUrl: $avatarUrl, type: $type, memberCount: $memberCount, userRole: $userRole, muted: $muted, muteUntil: $muteUntil, pinned: $pinned, hidden: $hidden, selfMuted: $selfMuted)';
}


}

/// @nodoc
abstract mixin class $UnreadRoomCopyWith<$Res>  {
  factory $UnreadRoomCopyWith(UnreadRoom value, $Res Function(UnreadRoom) _then) = _$UnreadRoomCopyWithImpl;
@useResult
$Res call({
 String roomId, int unreadMessages, int unreadMentions, String? lastMessage, DateTime? lastMessageTime, String? lastMessageUserId, String? lastMessageId, MessageType? lastMessageType, String? lastMessageMimeType, String? lastMessageFileName, int? lastMessageDurationMs, bool lastMessageIsDeleted, String? lastMessageReactionEmoji, ReceiptStatus? lastMessageReceipt, String? name, String? avatarUrl, String? type, int? memberCount, RoomRole? userRole, bool muted, DateTime? muteUntil, bool pinned, bool hidden, bool selfMuted
});




}
/// @nodoc
class _$UnreadRoomCopyWithImpl<$Res>
    implements $UnreadRoomCopyWith<$Res> {
  _$UnreadRoomCopyWithImpl(this._self, this._then);

  final UnreadRoom _self;
  final $Res Function(UnreadRoom) _then;

/// Create a copy of UnreadRoom
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? roomId = null,Object? unreadMessages = null,Object? unreadMentions = null,Object? lastMessage = freezed,Object? lastMessageTime = freezed,Object? lastMessageUserId = freezed,Object? lastMessageId = freezed,Object? lastMessageType = freezed,Object? lastMessageMimeType = freezed,Object? lastMessageFileName = freezed,Object? lastMessageDurationMs = freezed,Object? lastMessageIsDeleted = null,Object? lastMessageReactionEmoji = freezed,Object? lastMessageReceipt = freezed,Object? name = freezed,Object? avatarUrl = freezed,Object? type = freezed,Object? memberCount = freezed,Object? userRole = freezed,Object? muted = null,Object? muteUntil = freezed,Object? pinned = null,Object? hidden = null,Object? selfMuted = null,}) {
  return _then(_self.copyWith(
roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,unreadMessages: null == unreadMessages ? _self.unreadMessages : unreadMessages // ignore: cast_nullable_to_non_nullable
as int,unreadMentions: null == unreadMentions ? _self.unreadMentions : unreadMentions // ignore: cast_nullable_to_non_nullable
as int,lastMessage: freezed == lastMessage ? _self.lastMessage : lastMessage // ignore: cast_nullable_to_non_nullable
as String?,lastMessageTime: freezed == lastMessageTime ? _self.lastMessageTime : lastMessageTime // ignore: cast_nullable_to_non_nullable
as DateTime?,lastMessageUserId: freezed == lastMessageUserId ? _self.lastMessageUserId : lastMessageUserId // ignore: cast_nullable_to_non_nullable
as String?,lastMessageId: freezed == lastMessageId ? _self.lastMessageId : lastMessageId // ignore: cast_nullable_to_non_nullable
as String?,lastMessageType: freezed == lastMessageType ? _self.lastMessageType : lastMessageType // ignore: cast_nullable_to_non_nullable
as MessageType?,lastMessageMimeType: freezed == lastMessageMimeType ? _self.lastMessageMimeType : lastMessageMimeType // ignore: cast_nullable_to_non_nullable
as String?,lastMessageFileName: freezed == lastMessageFileName ? _self.lastMessageFileName : lastMessageFileName // ignore: cast_nullable_to_non_nullable
as String?,lastMessageDurationMs: freezed == lastMessageDurationMs ? _self.lastMessageDurationMs : lastMessageDurationMs // ignore: cast_nullable_to_non_nullable
as int?,lastMessageIsDeleted: null == lastMessageIsDeleted ? _self.lastMessageIsDeleted : lastMessageIsDeleted // ignore: cast_nullable_to_non_nullable
as bool,lastMessageReactionEmoji: freezed == lastMessageReactionEmoji ? _self.lastMessageReactionEmoji : lastMessageReactionEmoji // ignore: cast_nullable_to_non_nullable
as String?,lastMessageReceipt: freezed == lastMessageReceipt ? _self.lastMessageReceipt : lastMessageReceipt // ignore: cast_nullable_to_non_nullable
as ReceiptStatus?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,type: freezed == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String?,memberCount: freezed == memberCount ? _self.memberCount : memberCount // ignore: cast_nullable_to_non_nullable
as int?,userRole: freezed == userRole ? _self.userRole : userRole // ignore: cast_nullable_to_non_nullable
as RoomRole?,muted: null == muted ? _self.muted : muted // ignore: cast_nullable_to_non_nullable
as bool,muteUntil: freezed == muteUntil ? _self.muteUntil : muteUntil // ignore: cast_nullable_to_non_nullable
as DateTime?,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,hidden: null == hidden ? _self.hidden : hidden // ignore: cast_nullable_to_non_nullable
as bool,selfMuted: null == selfMuted ? _self.selfMuted : selfMuted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [UnreadRoom].
extension UnreadRoomPatterns on UnreadRoom {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UnreadRoom value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UnreadRoom() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UnreadRoom value)  $default,){
final _that = this;
switch (_that) {
case _UnreadRoom():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UnreadRoom value)?  $default,){
final _that = this;
switch (_that) {
case _UnreadRoom() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String roomId,  int unreadMessages,  int unreadMentions,  String? lastMessage,  DateTime? lastMessageTime,  String? lastMessageUserId,  String? lastMessageId,  MessageType? lastMessageType,  String? lastMessageMimeType,  String? lastMessageFileName,  int? lastMessageDurationMs,  bool lastMessageIsDeleted,  String? lastMessageReactionEmoji,  ReceiptStatus? lastMessageReceipt,  String? name,  String? avatarUrl,  String? type,  int? memberCount,  RoomRole? userRole,  bool muted,  DateTime? muteUntil,  bool pinned,  bool hidden,  bool selfMuted)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UnreadRoom() when $default != null:
return $default(_that.roomId,_that.unreadMessages,_that.unreadMentions,_that.lastMessage,_that.lastMessageTime,_that.lastMessageUserId,_that.lastMessageId,_that.lastMessageType,_that.lastMessageMimeType,_that.lastMessageFileName,_that.lastMessageDurationMs,_that.lastMessageIsDeleted,_that.lastMessageReactionEmoji,_that.lastMessageReceipt,_that.name,_that.avatarUrl,_that.type,_that.memberCount,_that.userRole,_that.muted,_that.muteUntil,_that.pinned,_that.hidden,_that.selfMuted);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String roomId,  int unreadMessages,  int unreadMentions,  String? lastMessage,  DateTime? lastMessageTime,  String? lastMessageUserId,  String? lastMessageId,  MessageType? lastMessageType,  String? lastMessageMimeType,  String? lastMessageFileName,  int? lastMessageDurationMs,  bool lastMessageIsDeleted,  String? lastMessageReactionEmoji,  ReceiptStatus? lastMessageReceipt,  String? name,  String? avatarUrl,  String? type,  int? memberCount,  RoomRole? userRole,  bool muted,  DateTime? muteUntil,  bool pinned,  bool hidden,  bool selfMuted)  $default,) {final _that = this;
switch (_that) {
case _UnreadRoom():
return $default(_that.roomId,_that.unreadMessages,_that.unreadMentions,_that.lastMessage,_that.lastMessageTime,_that.lastMessageUserId,_that.lastMessageId,_that.lastMessageType,_that.lastMessageMimeType,_that.lastMessageFileName,_that.lastMessageDurationMs,_that.lastMessageIsDeleted,_that.lastMessageReactionEmoji,_that.lastMessageReceipt,_that.name,_that.avatarUrl,_that.type,_that.memberCount,_that.userRole,_that.muted,_that.muteUntil,_that.pinned,_that.hidden,_that.selfMuted);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String roomId,  int unreadMessages,  int unreadMentions,  String? lastMessage,  DateTime? lastMessageTime,  String? lastMessageUserId,  String? lastMessageId,  MessageType? lastMessageType,  String? lastMessageMimeType,  String? lastMessageFileName,  int? lastMessageDurationMs,  bool lastMessageIsDeleted,  String? lastMessageReactionEmoji,  ReceiptStatus? lastMessageReceipt,  String? name,  String? avatarUrl,  String? type,  int? memberCount,  RoomRole? userRole,  bool muted,  DateTime? muteUntil,  bool pinned,  bool hidden,  bool selfMuted)?  $default,) {final _that = this;
switch (_that) {
case _UnreadRoom() when $default != null:
return $default(_that.roomId,_that.unreadMessages,_that.unreadMentions,_that.lastMessage,_that.lastMessageTime,_that.lastMessageUserId,_that.lastMessageId,_that.lastMessageType,_that.lastMessageMimeType,_that.lastMessageFileName,_that.lastMessageDurationMs,_that.lastMessageIsDeleted,_that.lastMessageReactionEmoji,_that.lastMessageReceipt,_that.name,_that.avatarUrl,_that.type,_that.memberCount,_that.userRole,_that.muted,_that.muteUntil,_that.pinned,_that.hidden,_that.selfMuted);case _:
  return null;

}
}

}

/// @nodoc


class _UnreadRoom implements UnreadRoom {
  const _UnreadRoom({required this.roomId, required this.unreadMessages, this.unreadMentions = 0, this.lastMessage, this.lastMessageTime, this.lastMessageUserId, this.lastMessageId, this.lastMessageType, this.lastMessageMimeType, this.lastMessageFileName, this.lastMessageDurationMs, this.lastMessageIsDeleted = false, this.lastMessageReactionEmoji, this.lastMessageReceipt, this.name, this.avatarUrl, this.type, this.memberCount, this.userRole, this.muted = false, this.muteUntil, this.pinned = false, this.hidden = false, this.selfMuted = false});
  

@override final  String roomId;
@override final  int unreadMessages;
/// Count of unread messages in this room that mention the current user.
/// `0` when there are none. Drives the "@" badge on the room tile
/// without fetching message bodies.
@override@JsonKey() final  int unreadMentions;
@override final  String? lastMessage;
@override final  DateTime? lastMessageTime;
@override final  String? lastMessageUserId;
@override final  String? lastMessageId;
@override final  MessageType? lastMessageType;
@override final  String? lastMessageMimeType;
@override final  String? lastMessageFileName;
@override final  int? lastMessageDurationMs;
@override@JsonKey() final  bool lastMessageIsDeleted;
@override final  String? lastMessageReactionEmoji;
@override final  ReceiptStatus? lastMessageReceipt;
@override final  String? name;
@override final  String? avatarUrl;
@override final  String? type;
@override final  int? memberCount;
@override final  RoomRole? userRole;
@override@JsonKey() final  bool muted;
/// When the notification mute expires (UTC). `null` means a permanent
/// mute (or not muted at all — check [muted]). Lets the UI show "muted
/// until 14:00" and the consumer re-derive [muted] after expiry.
@override final  DateTime? muteUntil;
@override@JsonKey() final  bool pinned;
@override@JsonKey() final  bool hidden;
@override@JsonKey() final  bool selfMuted;

/// Create a copy of UnreadRoom
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UnreadRoomCopyWith<_UnreadRoom> get copyWith => __$UnreadRoomCopyWithImpl<_UnreadRoom>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UnreadRoom&&(identical(other.roomId, roomId) || other.roomId == roomId)&&(identical(other.unreadMessages, unreadMessages) || other.unreadMessages == unreadMessages)&&(identical(other.unreadMentions, unreadMentions) || other.unreadMentions == unreadMentions)&&(identical(other.lastMessage, lastMessage) || other.lastMessage == lastMessage)&&(identical(other.lastMessageTime, lastMessageTime) || other.lastMessageTime == lastMessageTime)&&(identical(other.lastMessageUserId, lastMessageUserId) || other.lastMessageUserId == lastMessageUserId)&&(identical(other.lastMessageId, lastMessageId) || other.lastMessageId == lastMessageId)&&(identical(other.lastMessageType, lastMessageType) || other.lastMessageType == lastMessageType)&&(identical(other.lastMessageMimeType, lastMessageMimeType) || other.lastMessageMimeType == lastMessageMimeType)&&(identical(other.lastMessageFileName, lastMessageFileName) || other.lastMessageFileName == lastMessageFileName)&&(identical(other.lastMessageDurationMs, lastMessageDurationMs) || other.lastMessageDurationMs == lastMessageDurationMs)&&(identical(other.lastMessageIsDeleted, lastMessageIsDeleted) || other.lastMessageIsDeleted == lastMessageIsDeleted)&&(identical(other.lastMessageReactionEmoji, lastMessageReactionEmoji) || other.lastMessageReactionEmoji == lastMessageReactionEmoji)&&(identical(other.lastMessageReceipt, lastMessageReceipt) || other.lastMessageReceipt == lastMessageReceipt)&&(identical(other.name, name) || other.name == name)&&(identical(other.avatarUrl, avatarUrl) || other.avatarUrl == avatarUrl)&&(identical(other.type, type) || other.type == type)&&(identical(other.memberCount, memberCount) || other.memberCount == memberCount)&&(identical(other.userRole, userRole) || other.userRole == userRole)&&(identical(other.muted, muted) || other.muted == muted)&&(identical(other.muteUntil, muteUntil) || other.muteUntil == muteUntil)&&(identical(other.pinned, pinned) || other.pinned == pinned)&&(identical(other.hidden, hidden) || other.hidden == hidden)&&(identical(other.selfMuted, selfMuted) || other.selfMuted == selfMuted));
}


@override
int get hashCode => Object.hashAll([runtimeType,roomId,unreadMessages,unreadMentions,lastMessage,lastMessageTime,lastMessageUserId,lastMessageId,lastMessageType,lastMessageMimeType,lastMessageFileName,lastMessageDurationMs,lastMessageIsDeleted,lastMessageReactionEmoji,lastMessageReceipt,name,avatarUrl,type,memberCount,userRole,muted,muteUntil,pinned,hidden,selfMuted]);

@override
String toString() {
  return 'UnreadRoom(roomId: $roomId, unreadMessages: $unreadMessages, unreadMentions: $unreadMentions, lastMessage: $lastMessage, lastMessageTime: $lastMessageTime, lastMessageUserId: $lastMessageUserId, lastMessageId: $lastMessageId, lastMessageType: $lastMessageType, lastMessageMimeType: $lastMessageMimeType, lastMessageFileName: $lastMessageFileName, lastMessageDurationMs: $lastMessageDurationMs, lastMessageIsDeleted: $lastMessageIsDeleted, lastMessageReactionEmoji: $lastMessageReactionEmoji, lastMessageReceipt: $lastMessageReceipt, name: $name, avatarUrl: $avatarUrl, type: $type, memberCount: $memberCount, userRole: $userRole, muted: $muted, muteUntil: $muteUntil, pinned: $pinned, hidden: $hidden, selfMuted: $selfMuted)';
}


}

/// @nodoc
abstract mixin class _$UnreadRoomCopyWith<$Res> implements $UnreadRoomCopyWith<$Res> {
  factory _$UnreadRoomCopyWith(_UnreadRoom value, $Res Function(_UnreadRoom) _then) = __$UnreadRoomCopyWithImpl;
@override @useResult
$Res call({
 String roomId, int unreadMessages, int unreadMentions, String? lastMessage, DateTime? lastMessageTime, String? lastMessageUserId, String? lastMessageId, MessageType? lastMessageType, String? lastMessageMimeType, String? lastMessageFileName, int? lastMessageDurationMs, bool lastMessageIsDeleted, String? lastMessageReactionEmoji, ReceiptStatus? lastMessageReceipt, String? name, String? avatarUrl, String? type, int? memberCount, RoomRole? userRole, bool muted, DateTime? muteUntil, bool pinned, bool hidden, bool selfMuted
});




}
/// @nodoc
class __$UnreadRoomCopyWithImpl<$Res>
    implements _$UnreadRoomCopyWith<$Res> {
  __$UnreadRoomCopyWithImpl(this._self, this._then);

  final _UnreadRoom _self;
  final $Res Function(_UnreadRoom) _then;

/// Create a copy of UnreadRoom
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? roomId = null,Object? unreadMessages = null,Object? unreadMentions = null,Object? lastMessage = freezed,Object? lastMessageTime = freezed,Object? lastMessageUserId = freezed,Object? lastMessageId = freezed,Object? lastMessageType = freezed,Object? lastMessageMimeType = freezed,Object? lastMessageFileName = freezed,Object? lastMessageDurationMs = freezed,Object? lastMessageIsDeleted = null,Object? lastMessageReactionEmoji = freezed,Object? lastMessageReceipt = freezed,Object? name = freezed,Object? avatarUrl = freezed,Object? type = freezed,Object? memberCount = freezed,Object? userRole = freezed,Object? muted = null,Object? muteUntil = freezed,Object? pinned = null,Object? hidden = null,Object? selfMuted = null,}) {
  return _then(_UnreadRoom(
roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,unreadMessages: null == unreadMessages ? _self.unreadMessages : unreadMessages // ignore: cast_nullable_to_non_nullable
as int,unreadMentions: null == unreadMentions ? _self.unreadMentions : unreadMentions // ignore: cast_nullable_to_non_nullable
as int,lastMessage: freezed == lastMessage ? _self.lastMessage : lastMessage // ignore: cast_nullable_to_non_nullable
as String?,lastMessageTime: freezed == lastMessageTime ? _self.lastMessageTime : lastMessageTime // ignore: cast_nullable_to_non_nullable
as DateTime?,lastMessageUserId: freezed == lastMessageUserId ? _self.lastMessageUserId : lastMessageUserId // ignore: cast_nullable_to_non_nullable
as String?,lastMessageId: freezed == lastMessageId ? _self.lastMessageId : lastMessageId // ignore: cast_nullable_to_non_nullable
as String?,lastMessageType: freezed == lastMessageType ? _self.lastMessageType : lastMessageType // ignore: cast_nullable_to_non_nullable
as MessageType?,lastMessageMimeType: freezed == lastMessageMimeType ? _self.lastMessageMimeType : lastMessageMimeType // ignore: cast_nullable_to_non_nullable
as String?,lastMessageFileName: freezed == lastMessageFileName ? _self.lastMessageFileName : lastMessageFileName // ignore: cast_nullable_to_non_nullable
as String?,lastMessageDurationMs: freezed == lastMessageDurationMs ? _self.lastMessageDurationMs : lastMessageDurationMs // ignore: cast_nullable_to_non_nullable
as int?,lastMessageIsDeleted: null == lastMessageIsDeleted ? _self.lastMessageIsDeleted : lastMessageIsDeleted // ignore: cast_nullable_to_non_nullable
as bool,lastMessageReactionEmoji: freezed == lastMessageReactionEmoji ? _self.lastMessageReactionEmoji : lastMessageReactionEmoji // ignore: cast_nullable_to_non_nullable
as String?,lastMessageReceipt: freezed == lastMessageReceipt ? _self.lastMessageReceipt : lastMessageReceipt // ignore: cast_nullable_to_non_nullable
as ReceiptStatus?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,type: freezed == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String?,memberCount: freezed == memberCount ? _self.memberCount : memberCount // ignore: cast_nullable_to_non_nullable
as int?,userRole: freezed == userRole ? _self.userRole : userRole // ignore: cast_nullable_to_non_nullable
as RoomRole?,muted: null == muted ? _self.muted : muted // ignore: cast_nullable_to_non_nullable
as bool,muteUntil: freezed == muteUntil ? _self.muteUntil : muteUntil // ignore: cast_nullable_to_non_nullable
as DateTime?,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,hidden: null == hidden ? _self.hidden : hidden // ignore: cast_nullable_to_non_nullable
as bool,selfMuted: null == selfMuted ? _self.selfMuted : selfMuted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
