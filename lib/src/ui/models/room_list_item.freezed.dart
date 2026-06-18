// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'room_list_item.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RoomListItem {

 String get id; String? get name; String? get subject; String? get avatarUrl; String? get lastMessage; DateTime? get lastMessageTime; String? get lastMessageUserId;/// Display name of [lastMessageUserId], resolved by the adapter from
/// its user cache when available. Lets the chat list show the WhatsApp
/// "Alice: hola" prefix in groups without the consumer wiring its own
/// name resolver. `null` when the sender is the current user, when
/// `lastMessageUserId` is null, or when the user has not been fetched
/// yet — in that last case the adapter refreshes the row as soon as
/// the user lands in the cache (typically within a few hundred ms of
/// the first room load).
 String? get lastMessageSenderName; String? get lastMessageId; ReceiptStatus? get lastMessageReceipt; MessageType? get lastMessageType; String? get lastMessageMimeType; String? get lastMessageFileName; int? get lastMessageDurationMs; bool get lastMessageIsDeleted; String? get lastMessageReactionEmoji; int get unreadCount;/// Count of unread messages in this room that mention the current user.
/// Drives the "@" badge on the tile. `0` when none.
 int get unreadMentions; bool get muted;/// When the notification mute expires (UTC). `null` means a permanent
/// mute (or not muted — check [muted]).
 DateTime? get muteUntil; bool get pinned; bool get hidden;/// Moderation mute: an admin/owner silenced the current user in this
/// room (distinct from [muted] = the user's own notification
/// preference). Drives the read-only composer via [isReadOnly].
 bool get selfMuted; bool get isGroup; bool get isAnnouncement; bool? get isOnline; PresenceStatus? get presenceStatus; String? get otherUserId; RoomRole? get userRole; int? get memberCount; Map<String, dynamic>? get custom; Set<String> get typingUserIds;/// Title computed by the adapter via the configured `RoomTitleResolver` or
/// the SDK's DM-aware default (for one-to-one rooms, the other member's
/// `displayName`). Kept separate from [name] so the server-provided room
/// name remains intact and consumers can fall back to it (e.g. in tests or
/// during enrichment races where the other member has not been resolved
/// yet). `null` means the SDK has not produced an effective title for this
/// row.
 String? get effectiveDisplayName;/// `false` when the local user has been removed from this room by
/// an admin kick — WhatsApp-parity. The chat stays in the list
/// with full history, but the composer is swapped for the
/// "You are no longer a participant" banner (see
/// `ChatView.isParticipating`). Set to `false` by the event router
/// when a `user_left` event arrives with `actorUserId != userId &&
/// userId == me`, and flipped back to `true` when the admin
/// re-adds the user via `user_joined`.
 bool get isParticipating;
/// Create a copy of RoomListItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoomListItemCopyWith<RoomListItem> get copyWith => _$RoomListItemCopyWithImpl<RoomListItem>(this as RoomListItem, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoomListItem&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.subject, subject) || other.subject == subject)&&(identical(other.avatarUrl, avatarUrl) || other.avatarUrl == avatarUrl)&&(identical(other.lastMessage, lastMessage) || other.lastMessage == lastMessage)&&(identical(other.lastMessageTime, lastMessageTime) || other.lastMessageTime == lastMessageTime)&&(identical(other.lastMessageUserId, lastMessageUserId) || other.lastMessageUserId == lastMessageUserId)&&(identical(other.lastMessageSenderName, lastMessageSenderName) || other.lastMessageSenderName == lastMessageSenderName)&&(identical(other.lastMessageId, lastMessageId) || other.lastMessageId == lastMessageId)&&(identical(other.lastMessageReceipt, lastMessageReceipt) || other.lastMessageReceipt == lastMessageReceipt)&&(identical(other.lastMessageType, lastMessageType) || other.lastMessageType == lastMessageType)&&(identical(other.lastMessageMimeType, lastMessageMimeType) || other.lastMessageMimeType == lastMessageMimeType)&&(identical(other.lastMessageFileName, lastMessageFileName) || other.lastMessageFileName == lastMessageFileName)&&(identical(other.lastMessageDurationMs, lastMessageDurationMs) || other.lastMessageDurationMs == lastMessageDurationMs)&&(identical(other.lastMessageIsDeleted, lastMessageIsDeleted) || other.lastMessageIsDeleted == lastMessageIsDeleted)&&(identical(other.lastMessageReactionEmoji, lastMessageReactionEmoji) || other.lastMessageReactionEmoji == lastMessageReactionEmoji)&&(identical(other.unreadCount, unreadCount) || other.unreadCount == unreadCount)&&(identical(other.unreadMentions, unreadMentions) || other.unreadMentions == unreadMentions)&&(identical(other.muted, muted) || other.muted == muted)&&(identical(other.muteUntil, muteUntil) || other.muteUntil == muteUntil)&&(identical(other.pinned, pinned) || other.pinned == pinned)&&(identical(other.hidden, hidden) || other.hidden == hidden)&&(identical(other.selfMuted, selfMuted) || other.selfMuted == selfMuted)&&(identical(other.isGroup, isGroup) || other.isGroup == isGroup)&&(identical(other.isAnnouncement, isAnnouncement) || other.isAnnouncement == isAnnouncement)&&(identical(other.isOnline, isOnline) || other.isOnline == isOnline)&&(identical(other.presenceStatus, presenceStatus) || other.presenceStatus == presenceStatus)&&(identical(other.otherUserId, otherUserId) || other.otherUserId == otherUserId)&&(identical(other.userRole, userRole) || other.userRole == userRole)&&(identical(other.memberCount, memberCount) || other.memberCount == memberCount)&&const DeepCollectionEquality().equals(other.custom, custom)&&const DeepCollectionEquality().equals(other.typingUserIds, typingUserIds)&&(identical(other.effectiveDisplayName, effectiveDisplayName) || other.effectiveDisplayName == effectiveDisplayName)&&(identical(other.isParticipating, isParticipating) || other.isParticipating == isParticipating));
}


