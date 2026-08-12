import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/src/_internal/cache/cache_manager.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class _MockRest extends Mock implements RestClient {}

class _MockCache extends Mock implements ChatLocalDatasource {}

/// `RoomsApi.getUserRooms(cachePolicy: cacheOnly)` must keep "the cache
/// read back empty" apart from "the cache could not be read": only the
/// second is a miss. Without the split a brand-new install, an account
/// that deleted every chat and an unreadable store are the same
/// `ChatFailureResult` from outside, and no host can paint an honest
/// empty state.
void main() {
  late _MockRest rest;
  late _MockCache cache;
  late RoomsApi api;

  const unread = UnreadRoom(roomId: 'r1', unreadMessages: 2);
  const invitation = InvitedRoom(roomId: 'r9', invitedBy: 'bob');

  setUpAll(() {
    registerFallbackValue(<UnreadRoom>[]);
    registerFallbackValue(<InvitedRoom>[]);
  });

  setUp(() {
    rest = _MockRest();
    cache = _MockCache();
    api = RoomsApi(
      rest: rest,
      cache: cache,
      cacheManager: CacheManager(config: const CacheConfig()),
    );
    when(
      () => cache.getUnreads(),
    ).thenAnswer((_) async => const ChatSuccess(<UnreadRoom>[]));
    when(
      () => cache.getInvitedRooms(),
    ).thenAnswer((_) async => const ChatSuccess(<InvitedRoom>[]));
  });

  Future<ChatResult<UserRooms>> read({String type = 'all'}) =>
      api.getUserRooms(type: type, cachePolicy: CachePolicy.cacheOnly);

  test('a readable but empty cache resolves to an empty success, never a '
      'miss, and never touches the network', () async {
    final result = await read();

    expect(result.isSuccess, isTrue);
    expect(result.dataOrThrow.rooms, isEmpty);
    expect(result.dataOrThrow.invitedRooms, isEmpty);
    verifyNever(() => rest.get(any(), queryParams: any(named: 'queryParams')));
  });

  test('an unreadable unread box is a miss, so the caller can still tell '
      '"I cannot read your rooms" from "you have none"', () async {
    when(() => cache.getUnreads()).thenAnswer(
      (_) async => const ChatFailureResult(UnexpectedFailure('disk on fire')),
    );

    final result = await read();

    expect(result.isFailure, isTrue);
  });

  test('cached invitations are reachable with zero unread rooms', () async {
    when(
      () => cache.getInvitedRooms(),
    ).thenAnswer((_) async => const ChatSuccess([invitation]));

    final result = await read();

    expect(result.isSuccess, isTrue);
    expect(result.dataOrThrow.rooms, isEmpty);
    expect(result.dataOrThrow.invitedRooms, [invitation]);
  });

  test('an unreadable invitation box degrades to "no invitations" while '
      'there are rooms to paint', () async {
    when(
      () => cache.getUnreads(),
    ).thenAnswer((_) async => const ChatSuccess([unread]));
    when(() => cache.getInvitedRooms()).thenAnswer(
      (_) async => const ChatFailureResult(UnexpectedFailure('disk on fire')),
    );

    final result = await read();

    expect(result.isSuccess, isTrue);
    expect(result.dataOrThrow.rooms, [unread]);
    expect(result.dataOrThrow.invitedRooms, isEmpty);
  });

  test(
    'an unreadable invitation box with zero rooms is a miss — claiming '
    '"you have nothing" off a box we failed to read would be a lie',
    () async {
      when(() => cache.getInvitedRooms()).thenAnswer(
        (_) async => const ChatFailureResult(UnexpectedFailure('disk on fire')),
      );

      final result = await read();

      expect(result.isFailure, isTrue);
    },
  );

  group('a client built with no cache at all', () {
    late RoomsApi bare;

    setUp(() => bare = RoomsApi(rest: rest));

    test('answers a cacheOnly listing with a miss instead of a GET '
        '/rooms', () async {
      final result = await bare.getUserRooms(
        cachePolicy: CachePolicy.cacheOnly,
      );

      expect(result.isFailure, isTrue);
      verifyNever(
        () => rest.get(any(), queryParams: any(named: 'queryParams')),
      );
    });

    test('answers a cacheOnly room detail with a miss instead of a GET '
        '/rooms/{id} — the hydration pass makes one call per room', () async {
      final result = await bare.get('r1', cachePolicy: CachePolicy.cacheOnly);

      expect(result.isFailure, isTrue);
      verifyNever(
        () => rest.get(any(), queryParams: any(named: 'queryParams')),
      );
    });

    test('still reaches the network when no policy forbids it', () async {
      when(
        () => rest.get(any(), queryParams: any(named: 'queryParams')),
      ).thenAnswer((_) async => {'rooms': [], 'invitedRooms': []});

      final result = await bare.getUserRooms();

      expect(result.isSuccess, isTrue);
      verify(
        () => rest.get(any(), queryParams: any(named: 'queryParams')),
      ).called(1);
    });
  });

  test('a full cache with nothing left unread is an empty success for the '
      '"unread" view, not a miss', () async {
    when(() => cache.getUnreads()).thenAnswer(
      (_) async =>
          const ChatSuccess([UnreadRoom(roomId: 'r1', unreadMessages: 0)]),
    );

    final result = await read(type: 'unread');

    expect(result.isSuccess, isTrue);
    expect(result.dataOrThrow.rooms, isEmpty);
  });
}
