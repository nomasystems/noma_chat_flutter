import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Concrete subclass that implements none of the abstract members (they
/// route to `noSuchMethod` and would throw if called) so we can exercise
/// the default no-op implementations [ChatLocalDatasource] provides for
/// optional persistence hooks.
class _DefaultsDatasource extends ChatLocalDatasource {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _DefaultsDatasource ds;

  setUp(() => ds = _DefaultsDatasource());

  group('ChatLocalDatasource — default implementations', () {
    test('hidden-message hooks are no-op successes', () async {
      expect((await ds.hideMessageLocally('r', 'm')).isSuccess, isTrue);
      expect((await ds.getHiddenMessageIds('r')).dataOrThrow, isEmpty);
      expect((await ds.clearHiddenMessages('r')).isSuccess, isTrue);
    });

    test('pending-message hooks are no-op successes', () async {
      final msg = ChatMessage(id: 'm1', from: 'me', timestamp: DateTime(2026));

      expect((await ds.savePendingMessage('r', msg)).isSuccess, isTrue);
      expect((await ds.getPendingMessages('r')).dataOrThrow, isEmpty);
      expect((await ds.deletePendingMessage('r', 'm1')).isSuccess, isTrue);
      expect((await ds.clearPendingMessages('r')).isSuccess, isTrue);
    });

    test('cache-timestamp hooks default to empty / no-op', () async {
      expect(await ds.loadCacheTimestamps(), isEmpty);
      // saveCacheTimestamps default is a no-op that must not throw.
      await ds.saveCacheTimestamps({'rooms': DateTime(2026)});
    });

    test('kicked-room hooks are no-op successes', () async {
      expect((await ds.markKicked('r')).isSuccess, isTrue);
      expect((await ds.unmarkKicked('r')).isSuccess, isTrue);
      expect((await ds.getKickedRoomIds()).dataOrThrow, isEmpty);
    });
  });
}
