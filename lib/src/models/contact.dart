import 'package:flutter/foundation.dart';

/// A contact in the user's contact list, identified by user ID.
@immutable
class ChatContact {
  final String userId;

  const ChatContact({required this.userId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ChatContact && other.userId == userId;

  @override
  int get hashCode => userId.hashCode;

  @override
  String toString() => 'ChatContact($userId)';
}
