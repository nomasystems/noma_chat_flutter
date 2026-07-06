// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'message.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ChatMessage {

 String get id; String get from; DateTime get timestamp; String? get text; MessageType get messageType; String? get attachmentUrl; String? get referencedMessageId;/// Echo of the client-supplied idempotency key sent with the message
/// (see [ChatMessagesApi.send]'s `clientMessageId`). The backend
/// round-trips it inside the response `metadata.clientMessageId`; the
/// SDK lifts it out to this field so it can reconcile the optimistic
/// temporary message with the server-assigned [id]. `null` when the
/// sender did not supply one (e.g. messages from other users).
 String? get clientMessageId; String? get reaction; String? get reply; Map<String, dynamic>? get metadata; ReceiptStatus? get receipt; bool get isEdited; bool get isDeleted; bool get isForwarded; bool get isStarred; bool get isSystem; String? get mimeType; String? get fileName; String? get fileSize; String? get thumbnailUrl;/// `true` when this message was accepted by the server but silently
/// dropped instead of delivered, because the recipient has blocked
/// the sender (`POST /contacts/{id}/messages` answers `204 No
/// Content` in that case — see [ChatContactsApi.sendDirectMessage]).
/// The SDK still synthesizes a local message with
/// [ReceiptStatus.sent] so the composer clears, but this flag lets
/// the UI distinguish that case from a normal send instead of
/// showing "sent" and then silently never advancing to
/// delivered/read.
 bool get silentlyDropped;
/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatMessageCopyWith<ChatMessage> get copyWith => _$ChatMessageCopyWithImpl<ChatMessage>(this as ChatMessage, _$identity);







}

