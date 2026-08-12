import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/src/_internal/api_factory.dart';
import 'package:noma_chat/src/_internal/cache/cache_manager.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class _MockRest extends Mock implements RestClient {}

/// A read shape that accepts a `cachePolicy`, tied to the source
/// declaration it exercises so the coverage guard below can pair them.
class _Probe {
  const _Probe(this.declaration, this.name, this.call);

  /// `path:Class.method`, matching what [_declarationsUnderSweep] emits.
  final String declaration;
  final String name;
  final Future<ChatResult<Object?>> Function() call;
}

/// One rule, swept across the whole read surface: with no cached answer
/// available, [CachePolicy.cacheOnly] never puts a byte on the wire.
///
/// The per-site tests in `cache_only_no_request_test.dart` pin each fix.
/// This file is the net under them. It walks every sub-API the SDK wires —
/// through the same [ApiFactory] `NomaChatClient` uses, built with no
/// cache — in every shape that accepts the policy, and it fails when a
/// method carrying a `cachePolicy` parameter exists in the API layer
/// without a shape here calling it. A seventh site cannot be added
/// tomorrow without this test naming it.
///
/// The cached messages decorator is the one layer that cannot be built
/// without a store, so it is swept the only way it can be: with a real
/// but empty one, which is the same starting point — nothing to read.
void main() {
  late _MockRest rest;
  late ApiFactory apis;
  late CachedMessagesApi cachedMessages;

  setUp(() {
    rest = _MockRest();
    apis = ApiFactory(rest: rest, userId: 'me');
    cachedMessages = CachedMessagesApi(
      rest: rest,
      cache: MemoryChatLocalDatasource(),
      cacheManager: CacheManager(config: const CacheConfig()),
    );
  });

  final probes = <_Probe>[
    _Probe(
      'lib/src/api/users_api.dart:UsersApi.get',
      'users.get',
      () => apis.users().get('u1', cachePolicy: CachePolicy.cacheOnly),
    ),
    _Probe(
      'lib/src/api/rooms_api.dart:RoomsApi.getUserRooms',
      'rooms.getUserRooms',
      () => apis.rooms().getUserRooms(cachePolicy: CachePolicy.cacheOnly),
    ),
    _Probe(
      'lib/src/api/rooms_api.dart:RoomsApi.getUserRooms',
      'rooms.getUserRooms, filtered + paginated',
      () => apis.rooms().getUserRooms(
        type: 'unread',
        pagination: const ChatPaginationParams(limit: 20, offset: 40),
        cachePolicy: CachePolicy.cacheOnly,
      ),
    ),
    _Probe(
      'lib/src/api/rooms_api.dart:RoomsApi.get',
      'rooms.get',
      () => apis.rooms().get('r1', cachePolicy: CachePolicy.cacheOnly),
    ),
    _Probe(
      'lib/src/api/members_api.dart:MembersApi.list',
      'members.list',
      () => apis.members().list('r1', cachePolicy: CachePolicy.cacheOnly),
    ),
    _Probe(
      'lib/src/api/members_api.dart:MembersApi.list',
      'members.list, paginated',
      () => apis.members().list(
        'r1',
        pagination: const ChatPaginationParams(limit: 50),
        cachePolicy: CachePolicy.cacheOnly,
      ),
    ),
    _Probe(
      'lib/src/api/members_api.dart:MembersApi.list',
      'members.list, expanded',
      () => apis.members().list(
        'r1',
        expand: const [RoomMemberExpand.users],
        cachePolicy: CachePolicy.cacheOnly,
      ),
    ),
    _Probe(
      'lib/src/api/contacts_api.dart:ContactsApi.list',
      'contacts.list',
      () => apis.contacts().list(cachePolicy: CachePolicy.cacheOnly),
    ),
    _Probe(
      'lib/src/api/contacts_api.dart:ContactsApi.list',
      'contacts.list, paginated',
      () => apis.contacts().list(
        pagination: const ChatPaginationParams(limit: 25),
        cachePolicy: CachePolicy.cacheOnly,
      ),
    ),
    _Probe(
      'lib/src/api/messages_api_rest.dart:RestMessagesApi.list',
      'messages.list',
      () => apis.messages().list('r1', cachePolicy: CachePolicy.cacheOnly),
    ),
    _Probe(
      'lib/src/api/messages_api_rest.dart:RestMessagesApi.list',
      'messages.list, cursor page + unreadOnly',
      () => apis.messages().list(
        'r1',
        pagination: const ChatCursorPaginationParams(
          limit: 30,
          cursor: 'opaque',
          direction: ChatCursorDirection.older,
        ),
        unreadOnly: true,
        cachePolicy: CachePolicy.cacheOnly,
      ),
    ),
    _Probe(
      'lib/src/api/messages_api_rest.dart:RestMessagesApi.getReactions',
      'messages.getReactions',
      () => apis.messages().getReactions(
        'r1',
        'm1',
        cachePolicy: CachePolicy.cacheOnly,
      ),
    ),
    _Probe(
      'lib/src/api/messages_api_cached.dart:CachedMessagesApi.list',
      'messages.list, cached layer over an empty store',
      () => cachedMessages.list('r1', cachePolicy: CachePolicy.cacheOnly),
    ),
    _Probe(
      'lib/src/api/messages_api_cached.dart:CachedMessagesApi.getReactions',
      'messages.getReactions, cached layer over an empty store',
      () => cachedMessages.getReactions(
        'r1',
        'm1',
        cachePolicy: CachePolicy.cacheOnly,
      ),
    ),
  ];

  group('nothing reaches the wire under cacheOnly', () {
    for (final probe in probes) {
      test('${probe.name} is a miss and leaves the HTTP client '
          'untouched', () async {
        final result = await probe.call();

        expect(
          result.isFailure,
          isTrue,
          reason:
              '${probe.name} answered a success off a store with nothing in '
              'it; cacheOnly must report the miss the caller already handles',
        );
        expect(result.failureOrNull, isA<NetworkFailure>());
        expect(result.failureOrNull!.message, 'No cached data available');
        verifyZeroInteractions(rest);
      });
    }
  });

  group('coverage guard', () {
    test('every cachePolicy declaration in the API layer is swept', () {
      final declared = _declarationsUnderSweep();
      final swept = probes.map((p) => p.declaration).toSet();

      expect(
        declared,
        isNotEmpty,
        reason:
            'found no `cachePolicy` declaration at all — the scan is broken, '
            'not the code; flutter test must run from the package root',
      );

      final implementations = declared
          .where((d) => d.startsWith('lib/src/api/'))
          .toSet();
      final interfaces = declared
          .where((d) => d.startsWith('lib/src/client/'))
          .toSet();

      expect(
        implementations.difference(swept),
        isEmpty,
        reason:
            'a sub-API method takes a `cachePolicy` and no shape in this '
            'sweep calls it with `CachePolicy.cacheOnly`. Add it to `probes` '
            '— and make it answer the miss without a request — before '
            'landing.',
      );
      expect(
        swept.difference(implementations),
        isEmpty,
        reason:
            'this sweep probes a declaration that no longer exists under '
            'lib/src/api — drop the stale entry from `probes`',
      );

      // Interface and implementation must move together: a policy offered
      // on the abstract sub-API with nobody honouring it, or honoured
      // without being offered, is how the original sites drifted apart.
      expect(
        interfaces.map(_methodOf).toSet(),
        implementations.map(_methodOf).toSet(),
        reason:
            'the `cachePolicy` methods declared on the abstract sub-APIs in '
            'chat_client.dart and the ones implemented under lib/src/api '
            'have diverged',
      );
    });
  });
}

