import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// A suggestion nobody can name is a blank row, not a row with a uuid in it.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');
  const namelessId = '9f2a1c44-0e7b-4d31-9a55-6b0f6f0a1c22';

  late MockChatClient client;

  setUp(() => client = MockChatClient(currentUserId: 'me'));

  tearDown(() async => client.dispose());

  ChatUiAdapter adapterWith() {
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: me,
      manageAppLifecycle: false,
    );
    addTearDown(adapter.dispose);
    return adapter;
  }

  Future<SuggestedContact> loadOne(ChatUiAdapter adapter, String id) async {
    final controller = SuggestionBarController(adapter);
    addTearDown(controller.dispose);
    await controller.load();
    return controller.suggestions.singleWhere((s) => s.id == id);
  }

  test('a contact chat has never heard of is not labelled by id', () async {
    await client.contacts.add(namelessId);

    final row = await loadOne(adapterWith(), namelessId);

    expect(
      row.displayName,
      isEmpty,
      reason: 'the host paints its own placeholder over a blank name',
    );
  });

  test('a contact chat does know still reads its chat name', () async {
    await client.contacts.add('u1');
    client.seedUser(const ChatUser(id: 'u1', displayName: 'Alice'));

    final row = await loadOne(adapterWith(), 'u1');

    expect(row.displayName, 'Alice');
  });
}
