import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// The temp id a send mints is the sole key of three registers at once —
/// the upload progress notifier, the upload cancel token, and the
/// optimistic row (`id`, `clientMessageId`, cached pending copy). Two sends
/// that mint the same string therefore do not merely look alike: they share
/// one notifier, one token and one row, and the second silently overwrites
/// the first.
///
/// A wall-clock reading cannot keep them apart. Every one of these sends
/// mints its id synchronously, before its first suspension point, so the
/// whole burst is minted inside a single event-loop turn — the exact case
/// where `DateTime.now().microsecondsSinceEpoch` is free to repeat.
///
/// Which is why there is one minter and not one counter per call site: text
/// sends, forwards and the two upload paths all draw from the same
/// `TempIdMinter`. Counters kept in step by hand are the same collision
/// again the day one of them is forgotten — and the text path, by far the
/// most travelled of the four, is the one that was.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  final bytes = Uint8List.fromList([1, 2, 3]);
  const burst = 200;

  late MockChatClient client;
  late ChatUiAdapter adapter;

  setUp(() {
    client = MockChatClient(currentUserId: 'me');
    client.seedRoom(
      const ChatRoom(id: 'r1', name: 'Room 1', members: ['me', 'u1']),
    );
    client.seedRoom(
      const ChatRoom(id: 'r2', name: 'Room 2', members: ['me', 'u2']),
    );
    adapter = ChatUiAdapter(client: client, currentUser: me);
    adapter.start();
  });

  tearDown(() async {
    await adapter.dispose();
    await client.dispose();
  });

  /// The per-send counter, read back off the id. Asserting on it — rather
  /// than only on set-uniqueness — is what makes this test independent of
  /// the host clock's resolution: with a timestamp-only id the trailing
  /// segment is a microsecond count, not `0, 1, 2, …`.
  List<int> countersOf(Iterable<String> ids) => [
    for (final id in ids) int.parse(id.split('_').last),
  ];

  test(
    'a burst of attachment sends minted in one turn cannot collide',
    () async {
      final results = await Future.wait([
        for (var i = 0; i < burst; i++)
          adapter.messages.sendAttachment(
            'r1',
            bytes: bytes,
            mimeType: 'image/png',
          ),
      ]);

      final ids = [
        for (final result in results) result.dataOrThrow.clientMessageId!,
      ];

      expect(ids.every((id) => id.startsWith('_pending_')), isTrue);
      expect(ids.toSet(), hasLength(burst));
      expect(countersOf(ids), List<int>.generate(burst, (i) => i));
    },
  );

  test('attachment and voice sends draw from the same counter, so the two '
      'entry points cannot collide with each other either', () async {
    final results = await Future.wait([
      for (var i = 0; i < burst; i++)
        i.isEven
            ? adapter.messages.sendAttachment(
                'r1',
                bytes: bytes,
                mimeType: 'image/png',
              )
            : adapter.messages.sendVoice(
                'r1',
                audioBytes: bytes,
                mimeType: 'audio/mp4',
                duration: const Duration(seconds: 1),
                waveform: const [1, 2, 3],
              ),
    ]);

    final ids = [
      for (final result in results) result.dataOrThrow.clientMessageId!,
    ];

    expect(ids.toSet(), hasLength(burst));
    expect(countersOf(ids), List<int>.generate(burst, (i) => i));
  });

  test('text sends draw from that same counter — the busiest path is not '
      'allowed its own', () async {
    // A plain text send is the one users fire hundreds of times an hour,
    // and it mints before its first `await` like every other. A counter of
    // its own (or none at all) puts it back on the raw wall clock.
    final results = await Future.wait([
      for (var i = 0; i < burst; i++)
        i.isEven
            ? adapter.messages.send('r1', text: 'hello $i')
            : adapter.messages.sendAttachment(
                'r1',
                bytes: bytes,
                mimeType: 'image/png',
              ),
    ]);

    final ids = [
      for (final result in results) result.dataOrThrow.clientMessageId!,
    ];

    expect(ids.every((id) => id.startsWith('_pending_')), isTrue);
    expect(ids.toSet(), hasLength(burst));
    expect(countersOf(ids), List<int>.generate(burst, (i) => i));
  });

  test('forwards draw from it too, so a fan-out cannot collide with the '
      'sends around it', () async {
    final sent = await adapter.messages.send('r1', text: 'before');
    final forwarded = await adapter.messages.forward(
      sourceRoomId: 'r1',
      messageId: 'm1',
      targetRoomIds: const ['r1', 'r2', 'r1'],
    );
    final after = await adapter.messages.send('r2', text: 'after');

    final ids = [
      sent.dataOrThrow.clientMessageId!,
      for (final result in forwarded) result.dataOrThrow.clientMessageId!,
      after.dataOrThrow.clientMessageId!,
    ];

    // Repeating a target is legitimate — forwarding the same message twice
    // into one room — and used to mint the same id twice, because the id
    // was keyed on the target instead of on a counter.
    expect(ids.toSet(), hasLength(ids.length));
    expect(countersOf(ids), List<int>.generate(ids.length, (i) => i));
  });

  test('colliding ids would collide in the registries, so distinct ids keep '
      'each in-flight upload its own progress notifier', () async {
    final controller = adapter.getChatController('r1');

    // Not awaited: both mint their temp id and register their notifier
    // before either suspends.
    final first = adapter.messages.sendAttachment(
      'r1',
      bytes: bytes,
      mimeType: 'image/png',
    );
    final second = adapter.messages.sendAttachment(
      'r1',
      bytes: bytes,
      mimeType: 'image/png',
    );

    final rows = controller.messages.map((m) => m.id).toList();
    expect(rows, hasLength(2));
    expect(rows.toSet(), hasLength(2));

    final progressA = adapter.attachmentUploadProgressFor(rows[0]);
    final progressB = adapter.attachmentUploadProgressFor(rows[1]);
    expect(progressA, isNotNull);
    expect(progressB, isNotNull);
    expect(identical(progressA, progressB), isFalse);

    final cancelA = adapter.attachmentUploadCancellableFor(rows[0]);
    final cancelB = adapter.attachmentUploadCancellableFor(rows[1]);
    expect(cancelA, isNotNull);
    expect(cancelB, isNotNull);
    expect(identical(cancelA, cancelB), isFalse);

    await Future.wait([first, second]);
  });
}
