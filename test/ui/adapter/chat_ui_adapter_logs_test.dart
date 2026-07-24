import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

void main() {
  late MockChatClient mockClient;
  const currentUser = ChatUser(id: 'u1', displayName: 'Me');

  setUp(() {
    mockClient = MockChatClient(currentUserId: 'u1');
  });

  tearDown(() async {
    await mockClient.dispose();
  });

  group('ChatUiAdapter.logs', () {
    test('defaults to warn + redacted content when unset', () async {
      final calls = <(String, String)>[];
      final adapter = ChatUiAdapter(
        client: mockClient,
        currentUser: currentUser,
        manageAppLifecycle: false,
      );
      adapter.logger = (level, message) => calls.add((level, message));

      adapter.logs!.log(ChatLogLevel.debug, ChatLogTag.presence, 'hidden');
      expect(calls, isEmpty, reason: 'debug is below the default warn floor');

      adapter.logs!.log(ChatLogLevel.warn, ChatLogTag.presence, 'shown');
      expect(calls, hasLength(1));

      expect(adapter.logs!.content('secret text'), isNot('secret text'));

      await adapter.dispose();
    });

    test('propagates logLevel to the ChatLogger it builds', () async {
      final calls = <(String, String)>[];
      final adapter = ChatUiAdapter(
        client: mockClient,
        currentUser: currentUser,
        manageAppLifecycle: false,
        logLevel: ChatLogLevel.debug,
      );
      adapter.logger = (level, message) => calls.add((level, message));

      adapter.logs!.log(
        ChatLogLevel.debug,
        ChatLogTag.attachments,
        're-minted',
      );
      expect(
        calls,
        hasLength(1),
        reason:
            'logLevel: debug must let sub-manager debug lines (presence, '
            'attachment resolution, optimistic send) through instead of '
            'being silently clamped to warn',
      );

      await adapter.dispose();
    });

    test('propagates logMessageContent to the ChatLogger it builds', () async {
      final adapter = ChatUiAdapter(
        client: mockClient,
        currentUser: currentUser,
        manageAppLifecycle: false,
        logMessageContent: true,
      );
      adapter.logger = (level, message) {};

      expect(adapter.logs!.content('hello world'), 'hello world');

      await adapter.dispose();
    });

    test('is null when no logger callback is ever wired, regardless of '
        'logLevel/logMessageContent', () async {
      final adapter = ChatUiAdapter(
        client: mockClient,
        currentUser: currentUser,
        manageAppLifecycle: false,
        logLevel: ChatLogLevel.debug,
        logMessageContent: true,
      );

      expect(adapter.logs, isNull);

      await adapter.dispose();
    });
  });
}
