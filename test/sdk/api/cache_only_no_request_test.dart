import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/src/_internal/cache/cache_manager.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class _MockRest extends Mock implements RestClient {}

class _MockCache extends Mock implements ChatLocalDatasource {}

/// One contract, checked on every sub-API that takes a `cachePolicy`:
/// [CachePolicy.cacheOnly] never puts a request on the wire. Wherever
/// there is no store to read — a client built without a cache, a layer
/// that has none, a shape the cached record cannot answer — the answer is
/// the same miss [CacheManager] gives for an empty store, and the HTTP
/// client is left untouched.
///
/// The miss matters as much as the silence: an empty success would claim
/// "this user has no contacts / this room has no reactions" off a store
/// that was never consulted.
void main() {
  late _MockRest rest;
  late _MockCache cache;
  late CacheManager cm;

  setUp(() {
    rest = _MockRest();
    cache = _MockCache();
    cm = CacheManager(config: const CacheConfig());

    when(
      () => rest.get(
        any(),
        queryParams: any(named: 'queryParams'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer((_) async => <String, dynamic>{});
    when(
      () =>
          rest.getWithTotalCount(any(), queryParams: any(named: 'queryParams')),
    ).thenAnswer((_) async => (<String, dynamic>{}, 0));
  });

  void expectNoRequest() {
    verifyNever(
      () => rest.get(
        any(),
        queryParams: any(named: 'queryParams'),
        headers: any(named: 'headers'),
      ),
    );
    verifyNever(
      () =>
          rest.getWithTotalCount(any(), queryParams: any(named: 'queryParams')),
    );
  }

  group('users.get', () {
    test('with no cache configured, cacheOnly is a miss and emits '
        'nothing', () async {
      final api = UsersApi(rest: rest);

      final result = await api.get('u1', cachePolicy: CachePolicy.cacheOnly);

      expect(result.isFailure, isTrue);
      expectNoRequest();
    });

    test('any other policy still fetches', () async {
      final api = UsersApi(rest: rest);

      await api.get('u1');

      verify(
        () => rest.get(
          '/users/u1',
          queryParams: any(named: 'queryParams'),
          headers: any(named: 'headers'),
        ),
      ).called(1);
    });
  });

  group('messages, REST layer', () {
    test('list under cacheOnly is a miss and emits nothing', () async {
      final api = RestMessagesApi(rest: rest);

      final result = await api.list(
        'r1',
        pagination: const ChatCursorPaginationParams(limit: 30),
        cachePolicy: CachePolicy.cacheOnly,
      );

      expect(result.isFailure, isTrue);
      expectNoRequest();
    });

    test('list without a policy still fetches', () async {
      final api = RestMessagesApi(rest: rest);

      await api.list('r1');

      verify(
        () => rest.getWithTotalCount(
          '/rooms/r1/messages',
          queryParams: any(named: 'queryParams'),
        ),
      ).called(1);
    });

    test('getReactions under cacheOnly is a miss and emits nothing', () async {
      final api = RestMessagesApi(rest: rest);

      final result = await api.getReactions(
        'r1',
        'm1',
        cachePolicy: CachePolicy.cacheOnly,
      );

      expect(result.isFailure, isTrue);
      expectNoRequest();
    });
  });

  group('messages, cached layer', () {
    late CachedMessagesApi api;

    setUp(() {
      when(
        () => cache.getClearedAt(any()),
      ).thenAnswer((_) async => const ChatSuccess(null));
      when(
        () => cache.getHiddenMessageIds(any()),
      ).thenAnswer((_) async => const ChatSuccess(<String>{}));
      when(
        () => cache.getReactions(any(), any()),
      ).thenAnswer((_) async => const ChatSuccess(<AggregatedReaction>[]));
      api = CachedMessagesApi(rest: rest, cache: cache, cacheManager: cm);
    });

    test('getReactions honours cacheOnly instead of the configured default '
        'read policy', () async {
      final result = await api.getReactions(
        'r1',
        'm1',
        cachePolicy: CachePolicy.cacheOnly,
      );

      expect(result.isFailure, isTrue);
      expectNoRequest();
    });

    test('a stored aggregate answers cacheOnly from disk', () async {
      when(() => cache.getReactions('r1', 'm1')).thenAnswer(
        (_) async => const ChatSuccess([
          AggregatedReaction(emoji: '👍', count: 1, users: ['bob']),
        ]),
      );

      final result = await api.getReactions(
        'r1',
        'm1',
        cachePolicy: CachePolicy.cacheOnly,
      );

      expect(result.dataOrThrow.single.emoji, '👍');
      expectNoRequest();
    });

    test('an explicit cacheOnly outranks a host that configured '
        'networkOnly as its default read policy', () async {
      when(() => cache.getReactions('r1', 'm1')).thenAnswer(
        (_) async => const ChatSuccess([
          AggregatedReaction(emoji: '👍', count: 1, users: ['bob']),
        ]),
      );
      final strict = CachedMessagesApi(
        rest: rest,
        cache: cache,
        cacheManager: CacheManager(
          config: const CacheConfig(
            defaultReadPolicy: CachePolicy.networkOnly,
          ),
        ),
      );

      final result = await strict.getReactions(
        'r1',
        'm1',
        cachePolicy: CachePolicy.cacheOnly,
      );

      expect(result.dataOrThrow.single.emoji, '👍');
      expectNoRequest();
    });
  });

  group('contacts.list', () {
    test('with no cache configured, cacheOnly is a miss and emits '
        'nothing', () async {
      final api = ContactsApi(rest: rest);

      final result = await api.list(cachePolicy: CachePolicy.cacheOnly);

      expect(result.isFailure, isTrue);
      expectNoRequest();
    });

    test('an empty store still answers cacheOnly with a miss, never an '
        'empty contact list', () async {
      when(
        () => cache.getContacts(),
      ).thenAnswer((_) async => const ChatSuccess(<ChatContact>[]));
      final api = ContactsApi(rest: rest, cache: cache, cacheManager: cm);

      final result = await api.list(cachePolicy: CachePolicy.cacheOnly);

      expect(result.isFailure, isTrue);
      expectNoRequest();
    });
  });
}
