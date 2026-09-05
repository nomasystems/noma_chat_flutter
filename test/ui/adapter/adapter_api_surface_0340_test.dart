import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// The 0.34 surface a host writes against: the directory hook, the
/// bootstrap switch, the send-retry policy, the read-only notice, and the
/// write policy a room's config carries.
///
/// What is pinned here is the *contract* — what a host gets when it says
/// nothing, what survives when it does say something, and how the wire
/// values decode. Not the machinery behind it, which lands piece by piece.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient client;

  setUp(() {
    client = MockChatClient(currentUserId: me.id);
  });

  tearDown(() async {
    await client.dispose();
  });

  ChatUiAdapter adapterWith({
    UserDirectoryResolver? userDirectoryResolver,
    Duration? userDirectoryTtl,
    bool? bootstrapCurrentUser,
    SendRetryPolicy? sendRetryPolicy,
  }) {
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: me,
      manageAppLifecycle: false,
      userDirectoryResolver: userDirectoryResolver,
      userDirectoryTtl: userDirectoryTtl ?? const Duration(hours: 12),
      bootstrapCurrentUser: bootstrapCurrentUser ?? false,
      sendRetryPolicy: sendRetryPolicy ?? const SendRetryPolicy.firstSendOnly(),
    );
    addTearDown(adapter.dispose);
    return adapter;
  }

  group('ChatUiAdapter defaults', () {
    test('a host that says nothing keeps asking chat and nobody else', () {
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: me,
        manageAppLifecycle: false,
      );
      addTearDown(adapter.dispose);

      expect(adapter.userDirectoryResolver, isNull);
      expect(adapter.bootstrapCurrentUser, isFalse);
      expect(
        adapter.userDirectoryTtl,
        const Duration(hours: 12),
        reason: 'a name is good for an afternoon, not for a round trip',
      );
      expect(adapter.sendRetryPolicy, const SendRetryPolicy.firstSendOnly());
    });

    test('what the host passes is what the adapter holds', () async {
      Future<Map<String, HostUser>> resolver(Set<String> ids) async =>
          const <String, HostUser>{};
      final adapter = adapterWith(
        userDirectoryResolver: resolver,
        userDirectoryTtl: const Duration(minutes: 5),
        bootstrapCurrentUser: true,
        sendRetryPolicy: const SendRetryPolicy.none(),
      );

      expect(adapter.userDirectoryResolver, same(resolver));
      expect(adapter.userDirectoryTtl, const Duration(minutes: 5));
      expect(adapter.bootstrapCurrentUser, isTrue);
      expect(adapter.sendRetryPolicy, const SendRetryPolicy.none());
    });
  });

  group('HostUser', () {
    test('an id nobody is behind answers, instead of staying silent', () {
      const answer = HostUser.missing('u404');

      expect(answer.id, 'u404');
      expect(answer.gone, isTrue);
      expect(answer.displayName, isNull);
      expect(answer.hasDisplayName, isFalse);
    });

    test('a name made of spaces is not a name', () {
      const blank = HostUser(id: 'u1', displayName: '   ');

      expect(blank.hasDisplayName, isFalse);
      expect(const HostUser(id: 'u1', displayName: 'Ana').hasDisplayName, true);
    });

    test('two answers about the same person are the same value', () {
      const a = HostUser(id: 'u1', displayName: 'Ana', avatarUrl: 'https://a');
      const b = HostUser(id: 'u1', displayName: 'Ana', avatarUrl: 'https://a');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.copyWith(gone: true), isNot(a));
      expect(a.copyWith(displayName: 'Ana B').displayName, 'Ana B');
    });
  });

  group('SendRetryPolicy', () {
    test('the default backs off three times and then stops', () {
      const policy = SendRetryPolicy.firstSendOnly();

      expect(policy.mode, SendRetryMode.firstSendOnly);
      expect(policy.delays, SendRetryPolicy.defaultDelays);
      expect(policy.maxAttempts, 3);
      expect(policy.delayFor(0), const Duration(milliseconds: 400));
      expect(policy.delayFor(2), const Duration(milliseconds: 1500));
      expect(policy.delayFor(3), isNull);
      expect(policy.delayFor(-1), isNull);
    });

    test('none never retries', () {
      const policy = SendRetryPolicy.none();

      expect(policy.mode, SendRetryMode.none);
      expect(policy.maxAttempts, 0);
      expect(policy.delays, isEmpty);
      expect(policy.delayFor(0), isNull);
    });

    test('a host can pick its own backoff', () {
      const policy = SendRetryPolicy.firstSendOnly(
        delays: [Duration(milliseconds: 50)],
      );

      expect(policy.maxAttempts, 1);
      expect(policy.delayFor(0), const Duration(milliseconds: 50));
      expect(policy, isNot(const SendRetryPolicy.firstSendOnly()));
      expect(
        policy,
        const SendRetryPolicy.firstSendOnly(
          delays: [Duration(milliseconds: 50)],
        ),
      );
    });
  });

  group('RoomWritePolicy on the wire', () {
    test('only the exact owner-only value closes a room', () {
      expect(
        RoomWritePolicyWire.fromWire('owner_only'),
        RoomWritePolicy.ownerOnly,
      );
      expect(RoomWritePolicy.ownerOnly.wireValue, 'owner_only');
      expect(RoomWritePolicy.members.wireValue, 'members');
    });

    test('anything the SDK does not know fails open', () {
      for (final raw in <Object?>[
        null,
        'members',
        'moderators',
        'OWNER_ONLY',
        'ownerOnly',
        42,
        <String, dynamic>{},
      ]) {
        expect(
          RoomWritePolicyWire.fromWire(raw),
          RoomWritePolicy.members,
          reason: 'a room nobody can write to is worse than a missed policy',
        );
      }
    });
  });

  group('ChatViewBuilders', () {
    test('the read-only notice is the SDK default until a host says so', () {
      expect(const ChatViewBuilders().readOnlyNoticeBuilder, isNull);
    });

    testWidgets('NomaChatView hands the read-only notice down to ChatView', (
      tester,
    ) async {
      final adapter = adapterWith();
      adapter.roomListController.addRoom(const RoomListItem(id: 'r1'));
      Widget? notice(BuildContext context, ReadOnlyReason reason) =>
          const SizedBox.shrink();

      await tester.pumpWidget(
        MaterialApp(
          home: NomaChatView(
            roomId: 'r1',
            adapter: adapter,
            hydrateGroupMembers: false,
            builders: ChatViewBuilders(readOnlyNoticeBuilder: notice),
          ),
        ),
      );
      await tester.pump();

      final view = tester.widget<ChatView>(find.byType(ChatView));
      expect(view.builders.readOnlyNoticeBuilder, same(notice));
    });

    testWidgets('the delivery-tick override is not dropped on the way down', (
      tester,
    ) async {
      // `ChatView` reads `builders.statusIconBuilder`, but `NomaChatView`
      // rebuilds the whole `ChatViewBuilders` before handing it over and
      // used to forget this one field: a host that redrew its ticks got the
      // SDK's back and no error anywhere.
      final adapter = adapterWith();
      adapter.roomListController.addRoom(const RoomListItem(id: 'r1'));
      Widget? tick(BuildContext context, MessageStatusIconData data) =>
          const SizedBox.shrink();

      await tester.pumpWidget(
        MaterialApp(
          home: NomaChatView(
            roomId: 'r1',
            adapter: adapter,
            hydrateGroupMembers: false,
            builders: ChatViewBuilders(statusIconBuilder: tick),
          ),
        ),
      );
      await tester.pump();

      final view = tester.widget<ChatView>(find.byType(ChatView));
      expect(view.builders.statusIconBuilder, same(tick));
    });
  });

  group('the image shrinker hook', () {
    test('is inert until the host supplies an engine', () async {
      final adapter = adapterWith();

      expect(adapter.attachmentShrinker, isA<NoAttachmentShrinker>());
      expect(
        await adapter.attachmentShrinker.fit(
          Uint8List.fromList(const [1, 2, 3]),
          mimeType: 'image/png',
          maxBytes: 1,
          fileName: 'shot.png',
        ),
        isNull,
        reason: 'the default sends the bytes the user picked, untouched',
      );
    });

    test('is the host engine once one is supplied', () async {
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: me,
        manageAppLifecycle: false,
        attachmentShrinker: _TruncatingShrinker(),
      );
      addTearDown(adapter.dispose);

      final shrunk = await adapter.attachmentShrinker.fit(
        Uint8List.fromList(List<int>.filled(8, 7)),
        mimeType: 'image/heic',
        maxBytes: 4,
        fileName: 'shot.heic',
      );

      expect(shrunk, isNotNull);
      expect(shrunk!.bytes, hasLength(4));
      expect(
        shrunk.mimeType,
        'image/jpeg',
        reason: 're-encoding changes the type the blob must be stored under',
      );
      expect(shrunk.fileName, 'shot.jpg');
    });
  });
}

/// Stand-in for the real encoder: cuts the payload down to the cap and
/// renames it, which is all the surface under test has to carry.
class _TruncatingShrinker implements AttachmentShrinker {
  @override
  Future<ShrunkAttachment?> fit(
    Uint8List bytes, {
    required String mimeType,
    required int maxBytes,
    required String fileName,
  }) async {
    if (bytes.length <= maxBytes) return null;
    return ShrunkAttachment(
      bytes: Uint8List.fromList(bytes.sublist(0, maxBytes)),
      mimeType: 'image/jpeg',
      fileName: '${fileName.split('.').first}.jpg',
    );
  }
}