@override
int get hashCode => Object.hashAll([runtimeType,id,name,subject,avatarUrl,lastMessage,lastMessageTime,lastMessageUserId,lastMessageSenderName,lastMessageId,lastMessageReceipt,lastMessageType,lastMessageMimeType,lastMessageFileName,lastMessageDurationMs,lastMessageIsDeleted,lastMessageReactionEmoji,unreadCount,unreadMentions,muted,muteUntil,pinned,hidden,selfMuted,isGroup,isAnnouncement,isOnline,presenceStatus,otherUserId,userRole,memberCount,const DeepCollectionEquality().hash(custom),const DeepCollectionEquality().hash(typingUserIds),effectiveDisplayName,isParticipating]);

@override
String toString() {
  return 'RoomListItem(id: $id, name: $name, subject: $subject, avatarUrl: $avatarUrl, lastMessage: $lastMessage, lastMessageTime: $lastMessageTime, lastMessageUserId: $lastMessageUserId, lastMessageSenderName: $lastMessageSenderName, lastMessageId: $lastMessageId, lastMessageReceipt: $lastMessageReceipt, lastMessageType: $lastMessageType, lastMessageMimeType: $lastMessageMimeType, lastMessageFileName: $lastMessageFileName, lastMessageDurationMs: $lastMessageDurationMs, lastMessageIsDeleted: $lastMessageIsDeleted, lastMessageReactionEmoji: $lastMessageReactionEmoji, unreadCount: $unreadCount, unreadMentions: $unreadMentions, muted: $muted, muteUntil: $muteUntil, pinned: $pinned, hidden: $hidden, selfMuted: $selfMuted, isGroup: $isGroup, isAnnouncement: $isAnnouncement, isOnline: $isOnline, presenceStatus: $presenceStatus, otherUserId: $otherUserId, userRole: $userRole, memberCount: $memberCount, custom: $custom, typingUserIds: $typingUserIds, effectiveDisplayName: $effectiveDisplayName, isParticipating: $isParticipating)';
}


}

