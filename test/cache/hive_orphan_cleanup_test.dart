import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/src/_internal/cache/cache_manager.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class _MockRestClient extends Mock implements RestClient {}

/// Covers the reclamation of per-room boxes whose room is gone.
///
/// The invariant under test is one-directional: a box a live room still
/// needs must never be destroyed, while a box no room needs may be
/// destroyed late. Every test here is written from that asymmetry —
/// "survives" cases assert exact contents, "reclaimed" cases only assert
/// that reclamation eventually happens.
///
/// The whole suite runs twice, once per cache layout: the legacy
/// device-wide store, and the per-user store, where every box name is
/// namespaced and the unscoped-cache adoption runs ahead of the sweep
/// inside `create()`.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_orphan_');
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  ChatMessage message(String id) => ChatMessage(
    id: id,
    from: 'user-1',
    timestamp: DateTime.utc(2026),
    text: id,
  );

  // The scoped id carries punctuation and case on purpose: it is the
  // shape a host really passes, and it does not survive being spelled
  // into a box name.
  for (final scopeUserId in const <String?>[null, 'User.7@example.com']) {
    final layout = scopeUserId == null ? 'device-wide store' : 'per-user store';

    /// The on-disk name of a logical box under the layout being
    /// exercised. Asked of the datasource rather than spelled out here:
    /// a scoped name embeds a digest of the user id, and a test that
    /// guessed it wrong would assert on a file that never existed and
    /// pass for the wrong reason.
    String physical(String boxName) =>
        HiveChatDatasource.physicalBoxName(boxName, userId: scopeUserId);

    Future<HiveChatDatasource> open({Duration grace = Duration.zero}) =>
        HiveChatDatasource.create(
          basePath: tempDir.path,
          userId: scopeUserId,
          orphanGracePeriod: grace,
        );

    Future<HiveChatDatasource> restart(
      HiveChatDatasource ds, {
      Duration grace = Duration.zero,
    }) async {
      await ds.dispose();
      await Hive.close();
      return open(grace: grace);
    }

    /// One authoritative listing naming a single room this device does
    /// not track. It is the weakest response that still counts as
    /// evidence: it proves the account has rooms, so a tracked room it
    /// omits was really omitted rather than merely unmentioned.
    /// `room-elsewhere` never gets a message box, so it is never a
    /// candidate itself.
    Future<void> listingWithoutTrackedRooms(HiveChatDatasource ds) =>
        ds.reconcileUnreads([
          const UnreadRoom(roomId: 'room-elsewhere', unreadMessages: 0),
        ]);

    group('$layout — rooms the cache can still prove exist', () {
      test('a room known only through chat_unreads survives a cold start '
          'and repeated authoritative listings', () async {
        var ds = await open();
        // Loading the room LIST never writes chat_rooms — it writes
        // chat_unreads. This is the shape of every install that joined its
        // rooms instead of creating them locally.
        await ds.reconcileUnreads([
          const UnreadRoom(roomId: 'room-joined', unreadMessages: 0),
        ]);
        await ds.saveMessages('room-joined', [message('msg-1')]);
        await ds.reconcileUnreads([
          const UnreadRoom(roomId: 'room-joined', unreadMessages: 0),
        ]);

        expect((await ds.getRooms()).dataOrNull, isEmpty);

        ds = await restart(ds);
        expect((await ds.getMessages('room-joined')).dataOrNull, hasLength(1));

        ds = await restart(ds);
        expect((await ds.getMessages('room-joined')).dataOrNull, hasLength(1));
        await ds.dispose();
      });

      test('a room known only through an invitation survives', () async {
        var ds = await open();
        await ds.saveInvitedRooms([
          const InvitedRoom(roomId: 'room-invited', invitedBy: 'user-2'),
        ]);
        await ds.saveMessages('room-invited', [message('msg-1')]);
        await listingWithoutTrackedRooms(ds);
        await listingWithoutTrackedRooms(ds);

        ds = await restart(ds);
        expect((await ds.getMessages('room-invited')).dataOrNull, hasLength(1));
        await ds.dispose();
      });

      test('a room known only through its detail survives', () async {
        var ds = await open();
        await ds.saveRoomDetail(
          const RoomDetail(
            id: 'room-detail',
            type: RoomType.group,
            memberCount: 2,
            userRole: RoomRole.member,
            config: RoomConfig(),
          ),
        );
        await ds.saveMessages('room-detail', [message('msg-1')]);
        await listingWithoutTrackedRooms(ds);
        await listingWithoutTrackedRooms(ds);

        ds = await restart(ds);
        expect((await ds.getMessages('room-detail')).dataOrNull, hasLength(1));
        await ds.dispose();
      });

      test('a kicked room keeps its read-only history', () async {
        var ds = await open();
        await ds.saveMessages('room-kicked', [message('msg-1')]);
        await ds.markKicked('room-kicked');
        await listingWithoutTrackedRooms(ds);
        await listingWithoutTrackedRooms(ds);

        ds = await restart(ds);
        expect((await ds.getMessages('room-kicked')).dataOrNull, hasLength(1));
        await ds.dispose();
      });
    });

    group('$layout — listings that prove nothing', () {
      test(
        'an empty listing never nominates, however often it repeats',
        () async {
          // A user with no rooms is a 200 with `rooms: []` — and so is a
          // token that resolved to another subject, a tenant switch, or a
          // staging backend answering for somebody else. None of them has
          // seen this device's rooms, so none of them may condemn one.
          var ds = await open();
          await ds.saveMessages('room-gone', [message('msg-1')]);
          await ds.reconcileUnreads([]);
          await ds.reconcileUnreads([]);
          await ds.reconcileUnreads([]);

          ds = await restart(ds);
          expect((await ds.getMessages('room-gone')).dataOrNull, hasLength(1));
          await ds.dispose();
        },
      );

      test(
        'an empty listing does not advance a nomination already made',
        () async {
          var ds = await open();
          await ds.saveMessages('room-gone', [message('msg-1')]);
          // One real confirmation, then two empty listings that must not
          // count as the second one.
          await listingWithoutTrackedRooms(ds);
          await ds.reconcileUnreads([]);
          await ds.reconcileUnreads([]);

          ds = await restart(ds);
          expect((await ds.getMessages('room-gone')).dataOrNull, hasLength(1));
          await ds.dispose();
        },
      );

      test(
        'unsent messages survive a sweep with no evidence behind it',
        () async {
          // The outbox is the one thing reclamation destroys that no server
          // can hand back.
          var ds = await open();
          await ds.saveMessages('room-gone', [message('msg-1')]);
          await ds.savePendingMessage('room-gone', message('msg-unsent'));
          await ds.reconcileUnreads([]);
          await ds.reconcileUnreads([]);

          ds = await restart(ds);
          final pending = (await ds.getPendingMessages('room-gone')).dataOrNull;
          expect(pending, hasLength(1));
          expect(pending!.single.message.id, 'msg-unsent');
          expect((await ds.getMessages('room-gone')).dataOrNull, hasLength(1));
          await ds.dispose();
        },
      );
    });

    group('$layout — rooms the server has proven are gone', () {
      test(
        'are reclaimed once confirmed twice and past the grace period',
        () async {
          var ds = await open();
          await ds.saveMessages('room-gone', [message('msg-1')]);
          await ds.saveMessages('room-live', [message('msg-2')]);

          await ds.reconcileUnreads([
            const UnreadRoom(roomId: 'room-live', unreadMessages: 0),
          ]);
          await ds.reconcileUnreads([
            const UnreadRoom(roomId: 'room-live', unreadMessages: 0),
          ]);

          ds = await restart(ds);
          expect((await ds.getMessages('room-gone')).dataOrNull, isEmpty);
          expect((await ds.getMessages('room-live')).dataOrNull, hasLength(1));
          await ds.dispose();
        },
      );

      test('a single authoritative listing is not enough', () async {
        var ds = await open();
        await ds.saveMessages('room-gone', [message('msg-1')]);
        await listingWithoutTrackedRooms(ds);

        ds = await restart(ds);
        expect((await ds.getMessages('room-gone')).dataOrNull, hasLength(1));
        await ds.dispose();
      });

      test(
        'the grace period holds a confirmed room until it elapses',
        () async {
          var ds = await open(grace: const Duration(days: 7));
          await ds.saveMessages('room-gone', [message('msg-1')]);
          await listingWithoutTrackedRooms(ds);
          await listingWithoutTrackedRooms(ds);

          ds = await restart(ds, grace: const Duration(days: 7));
          expect((await ds.getMessages('room-gone')).dataOrNull, hasLength(1));

          // Same on-disk candidate, a build that no longer waits: the
          // pending nomination is honoured rather than restarted.
          ds = await restart(ds);
          expect((await ds.getMessages('room-gone')).dataOrNull, isEmpty);
          await ds.dispose();
        },
      );

      test(
        'a room that comes back before the sweep loses its candidacy',
        () async {
          var ds = await open();
          await ds.saveMessages('room-flaky', [message('msg-1')]);
          await listingWithoutTrackedRooms(ds);
          await listingWithoutTrackedRooms(ds);
          await ds.reconcileUnreads([
            const UnreadRoom(roomId: 'room-flaky', unreadMessages: 1),
          ]);

          ds = await restart(ds);
          expect((await ds.getMessages('room-flaky')).dataOrNull, hasLength(1));
          await ds.dispose();
        },
      );

      test('reclamation removes the pending and reaction boxes too', () async {
        const boxes = [
          'chat_messages_room-gone',
          'chat_pending_room-gone',
          'chat_reactions_room-gone',
        ];
        var ds = await open();
        await ds.saveMessages('room-gone', [message('msg-1')]);
        await ds.savePendingMessage('room-gone', message('msg-pending'));
        await ds.saveReactions('room-gone', 'msg-1', [
          const AggregatedReaction(emoji: '👍', count: 1, users: ['user-2']),
        ]);
        await listingWithoutTrackedRooms(ds);
        await listingWithoutTrackedRooms(ds);
        await ds.dispose();
        await Hive.close();

        // Named before the sweep as well as after: an absence assertion
        // on a path that never held a file passes for the wrong reason.
        for (final name in boxes) {
          expect(
            File('${tempDir.path}/${physical(name)}.hive').existsSync(),
            isTrue,
            reason: '${physical(name)} should exist before the sweep',
          );
        }

        // Asserted on disk and before any read: a getX() call would reopen
        // the very box under test and recreate its file.
        ds = await open();
        await ds.dispose();
        await Hive.close();

        for (final name in boxes) {
          expect(
            File('${tempDir.path}/${physical(name)}.hive').existsSync(),
            isFalse,
            reason: '${physical(name)} should have been deleted from disk',
          );
        }
      });
    });

    group('$layout — the listing that reaches the cache', () {
      late _MockRestClient rest;

      setUp(() {
        rest = _MockRestClient();
      });

      RoomsApi apiOver(HiveChatDatasource ds) => RoomsApi(
        rest: rest,
        cache: ds,
        cacheManager: CacheManager(config: const CacheConfig()),
      );

      void answerWith({required bool hasMore}) {
        when(
          () => rest.get('/rooms', queryParams: any(named: 'queryParams')),
        ).thenAnswer(
          (_) async => {
            'rooms': [
              {'roomId': 'room-elsewhere', 'unreadMessages': 0},
            ],
            'invitedRooms': <Map<String, dynamic>>[],
            'hasMore': hasMore,
          },
        );
      }

      test('a truncated page never nominates', () async {
        // Same request, same 200, but the body is one page of an unknown
        // number: the rooms it omits may simply be on the pages nobody
        // asked for.
        answerWith(hasMore: true);
        var ds = await open();
        await ds.saveMessages('room-gone', [message('msg-1')]);
        final api = apiOver(ds);
        await api.getUserRooms(cachePolicy: CachePolicy.networkOnly);
        await api.getUserRooms(cachePolicy: CachePolicy.networkOnly);

        ds = await restart(ds);
        expect((await ds.getMessages('room-gone')).dataOrNull, hasLength(1));
        await ds.dispose();
      });

      test('a complete page still nominates', () async {
        answerWith(hasMore: false);
        var ds = await open();
        await ds.saveMessages('room-gone', [message('msg-1')]);
        final api = apiOver(ds);
        await api.getUserRooms(cachePolicy: CachePolicy.networkOnly);
        await api.getUserRooms(cachePolicy: CachePolicy.networkOnly);

        ds = await restart(ds);
        expect((await ds.getMessages('room-gone')).dataOrNull, isEmpty);
        await ds.dispose();
      });
    });

    group('$layout — defensive reads on the create() path', () {
      test('a corrupted kickedRoomIds entry does not crash startup', () async {
        final ds = await open();
        await ds.saveMessages('room-1', [message('msg-1')]);
        await ds.dispose();
        await Hive.close();

        Hive.init(tempDir.path);
        final metaBox = await Hive.openBox<Map>(physical('chat_meta'));
        // The store just written, not a fresh box under a name this test
        // guessed: corrupting the wrong one proves nothing.
        expect(metaBox.get('messageRoomIds'), isNotNull);
        // A list holding a non-String element: a lazy `cast<String>()`
        // survives the read and throws mid-iteration inside the sweep.
        await metaBox.put('kickedRoomIds', {
          'ids': ['room-1', 42],
        });
        await metaBox.close();
        await Hive.close();

        final ds2 = await open();
        expect((await ds2.getMessages('room-1')).dataOrNull, hasLength(1));
        await ds2.dispose();
      });

      test('a non-String key in chat_rooms does not crash the sweep', () async {
        final ds = await open();
        await ds.saveMessages('room-1', [message('msg-1')]);
        await listingWithoutTrackedRooms(ds);
        await listingWithoutTrackedRooms(ds);
        await ds.dispose();
        await Hive.close();

        // Same caveat as above: this must be the box `_openCoreBoxes`
        // already created for the store under test.
        expect(
          File('${tempDir.path}/${physical('chat_rooms')}.hive').existsSync(),
          isTrue,
        );
        Hive.init(tempDir.path);
        final roomsBox = await Hive.openBox<Map>(physical('chat_rooms'));
        await roomsBox.put(7, {'id': 'bogus'});
        await roomsBox.close();
        await Hive.close();

        final ds2 = await open();
        expect((await ds2.getMessages('room-1')).dataOrNull, isEmpty);
        await ds2.dispose();
      });
    });

    group('$layout — clear()', () {
      test('removes pending and reaction boxes of rooms never opened this '
          'session', () async {
        var ds = await open();
        await ds.saveMessages('room-1', [message('msg-1')]);
        await ds.savePendingMessage('room-1', message('msg-pending'));
        await ds.saveReactions('room-1', 'msg-1', [
          const AggregatedReaction(emoji: '👍', count: 1, users: ['user-2']),
        ]);

        const boxes = [
          'chat_messages_room-1',
          'chat_pending_room-1',
          'chat_reactions_room-1',
        ];
        ds = await restart(ds);
        for (final name in boxes) {
          expect(
            File('${tempDir.path}/${physical(name)}.hive').existsSync(),
            isTrue,
            reason: '${physical(name)} should exist before clear()',
          );
        }

        // Nothing has touched room-1 in this session, so its boxes are
        // untracked and only a disk-level delete reaches them.
        await ds.clear();
        await ds.dispose();
        await Hive.close();

        for (final name in boxes) {
          expect(
            File('${tempDir.path}/${physical(name)}.hive').existsSync(),
            isFalse,
            reason: '${physical(name)} should have been deleted from disk',
          );
        }
      });
    });

    if (scopeUserId != null) {
      group('$layout — adoption then sweep, on one launch', () {
        test('a room adopted from the device-wide store is not swept as an '
            'orphan', () async {
          // The adoption runs before the sweep inside create(), so the
          // very first launch of a scoped store sees rooms it has never
          // listed, tracked by a meta box that arrived seconds earlier.
          final legacy = await HiveChatDatasource.create(
            basePath: tempDir.path,
            orphanGracePeriod: Duration.zero,
          );
          await legacy.saveMessages('room-adopted', [message('msg-1')]);
          await legacy.savePendingMessage('room-adopted', message('msg-out'));
          await legacy.dispose();
          await Hive.close();

          final ds = await HiveChatDatasource.create(
            basePath: tempDir.path,
            userId: scopeUserId,
            adoptUnscopedCacheFor: scopeUserId,
            orphanGracePeriod: Duration.zero,
          );
          expect(
            (await ds.getMessages('room-adopted')).dataOrNull,
            hasLength(1),
          );
          final pending = (await ds.getPendingMessages(
            'room-adopted',
          )).dataOrNull;
          expect(pending, hasLength(1));
          expect(pending!.single.message.id, 'msg-out');
          await ds.dispose();
        });
      });
    }
  }
}