/// @nodoc
abstract mixin class $ChatMessageCopyWith<$Res>  {
  factory $ChatMessageCopyWith(ChatMessage value, $Res Function(ChatMessage) _then) = _$ChatMessageCopyWithImpl;
@useResult
$Res call({
 String id, String from, DateTime timestamp, String? text, MessageType messageType, String? attachmentUrl, String? referencedMessageId, String? clientMessageId, String? reaction, String? reply, Map<String, dynamic>? metadata, ReceiptStatus? receipt, bool isEdited, bool isDeleted, bool isForwarded, bool isStarred, bool isSystem, String? mimeType, String? fileName, String? fileSize, String? thumbnailUrl, bool silentlyDropped
});




}
/// @nodoc
class _$ChatMessageCopyWithImpl<$Res>
    implements $ChatMessageCopyWith<$Res> {
  _$ChatMessageCopyWithImpl(this._self, this._then);

  final ChatMessage _self;
  final $Res Function(ChatMessage) _then;

/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? from = null,Object? timestamp = null,Object? text = freezed,Object? messageType = null,Object? attachmentUrl = freezed,Object? referencedMessageId = freezed,Object? clientMessageId = freezed,Object? reaction = freezed,Object? reply = freezed,Object? metadata = freezed,Object? receipt = freezed,Object? isEdited = null,Object? isDeleted = null,Object? isForwarded = null,Object? isStarred = null,Object? isSystem = null,Object? mimeType = freezed,Object? fileName = freezed,Object? fileSize = freezed,Object? thumbnailUrl = freezed,Object? silentlyDropped = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as DateTime,text: freezed == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String?,messageType: null == messageType ? _self.messageType : messageType // ignore: cast_nullable_to_non_nullable
as MessageType,attachmentUrl: freezed == attachmentUrl ? _self.attachmentUrl : attachmentUrl // ignore: cast_nullable_to_non_nullable
as String?,referencedMessageId: freezed == referencedMessageId ? _self.referencedMessageId : referencedMessageId // ignore: cast_nullable_to_non_nullable
as String?,clientMessageId: freezed == clientMessageId ? _self.clientMessageId : clientMessageId // ignore: cast_nullable_to_non_nullable
as String?,reaction: freezed == reaction ? _self.reaction : reaction // ignore: cast_nullable_to_non_nullable
as String?,reply: freezed == reply ? _self.reply : reply // ignore: cast_nullable_to_non_nullable
as String?,metadata: freezed == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,receipt: freezed == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as ReceiptStatus?,isEdited: null == isEdited ? _self.isEdited : isEdited // ignore: cast_nullable_to_non_nullable
as bool,isDeleted: null == isDeleted ? _self.isDeleted : isDeleted // ignore: cast_nullable_to_non_nullable
as bool,isForwarded: null == isForwarded ? _self.isForwarded : isForwarded // ignore: cast_nullable_to_non_nullable
as bool,isStarred: null == isStarred ? _self.isStarred : isStarred // ignore: cast_nullable_to_non_nullable
as bool,isSystem: null == isSystem ? _self.isSystem : isSystem // ignore: cast_nullable_to_non_nullable
as bool,mimeType: freezed == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String?,fileName: freezed == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String?,fileSize: freezed == fileSize ? _self.fileSize : fileSize // ignore: cast_nullable_to_non_nullable
as String?,thumbnailUrl: freezed == thumbnailUrl ? _self.thumbnailUrl : thumbnailUrl // ignore: cast_nullable_to_non_nullable
as String?,silentlyDropped: null == silentlyDropped ? _self.silentlyDropped : silentlyDropped // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ChatMessage].
extension ChatMessagePatterns on ChatMessage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatMessage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatMessage value)  $default,){
final _that = this;
switch (_that) {
case _ChatMessage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatMessage value)?  $default,){
final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String from,  DateTime timestamp,  String? text,  MessageType messageType,  String? attachmentUrl,  String? referencedMessageId,  String? clientMessageId,  String? reaction,  String? reply,  Map<String, dynamic>? metadata,  ReceiptStatus? receipt,  bool isEdited,  bool isDeleted,  bool isForwarded,  bool isStarred,  bool isSystem,  String? mimeType,  String? fileName,  String? fileSize,  String? thumbnailUrl,  bool silentlyDropped)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
return $default(_that.id,_that.from,_that.timestamp,_that.text,_that.messageType,_that.attachmentUrl,_that.referencedMessageId,_that.clientMessageId,_that.reaction,_that.reply,_that.metadata,_that.receipt,_that.isEdited,_that.isDeleted,_that.isForwarded,_that.isStarred,_that.isSystem,_that.mimeType,_that.fileName,_that.fileSize,_that.thumbnailUrl,_that.silentlyDropped);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String from,  DateTime timestamp,  String? text,  MessageType messageType,  String? attachmentUrl,  String? referencedMessageId,  String? clientMessageId,  String? reaction,  String? reply,  Map<String, dynamic>? metadata,  ReceiptStatus? receipt,  bool isEdited,  bool isDeleted,  bool isForwarded,  bool isStarred,  bool isSystem,  String? mimeType,  String? fileName,  String? fileSize,  String? thumbnailUrl,  bool silentlyDropped)  $default,) {final _that = this;
switch (_that) {
case _ChatMessage():
return $default(_that.id,_that.from,_that.timestamp,_that.text,_that.messageType,_that.attachmentUrl,_that.referencedMessageId,_that.clientMessageId,_that.reaction,_that.reply,_that.metadata,_that.receipt,_that.isEdited,_that.isDeleted,_that.isForwarded,_that.isStarred,_that.isSystem,_that.mimeType,_that.fileName,_that.fileSize,_that.thumbnailUrl,_that.silentlyDropped);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String from,  DateTime timestamp,  String? text,  MessageType messageType,  String? attachmentUrl,  String? referencedMessageId,  String? clientMessageId,  String? reaction,  String? reply,  Map<String, dynamic>? metadata,  ReceiptStatus? receipt,  bool isEdited,  bool isDeleted,  bool isForwarded,  bool isStarred,  bool isSystem,  String? mimeType,  String? fileName,  String? fileSize,  String? thumbnailUrl,  bool silentlyDropped)?  $default,) {final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
return $default(_that.id,_that.from,_that.timestamp,_that.text,_that.messageType,_that.attachmentUrl,_that.referencedMessageId,_that.clientMessageId,_that.reaction,_that.reply,_that.metadata,_that.receipt,_that.isEdited,_that.isDeleted,_that.isForwarded,_that.isStarred,_that.isSystem,_that.mimeType,_that.fileName,_that.fileSize,_that.thumbnailUrl,_that.silentlyDropped);case _:
  return null;

}
}

}

