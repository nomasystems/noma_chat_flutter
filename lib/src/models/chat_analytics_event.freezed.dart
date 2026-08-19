// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat_analytics_event.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ChatAnalyticsEvent {

 String get roomId;
/// Create a copy of ChatAnalyticsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatAnalyticsEventCopyWith<ChatAnalyticsEvent> get copyWith => _$ChatAnalyticsEventCopyWithImpl<ChatAnalyticsEvent>(this as ChatAnalyticsEvent, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatAnalyticsEvent&&(identical(other.roomId, roomId) || other.roomId == roomId));
}


@override
int get hashCode => Object.hash(runtimeType,roomId);

@override
String toString() {
  return 'ChatAnalyticsEvent(roomId: $roomId)';
}


}

/// @nodoc
abstract mixin class $ChatAnalyticsEventCopyWith<$Res>  {
  factory $ChatAnalyticsEventCopyWith(ChatAnalyticsEvent value, $Res Function(ChatAnalyticsEvent) _then) = _$ChatAnalyticsEventCopyWithImpl;
@useResult
$Res call({
 String roomId
});




}
/// @nodoc
class _$ChatAnalyticsEventCopyWithImpl<$Res>
    implements $ChatAnalyticsEventCopyWith<$Res> {
  _$ChatAnalyticsEventCopyWithImpl(this._self, this._then);

  final ChatAnalyticsEvent _self;
  final $Res Function(ChatAnalyticsEvent) _then;

/// Create a copy of ChatAnalyticsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? roomId = null,}) {
  return _then(_self.copyWith(
roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ChatAnalyticsEvent].
extension ChatAnalyticsEventPatterns on ChatAnalyticsEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ChatAnalyticsRoomOpened value)?  roomOpened,TResult Function( ChatAnalyticsMessageReceived value)?  messageReceived,TResult Function( ChatAnalyticsVoicePlayed value)?  voicePlayed,TResult Function( ChatAnalyticsSendOutcome value)?  sendOutcome,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ChatAnalyticsRoomOpened() when roomOpened != null:
return roomOpened(_that);case ChatAnalyticsMessageReceived() when messageReceived != null:
return messageReceived(_that);case ChatAnalyticsVoicePlayed() when voicePlayed != null:
return voicePlayed(_that);case ChatAnalyticsSendOutcome() when sendOutcome != null:
return sendOutcome(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ChatAnalyticsRoomOpened value)  roomOpened,required TResult Function( ChatAnalyticsMessageReceived value)  messageReceived,required TResult Function( ChatAnalyticsVoicePlayed value)  voicePlayed,required TResult Function( ChatAnalyticsSendOutcome value)  sendOutcome,}){
final _that = this;
switch (_that) {
case ChatAnalyticsRoomOpened():
return roomOpened(_that);case ChatAnalyticsMessageReceived():
return messageReceived(_that);case ChatAnalyticsVoicePlayed():
return voicePlayed(_that);case ChatAnalyticsSendOutcome():
return sendOutcome(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ChatAnalyticsRoomOpened value)?  roomOpened,TResult? Function( ChatAnalyticsMessageReceived value)?  messageReceived,TResult? Function( ChatAnalyticsVoicePlayed value)?  voicePlayed,TResult? Function( ChatAnalyticsSendOutcome value)?  sendOutcome,}){
final _that = this;
switch (_that) {
case ChatAnalyticsRoomOpened() when roomOpened != null:
return roomOpened(_that);case ChatAnalyticsMessageReceived() when messageReceived != null:
return messageReceived(_that);case ChatAnalyticsVoicePlayed() when voicePlayed != null:
return voicePlayed(_that);case ChatAnalyticsSendOutcome() when sendOutcome != null:
return sendOutcome(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String roomId,  bool isGroup)?  roomOpened,TResult Function( String roomId,  String messageId,  MessageType kind,  bool isGroup)?  messageReceived,TResult Function( String roomId,  String messageId,  int durationMs,  bool firstListen)?  voicePlayed,TResult Function( String roomId,  MessageType kind,  bool success,  String? failureKind)?  sendOutcome,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ChatAnalyticsRoomOpened() when roomOpened != null:
return roomOpened(_that.roomId,_that.isGroup);case ChatAnalyticsMessageReceived() when messageReceived != null:
return messageReceived(_that.roomId,_that.messageId,_that.kind,_that.isGroup);case ChatAnalyticsVoicePlayed() when voicePlayed != null:
return voicePlayed(_that.roomId,_that.messageId,_that.durationMs,_that.firstListen);case ChatAnalyticsSendOutcome() when sendOutcome != null:
return sendOutcome(_that.roomId,_that.kind,_that.success,_that.failureKind);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String roomId,  bool isGroup)  roomOpened,required TResult Function( String roomId,  String messageId,  MessageType kind,  bool isGroup)  messageReceived,required TResult Function( String roomId,  String messageId,  int durationMs,  bool firstListen)  voicePlayed,required TResult Function( String roomId,  MessageType kind,  bool success,  String? failureKind)  sendOutcome,}) {final _that = this;
switch (_that) {
case ChatAnalyticsRoomOpened():
return roomOpened(_that.roomId,_that.isGroup);case ChatAnalyticsMessageReceived():
return messageReceived(_that.roomId,_that.messageId,_that.kind,_that.isGroup);case ChatAnalyticsVoicePlayed():
return voicePlayed(_that.roomId,_that.messageId,_that.durationMs,_that.firstListen);case ChatAnalyticsSendOutcome():
return sendOutcome(_that.roomId,_that.kind,_that.success,_that.failureKind);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String roomId,  bool isGroup)?  roomOpened,TResult? Function( String roomId,  String messageId,  MessageType kind,  bool isGroup)?  messageReceived,TResult? Function( String roomId,  String messageId,  int durationMs,  bool firstListen)?  voicePlayed,TResult? Function( String roomId,  MessageType kind,  bool success,  String? failureKind)?  sendOutcome,}) {final _that = this;
switch (_that) {
case ChatAnalyticsRoomOpened() when roomOpened != null:
return roomOpened(_that.roomId,_that.isGroup);case ChatAnalyticsMessageReceived() when messageReceived != null:
return messageReceived(_that.roomId,_that.messageId,_that.kind,_that.isGroup);case ChatAnalyticsVoicePlayed() when voicePlayed != null:
return voicePlayed(_that.roomId,_that.messageId,_that.durationMs,_that.firstListen);case ChatAnalyticsSendOutcome() when sendOutcome != null:
return sendOutcome(_that.roomId,_that.kind,_that.success,_that.failureKind);case _:
  return null;

}
}

}

