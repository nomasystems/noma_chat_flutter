import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';

// This file is a different library from `chat_ui_adapter.dart` (and its
// `part of` sub-controller files), which is exactly the boundary a host app
// like WB/mobile sits across. Each `MockXController extends Mock implements
// XController` below only compiles because the sub-controllers are
// `interface class`, not `final class` — `implements` across a library
// boundary is rejected by the analyzer for `final` types. Regressing any of
// the five back to `final class` turns this file red.

class MockChatRoomsController extends Mock implements ChatRoomsController {}

class MockChatDmController extends Mock implements ChatDmController {}

class MockChatMessagesController extends Mock
    implements ChatMessagesController {}

class MockChatContactsController extends Mock
    implements ChatContactsController {}

class MockChatProfileController extends Mock implements ChatProfileController {}

void main() {
  group('sub-controller cross-library mockability', () {
    test('ChatRoomsController can be mocked and stubbed', () async {
      final mock = MockChatRoomsController();
      when(
        () => mock.leave('room-1'),
      ).thenAnswer((_) async => const ChatSuccess<void>(null));

      final result = await mock.leave('room-1');

      expect(result.isSuccess, isTrue);
      verify(() => mock.leave('room-1')).called(1);
    });

    test('ChatDmController can be mocked and stubbed', () {
      final mock = MockChatDmController();
      when(() => mock.draftRoutingKey('other-1')).thenReturn('draft:other-1');

      expect(mock.draftRoutingKey('other-1'), 'draft:other-1');
    });

    test('ChatMessagesController can be mocked and stubbed', () async {
      final mock = MockChatMessagesController();
      when(
        () => mock.markAsRead('room-1'),
      ).thenAnswer((_) async => const ChatSuccess<void>(null));

      final result = await mock.markAsRead('room-1');

      expect(result.isSuccess, isTrue);
    });

    test('ChatContactsController can be mocked and stubbed', () {
      final mock = MockChatContactsController();
      when(() => mock.blockedUserIds).thenReturn({'user-1'});

      expect(mock.blockedUserIds, {'user-1'});
    });

    test('ChatProfileController can be mocked and stubbed', () {
      final mock = MockChatProfileController();
      when(() => mock.currentUser).thenReturn(const ChatUser(id: 'user-1'));

      expect(mock.currentUser.id, 'user-1');
    });
  });
}
