import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

import '../../_helpers/material_localizations_for_any_locale.dart';

/// What a host gets for registering `ChatUiLocalizations.delegate` and
/// nothing else: the room list, previews included, in the app's language,
/// and following it when it changes.
void main() {
  const me = ChatUser(id: 'u1', displayName: 'Me');
  const en = ChatUiLocalizations.en;
  const es = ChatUiLocalizations.es;

  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: me.id);
    adapter = ChatUiAdapter(
      client: client,
      currentUser: me,
      manageAppLifecycle: false,
    );
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  Widget app(Locale locale, {ChatUiAdapter? wired}) => MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      ChatUiLocalizations.delegate,
      ...anyLocaleMaterialDelegates,
    ],
    supportedLocales: ChatUiLocalizations.supportedLocales,
    home: Scaffold(
      body: RoomListView(
        controller: adapter.roomListController,
        adapter: wired,
        currentUserId: me.id,
        showHeader: false,
        showSearch: false,
      ),
    ),
  );

  testWidgets('every template preview follows the app locale, live', (
    tester,
  ) async {
    adapter.roomListController.setRooms([
      const RoomListItem(
        id: 'photo',
        name: 'Photos',
        lastMessageType: MessageType.attachment,
        lastMessageMimeType: 'image/jpeg',
      ),
      const RoomListItem(
        id: 'voice',
        name: 'Voice',
        lastMessageType: MessageType.audio,
        lastMessageDurationMs: 14000,
      ),
      const RoomListItem(
        id: 'deleted',
        name: 'Deleted',
        lastMessageIsDeleted: true,
        lastMessageUserId: 'u2',
      ),
      const RoomListItem(
        id: 'forward',
        name: 'Forward',
        lastMessageType: MessageType.forward,
      ),
      const RoomListItem(
        id: 'typed',
        name: 'Typed',
        lastMessage: 'hasta mañana',
      ),
    ]);

    await tester.pumpWidget(app(const Locale('en')));
    await tester.pump();
    expect(find.text(en.previewPhoto), findsOneWidget);
    expect(find.text(en.previewVoice('0:14')), findsOneWidget);
    expect(find.text(en.previewDeletedByOther), findsOneWidget);
    expect(find.text(en.forwarded), findsOneWidget);

    await tester.pumpWidget(app(const Locale('es')));
    await tester.pump();
    expect(find.text(es.previewPhoto), findsOneWidget);
    expect(find.text(es.previewVoice('0:14')), findsOneWidget);
    expect(find.text(es.previewDeletedByOther), findsOneWidget);
    expect(find.text(es.forwarded), findsOneWidget);
    expect(find.text('hasta mañana'), findsOneWidget);
  });

  testWidgets('a reaction row is rebuilt whole, with no doubled-up sender', (
    tester,
  ) async {
    adapter.roomListController.setRooms([
      const RoomListItem(
        id: 'group',
        name: 'Team',
        isGroup: true,
        lastMessageType: MessageType.reaction,
        lastMessageReactionEmoji: '🔥',
        lastMessageUserId: 'u2',
        lastMessageSenderName: 'Alice',
        lastMessageReactionTargetText: 'hasta mañana',
      ),
    ]);

    await tester.pumpWidget(app(const Locale('es')));
    await tester.pump();

    expect(
      find.text(es.reactionPreviewOther('Alice', '🔥', 'hasta mañana')),
      findsOneWidget,
    );
  });

  testWidgets('a wired adapter picks up the app locale with no assignment', (
    tester,
  ) async {
    await tester.pumpWidget(app(const Locale('es'), wired: adapter));
    await tester.pump();

    expect(adapter.l10n.localeCode, 'es');

    await tester.pumpWidget(app(const Locale('fr'), wired: adapter));
    await tester.pump();

    expect(adapter.l10n.localeCode, 'fr');
  });

  testWidgets('an adapter the host set keeps the host language', (
    tester,
  ) async {
    adapter.l10n = ChatUiLocalizations.fr;

    await tester.pumpWidget(app(const Locale('es'), wired: adapter));
    await tester.pump();

    expect(adapter.l10n.localeCode, 'fr');
  });

  testWidgets('the self-chat title re-stamp survives a listener the host '
      'mounted outside the view', (tester) async {
    adapter.roomListController.setRooms([
      RoomListItem(id: 'self', effectiveDisplayName: en.selfChatTitle('Me')),
    ]);

    Widget hostApp(Locale locale) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        ChatUiLocalizations.delegate,
        ...anyLocaleMaterialDelegates,
      ],
      supportedLocales: ChatUiLocalizations.supportedLocales,
      home: Scaffold(
        body: Column(
          children: [
            ListenableBuilder(
              listenable: adapter.roomListController,
              builder: (context, _) =>
                  Text('${adapter.roomListController.allRooms.length}'),
            ),
            Expanded(
              child: RoomListView(
                controller: adapter.roomListController,
                adapter: adapter,
                currentUserId: me.id,
                showHeader: false,
                showSearch: false,
              ),
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(hostApp(const Locale('en')));
    await tester.pumpAndSettle();

    await tester.pumpWidget(hostApp(const Locale('es')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      adapter.roomListController.getRoomById('self')?.effectiveDisplayName,
      es.selfChatTitle('Me'),
    );
  });
}
