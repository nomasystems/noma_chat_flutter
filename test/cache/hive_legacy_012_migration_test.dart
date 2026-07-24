import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:noma_chat/noma_chat.dart';

/// Simulates a cache directory left behind by SDK 0.12.x and confirms
/// 0.13's `HiveChatDatasource` reads it back without crashing, without
/// losing data, and with sane defaults for every field 0.13 introduced.
///
/// The fixtures below write raw maps directly into the boxes via the
/// `hive_ce` API — bypassing `messageToMap`/`roomToMap` entirely — so
/// they reflect exactly what a real 0.12 install left on disk, not what
/// the current serializer happens to produce. `_schemaVersion` did not
/// change between 0.12.1 and 0.13.0 (still `2`), so this is the actual
/// upgrade path a user's device takes: no migration/wipe fires, and the
/// old rows are read as-is by the new deserializers.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_legacy_012_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('0.12 messages (no attachmentId, no clientMessageId) load with sane '
      'defaults and are usable by 0.13', () async {
    Hive.init(tempDir.path);
    final metaBox = await Hive.openBox<Map>('chat_meta');
    // 0.12.1's own on-disk schema version — no migration/wipe should
    // fire for this upgrade.
    await metaBox.put('schemaVersion', {'version': 2});
    await metaBox.close();

    final roomsBox = await Hive.openBox<Map>('chat_rooms');
    await roomsBox.put('room-legacy', {
      'id': 'room-legacy',
      'audience': 'contacts',
      'allowInvitations': false,
      'members': ['user-1', 'user-2'],
    });
    await roomsBox.close();

    final msgBox = await Hive.openBox<Map>('chat_messages_room-legacy');
    // Shape a 0.12 attachment message actually would have had: a
    // (possibly by-now-expired) attachmentUrl and no attachmentId key
    // at all — the field didn't exist yet.
    await msgBox.put('2026-01-01T00:00:00.000Z_msg-legacy-1', {
      'id': 'msg-legacy-1',
      'from': 'user-1',
      'timestamp': '2026-01-01T00:00:00.000Z',
      'messageType': 'attachment',
      'attachmentUrl': 'https://cdn.example.com/dead/expired-signed-url',
      'mimeType': 'image/jpeg',
    });
    // A plain text message, the common case.
    await msgBox.put('2026-01-01T00:01:00.000Z_msg-legacy-2', {
      'id': 'msg-legacy-2',
      'from': 'user-2',
      'timestamp': '2026-01-01T00:01:00.000Z',
      'text': 'hello from 0.12',
    });
    await msgBox.close();
    await Hive.close();

    final ds = await HiveChatDatasource.create(basePath: tempDir.path);

    final rooms = (await ds.getRooms()).dataOrNull!;
    expect(rooms, hasLength(1));
    expect(rooms.first.id, 'room-legacy');
    expect(rooms.first.members, ['user-1', 'user-2']);

    final messages = (await ds.getMessages('room-legacy')).dataOrNull!;
    expect(messages, hasLength(2));

    final attachment = messages.firstWhere((m) => m.id == 'msg-legacy-1');
    expect(attachment.messageType, MessageType.attachment);
    expect(
      attachment.attachmentUrl,
      'https://cdn.example.com/dead/expired-signed-url',
    );
    // The field 0.13 added: absent in the legacy row, must default to
    // null (not throw) so the UI's attachmentIdFromUrl fallback can
    // take over instead of crashing on a missing key.
    expect(attachment.attachmentId, isNull);
    expect(attachment.isEdited, isFalse);
    expect(attachment.silentlyDropped, isFalse);
    expect(attachment.receipt, isNull);

    final text = messages.firstWhere((m) => m.id == 'msg-legacy-2');
    expect(text.text, 'hello from 0.12');
    expect(text.messageType, MessageType.regular);

    await ds.dispose();
    await Hive.close();
  });

  test(
    '0.12 users/contacts/unreads without newer optional keys load cleanly',
    () async {
      Hive.init(tempDir.path);
      final metaBox = await Hive.openBox<Map>('chat_meta');
      await metaBox.put('schemaVersion', {'version': 2});
      await metaBox.close();

      final usersBox = await Hive.openBox<Map>('chat_users');
      await usersBox.put('user-legacy', {
        'id': 'user-legacy',
        'displayName': 'Legacy User',
        'role': 'user',
        'active': true,
        // no 'configuration' key — introduced after this hypothetical row.
      });
      await usersBox.close();

      final unreadsBox = await Hive.openBox<Map>('chat_unreads');
      await unreadsBox.put('room-legacy', {
        'roomId': 'room-legacy',
        'unreadMessages': 3,
        // no lastMessageReceipt / muteUntil / selfMuted keys.
      });
      await unreadsBox.close();
      await Hive.close();

      final ds = await HiveChatDatasource.create(basePath: tempDir.path);

      final user = (await ds.getUser('user-legacy')).dataOrNull;
      expect(user, isNotNull);
      expect(user!.displayName, 'Legacy User');
      expect(user.configuration, isNull);

      final unreads = (await ds.getUnreads()).dataOrNull!;
      expect(unreads, hasLength(1));
      expect(unreads.first.unreadMessages, 3);
      expect(unreads.first.lastMessageReceipt, isNull);
      expect(unreads.first.muteUntil, isNull);
      expect(unreads.first.selfMuted, isFalse);

      await ds.dispose();
      await Hive.close();
    },
  );

  test('a message saved fresh under 0.13 (with attachmentId) survives '
      'a simulated app restart on the same on-disk cache', () async {
    final ds = await HiveChatDatasource.create(basePath: tempDir.path);
    await ds.saveRooms([const ChatRoom(id: 'room-fresh')]);
    await ds.saveMessages('room-fresh', [
      ChatMessage(
        id: 'msg-fresh',
        from: 'user-1',
        timestamp: DateTime.utc(2026, 2, 1),
        messageType: MessageType.attachment,
        attachmentUrl: 'https://cdn.example.com/fresh/signed-url',
        attachmentId: 'att-fresh-1',
      ),
    ]);
    await ds.dispose();
    await Hive.close();

    final ds2 = await HiveChatDatasource.create(basePath: tempDir.path);
    final messages = (await ds2.getMessages('room-fresh')).dataOrNull!;
    expect(messages, hasLength(1));
    expect(messages.first.attachmentId, 'att-fresh-1');

    await ds2.dispose();
    await Hive.close();
  });
}