String _methodOf(String declaration) => declaration.split('.').last;

/// Scans the source for every method that accepts a `cachePolicy`.
///
/// Returns entries shaped `path:Class.method`. Every sub-API lives under
/// the flat `lib/src/api/`, and every policy a caller can pass is declared
/// on an abstract class in `chat_client.dart`, so those two locations are
/// the whole surface this rule has to hold on.
Set<String> _declarationsUnderSweep() {
  final files = <File>[
    ...Directory('lib/src/api')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart')),
    File('lib/src/client/chat_client.dart'),
  ]..sort((a, b) => a.path.compareTo(b.path));

  final classPattern = RegExp(
    r'^(?:abstract\s+)?(?:final\s+|base\s+)?class\s+(\w+)',
  );
  final methodPattern = RegExp(r'^\s*(?:Future|Stream)<.*>\s+(\w+)\s*\(');
  final policyPattern = RegExp(r'\bCachePolicy\??\s+cachePolicy\b');

  final found = <String>{};
  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (!policyPattern.hasMatch(lines[i])) continue;
      String? method;
      String? owner;
      for (var j = i; j >= 0 && owner == null; j--) {
        method ??= methodPattern.firstMatch(lines[j])?.group(1);
        if (method != null) owner = classPattern.firstMatch(lines[j])?.group(1);
      }
      expect(
        method != null && owner != null,
        isTrue,
        reason:
            'could not attribute the `cachePolicy` at ${file.path}:${i + 1} '
            'to a class and method; widen the scan rather than dropping it',
      );
      found.add('${file.path}:$owner.$method');
    }
  }
  return found;
}
