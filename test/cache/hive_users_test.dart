import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  late HiveChatDatasource ds;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    ds = await HiveChatDatasource.create(basePath: tempDir.path);
  });

  tearDown(() async {
    await ds.dispose();
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('users', () {
    const user1 = ChatUser(
      id: 'user-1',
      displayName: 'Alice',
      avatarUrl: 'https://example.com/alice.png',
      role: UserRole.admin,
    );

    test('save and get user', () async {
      await ds.saveUsers([user1]);
      final user = (await ds.getUser('user-1')).dataOrNull;
      expect(user, isNotNull);
      expect(user!.displayName, 'Alice');
      expect(user.role, UserRole.admin);
      expect(user.avatarUrl, 'https://example.com/alice.png');
    });

    test('get all users', () async {
      await ds.saveUsers([
        const ChatUser(id: 'u-1', displayName: 'Alice'),
        const ChatUser(id: 'u-2', displayName: 'Bob'),
      ]);
      final users = (await ds.getUsers()).dataOrNull!;
      expect(users.length, 2);
      final ids = users.map((u) => u.id).toSet();
      expect(ids, containsAll(['u-1', 'u-2']));
    });

    test('getUsers returns empty before save', () async {
      expect((await ds.getUsers()).dataOrNull, isEmpty);
    });

    test('get nonexistent user returns null', () async {
      expect((await ds.getUser('nonexistent')).dataOrNull, isNull);
    });

    test('delete user', () async {
      await ds.saveUsers([user1]);
      await ds.deleteUser('user-1');
      expect((await ds.getUser('user-1')).dataOrNull, isNull);
    });

    test('preserves UserConfiguration with webhook', () async {
      const user = ChatUser(
        id: 'user-cfg',
        displayName: 'Bob',
        configuration: UserConfiguration(
          metadata: {'tier': 'premium'},
          webhook: WebhookConfig(
            url: 'https://hook.example.com/cb',
            authType: WebhookAuthType.basic,
            username: 'admin',
            password: 'secret',
          ),
        ),
      );
      await ds.saveUsers([user]);
      final loaded = (await ds.getUser('user-cfg')).dataOrNull;
      expect(loaded, isNotNull);
      expect(loaded!.configuration, isNotNull);
      expect(loaded.configuration!.metadata, {'tier': 'premium'});
      expect(loaded.configuration!.webhook, isNotNull);
      expect(loaded.configuration!.webhook!.url, 'https://hook.example.com/cb');
      expect(loaded.configuration!.webhook!.authType, WebhookAuthType.basic);
      expect(loaded.configuration!.webhook!.username, 'admin');
      expect(loaded.configuration!.webhook!.password, 'secret');
    });

    test('preserves UserConfiguration with bearer token', () async {
      const user = ChatUser(
        id: 'user-bearer',
        configuration: UserConfiguration(
          webhook: WebhookConfig(
            url: 'https://hook.example.com/bearer',
            authType: WebhookAuthType.bearer,
            token: 'my-token-123',
          ),
        ),
      );
      await ds.saveUsers([user]);
      final loaded = (await ds.getUser('user-bearer')).dataOrNull;
      expect(loaded!.configuration!.webhook!.authType, WebhookAuthType.bearer);
      expect(loaded.configuration!.webhook!.token, 'my-token-123');
    });

    test('preserves UserConfiguration with only metadata', () async {
      const user = ChatUser(
        id: 'user-meta',
        configuration: UserConfiguration(metadata: {'key': 'value'}),
      );
      await ds.saveUsers([user]);
      final loaded = (await ds.getUser('user-meta')).dataOrNull;
      expect(loaded!.configuration, isNotNull);
      expect(loaded.configuration!.metadata, {'key': 'value'});
      expect(loaded.configuration!.webhook, isNull);
    });

    test('user without configuration stays null', () async {
      await ds.saveUsers([user1]);
      final loaded = (await ds.getUser('user-1')).dataOrNull;
      expect(loaded!.configuration, isNull);
    });
  });

  group('contacts', () {
    test('save and get contacts', () async {
      await ds.saveContacts([
        const ChatContact(userId: 'c-1'),
        const ChatContact(userId: 'c-2'),
      ]);
      final contacts = (await ds.getContacts()).dataOrNull!;
      expect(contacts.length, 2);
      expect(contacts.first.userId, 'c-1');
    });

    test('getContacts returns empty before save', () async {
      expect((await ds.getContacts()).dataOrNull, isEmpty);
    });

    test('saveContacts replaces previous list', () async {
      await ds.saveContacts([const ChatContact(userId: 'c-1')]);
      await ds.saveContacts([const ChatContact(userId: 'c-2')]);
      final contacts = (await ds.getContacts()).dataOrNull!;
      expect(contacts.length, 1);
      expect(contacts.first.userId, 'c-2');
    });
  });
}
