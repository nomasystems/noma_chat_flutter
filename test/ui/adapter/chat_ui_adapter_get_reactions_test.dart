import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  late MockChatClient mockClient;
  late ChatUiAdapter adapter;

  final currentUser = const ChatUser(id: 'u1', displayName: 'Me');

  setUp(() {
    mockClient = MockChatClient(currentUserId: 'u1');
    adapter = ChatUiAdapter(client: mockClient, currentUser: currentUser);
  });

  tearDown(() async {
    await adapter.dispose();
    await mockClient.dispose();
  });

  group('getReactions', () {
    test(
      'delegates to client.messages.getReactions and returns result',
      () async {
        final result = await adapter.getReactions('room1', 'msg1');
        expect(result.isSuccess, true);
        expect(result.dataOrNull, isEmpty);
      },
    );
  });
}
