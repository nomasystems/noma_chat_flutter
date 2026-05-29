import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/ui/adapter/services/operation_hub.dart';

void main() {
  group('OperationHub', () {
    late OperationHub hub;

    setUp(() => hub = OperationHub());

    tearDown(() async => hub.dispose());

    test(
      'emitFailure adds to errors stream and returns same ChatResult',
      () async {
        final received = <OperationError>[];
        final sub = hub.errors.listen(received.add);

        const input = ChatFailureResult<int>(NotFoundFailure('not here'));
        final out = hub.emitFailure(
          input,
          OperationKind.deleteMessage,
          roomId: 'r1',
          messageId: 'm1',
        );

        expect(identical(out, input), isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(received, hasLength(1));
        expect(received.single.kind, OperationKind.deleteMessage);
        expect(received.single.roomId, 'r1');
        expect(received.single.failure, isA<NotFoundFailure>());
        await sub.cancel();
      },
    );

    test(
      'emitFailure with ChatSuccess does NOT emit and returns ChatSuccess',
      () async {
        final received = <OperationError>[];
        final sub = hub.errors.listen(received.add);

        const input = ChatSuccess<int>(42);
        final out = hub.emitFailure(input, OperationKind.sendMessage);

        expect(identical(out, input), isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(received, isEmpty);
        await sub.cancel();
      },
    );

    test('emitSuccess adds to successes stream', () async {
      final received = <OperationSuccess>[];
      final sub = hub.successes.listen(received.add);

      hub.emitSuccess(OperationKind.pinMessage, roomId: 'r1', messageId: 'm1');

      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
      expect(received.single.kind, OperationKind.pinMessage);
      expect(received.single.roomId, 'r1');
      expect(received.single.messageId, 'm1');
      await sub.cancel();
    });

    test(
      'streams are broadcast — multiple subscribers receive each event',
      () async {
        final a = <OperationSuccess>[];
        final b = <OperationSuccess>[];
        final subA = hub.successes.listen(a.add);
        final subB = hub.successes.listen(b.add);

        hub.emitSuccess(OperationKind.forwardMessage);
        await Future<void>.delayed(Duration.zero);
        expect(a, hasLength(1));
        expect(b, hasLength(1));
        await subA.cancel();
        await subB.cancel();
      },
    );

    test('dispose closes both streams and isClosed flips to true', () async {
      expect(hub.isClosed, isFalse);
      await hub.dispose();
      expect(hub.isClosed, isTrue);
    });

    test('emit after dispose is a silent no-op (does not throw)', () async {
      await hub.dispose();
      expect(() => hub.emitSuccess(OperationKind.pinMessage), returnsNormally);
      expect(
        () => hub.emitFailure<int>(
          const ChatFailureResult(ServerFailure(statusCode: 500)),
          OperationKind.sendMessage,
        ),
        returnsNormally,
      );
    });

    test(
      'emitFailure post-dispose still returns the input ChatResult',
      () async {
        await hub.dispose();
        const input = ChatSuccess<String>('hello');
        final out = hub.emitFailure(input, OperationKind.sendMessage);
        expect(identical(out, input), isTrue);
      },
    );
  });
}
