import 'package:noma_chat/noma_chat.dart';
import 'package:flutter/foundation.dart';

/// Lightweight projection of a user shown in [ContactSuggestionsBar] —
/// just enough to render an avatar with name and presence dot.
@immutable
class SuggestedContact {
  final String id;
  final String displayName;
  final String? avatarUrl;
  final bool? isOnline;
  final PresenceStatus? presenceStatus;

  const SuggestedContact({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.isOnline,
    this.presenceStatus,
  });
}
