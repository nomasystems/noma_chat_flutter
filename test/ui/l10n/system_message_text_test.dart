import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

import '../../_helpers/material_localizations_for_any_locale.dart';

Widget _host({
  required Locale locale,
  required Widget child,
  List<LocalizationsDelegate<dynamic>> delegates = const [],
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: [...delegates, ...anyLocaleMaterialDelegates],
    supportedLocales: ChatUiLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

ChatMessage _systemMessage({
  required String text,
  Map<String, dynamic>? metadata,
}) => ChatMessage(
  id: 'sys1',
  from: 'system',
  timestamp: DateTime(2026, 1, 1),
  text: text,
  isSystem: true,
  metadata: metadata,
);

/// A membership banner is composed by the adapter (which has no
/// `BuildContext`) and persisted, so the stored sentence is frozen in
/// whatever language the session had when the event arrived. These tests
/// pin the way out: the row carries the ingredients, so the text is rebuilt
/// at paint time in the language on screen, and a row without them keeps
/// the frozen text.
void main() {
  group('localizedSystemMessageTextFromMetadata', () {
    test('rebuilds a join banner in the requested language', () {
      const metadata = <String, dynamic>{
        SystemMessageMetadataKeys.event: 'user_joined',
        SystemMessageMetadataKeys.userId: 'u2',
        SystemMessageMetadataKeys.userLabel: 'Alice',
      };

      expect(
        localizedSystemMessageTextFromMetadata(
          metadata,
          ChatUiLocalizations.en,
        ),
        'Alice joined',
      );
      expect(
        localizedSystemMessageTextFromMetadata(
          metadata,
          ChatUiLocalizations.es,
        ),
        'Alice se ha unido',
      );
    });

    test('rebuilds a plain leave banner', () {
      expect(
        localizedSystemMessageTextFromMetadata(const {
          SystemMessageMetadataKeys.event: 'user_left',
          SystemMessageMetadataKeys.userId: 'u2',
          SystemMessageMetadataKeys.userLabel: 'Alice',
        }, ChatUiLocalizations.es),
        'Alice ha salido',
      );
    });

    test('picks the "you were removed" wording for a kick on the local '
        'user', () {
      expect(
        localizedSystemMessageTextFromMetadata(const {
          SystemMessageMetadataKeys.event: 'user_left',
          SystemMessageMetadataKeys.userId: 'u1',
          SystemMessageMetadataKeys.actorUserId: 'u2',
          SystemMessageMetadataKeys.userLabel: 'Me',
          SystemMessageMetadataKeys.actorLabel: 'Alice',
          SystemMessageMetadataKeys.userIsSelf: true,
        }, ChatUiLocalizations.es),
        'Alice te ha eliminado',
      );
    });

    test('picks the "you removed" wording for a kick performed by the local '
        'user', () {
      expect(
        localizedSystemMessageTextFromMetadata(const {
          SystemMessageMetadataKeys.event: 'user_left',
          SystemMessageMetadataKeys.userId: 'u3',
          SystemMessageMetadataKeys.actorUserId: 'u1',
          SystemMessageMetadataKeys.userLabel: 'Bob',
          SystemMessageMetadataKeys.actorLabel: 'Me',
          SystemMessageMetadataKeys.actorIsSelf: true,
        }, ChatUiLocalizations.es),
        'Has eliminado a Bob',
      );
    });

    test('names both sides for a kick between third parties', () {
      expect(
        localizedSystemMessageTextFromMetadata(const {
          SystemMessageMetadataKeys.event: 'user_left',
          SystemMessageMetadataKeys.userId: 'u3',
          SystemMessageMetadataKeys.actorUserId: 'u2',
          SystemMessageMetadataKeys.userLabel: 'Bob',
          SystemMessageMetadataKeys.actorLabel: 'Alice',
        }, ChatUiLocalizations.es),
        'Alice ha eliminado a Bob',
      );
    });

    test('rebuilds a role-change banner', () {
      expect(
        localizedSystemMessageTextFromMetadata(const {
          SystemMessageMetadataKeys.event: 'user_role_changed',
          SystemMessageMetadataKeys.userId: 'u2',
          SystemMessageMetadataKeys.userLabel: 'Alice',
        }, ChatUiLocalizations.es),
        'El rol de Alice ha cambiado',
      );
    });

    test('returns null for a row persisted without the display labels', () {
      expect(
        localizedSystemMessageTextFromMetadata(const {
          SystemMessageMetadataKeys.event: 'user_joined',
          SystemMessageMetadataKeys.userId: 'u2',
        }, ChatUiLocalizations.es),
        isNull,
      );
    });

    test('returns null for a kick whose actor has no label', () {
      expect(
        localizedSystemMessageTextFromMetadata(const {
          SystemMessageMetadataKeys.event: 'user_left',
          SystemMessageMetadataKeys.userId: 'u3',
          SystemMessageMetadataKeys.actorUserId: 'u2',
          SystemMessageMetadataKeys.userLabel: 'Bob',
        }, ChatUiLocalizations.es),
        isNull,
      );
    });

    test('resolves a label that is still the raw user id', () {
      expect(
        localizedSystemMessageTextFromMetadata(
          const {
            SystemMessageMetadataKeys.event: 'user_joined',
            SystemMessageMetadataKeys.userId: 'u2',
            SystemMessageMetadataKeys.userLabel: 'u2',
          },
          ChatUiLocalizations.es,
          resolveDisplayName: (id) => id == 'u2' ? 'Alice' : null,
        ),
        'Alice se ha unido',
      );
    });

    test('resolves the actor label of a kick that froze the raw id', () {
      expect(
        localizedSystemMessageTextFromMetadata(
          const {
            SystemMessageMetadataKeys.event: 'user_left',
            SystemMessageMetadataKeys.userId: 'u3',
            SystemMessageMetadataKeys.actorUserId: 'u2',
            SystemMessageMetadataKeys.userLabel: 'u3',
            SystemMessageMetadataKeys.actorLabel: 'u2',
          },
          ChatUiLocalizations.es,
          resolveDisplayName: (id) => switch (id) {
            'u2' => 'Alice',
            'u3' => 'Bob',
            _ => null,
          },
        ),
        'Alice ha eliminado a Bob',
      );
    });

    test('resolves a label minted blank because nobody had a name yet', () {
      expect(
        localizedSystemMessageTextFromMetadata(
          const {
            SystemMessageMetadataKeys.event: 'user_joined',
            SystemMessageMetadataKeys.userId: 'u2',
            SystemMessageMetadataKeys.userLabel: '',
          },
          ChatUiLocalizations.es,
          resolveDisplayName: (id) => id == 'u2' ? 'Alice' : null,
        ),
        'Alice se ha unido',
      );
    });

    test('spells an unresolved label as the member noun, never as the id', () {
      expect(
        localizedSystemMessageTextFromMetadata(const {
          SystemMessageMetadataKeys.event: 'user_joined',
          SystemMessageMetadataKeys.userId: 'u2',
          SystemMessageMetadataKeys.userLabel: '',
        }, ChatUiLocalizations.en),
        'Member joined',
      );
    });

    test(
      'names the kicked member generically when only the actor is known',
      () {
        expect(
          localizedSystemMessageTextFromMetadata(const {
            SystemMessageMetadataKeys.event: 'user_left',
            SystemMessageMetadataKeys.userId: 'u3',
            SystemMessageMetadataKeys.actorUserId: 'u2',
            SystemMessageMetadataKeys.userLabel: '',
            SystemMessageMetadataKeys.actorLabel: 'Alice',
          }, ChatUiLocalizations.en),
          ChatUiLocalizations.en.userRemovedBy(
            ChatUiLocalizations.en.member,
            'Alice',
          ),
        );
      },
    );

    test('keeps the stored label when the resolver has nothing better', () {
      expect(
        localizedSystemMessageTextFromMetadata(
          const {
            SystemMessageMetadataKeys.event: 'user_joined',
            SystemMessageMetadataKeys.userId: 'u2',
            SystemMessageMetadataKeys.userLabel: 'Alice',
          },
          ChatUiLocalizations.es,
          resolveDisplayName: (_) => 'Someone else',
        ),
        'Alice se ha unido',
      );
      expect(
        localizedSystemMessageTextFromMetadata(
          const {
            SystemMessageMetadataKeys.event: 'user_joined',
            SystemMessageMetadataKeys.userId: 'u2',
            SystemMessageMetadataKeys.userLabel: 'u2',
          },
          ChatUiLocalizations.es,
          resolveDisplayName: (_) => '  ',
        ),
        'u2 se ha unido',
      );
    });

    test('returns null for metadata that is not a membership banner', () {
      expect(
        localizedSystemMessageTextFromMetadata(null, ChatUiLocalizations.es),
        isNull,
      );
      expect(
        localizedSystemMessageTextFromMetadata(const {
          'event': 'plan_cancelled',
          'userLabel': 'Alice',
        }, ChatUiLocalizations.es),
        isNull,
      );
    });
  });

  group('MessageBubble system rows', () {
    const joinedMetadata = <String, dynamic>{
      SystemMessageMetadataKeys.event: 'user_joined',
      SystemMessageMetadataKeys.userId: 'u2',
      SystemMessageMetadataKeys.userLabel: 'Alice',
    };

    testWidgets('repaints the banner in the app locale, not the one it was '
        'stored in', (tester) async {
      final message = _systemMessage(
        text: 'Alice joined',
        metadata: joinedMetadata,
      );

      await tester.pumpWidget(
        _host(
          locale: const Locale('es'),
          delegates: const [ChatUiLocalizations.delegate],
          child: MessageBubble(message: message, isOutgoing: false),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice se ha unido'), findsOneWidget);
      expect(find.text('Alice joined'), findsNothing);
    });

    testWidgets('follows a live language change', (tester) async {
      final message = _systemMessage(
        text: 'Alice joined',
        metadata: joinedMetadata,
      );
      Widget app(Locale locale) => _host(
        locale: locale,
        delegates: const [ChatUiLocalizations.delegate],
        child: MessageBubble(message: message, isOutgoing: false),
      );

      await tester.pumpWidget(app(const Locale('en')));
      await tester.pumpAndSettle();
      expect(find.text('Alice joined'), findsOneWidget);

      await tester.pumpWidget(app(const Locale('es')));
      await tester.pumpAndSettle();
      expect(find.text('Alice se ha unido'), findsOneWidget);
    });

    testWidgets('honours the language the host put on the theme', (
      tester,
    ) async {
      final message = _systemMessage(
        text: 'Alice joined',
        metadata: joinedMetadata,
      );

      await tester.pumpWidget(
        _host(
          locale: const Locale('es'),
          delegates: const [ChatUiLocalizations.delegate],
          child: MessageBubble(
            message: message,
            isOutgoing: false,
            theme: ChatTheme.defaults.copyWith(l10n: ChatUiLocalizations.fr),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice a rejoint'), findsOneWidget);
    });

    testWidgets('keeps the stored text for a row without the labels', (
      tester,
    ) async {
      final message = _systemMessage(
        text: 'Alice joined',
        metadata: const {'event': 'user_joined', 'userId': 'u2'},
      );

      await tester.pumpWidget(
        _host(
          locale: const Locale('es'),
          delegates: const [ChatUiLocalizations.delegate],
          child: MessageBubble(message: message, isOutgoing: false),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice joined'), findsOneWidget);
    });

    testWidgets('turns a frozen raw id into a name on repaint', (tester) async {
      final message = _systemMessage(
        text: 'u2 joined',
        metadata: const {
          SystemMessageMetadataKeys.event: 'user_joined',
          SystemMessageMetadataKeys.userId: 'u2',
          SystemMessageMetadataKeys.userLabel: 'u2',
        },
      );

      await tester.pumpWidget(
        _host(
          locale: const Locale('es'),
          delegates: const [ChatUiLocalizations.delegate],
          child: MessageBubble(
            message: message,
            isOutgoing: false,
            displayNameResolver: (id) => id == 'u2' ? 'Alice' : null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice se ha unido'), findsOneWidget);
      expect(find.textContaining('u2'), findsNothing);
    });

    testWidgets('repairs the id for a host that recomposes the row', (
      tester,
    ) async {
      final message = _systemMessage(
        text: 'u2 joined',
        metadata: const {
          SystemMessageMetadataKeys.event: 'user_joined',
          SystemMessageMetadataKeys.userId: 'u2',
          SystemMessageMetadataKeys.userLabel: 'u2',
        },
      );

      await tester.pumpWidget(
        _host(
          locale: const Locale('es'),
          delegates: const [ChatUiLocalizations.delegate],
          child: MessageBubble(
            message: message,
            isOutgoing: false,
            displayNameResolver: (id) => id == 'u2' ? 'Alice' : null,
            systemMessageTextResolver: (row) =>
                localizedSystemMessageText(row, ChatUiLocalizations.es) ??
                row.text ??
                '',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice se ha unido'), findsOneWidget);
      expect(find.textContaining('u2'), findsNothing);
    });

    testWidgets('repairs the kick actor for a host that recomposes the row', (
      tester,
    ) async {
      final message = _systemMessage(
        text: 'u2 removed',
        metadata: const {
          SystemMessageMetadataKeys.event: 'user_left',
          SystemMessageMetadataKeys.userId: 'u2',
          SystemMessageMetadataKeys.userLabel: 'Alice',
          SystemMessageMetadataKeys.actorUserId: 'u3',
          SystemMessageMetadataKeys.actorLabel: 'u3',
        },
      );

      await tester.pumpWidget(
        _host(
          locale: const Locale('es'),
          delegates: const [ChatUiLocalizations.delegate],
          child: MessageBubble(
            message: message,
            isOutgoing: false,
            displayNameResolver: (id) => id == 'u3' ? 'Bob' : null,
            systemMessageTextResolver: (row) =>
                localizedSystemMessageText(row, ChatUiLocalizations.es) ??
                row.text ??
                '',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Bob'), findsOneWidget);
      expect(find.textContaining('u3'), findsNothing);
    });

    testWidgets('hands the custom system builder the repaired row', (
      tester,
    ) async {
      final message = _systemMessage(
        text: 'u2 joined',
        metadata: const {
          SystemMessageMetadataKeys.event: 'user_joined',
          SystemMessageMetadataKeys.userId: 'u2',
          SystemMessageMetadataKeys.userLabel: 'u2',
        },
      );

      await tester.pumpWidget(
        _host(
          locale: const Locale('es'),
          delegates: const [ChatUiLocalizations.delegate],
          child: MessageBubble(
            message: message,
            isOutgoing: false,
            displayNameResolver: (id) => id == 'u2' ? 'Alice' : null,
            systemMessageBuilder: (_, row) => Text(
              row.metadata?[SystemMessageMetadataKeys.userLabel] as String? ??
                  '',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('a host resolver still wins over both', (tester) async {
      final message = _systemMessage(
        text: 'Alice joined',
        metadata: joinedMetadata,
      );

      await tester.pumpWidget(
        _host(
          locale: const Locale('es'),
          delegates: const [ChatUiLocalizations.delegate],
          child: MessageBubble(
            message: message,
            isOutgoing: false,
            systemMessageTextResolver: (_) => 'Host copy',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Host copy'), findsOneWidget);
    });
  });
}
