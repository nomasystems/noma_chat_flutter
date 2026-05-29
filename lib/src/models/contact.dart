import 'package:freezed_annotation/freezed_annotation.dart';

part 'contact.freezed.dart';

/// A contact in the user's contact list, identified by user ID.
///
/// Equality and hash are id-based so `Set<ChatContact>` deduplicates by
/// `userId` regardless of any future extra fields.
@Freezed(equal: false)
abstract class ChatContact with _$ChatContact {
  const ChatContact._();

  const factory ChatContact({required String userId}) = _ChatContact;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ChatContact && other.userId == userId;

  @override
  int get hashCode => userId.hashCode;

  @override
  String toString() => 'ChatContact($userId)';
}
