import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/ui/adapter/services/host_user_directory.dart';
import 'package:noma_chat/src/ui/adapter/services/user_cache_service.dart';

class _MockUsersApi extends Mock implements ChatUsersApi {}

void main() {
  group('a host answer never settles the chat profile', () {
    late _MockUsersApi api;

    setUp(() => api = _MockUsersApi());

    UserCacheService make(UserDirectoryResolver resolver) => UserCacheService(
      api: api,
      isDisposed: () => false,
      directory: HostUserDirectory(
        resolver: resolver,
        batchWindow: Duration.zero,
      ),
    );

    test(
      'the chat fetch is tried again after it failed under a host name',
      () async {
        var directoryCalls = 0;
        final service = make((ids) async {
          directoryCalls++;
          return {
            for (final id in ids)
              id: const HostUser(id: 'u1', displayName: 'Alice Host'),
          };
        });
        when(
          () => api.get('u1'),
        ).thenAnswer((_) async => const ChatFailureResult(NotFoundFailure()));

        final first = await service.ensureCached('u1');

        expect(
          first?.displayName,
          'Alice Host',
          reason: 'the host answer paints straight away',
        );
        expect(
          service.contains('u1'),
          isFalse,
          reason: 'a name is not a profile: the id is still worth fetching',
        );

        const profile = ChatUser(
          id: 'u1',
          displayName: 'Alice Chat',
          bio: 'on the road',
          email: 'alice@example.com',
        );
        when(
          () => api.get('u1'),
        ).thenAnswer((_) async => const ChatSuccess(profile));

        final second = await service.ensureCached('u1');

        expect(second?.bio, 'on the road');
        expect(second?.email, 'alice@example.com');
        expect(
          second?.displayName,
          'Alice Host',
          reason: 'the host stays authoritative about the name',
        );
        expect(service.contains('u1'), isTrue);
        verify(() => api.get('u1')).called(2);
        expect(
          directoryCalls,
          1,
          reason: 'the retry reuses the answer the host already gave',
        );
      },
    );

    test('and the host identity paints while the retry is still pending', () {
      final service = make(
        (ids) async => {
          for (final id in ids) id: const HostUser(id: 'u1', displayName: 'Al'),
        },
      );

      expect(service.find('u1'), isNull);
      expect(service.length, 0);
    });

    test(
      'feeding the host identity back in does not close the door either',
      () async {
        final service = make(
          (ids) async => {
            for (final id in ids)
              id: const HostUser(id: 'u1', displayName: 'Alice Host'),
          },
        );
        when(
          () => api.get('u1'),
        ).thenAnswer((_) async => const ChatFailureResult(NotFoundFailure()));

        final provisional = await service.ensureCached('u1');
        expect(provisional, isNotNull);

        // What `cacheUsers` does with whatever `ensureCached` handed back.
        service.insert(provisional!);

        expect(
          service.contains('u1'),
          isFalse,
          reason: 'a round trip through the caller must not settle it',
        );
        expect(service.find('u1')?.displayName, 'Alice Host');

        const profile = ChatUser(
          id: 'u1',
          displayName: 'Alice Chat',
          bio: 'hi',
        );
        when(
          () => api.get('u1'),
        ).thenAnswer((_) async => const ChatSuccess(profile));

        expect((await service.ensureCached('u1'))?.bio, 'hi');
        expect(service.contains('u1'), isTrue);
      },
    );

    test('a real chat user still settles on the first insert', () {
      final service = make((ids) async => const {});

      const u = ChatUser(id: 'u2', displayName: 'Bob');
      expect(service.insert(u), isNull);
      expect(service.contains('u2'), isTrue);
      expect(service.find('u2'), u);
      expect(service.length, 1);
    });
  });
}