/// @nodoc
abstract mixin class $RoomListItemCopyWith<$Res>  {
  factory $RoomListItemCopyWith(RoomListItem value, $Res Function(RoomListItem) _then) = _$RoomListItemCopyWithImpl;
@useResult
$Res call({
 String id, String? name, String? subject, String? avatarUrl, String? lastMessage, DateTime? lastMessageTime, String? lastMessageUserId, String? lastMessageSenderName, String? lastMessageId, ReceiptStatus? lastMessageReceipt, MessageType? lastMessageType, String? lastMessageMimeType, String? lastMessageFileName, int? lastMessageDurationMs, bool lastMessageIsDeleted, String? lastMessageReactionEmoji, int unreadCount, int unreadMentions, bool muted, DateTime? muteUntil, bool pinned, bool hidden, bool selfMuted, bool isGroup, bool isAnnouncement, bool? isOnline, PresenceStatus? presenceStatus, String? otherUserId, RoomRole? userRole, int? memberCount, Map<String, dynamic>? custom, Set<String> typingUserIds, String? effectiveDisplayName, bool isParticipating
});




}
/// @nodoc
class _$RoomListItemCopyWithImpl<$Res>
    implements $RoomListItemCopyWith<$Res> {
  _$RoomListItemCopyWithImpl(this._self, this._then);

  final RoomListItem _self;
  final $Res Function(RoomListItem) _then;

/// Create a copy of RoomListItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = freezed,Object? subject = freezed,Object? avatarUrl = freezed,Object? lastMessage = freezed,Object? lastMessageTime = freezed,Object? lastMessageUserId = freezed,Object? lastMessageSenderName = freezed,Object? lastMessageId = freezed,Object? lastMessageReceipt = freezed,Object? lastMessageType = freezed,Object? lastMessageMimeType = freezed,Object? lastMessageFileName = freezed,Object? lastMessageDurationMs = freezed,Object? lastMessageIsDeleted = null,Object? lastMessageReactionEmoji = freezed,Object? unreadCount = null,Object? unreadMentions = null,Object? muted = null,Object? muteUntil = freezed,Object? pinned = null,Object? hidden = null,Object? selfMuted = null,Object? isGroup = null,Object? isAnnouncement = null,Object? isOnline = freezed,Object? presenceStatus = freezed,Object? otherUserId = freezed,Object? userRole = freezed,Object? memberCount = freezed,Object? custom = freezed,Object? typingUserIds = null,Object? effectiveDisplayName = freezed,Object? isParticipating = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,subject: freezed == subject ? _self.subject : subject // ignore: cast_nullable_to_non_nullable
as String?,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,lastMessage: freezed == lastMessage ? _self.lastMessage : lastMessage // ignore: cast_nullable_to_non_nullable
as String?,lastMessageTime: freezed == lastMessageTime ? _self.lastMessageTime : lastMessageTime // ignore: cast_nullable_to_non_nullable
as DateTime?,lastMessageUserId: freezed == lastMessageUserId ? _self.lastMessageUserId : lastMessageUserId // ignore: cast_nullable_to_non_nullable
as String?,lastMessageSenderName: freezed == lastMessageSenderName ? _self.lastMessageSenderName : lastMessageSenderName // ignore: cast_nullable_to_non_nullable
as String?,lastMessageId: freezed == lastMessageId ? _self.lastMessageId : lastMessageId // ignore: cast_nullable_to_non_nullable
as String?,lastMessageReceipt: freezed == lastMessageReceipt ? _self.lastMessageReceipt : lastMessageReceipt // ignore: cast_nullable_to_non_nullable
as ReceiptStatus?,lastMessageType: freezed == lastMessageType ? _self.lastMessageType : lastMessageType // ignore: cast_nullable_to_non_nullable
as MessageType?,lastMessageMimeType: freezed == lastMessageMimeType ? _self.lastMessageMimeType : lastMessageMimeType // ignore: cast_nullable_to_non_nullable
as String?,lastMessageFileName: freezed == lastMessageFileName ? _self.lastMessageFileName : lastMessageFileName // ignore: cast_nullable_to_non_nullable
as String?,lastMessageDurationMs: freezed == lastMessageDurationMs ? _self.lastMessageDurationMs : lastMessageDurationMs // ignore: cast_nullable_to_non_nullable
as int?,lastMessageIsDeleted: null == lastMessageIsDeleted ? _self.lastMessageIsDeleted : lastMessageIsDeleted // ignore: cast_nullable_to_non_nullable
as bool,lastMessageReactionEmoji: freezed == lastMessageReactionEmoji ? _self.lastMessageReactionEmoji : lastMessageReactionEmoji // ignore: cast_nullable_to_non_nullable
as String?,unreadCount: null == unreadCount ? _self.unreadCount : unreadCount // ignore: cast_nullable_to_non_nullable
as int,unreadMentions: null == unreadMentions ? _self.unreadMentions : unreadMentions // ignore: cast_nullable_to_non_nullable
as int,muted: null == muted ? _self.muted : muted // ignore: cast_nullable_to_non_nullable
as bool,muteUntil: freezed == muteUntil ? _self.muteUntil : muteUntil // ignore: cast_nullable_to_non_nullable
as DateTime?,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,hidden: null == hidden ? _self.hidden : hidden // ignore: cast_nullable_to_non_nullable
as bool,selfMuted: null == selfMuted ? _self.selfMuted : selfMuted // ignore: cast_nullable_to_non_nullable
as bool,isGroup: null == isGroup ? _self.isGroup : isGroup // ignore: cast_nullable_to_non_nullable
as bool,isAnnouncement: null == isAnnouncement ? _self.isAnnouncement : isAnnouncement // ignore: cast_nullable_to_non_nullable
as bool,isOnline: freezed == isOnline ? _self.isOnline : isOnline // ignore: cast_nullable_to_non_nullable
as bool?,presenceStatus: freezed == presenceStatus ? _self.presenceStatus : presenceStatus // ignore: cast_nullable_to_non_nullable
as PresenceStatus?,otherUserId: freezed == otherUserId ? _self.otherUserId : otherUserId // ignore: cast_nullable_to_non_nullable
as String?,userRole: freezed == userRole ? _self.userRole : userRole // ignore: cast_nullable_to_non_nullable
as RoomRole?,memberCount: freezed == memberCount ? _self.memberCount : memberCount // ignore: cast_nullable_to_non_nullable
as int?,custom: freezed == custom ? _self.custom : custom // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,typingUserIds: null == typingUserIds ? _self.typingUserIds : typingUserIds // ignore: cast_nullable_to_non_nullable
as Set<String>,effectiveDisplayName: freezed == effectiveDisplayName ? _self.effectiveDisplayName : effectiveDisplayName // ignore: cast_nullable_to_non_nullable
as String?,isParticipating: null == isParticipating ? _self.isParticipating : isParticipating // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [RoomListItem].
extension RoomListItemPatterns on RoomListItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoomListItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoomListItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoomListItem value)  $default,){
final _that = this;
switch (_that) {
case _RoomListItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoomListItem value)?  $default,){
final _that = this;
switch (_that) {
case _RoomListItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String? name,  String? subject,  String? avatarUrl,  String? lastMessage,  DateTime? lastMessageTime,  String? lastMessageUserId,  String? lastMessageSenderName,  String? lastMessageId,  ReceiptStatus? lastMessageReceipt,  MessageType? lastMessageType,  String? lastMessageMimeType,  String? lastMessageFileName,  int? lastMessageDurationMs,  bool lastMessageIsDeleted,  String? lastMessageReactionEmoji,  int unreadCount,  int unreadMentions,  bool muted,  DateTime? muteUntil,  bool pinned,  bool hidden,  bool selfMuted,  bool isGroup,  bool isAnnouncement,  bool? isOnline,  PresenceStatus? presenceStatus,  String? otherUserId,  RoomRole? userRole,  int? memberCount,  Map<String, dynamic>? custom,  Set<String> typingUserIds,  String? effectiveDisplayName,  bool isParticipating)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoomListItem() when $default != null:
return $default(_that.id,_that.name,_that.subject,_that.avatarUrl,_that.lastMessage,_that.lastMessageTime,_that.lastMessageUserId,_that.lastMessageSenderName,_that.lastMessageId,_that.lastMessageReceipt,_that.lastMessageType,_that.lastMessageMimeType,_that.lastMessageFileName,_that.lastMessageDurationMs,_that.lastMessageIsDeleted,_that.lastMessageReactionEmoji,_that.unreadCount,_that.unreadMentions,_that.muted,_that.muteUntil,_that.pinned,_that.hidden,_that.selfMuted,_that.isGroup,_that.isAnnouncement,_that.isOnline,_that.presenceStatus,_that.otherUserId,_that.userRole,_that.memberCount,_that.custom,_that.typingUserIds,_that.effectiveDisplayName,_that.isParticipating);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String? name,  String? subject,  String? avatarUrl,  String? lastMessage,  DateTime? lastMessageTime,  String? lastMessageUserId,  String? lastMessageSenderName,  String? lastMessageId,  ReceiptStatus? lastMessageReceipt,  MessageType? lastMessageType,  String? lastMessageMimeType,  String? lastMessageFileName,  int? lastMessageDurationMs,  bool lastMessageIsDeleted,  String? lastMessageReactionEmoji,  int unreadCount,  int unreadMentions,  bool muted,  DateTime? muteUntil,  bool pinned,  bool hidden,  bool selfMuted,  bool isGroup,  bool isAnnouncement,  bool? isOnline,  PresenceStatus? presenceStatus,  String? otherUserId,  RoomRole? userRole,  int? memberCount,  Map<String, dynamic>? custom,  Set<String> typingUserIds,  String? effectiveDisplayName,  bool isParticipating)  $default,) {final _that = this;
switch (_that) {
case _RoomListItem():
return $default(_that.id,_that.name,_that.subject,_that.avatarUrl,_that.lastMessage,_that.lastMessageTime,_that.lastMessageUserId,_that.lastMessageSenderName,_that.lastMessageId,_that.lastMessageReceipt,_that.lastMessageType,_that.lastMessageMimeType,_that.lastMessageFileName,_that.lastMessageDurationMs,_that.lastMessageIsDeleted,_that.lastMessageReactionEmoji,_that.unreadCount,_that.unreadMentions,_that.muted,_that.muteUntil,_that.pinned,_that.hidden,_that.selfMuted,_that.isGroup,_that.isAnnouncement,_that.isOnline,_that.presenceStatus,_that.otherUserId,_that.userRole,_that.memberCount,_that.custom,_that.typingUserIds,_that.effectiveDisplayName,_that.isParticipating);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String? name,  String? subject,  String? avatarUrl,  String? lastMessage,  DateTime? lastMessageTime,  String? lastMessageUserId,  String? lastMessageSenderName,  String? lastMessageId,  ReceiptStatus? lastMessageReceipt,  MessageType? lastMessageType,  String? lastMessageMimeType,  String? lastMessageFileName,  int? lastMessageDurationMs,  bool lastMessageIsDeleted,  String? lastMessageReactionEmoji,  int unreadCount,  int unreadMentions,  bool muted,  DateTime? muteUntil,  bool pinned,  bool hidden,  bool selfMuted,  bool isGroup,  bool isAnnouncement,  bool? isOnline,  PresenceStatus? presenceStatus,  String? otherUserId,  RoomRole? userRole,  int? memberCount,  Map<String, dynamic>? custom,  Set<String> typingUserIds,  String? effectiveDisplayName,  bool isParticipating)?  $default,) {final _that = this;
switch (_that) {
case _RoomListItem() when $default != null:
return $default(_that.id,_that.name,_that.subject,_that.avatarUrl,_that.lastMessage,_that.lastMessageTime,_that.lastMessageUserId,_that.lastMessageSenderName,_that.lastMessageId,_that.lastMessageReceipt,_that.lastMessageType,_that.lastMessageMimeType,_that.lastMessageFileName,_that.lastMessageDurationMs,_that.lastMessageIsDeleted,_that.lastMessageReactionEmoji,_that.unreadCount,_that.unreadMentions,_that.muted,_that.muteUntil,_that.pinned,_that.hidden,_that.selfMuted,_that.isGroup,_that.isAnnouncement,_that.isOnline,_that.presenceStatus,_that.otherUserId,_that.userRole,_that.memberCount,_that.custom,_that.typingUserIds,_that.effectiveDisplayName,_that.isParticipating);case _:
  return null;

}
}

}

