import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';
import 'package:noma_chat_example/chat_session.dart';
import 'package:noma_chat_example/mock_data.dart';
import 'package:noma_chat_example/settings/example_settings.dart';

void main() {
  group('chatModeFromEnv', () {
    test('returns mock when no MODE dart-define is set', () {
      // Default dart-defines in test runs do not include MODE.
      expect(chatModeFromEnv(), ChatMode.mock);
    });
  });

  group('autologinAs', () {
    test('returns empty when AUTOLOGIN_AS dart-define is not set', () {
      expect(autologinAs(), '');
    });
  });

  group('LoginOutcome', () {
    test('is a sealed hierarchy with exactly the four expected variants', () async {
      // A switch with no default over a sealed type is exhaustiveness-checked
      // by the compiler: adding a fifth LoginOutcome subclass anywhere makes
      // this fail to compile, which is what actually reminds us to update
      // the onboarding switch in onboarding_page.dart — not the isNotNull
      // checks a tear-off would always pass anyway.
      String labelFor(LoginOutcome outcome) => switch (outcome) {
        LoginSuccess() => 'success',
        LoginAuthFailed() => 'authFailed',
        LoginNetworkFailed() => 'networkFailed',
        LoginUnexpected() => 'unexpected',
      };

      final success = await openChatSession(const ExampleSettings());
      expect(success, isA<LoginSuccess>());
      addTearDown((success as LoginSuccess).chat.dispose);

      expect(labelFor(success), 'success');
      expect(labelFor(const LoginAuthFailed('auth')), 'authFailed');
      expect(labelFor(const LoginNetworkFailed('network')), 'networkFailed');
      expect(labelFor(const LoginUnexpected('unexpected')), 'unexpected');
    });
  });

  group('demoUserDirectoryResolver', () {
    test('resolves the seeded host-only contractor by name', () async {
      final result = await demoUserDirectoryResolver({'dana'});
      final dana = result['dana'];
      expect(dana, isNotNull);
      expect(dana!.gone, isFalse);
      expect(dana.displayName, 'Dana');
    });

    test('answers HostUser.missing for an id it does not know', () async {
      final result = await demoUserDirectoryResolver({'nobody'});
      final nobody = result['nobody'];
      expect(nobody, isNotNull);
      expect(nobody!.gone, isTrue);
      expect(nobody.hasDisplayName, isFalse);
    });

    test('keys every answer by the requested id, batched', () async {
      final result = await demoUserDirectoryResolver({'dana', 'nobody'});
      expect(result.keys, unorderedEquals(<String>{'dana', 'nobody'}));
    });
  });

  group('seedDemoData', () {
    test('seeds an owner-only room the demo user cannot write to', () async {
      final client = MockChatClient(currentUserId: 'demo-user');
      seedDemoData(client);

      final result = await client.rooms.get('room-group-archive');
      expect(result, isA<ChatSuccess<RoomDetail>>());
      final detail = (result as ChatSuccess<RoomDetail>).data;
      expect(detail.userRole, RoomRole.member);
      expect(detail.config.writePolicy, RoomWritePolicy.ownerOnly);
      expect(detail.isReadOnly, isTrue);
    });
  });

  group('openChatSession — mock mode', () {
    test(
      'bootstraps the already-known demo user without duplicating it',
      () async {
        final outcome = await openChatSession(const ExampleSettings());
        expect(outcome, isA<LoginSuccess>());
        final chat = (outcome as LoginSuccess).chat;
        addTearDown(chat.dispose);

        final registered = await chat.adapter.profile.ensureRegistered();
        expect(registered.isSuccess, isTrue);
        expect(registered.dataOrNull?.id, 'demo-user');
      },
    );

    test('wires demoUserDirectoryResolver into the adapter', () async {
      final outcome = await openChatSession(const ExampleSettings());
      expect(outcome, isA<LoginSuccess>());
      final chat = (outcome as LoginSuccess).chat;
      addTearDown(chat.dispose);

      expect(chat.adapter.userDirectoryResolver, demoUserDirectoryResolver);
    });
  });
}
