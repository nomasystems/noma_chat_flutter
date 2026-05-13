/// An emoji reaction with its count and the list of users who reacted.
class AggregatedReaction {
  final String emoji;
  final int count;
  final List<String> users;

  const AggregatedReaction({
    required this.emoji,
    required this.count,
    this.users = const [],
  });
}