/// @nodoc


class _RoomListItem extends RoomListItem {
  const _RoomListItem({required this.id, this.name, this.subject, this.avatarUrl, this.lastMessage, this.lastMessageTime, this.lastMessageUserId, this.lastMessageSenderName, this.lastMessageId, this.lastMessageReceipt, this.lastMessageType, this.lastMessageMimeType, this.lastMessageFileName, this.lastMessageDurationMs, this.lastMessageIsDeleted = false, this.lastMessageReactionEmoji, this.unreadCount = 0, this.unreadMentions = 0, this.muted = false, this.muteUntil, this.pinned = false, this.hidden = false, this.selfMuted = false, this.isGroup = false, this.isAnnouncement = false, this.isOnline, this.presenceStatus, this.otherUserId, this.userRole, this.memberCount, final  Map<String, dynamic>? custom, final  Set<String> typingUserIds = const <String>{}, this.effectiveDisplayName, this.isParticipating = true}): _custom = custom,_typingUserIds = typingUserIds,super._();
  

@override final  String id;
@override final  String? name;
@override final  String? subject;
@override final  String? avatarUrl;
@override final  String? lastMessage;
@override final  DateTime? lastMessageTime;
@override final  String? lastMessageUserId;
/// Display name of [lastMessageUserId], resolved by the adapter from
/// its user cache when available. Lets the chat list show the WhatsApp
/// "Alice: hola" prefix in groups without the consumer wiring its own
/// name resolver. `null` when the sender is the current user, when
/// `lastMessageUserId` is null, or when the user has not been fetched
/// yet — in that last case the adapter refreshes the row as soon as
/// the user lands in the cache (typically within a few hundred ms of
/// the first room load).
@override final  String? lastMessageSenderName;
@override final  String? lastMessageId;
@override final  ReceiptStatus? lastMessageReceipt;
@override final  MessageType? lastMessageType;
@override final  String? lastMessageMimeType;
@override final  String? lastMessageFileName;
@override final  int? lastMessageDurationMs;
@override@JsonKey() final  bool lastMessageIsDeleted;
@override final  String? lastMessageReactionEmoji;
@override@JsonKey() final  int unreadCount;
/// Count of unread messages in this room that mention the current user.
/// Drives the "@" badge on the tile. `0` when none.
@override@JsonKey() final  int unreadMentions;
@override@JsonKey() final  bool muted;
/// When the notification mute expires (UTC). `null` means a permanent
/// mute (or not muted — check [muted]).
@override final  DateTime? muteUntil;
@override@JsonKey() final  bool pinned;
@override@JsonKey() final  bool hidden;
/// Moderation mute: an admin/owner silenced the current user in this
/// room (distinct from [muted] = the user's own notification
/// preference). Drives the read-only composer via [isReadOnly].
@override@JsonKey() final  bool selfMuted;
@override@JsonKey() final  bool isGroup;
@override@JsonKey() final  bool isAnnouncement;
@override final  bool? isOnline;
@override final  PresenceStatus? presenceStatus;
@override final  String? otherUserId;
@override final  RoomRole? userRole;
@override final  int? memberCount;
 final  Map<String, dynamic>? _custom;
@override Map<String, dynamic>? get custom {
  final value = _custom;
  if (value == null) return null;
  if (_custom is EqualUnmodifiableMapView) return _custom;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

 final  Set<String> _typingUserIds;
@override@JsonKey() Set<String> get typingUserIds {
  if (_typingUserIds is EqualUnmodifiableSetView) return _typingUserIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_typingUserIds);
}

/// Title computed by the adapter via the configured `RoomTitleResolver` or
/// the SDK's DM-aware default (for one-to-one rooms, the other member's
/// `displayName`). Kept separate from [name] so the server-provided room
/// name remains intact and consumers can fall back to it (e.g. in tests or
/// during enrichment races where the other member has not been resolved
/// yet). `null` means the SDK has not produced an effective title for this
/// row.
@override final  String? effectiveDisplayName;
/// `false` when the local user has been removed from this room by
/// an admin kick — WhatsApp-parity. The chat stays in the list
/// with full history, but the composer is swapped for the
/// "You are no longer a participant" banner (see
/// `ChatView.isParticipating`). Set to `false` by the event router
/// when a `user_left` event arrives with `actorUserId != userId &&
/// userId == me`, and flipped back to `true` when the admin
/// re-adds the user via `user_joined`.
@override@JsonKey() final  bool isParticipating;

/// Create a copy of RoomListItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoomListItemCopyWith<_RoomListItem> get copyWith => __$RoomListItemCopyWithImpl<_RoomListItem>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoomListItem&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.subject, subject) || other.subject == subject)&&(identical(other.avatarUrl, avatarUrl) || other.avatarUrl == avatarUrl)&&(identical(other.lastMessage, lastMessage) || other.lastMessage == lastMessage)&&(identical(other.lastMessageTime, lastMessageTime) || other.lastMessageTime == lastMessageTime)&&(identical(other.lastMessageUserId, lastMessageUserId) || other.lastMessageUserId == lastMessageUserId)&&(identical(other.lastMessageSenderName, lastMessageSenderName) || other.lastMessageSenderName == lastMessageSenderName)&&(identical(other.lastMessageId, lastMessageId) || other.lastMessageId == lastMessageId)&&(identical(other.lastMessageReceipt, lastMessageReceipt) || other.lastMessageReceipt == lastMessageReceipt)&&(identical(other.lastMessageType, lastMessageType) || other.lastMessageType == lastMessageType)&&(identical(other.lastMessageMimeType, lastMessageMimeType) || other.lastMessageMimeType == lastMessageMimeType)&&(identical(other.lastMessageFileName, lastMessageFileName) || other.lastMessageFileName == lastMessageFileName)&&(identical(other.lastMessageDurationMs, lastMessageDurationMs) || other.lastMessageDurationMs == lastMessageDurationMs)&&(identical(other.lastMessageIsDeleted, lastMessageIsDeleted) || other.lastMessageIsDeleted == lastMessageIsDeleted)&&(identical(other.lastMessageReactionEmoji, lastMessageReactionEmoji) || other.lastMessageReactionEmoji == lastMessageReactionEmoji)&&(identical(other.unreadCount, unreadCount) || other.unreadCount == unreadCount)&&(identical(other.unreadMentions, unreadMentions) || other.unreadMentions == unreadMentions)&&(identical(other.muted, muted) || other.muted == muted)&&(identical(other.muteUntil, muteUntil) || other.muteUntil == muteUntil)&&(identical(other.pinned, pinned) || other.pinned == pinned)&&(identical(other.hidden, hidden) || other.hidden == hidden)&&(identical(other.selfMuted, selfMuted) || other.selfMuted == selfMuted)&&(identical(other.isGroup, isGroup) || other.isGroup == isGroup)&&(identical(other.isAnnouncement, isAnnouncement) || other.isAnnouncement == isAnnouncement)&&(identical(other.isOnline, isOnline) || other.isOnline == isOnline)&&(identical(other.presenceStatus, presenceStatus) || other.presenceStatus == presenceStatus)&&(identical(other.otherUserId, otherUserId) || other.otherUserId == otherUserId)&&(identical(other.userRole, userRole) || other.userRole == userRole)&&(identical(other.memberCount, memberCount) || other.memberCount == memberCount)&&const DeepCollectionEquality().equals(other._custom, _custom)&&const DeepCollectionEquality().equals(other._typingUserIds, _typingUserIds)&&(identical(other.effectiveDisplayName, effectiveDisplayName) || other.effectiveDisplayName == effectiveDisplayName)&&(identical(other.isParticipating, isParticipating) || other.isParticipating == isParticipating));
}