/// @nodoc


class ChatAnalyticsRoomOpened implements ChatAnalyticsEvent {
  const ChatAnalyticsRoomOpened({required this.roomId, required this.isGroup});
  

@override final  String roomId;
 final  bool isGroup;

/// Create a copy of ChatAnalyticsEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatAnalyticsRoomOpenedCopyWith<ChatAnalyticsRoomOpened> get copyWith => _$ChatAnalyticsRoomOpenedCopyWithImpl<ChatAnalyticsRoomOpened>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatAnalyticsRoomOpened&&(identical(other.roomId, roomId) || other.roomId == roomId)&&(identical(other.isGroup, isGroup) || other.isGroup == isGroup));
}


@override
int get hashCode => Object.hash(runtimeType,roomId,isGroup);

@override
String toString() {
  return 'ChatAnalyticsEvent.roomOpened(roomId: $roomId, isGroup: $isGroup)';
}


}

/// @nodoc
abstract mixin class $ChatAnalyticsRoomOpenedCopyWith<$Res> implements $ChatAnalyticsEventCopyWith<$Res> {
  factory $ChatAnalyticsRoomOpenedCopyWith(ChatAnalyticsRoomOpened value, $Res Function(ChatAnalyticsRoomOpened) _then) = _$ChatAnalyticsRoomOpenedCopyWithImpl;
@override @useResult
$Res call({
 String roomId, bool isGroup
});




}
/// @nodoc
class _$ChatAnalyticsRoomOpenedCopyWithImpl<$Res>
    implements $ChatAnalyticsRoomOpenedCopyWith<$Res> {
  _$ChatAnalyticsRoomOpenedCopyWithImpl(this._self, this._then);

  final ChatAnalyticsRoomOpened _self;
  final $Res Function(ChatAnalyticsRoomOpened) _then;

/// Create a copy of ChatAnalyticsEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? roomId = null,Object? isGroup = null,}) {
  return _then(ChatAnalyticsRoomOpened(
roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,isGroup: null == isGroup ? _self.isGroup : isGroup // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class ChatAnalyticsMessageReceived implements ChatAnalyticsEvent {
  const ChatAnalyticsMessageReceived({required this.roomId, required this.messageId, required this.kind, required this.isGroup});
  

@override final  String roomId;
 final  String messageId;
 final  MessageType kind;
 final  bool isGroup;

/// Create a copy of ChatAnalyticsEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatAnalyticsMessageReceivedCopyWith<ChatAnalyticsMessageReceived> get copyWith => _$ChatAnalyticsMessageReceivedCopyWithImpl<ChatAnalyticsMessageReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatAnalyticsMessageReceived&&(identical(other.roomId, roomId) || other.roomId == roomId)&&(identical(other.messageId, messageId) || other.messageId == messageId)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.isGroup, isGroup) || other.isGroup == isGroup));
}


@override
int get hashCode => Object.hash(runtimeType,roomId,messageId,kind,isGroup);

@override
String toString() {
  return 'ChatAnalyticsEvent.messageReceived(roomId: $roomId, messageId: $messageId, kind: $kind, isGroup: $isGroup)';
}


}

/// @nodoc
abstract mixin class $ChatAnalyticsMessageReceivedCopyWith<$Res> implements $ChatAnalyticsEventCopyWith<$Res> {
  factory $ChatAnalyticsMessageReceivedCopyWith(ChatAnalyticsMessageReceived value, $Res Function(ChatAnalyticsMessageReceived) _then) = _$ChatAnalyticsMessageReceivedCopyWithImpl;
@override @useResult
$Res call({
 String roomId, String messageId, MessageType kind, bool isGroup
});




}
/// @nodoc
class _$ChatAnalyticsMessageReceivedCopyWithImpl<$Res>
    implements $ChatAnalyticsMessageReceivedCopyWith<$Res> {
  _$ChatAnalyticsMessageReceivedCopyWithImpl(this._self, this._then);

  final ChatAnalyticsMessageReceived _self;
  final $Res Function(ChatAnalyticsMessageReceived) _then;

/// Create a copy of ChatAnalyticsEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? roomId = null,Object? messageId = null,Object? kind = null,Object? isGroup = null,}) {
  return _then(ChatAnalyticsMessageReceived(
roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,messageId: null == messageId ? _self.messageId : messageId // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as MessageType,isGroup: null == isGroup ? _self.isGroup : isGroup // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class ChatAnalyticsVoicePlayed implements ChatAnalyticsEvent {
  const ChatAnalyticsVoicePlayed({required this.roomId, required this.messageId, required this.durationMs, required this.firstListen});
  

@override final  String roomId;
 final  String messageId;
 final  int durationMs;
 final  bool firstListen;

/// Create a copy of ChatAnalyticsEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatAnalyticsVoicePlayedCopyWith<ChatAnalyticsVoicePlayed> get copyWith => _$ChatAnalyticsVoicePlayedCopyWithImpl<ChatAnalyticsVoicePlayed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatAnalyticsVoicePlayed&&(identical(other.roomId, roomId) || other.roomId == roomId)&&(identical(other.messageId, messageId) || other.messageId == messageId)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&(identical(other.firstListen, firstListen) || other.firstListen == firstListen));
}


@override
int get hashCode => Object.hash(runtimeType,roomId,messageId,durationMs,firstListen);

@override
String toString() {
  return 'ChatAnalyticsEvent.voicePlayed(roomId: $roomId, messageId: $messageId, durationMs: $durationMs, firstListen: $firstListen)';
}


}

/// @nodoc
abstract mixin class $ChatAnalyticsVoicePlayedCopyWith<$Res> implements $ChatAnalyticsEventCopyWith<$Res> {
  factory $ChatAnalyticsVoicePlayedCopyWith(ChatAnalyticsVoicePlayed value, $Res Function(ChatAnalyticsVoicePlayed) _then) = _$ChatAnalyticsVoicePlayedCopyWithImpl;
@override @useResult
$Res call({
 String roomId, String messageId, int durationMs, bool firstListen
});




}
/// @nodoc
class _$ChatAnalyticsVoicePlayedCopyWithImpl<$Res>
    implements $ChatAnalyticsVoicePlayedCopyWith<$Res> {
  _$ChatAnalyticsVoicePlayedCopyWithImpl(this._self, this._then);

  final ChatAnalyticsVoicePlayed _self;
  final $Res Function(ChatAnalyticsVoicePlayed) _then;

/// Create a copy of ChatAnalyticsEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? roomId = null,Object? messageId = null,Object? durationMs = null,Object? firstListen = null,}) {
  return _then(ChatAnalyticsVoicePlayed(
roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,messageId: null == messageId ? _self.messageId : messageId // ignore: cast_nullable_to_non_nullable
as String,durationMs: null == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as int,firstListen: null == firstListen ? _self.firstListen : firstListen // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class ChatAnalyticsSendOutcome implements ChatAnalyticsEvent {
  const ChatAnalyticsSendOutcome({required this.roomId, required this.kind, required this.success, this.failureKind});
  

@override final  String roomId;
 final  MessageType kind;
 final  bool success;
 final  String? failureKind;

/// Create a copy of ChatAnalyticsEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatAnalyticsSendOutcomeCopyWith<ChatAnalyticsSendOutcome> get copyWith => _$ChatAnalyticsSendOutcomeCopyWithImpl<ChatAnalyticsSendOutcome>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatAnalyticsSendOutcome&&(identical(other.roomId, roomId) || other.roomId == roomId)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.success, success) || other.success == success)&&(identical(other.failureKind, failureKind) || other.failureKind == failureKind));
}


@override
int get hashCode => Object.hash(runtimeType,roomId,kind,success,failureKind);

@override
String toString() {
  return 'ChatAnalyticsEvent.sendOutcome(roomId: $roomId, kind: $kind, success: $success, failureKind: $failureKind)';
}


}

/// @nodoc
abstract mixin class $ChatAnalyticsSendOutcomeCopyWith<$Res> implements $ChatAnalyticsEventCopyWith<$Res> {
  factory $ChatAnalyticsSendOutcomeCopyWith(ChatAnalyticsSendOutcome value, $Res Function(ChatAnalyticsSendOutcome) _then) = _$ChatAnalyticsSendOutcomeCopyWithImpl;
@override @useResult
$Res call({
 String roomId, MessageType kind, bool success, String? failureKind
});




}
/// @nodoc
class _$ChatAnalyticsSendOutcomeCopyWithImpl<$Res>
    implements $ChatAnalyticsSendOutcomeCopyWith<$Res> {
  _$ChatAnalyticsSendOutcomeCopyWithImpl(this._self, this._then);

  final ChatAnalyticsSendOutcome _self;
  final $Res Function(ChatAnalyticsSendOutcome) _then;

/// Create a copy of ChatAnalyticsEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? roomId = null,Object? kind = null,Object? success = null,Object? failureKind = freezed,}) {
  return _then(ChatAnalyticsSendOutcome(
roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as MessageType,success: null == success ? _self.success : success // ignore: cast_nullable_to_non_nullable
as bool,failureKind: freezed == failureKind ? _self.failureKind : failureKind // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
