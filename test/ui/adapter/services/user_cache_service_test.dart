import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/ui/adapter/services/user_cache_service.dart';

class _MockUsersApi extends Mock implements ChatUsersApi {}

void main() {
  group('UserCacheService', () {
    late _MockUsersApi api;

    setUp(() => api = _MockUsersApi());

    UserCacheService make({bool isDisposed = false}) =>
        UserCacheService(api: api, isDisposed: () => isDisposed);

    test('find returns null when not cached', () {
      expect(make().find('u1'), isNull);
    });

    test('insert + find round-trip', () {
      final s = make();
      const u = ChatUser(id: 'u1', displayName: 'Alice');
      final prev = s.insert(u);
      expect(prev, isNull);
      expect(s.find('u1'), u);
      expect(s.contains('u1'), isTrue);
    });

    test('insert returns previous value on update', () {
      final s = make();
      const v1 = ChatUser(id: 'u1', displayName: 'Old');
      const v2 = ChatUser(id: 'u1', displayName: 'New');
      s.insert(v1);
      final prev = s.insert(v2);
      expect(prev, v1);
      expect(s.find('u1'), v2);
    });

    test('ensureCached returns cached user without fetching', () async {
      final s = make();
      const u = ChatUser(id: 'u1', displayName: 'Alice');
      s.insert(u);

      final fetched = await s.ensureCached('u1');
      expect(fetched, u);
      verifyNever(() => api.get(any()));
    });

    test('ensureCached fetches missing user and caches it', () async {
      final s = make();
      const u = ChatUser(id: 'u1', displayName: 'Alice');
      when(() => api.get('u1')).thenAnswer((_) async => const ChatSuccess(u));

      final fetched = await s.ensureCached('u1');
      expect(fetched, u);
      expect(s.find('u1'), u);
      verify(() => api.get('u1')).called(1);
    });

    test('ensureCached dedupes concurrent fetches for same id', () async {
      final s = make();
      final completer = Completer<ChatResult<ChatUser>>();
      when(() => api.get('u1')).thenAnswer((_) => completer.future);

      final f1 = s.ensureCached('u1');
      final f2 = s.ensureCached('u1');
      // Second call returns null synchronously (piggyback signal).
      expect(await f2, isNull);
      completer.complete(
        const ChatSuccess(ChatUser(id: 'u1', displayName: 'A')),
      );
      final r1 = await f1;
      expect(r1?.displayName, 'A');
      verify(() => api.get('u1')).called(1);
    });

    test('ensureCached returns null on API failure (silent)', () async {
      final s = make();
      when(
        () => api.get('u1'),
      ).thenAnswer((_) async => const ChatFailureResult(NotFoundFailure()));

      final fetched = await s.ensureCached('u1');
      expect(fetched, isNull);
      expect(s.contains('u1'), isFalse);
    });

    test('ensureCached short-circuits when isDisposed is true', () async {
      final s = make(isDisposed: true);

      final fetched = await s.ensureCached('u1');
      expect(fetched, isNull);
      verifyNever(() => api.get(any()));
    });

    test('clear drops cache + pending fetches', () {
      final s = make();
      s.insert(const ChatUser(id: 'u1', displayName: 'A'));
      s.insert(const ChatUser(id: 'u2', displayName: 'B'));
      expect(s.length, 2);
      s.clear();
      expect(s.length, 0);
      expect(s.pendingFetchCount, 0);
    });

    test('all returns every cached user', () {
      final s = make();
      s.insert(const ChatUser(id: 'u1', displayName: 'A'));
      s.insert(const ChatUser(id: 'u2', displayName: 'B'));
      final ids = s.all.map((u) => u.id).toSet();
      expect(ids, {'u1', 'u2'});
    });
  });
}