@override
int get hashCode => Object.hashAll([runtimeType,id,name,subject,avatarUrl,lastMessage,lastMessageTime,lastMessageUserId,lastMessageSenderName,lastMessageId,lastMessageReceipt,lastMessageType,lastMessageMimeType,lastMessageFileName,lastMessageDurationMs,lastMessageIsDeleted,lastMessageReactionEmoji,unreadCount,unreadMentions,muted,muteUntil,pinned,hidden,selfMuted,isGroup,isAnnouncement,isOnline,presenceStatus,otherUserId,userRole,memberCount,const DeepCollectionEquality().hash(_custom),const DeepCollectionEquality().hash(_typingUserIds),effectiveDisplayName,isParticipating]);

@override
String toString() {
  return 'RoomListItem(id: $id, name: $name, subject: $subject, avatarUrl: $avatarUrl, lastMessage: $lastMessage, lastMessageTime: $lastMessageTime, lastMessageUserId: $lastMessageUserId, lastMessageSenderName: $lastMessageSenderName, lastMessageId: $lastMessageId, lastMessageReceipt: $lastMessageReceipt, lastMessageType: $lastMessageType, lastMessageMimeType: $lastMessageMimeType, lastMessageFileName: $lastMessageFileName, lastMessageDurationMs: $lastMessageDurationMs, lastMessageIsDeleted: $lastMessageIsDeleted, lastMessageReactionEmoji: $lastMessageReactionEmoji, unreadCount: $unreadCount, unreadMentions: $unreadMentions, muted: $muted, muteUntil: $muteUntil, pinned: $pinned, hidden: $hidden, selfMuted: $selfMuted, isGroup: $isGroup, isAnnouncement: $isAnnouncement, isOnline: $isOnline, presenceStatus: $presenceStatus, otherUserId: $otherUserId, userRole: $userRole, memberCount: $memberCount, custom: $custom, typingUserIds: $typingUserIds, effectiveDisplayName: $effectiveDisplayName, isParticipating: $isParticipating)';
}


}