/// @nodoc


class _ChatMessage extends ChatMessage {
  const _ChatMessage({required this.id, required this.from, required this.timestamp, this.text, this.messageType = MessageType.regular, this.attachmentUrl, this.referencedMessageId, this.clientMessageId, this.reaction, this.reply, final  Map<String, dynamic>? metadata, this.receipt, this.isEdited = false, this.isDeleted = false, this.isForwarded = false, this.isStarred = false, this.isSystem = false, this.mimeType, this.fileName, this.fileSize, this.thumbnailUrl, this.silentlyDropped = false}): _metadata = metadata,super._();
  

@override final  String id;
@override final  String from;
@override final  DateTime timestamp;
@override final  String? text;
@override@JsonKey() final  MessageType messageType;
@override final  String? attachmentUrl;
@override final  String? referencedMessageId;
/// Echo of the client-supplied idempotency key sent with the message
/// (see [ChatMessagesApi.send]'s `clientMessageId`). The backend
/// round-trips it inside the response `metadata.clientMessageId`; the
/// SDK lifts it out to this field so it can reconcile the optimistic
/// temporary message with the server-assigned [id]. `null` when the
/// sender did not supply one (e.g. messages from other users).
@override final  String? clientMessageId;
@override final  String? reaction;
@override final  String? reply;
 final  Map<String, dynamic>? _metadata;
@override Map<String, dynamic>? get metadata {
  final value = _metadata;
  if (value == null) return null;
  if (_metadata is EqualUnmodifiableMapView) return _metadata;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

@override final  ReceiptStatus? receipt;
@override@JsonKey() final  bool isEdited;
@override@JsonKey() final  bool isDeleted;
@override@JsonKey() final  bool isForwarded;
@override@JsonKey() final  bool isStarred;
@override@JsonKey() final  bool isSystem;
@override final  String? mimeType;
@override final  String? fileName;
@override final  String? fileSize;
@override final  String? thumbnailUrl;
/// `true` when this message was accepted by the server but silently
/// dropped instead of delivered, because the recipient has blocked
/// the sender (`POST /contacts/{id}/messages` answers `204 No
/// Content` in that case — see [ChatContactsApi.sendDirectMessage]).
/// The SDK still synthesizes a local message with
/// [ReceiptStatus.sent] so the composer clears, but this flag lets
/// the UI distinguish that case from a normal send instead of
/// showing "sent" and then silently never advancing to
/// delivered/read.
@override@JsonKey() final  bool silentlyDropped;

/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatMessageCopyWith<_ChatMessage> get copyWith => __$ChatMessageCopyWithImpl<_ChatMessage>(this, _$identity);







}

/// @nodoc
abstract mixin class _$ChatMessageCopyWith<$Res> implements $ChatMessageCopyWith<$Res> {
  factory _$ChatMessageCopyWith(_ChatMessage value, $Res Function(_ChatMessage) _then) = __$ChatMessageCopyWithImpl;
@override @useResult
$Res call({
 String id, String from, DateTime timestamp, String? text, MessageType messageType, String? attachmentUrl, String? referencedMessageId, String? clientMessageId, String? reaction, String? reply, Map<String, dynamic>? metadata, ReceiptStatus? receipt, bool isEdited, bool isDeleted, bool isForwarded, bool isStarred, bool isSystem, String? mimeType, String? fileName, String? fileSize, String? thumbnailUrl, bool silentlyDropped
});




}
/// @nodoc
class __$ChatMessageCopyWithImpl<$Res>
    implements _$ChatMessageCopyWith<$Res> {
  __$ChatMessageCopyWithImpl(this._self, this._then);

  final _ChatMessage _self;
  final $Res Function(_ChatMessage) _then;

/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? from = null,Object? timestamp = null,Object? text = freezed,Object? messageType = null,Object? attachmentUrl = freezed,Object? referencedMessageId = freezed,Object? clientMessageId = freezed,Object? reaction = freezed,Object? reply = freezed,Object? metadata = freezed,Object? receipt = freezed,Object? isEdited = null,Object? isDeleted = null,Object? isForwarded = null,Object? isStarred = null,Object? isSystem = null,Object? mimeType = freezed,Object? fileName = freezed,Object? fileSize = freezed,Object? thumbnailUrl = freezed,Object? silentlyDropped = null,}) {
  return _then(_ChatMessage(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as DateTime,text: freezed == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String?,messageType: null == messageType ? _self.messageType : messageType // ignore: cast_nullable_to_non_nullable
as MessageType,attachmentUrl: freezed == attachmentUrl ? _self.attachmentUrl : attachmentUrl // ignore: cast_nullable_to_non_nullable
as String?,referencedMessageId: freezed == referencedMessageId ? _self.referencedMessageId : referencedMessageId // ignore: cast_nullable_to_non_nullable
as String?,clientMessageId: freezed == clientMessageId ? _self.clientMessageId : clientMessageId // ignore: cast_nullable_to_non_nullable
as String?,reaction: freezed == reaction ? _self.reaction : reaction // ignore: cast_nullable_to_non_nullable
as String?,reply: freezed == reply ? _self.reply : reply // ignore: cast_nullable_to_non_nullable
as String?,metadata: freezed == metadata ? _self._metadata : metadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,receipt: freezed == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as ReceiptStatus?,isEdited: null == isEdited ? _self.isEdited : isEdited // ignore: cast_nullable_to_non_nullable
as bool,isDeleted: null == isDeleted ? _self.isDeleted : isDeleted // ignore: cast_nullable_to_non_nullable
as bool,isForwarded: null == isForwarded ? _self.isForwarded : isForwarded // ignore: cast_nullable_to_non_nullable
as bool,isStarred: null == isStarred ? _self.isStarred : isStarred // ignore: cast_nullable_to_non_nullable
as bool,isSystem: null == isSystem ? _self.isSystem : isSystem // ignore: cast_nullable_to_non_nullable
as bool,mimeType: freezed == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String?,fileName: freezed == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String?,fileSize: freezed == fileSize ? _self.fileSize : fileSize // ignore: cast_nullable_to_non_nullable
as String?,thumbnailUrl: freezed == thumbnailUrl ? _self.thumbnailUrl : thumbnailUrl // ignore: cast_nullable_to_non_nullable
as String?,silentlyDropped: null == silentlyDropped ? _self.silentlyDropped : silentlyDropped // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$PendingChatMessage {

 ChatMessage get message; bool get isFailed;
/// Create a copy of PendingChatMessage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PendingChatMessageCopyWith<PendingChatMessage> get copyWith => _$PendingChatMessageCopyWithImpl<PendingChatMessage>(this as PendingChatMessage, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PendingChatMessage&&(identical(other.message, message) || other.message == message)&&(identical(other.isFailed, isFailed) || other.isFailed == isFailed));
}


@override
int get hashCode => Object.hash(runtimeType,message,isFailed);

@override
String toString() {
  return 'PendingChatMessage(message: $message, isFailed: $isFailed)';
}


}

/// @nodoc
abstract mixin class $PendingChatMessageCopyWith<$Res>  {
  factory $PendingChatMessageCopyWith(PendingChatMessage value, $Res Function(PendingChatMessage) _then) = _$PendingChatMessageCopyWithImpl;
@useResult
$Res call({
 ChatMessage message, bool isFailed
});


$ChatMessageCopyWith<$Res> get message;

}
/// @nodoc
class _$PendingChatMessageCopyWithImpl<$Res>
    implements $PendingChatMessageCopyWith<$Res> {
  _$PendingChatMessageCopyWithImpl(this._self, this._then);

  final PendingChatMessage _self;
  final $Res Function(PendingChatMessage) _then;

/// Create a copy of PendingChatMessage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? message = null,Object? isFailed = null,}) {
  return _then(_self.copyWith(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as ChatMessage,isFailed: null == isFailed ? _self.isFailed : isFailed // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of PendingChatMessage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ChatMessageCopyWith<$Res> get message {
  
  return $ChatMessageCopyWith<$Res>(_self.message, (value) {
    return _then(_self.copyWith(message: value));
  });
}
}


/// Adds pattern-matching-related methods to [PendingChatMessage].
extension PendingChatMessagePatterns on PendingChatMessage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PendingChatMessage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PendingChatMessage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PendingChatMessage value)  $default,){
final _that = this;
switch (_that) {
case _PendingChatMessage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PendingChatMessage value)?  $default,){
final _that = this;
switch (_that) {
case _PendingChatMessage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ChatMessage message,  bool isFailed)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PendingChatMessage() when $default != null:
return $default(_that.message,_that.isFailed);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ChatMessage message,  bool isFailed)  $default,) {final _that = this;
switch (_that) {
case _PendingChatMessage():
return $default(_that.message,_that.isFailed);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ChatMessage message,  bool isFailed)?  $default,) {final _that = this;
switch (_that) {
case _PendingChatMessage() when $default != null:
return $default(_that.message,_that.isFailed);case _:
  return null;

}
}

}

