import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('ChatLifecyclePolicy', () {
    test('default constructor is WhatsApp-like (keepAlive, reconnect, '
        'resync)', () {
      const policy = ChatLifecyclePolicy();
      expect(policy.reconnectOnResume, isTrue);
      expect(policy.onPause, ChatPauseAction.keepAlive);
      expect(policy.pauseGracePeriod, const Duration(seconds: 3));
      expect(policy.resyncOnResume, isTrue);
    });

    test('standard() is equivalent to the default constructor', () {
      const standard = ChatLifecyclePolicy.standard();
      const defaultPolicy = ChatLifecyclePolicy();
      expect(standard.reconnectOnResume, defaultPolicy.reconnectOnResume);
      expect(standard.onPause, defaultPolicy.onPause);
      expect(standard.pauseGracePeriod, defaultPolicy.pauseGracePeriod);
      expect(standard.resyncOnResume, defaultPolicy.resyncOnResume);
    });

    test('pushOptimized() disconnects on pause, keeps the 3s grace and '
        'reconnect/resync defaults', () {
      const policy = ChatLifecyclePolicy.pushOptimized();
      expect(policy.onPause, ChatPauseAction.disconnect);
      expect(policy.reconnectOnResume, isTrue);
      expect(policy.pauseGracePeriod, const Duration(seconds: 3));
      expect(policy.resyncOnResume, isTrue);
    });

    test('every field is overridable', () {
      const policy = ChatLifecyclePolicy(
        reconnectOnResume: false,
        onPause: ChatPauseAction.disconnect,
        pauseGracePeriod: Duration(seconds: 1),
        resyncOnResume: false,
      );
      expect(policy.reconnectOnResume, isFalse);
      expect(policy.onPause, ChatPauseAction.disconnect);
      expect(policy.pauseGracePeriod, const Duration(seconds: 1));
      expect(policy.resyncOnResume, isFalse);
    });
  });
}