/// @nodoc
abstract mixin class _$RoomListItemCopyWith<$Res> implements $RoomListItemCopyWith<$Res> {
  factory _$RoomListItemCopyWith(_RoomListItem value, $Res Function(_RoomListItem) _then) = __$RoomListItemCopyWithImpl;
@override @useResult
$Res call({
 String id, String? name, String? subject, String? avatarUrl, String? lastMessage, DateTime? lastMessageTime, String? lastMessageUserId, String? lastMessageSenderName, String? lastMessageId, ReceiptStatus? lastMessageReceipt, MessageType? lastMessageType, String? lastMessageMimeType, String? lastMessageFileName, int? lastMessageDurationMs, bool lastMessageIsDeleted, String? lastMessageReactionEmoji, int unreadCount, int unreadMentions, bool muted, DateTime? muteUntil, bool pinned, bool hidden, bool selfMuted, bool isGroup, bool isAnnouncement, bool? isOnline, PresenceStatus? presenceStatus, String? otherUserId, RoomRole? userRole, int? memberCount, Map<String, dynamic>? custom, Set<String> typingUserIds, String? effectiveDisplayName, bool isParticipating
});




}
/// @nodoc
class __$RoomListItemCopyWithImpl<$Res>
    implements _$RoomListItemCopyWith<$Res> {
  __$RoomListItemCopyWithImpl(this._self, this._then);

  final _RoomListItem _self;
  final $Res Function(_RoomListItem) _then;

/// Create a copy of RoomListItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = freezed,Object? subject = freezed,Object? avatarUrl = freezed,Object? lastMessage = freezed,Object? lastMessageTime = freezed,Object? lastMessageUserId = freezed,Object? lastMessageSenderName = freezed,Object? lastMessageId = freezed,Object? lastMessageReceipt = freezed,Object? lastMessageType = freezed,Object? lastMessageMimeType = freezed,Object? lastMessageFileName = freezed,Object? lastMessageDurationMs = freezed,Object? lastMessageIsDeleted = null,Object? lastMessageReactionEmoji = freezed,Object? unreadCount = null,Object? unreadMentions = null,Object? muted = null,Object? muteUntil = freezed,Object? pinned = null,Object? hidden = null,Object? selfMuted = null,Object? isGroup = null,Object? isAnnouncement = null,Object? isOnline = freezed,Object? presenceStatus = freezed,Object? otherUserId = freezed,Object? userRole = freezed,Object? memberCount = freezed,Object? custom = freezed,Object? typingUserIds = null,Object? effectiveDisplayName = freezed,Object? isParticipating = null,}) {
  return _then(_RoomListItem(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,subject: freezed == subject ? _self.subject : subject // ignore: cast_nullable_to_non_nullable
as String?,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,lastMessage: freezed == lastMessage ? _self.lastMessage : lastMessage // ignore: cast_nullable_to_non_nullable
as String?,lastMessageTime: freezed == lastMessageTime ? _self.lastMessageTime : lastMessageTime // ignore: cast_nullable_to_non_nullable
as DateTime?,lastMessageUserId: freezed == lastMessageUserId ? _self.lastMessageUserId : lastMessageUserId // ignore: cast_nullable_to_non_nullable
as String?,lastMessageSenderName: freezed == lastMessageSenderName ? _self.lastMessageSenderName : lastMessageSenderName // ignore: cast_nullable_to_non_nullable
as String?,lastMessageId: freezed == lastMessageId ? _self.lastMessageId : lastMessageId // ignore: cast_nullable_to_non_nullable
as String?,lastMessageReceipt: freezed == lastMessageReceipt ? _self.lastMessageReceipt : lastMessageReceipt // ignore: cast_nullable_to_non_nullable
as ReceiptStatus?,lastMessageType: freezed == lastMessageType ? _self.lastMessageType : lastMessageType // ignore: cast_nullable_to_non_nullable
as MessageType?,lastMessageMimeType: freezed == lastMessageMimeType ? _self.lastMessageMimeType : lastMessageMimeType // ignore: cast_nullable_to_non_nullable
as String?,lastMessageFileName: freezed == lastMessageFileName ? _self.lastMessageFileName : lastMessageFileName // ignore: cast_nullable_to_non_nullable
as String?,lastMessageDurationMs: freezed == lastMessageDurationMs ? _self.lastMessageDurationMs : lastMessageDurationMs // ignore: cast_nullable_to_non_nullable
as int?,lastMessageIsDeleted: null == lastMessageIsDeleted ? _self.lastMessageIsDeleted : lastMessageIsDeleted // ignore: cast_nullable_to_non_nullable
as bool,lastMessageReactionEmoji: freezed == lastMessageReactionEmoji ? _self.lastMessageReactionEmoji : lastMessageReactionEmoji // ignore: cast_nullable_to_non_nullable
as String?,unreadCount: null == unreadCount ? _self.unreadCount : unreadCount // ignore: cast_nullable_to_non_nullable
as int,unreadMentions: null == unreadMentions ? _self.unreadMentions : unreadMentions // ignore: cast_nullable_to_non_nullable
as int,muted: null == muted ? _self.muted : muted // ignore: cast_nullable_to_non_nullable
as bool,muteUntil: freezed == muteUntil ? _self.muteUntil : muteUntil // ignore: cast_nullable_to_non_nullable
as DateTime?,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,hidden: null == hidden ? _self.hidden : hidden // ignore: cast_nullable_to_non_nullable
as bool,selfMuted: null == selfMuted ? _self.selfMuted : selfMuted // ignore: cast_nullable_to_non_nullable
as bool,isGroup: null == isGroup ? _self.isGroup : isGroup // ignore: cast_nullable_to_non_nullable
as bool,isAnnouncement: null == isAnnouncement ? _self.isAnnouncement : isAnnouncement // ignore: cast_nullable_to_non_nullable
as bool,isOnline: freezed == isOnline ? _self.isOnline : isOnline // ignore: cast_nullable_to_non_nullable
as bool?,presenceStatus: freezed == presenceStatus ? _self.presenceStatus : presenceStatus // ignore: cast_nullable_to_non_nullable
as PresenceStatus?,otherUserId: freezed == otherUserId ? _self.otherUserId : otherUserId // ignore: cast_nullable_to_non_nullable
as String?,userRole: freezed == userRole ? _self.userRole : userRole // ignore: cast_nullable_to_non_nullable
as RoomRole?,memberCount: freezed == memberCount ? _self.memberCount : memberCount // ignore: cast_nullable_to_non_nullable
as int?,custom: freezed == custom ? _self._custom : custom // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,typingUserIds: null == typingUserIds ? _self._typingUserIds : typingUserIds // ignore: cast_nullable_to_non_nullable
as Set<String>,effectiveDisplayName: freezed == effectiveDisplayName ? _self.effectiveDisplayName : effectiveDisplayName // ignore: cast_nullable_to_non_nullable
as String?,isParticipating: null == isParticipating ? _self.isParticipating : isParticipating // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