/// @nodoc


class _PendingChatMessage implements PendingChatMessage {
  const _PendingChatMessage(this.message, {this.isFailed = false});
  

@override final  ChatMessage message;
@override@JsonKey() final  bool isFailed;

/// Create a copy of PendingChatMessage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PendingChatMessageCopyWith<_PendingChatMessage> get copyWith => __$PendingChatMessageCopyWithImpl<_PendingChatMessage>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PendingChatMessage&&(identical(other.message, message) || other.message == message)&&(identical(other.isFailed, isFailed) || other.isFailed == isFailed));
}


@override
int get hashCode => Object.hash(runtimeType,message,isFailed);

@override
String toString() {
  return 'PendingChatMessage(message: $message, isFailed: $isFailed)';
}


}

/// @nodoc
abstract mixin class _$PendingChatMessageCopyWith<$Res> implements $PendingChatMessageCopyWith<$Res> {
  factory _$PendingChatMessageCopyWith(_PendingChatMessage value, $Res Function(_PendingChatMessage) _then) = __$PendingChatMessageCopyWithImpl;
@override @useResult
$Res call({
 ChatMessage message, bool isFailed
});


@override $ChatMessageCopyWith<$Res> get message;

}
/// @nodoc
class __$PendingChatMessageCopyWithImpl<$Res>
    implements _$PendingChatMessageCopyWith<$Res> {
  __$PendingChatMessageCopyWithImpl(this._self, this._then);

  final _PendingChatMessage _self;
  final $Res Function(_PendingChatMessage) _then;

/// Create a copy of PendingChatMessage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? isFailed = null,}) {
  return _then(_PendingChatMessage(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as ChatMessage,isFailed: null == isFailed ? _self.isFailed : isFailed // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of PendingChatMessage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ChatMessageCopyWith<$Res> get message {
  
  return $ChatMessageCopyWith<$Res>(_self.message, (value) {
    return _then(_self.copyWith(message: value));
  });
}
}

// dart format on
