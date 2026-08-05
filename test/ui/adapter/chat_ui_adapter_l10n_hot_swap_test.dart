import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

void main() {
  const me = ChatUser(id: 'u1', displayName: 'Me');
  const en = ChatUiLocalizations.en;
  const fr = ChatUiLocalizations.fr;

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

  /// The rows a swap has no business rewriting: everything a person typed,
  /// plus the two shapes whose stored text reads exactly like a template —
  /// a caption that happens to be word for word the label it replaces, and
  /// a reaction whose quoted snippet is the sender's own sentence.
  List<RoomListItem> humanWrittenRows() => [
    const RoomListItem(id: 'plain', lastMessage: 'à demain'),
    RoomListItem(
      id: 'caption_reads_like_label',
      lastMessage: en.attachmentPreview,
      lastMessageType: MessageType.attachment,
      lastMessageMimeType: 'application/pdf',
      lastMessageFileName: 'notes.pdf',
    ),
    RoomListItem(
      id: 'forward_with_text',
      lastMessage: en.forwarded,
      lastMessageType: MessageType.forward,
    ),
  ];

  test('the bundle a widget paints with drives every template preview, and '
      'the swap leaves the connection alone', () async {
    await adapter.connect();
    await pumpEventQueue();
    adapter.roomListController.setRooms([
      const RoomListItem(
        id: 'photo_no_caption',
        lastMessageType: MessageType.attachment,
        lastMessageMimeType: 'image/jpeg',
      ),
      const RoomListItem(
        id: 'voice',
        lastMessageType: MessageType.audio,
        lastMessageDurationMs: 14000,
      ),
      const RoomListItem(
        id: 'forward_no_text',
        lastMessageType: MessageType.forward,
      ),
      const RoomListItem(
        id: 'deleted',
        lastMessageIsDeleted: true,
        lastMessageUserId: 'u2',
      ),
      const RoomListItem(
        id: 'reaction_by_other',
        lastMessageType: MessageType.reaction,
        lastMessageReactionEmoji: '🔥',
        lastMessageUserId: 'u2',
        lastMessageSenderName: 'Alice',
        lastMessageReactionTargetText: 'à demain',
      ),
      RoomListItem(
        id: 'reaction_on_a_photo',
        lastMessageType: MessageType.reaction,
        lastMessageReactionEmoji: '🔥',
        lastMessageUserId: me.id,
        lastMessageReactionTargetType: MessageType.attachment,
      ),
      RoomListItem(id: 'self', effectiveDisplayName: en.selfChatTitle('Me')),
    ]);

    String? previewOf(String roomId, ChatUiLocalizations l10n) =>
        buildLastMessagePreview(
          adapter.roomListController.getRoomById(roomId)!,
          l10n,
          currentUserId: me.id,
        );

    expect(previewOf('photo_no_caption', en), en.previewPhoto);
    expect(previewOf('photo_no_caption', fr), fr.previewPhoto);
    expect(previewOf('voice', en), en.previewVoice('0:14'));
    expect(previewOf('voice', fr), fr.previewVoice('0:14'));
    expect(previewOf('forward_no_text', en), en.forwarded);
    expect(previewOf('forward_no_text', fr), fr.forwarded);
    expect(previewOf('deleted', en), en.previewDeletedByOther);
    expect(previewOf('deleted', fr), fr.previewDeletedByOther);
    expect(
      previewOf('reaction_by_other', fr),
      fr.reactionPreviewOther('Alice', '🔥', 'à demain'),
    );
    expect(
      previewOf('reaction_on_a_photo', fr),
      fr.reactionPreviewSelf('🔥', fr.attachmentPreview),
    );

    adapter.l10n = fr;

    expect(adapter.l10n, same(fr));
    expect(
      adapter.roomListController.getRoomById('self')?.effectiveDisplayName,
      fr.selfChatTitle('Me'),
    );
    expect(client.connectionState, ChatConnectionState.connected);
  });

  test('a swap never rewrites text a person wrote', () async {
    final before = humanWrittenRows();
    adapter.roomListController.setRooms(before);

    adapter.l10n = fr;

    for (final room in before) {
      expect(
        adapter.roomListController.getRoomById(room.id)?.lastMessage,
        room.lastMessage,
        reason: 'row ${room.id} had its stored text rewritten',
      );
    }
    expect(
      buildLastMessagePreview(
        adapter.roomListController.getRoomById('caption_reads_like_label')!,
        fr,
      ),
      fr.previewDocument('notes.pdf'),
    );
    expect(
      buildLastMessagePreview(
        adapter.roomListController.getRoomById('forward_with_text')!,
        fr,
      ),
      en.forwarded,
    );
  });

  test('assigning the same bundle changes nothing', () async {
    adapter.roomListController.setRooms([
      RoomListItem(id: 'self', effectiveDisplayName: en.selfChatTitle('Me')),
    ]);

    adapter.l10n = en;

    expect(
      adapter.roomListController.getRoomById('self')?.effectiveDisplayName,
      en.selfChatTitle('Me'),
    );
  });

  test('the host keeps the language it assigned, ambient or not', () async {
    adapter.l10n = fr;
    adapter.adoptAmbientL10n(en);
    expect(adapter.l10n, same(fr));
  });

  test('a constructor bundle counts as the host taking control', () async {
    final pinned = ChatUiAdapter(
      client: client,
      currentUser: me,
      l10n: fr,
      manageAppLifecycle: false,
    );
    addTearDown(pinned.dispose);

    pinned.adoptAmbientL10n(en);

    expect(pinned.l10n, same(fr));
  });

  test('the ambient bundle reaches an adapter the host left alone', () async {
    adapter.roomListController.setRooms([
      RoomListItem(id: 'self', effectiveDisplayName: en.selfChatTitle('Me')),
    ]);

    adapter.adoptAmbientL10n(fr);

    expect(adapter.l10n, same(fr));
    expect(
      adapter.roomListController.getRoomById('self')?.effectiveDisplayName,
      fr.selfChatTitle('Me'),
    );
  });
}
