import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/ui/adapter/services/connection_lifecycle.dart';

void main() {
  group('ConnectionLifecycle', () {
    test('starts with disconnected state, initialized=false, !disposed', () {
      final l = ConnectionLifecycle();
      expect(l.connectionState.value, ChatConnectionState.disconnected);
      expect(l.initialized.value, isFalse);
      expect(l.isDisposed, isFalse);
      expect(l.pendingLoadRooms, isNull);
    });

    test('initialState parameter seeds the notifier', () {
      final l = ConnectionLifecycle(
        initialState: ChatConnectionState.connected,
      );
      expect(l.connectionState.value, ChatConnectionState.connected);
    });

    test('notifiers are observable and reflect mutations', () {
      final l = ConnectionLifecycle();
      var events = 0;
      l.connectionState.addListener(() => events++);
      l.connectionState.value = ChatConnectionState.connected;
      l.connectionState.value = ChatConnectionState.disconnected;
      expect(events, 2);
    });

    test('pendingLoadRooms setter / getter round-trip', () {
      final l = ConnectionLifecycle();
      final c = Completer<ChatResult<void>>();
      l.pendingLoadRooms = c;
      expect(l.pendingLoadRooms, same(c));
      l.pendingLoadRooms = null;
      expect(l.pendingLoadRooms, isNull);
    });

    test('dispose flips isDisposed and tears down notifiers', () async {
      final l = ConnectionLifecycle();
      await l.dispose();
      expect(l.isDisposed, isTrue);
      // Notifier disposed — addListener now throws.
      expect(
        () => l.connectionState.addListener(() {}),
        throwsA(isA<FlutterError>()),
      );
    });

    test('dispose is idempotent — second call is a silent no-op', () async {
      final l = ConnectionLifecycle();
      await l.dispose();
      await expectLater(l.dispose(), completes);
      expect(l.isDisposed, isTrue);
    });

    test('isDisposed latches forever once set', () async {
      final l = ConnectionLifecycle();
      expect(l.isDisposed, isFalse);
      await l.dispose();
      expect(l.isDisposed, isTrue);
    });
  });
}
