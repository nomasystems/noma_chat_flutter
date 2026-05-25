import 'package:freezed_annotation/freezed_annotation.dart';

part 'reaction.freezed.dart';

/// An emoji reaction with its count and the list of users who reacted.
@freezed
abstract class AggregatedReaction with _$AggregatedReaction {
  const factory AggregatedReaction({
    required String emoji,
    required int count,
    @Default(<String>[]) List<String> users,
  }) = _AggregatedReaction;
}
