import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  final reactions = [
    const AggregatedReaction(emoji: '👍', count: 2, users: ['u1', 'u2']),
    const AggregatedReaction(emoji: '❤️', count: 1, users: ['u1']),
  ];

  Future<ReactionUser> resolver(String userId) async {
    final names = {'u1': 'Alice', 'u2': 'Bob'};
    return ReactionUser(id: userId, displayName: names[userId] ?? userId);
  }

  group('ReactionDetailSheet', () {
    testWidgets('shows loading indicator initially', (tester) async {
      final completer = Completer<List<AggregatedReaction>>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => ReactionDetailSheet.show(
                    context,
                    fetchReactions: () => completer.future,
                    currentUserId: 'u1',
                    userResolver: resolver,
                    onRemoveReaction: (_) {},
                  ),
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(reactions);
      await tester.pumpAndSettle();
    });

    testWidgets('shows tabs and users after loading', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => ReactionDetailSheet.show(
                    context,
                    fetchReactions: () async => reactions,
                    currentUserId: 'u1',
                    userResolver: resolver,
                    onRemoveReaction: (_) {},
                  ),
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('All 3'), findsOneWidget);
      expect(find.text('👍 2'), findsOneWidget);
      expect(find.text('❤️ 1'), findsOneWidget);

      // u1 is current user → shown as "You", u2 is "Bob"
      expect(find.text('You'), findsWidgets);
      expect(find.text('Bob'), findsWidgets);
    });

    testWidgets('shows You for current user', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => ReactionDetailSheet.show(
                    context,
                    fetchReactions: () async => reactions,
                    currentUserId: 'u1',
                    userResolver: resolver,
                    onRemoveReaction: (_) {},
                  ),
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('You'), findsWidgets);
    });

    testWidgets('shows remove button for own reaction', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => ReactionDetailSheet.show(
                    context,
                    fetchReactions: () async => reactions,
                    currentUserId: 'u1',
                    userResolver: resolver,
                    onRemoveReaction: (_) {},
                  ),
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close), findsWidgets);
    });

    testWidgets('calls onRemoveReaction and closes sheet', (tester) async {
      String? removedEmoji;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => ReactionDetailSheet.show(
                    context,
                    fetchReactions: () async => [
                      const AggregatedReaction(
                        emoji: '👍',
                        count: 1,
                        users: ['u1'],
                      ),
                    ],
                    currentUserId: 'u1',
                    userResolver: resolver,
                    onRemoveReaction: (emoji) => removedEmoji = emoji,
                  ),
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();

      expect(removedEmoji, '👍');
    });

    testWidgets('shows error state on fetch failure', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => ReactionDetailSheet.show(
                    context,
                    fetchReactions: () async => throw Exception('fail'),
                    currentUserId: 'u1',
                    userResolver: resolver,
                    onRemoveReaction: (_) {},
                  ),
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Exception'), findsOneWidget);
    });
  });

  group('ReactionBar onShowDetail', () {
    testWidgets('calls onShowDetail instead of add/remove when provided', (
      tester,
    ) async {
      bool detailOpened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReactionBar(
              reactions: const {'👍': 3},
              userReactions: const {'👍'},
              onDeleteReaction: (_) => fail('should not be called'),
              onShowDetail: () => detailOpened = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('👍 3'));
      expect(detailOpened, true);
    });

    testWidgets('falls back to legacy behavior when onShowDetail is null', (
      tester,
    ) async {
      String? deleted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReactionBar(
              reactions: const {'👍': 3},
              userReactions: const {'👍'},
              onDeleteReaction: (emoji) => deleted = emoji,
            ),
          ),
        ),
      );

      await tester.tap(find.text('👍 3'));
      expect(deleted, '👍');
    });
  });
}
