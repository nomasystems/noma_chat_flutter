import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  group('ChatLogLevel', () {
    test('operator >= is ordered debug < info < warn < error', () {
      expect(ChatLogLevel.error >= ChatLogLevel.warn, isTrue);
      expect(ChatLogLevel.warn >= ChatLogLevel.warn, isTrue);
      expect(ChatLogLevel.info >= ChatLogLevel.warn, isFalse);
      expect(ChatLogLevel.debug >= ChatLogLevel.info, isFalse);
    });
  });

  group('ChatLogger filtering', () {
    test('drops records below minLevel', () {
      final buffer = BufferChatLogSink();
      final logger = ChatLogger(sink: buffer, minLevel: ChatLogLevel.warn);

      logger.log(ChatLogLevel.debug, ChatLogTag.ws, 'debug line');
      logger.log(ChatLogLevel.info, ChatLogTag.ws, 'info line');
      logger.log(ChatLogLevel.warn, ChatLogTag.ws, 'warn line');
      logger.log(ChatLogLevel.error, ChatLogTag.ws, 'error line');

      expect(buffer.records, hasLength(2));
      expect(buffer.records.map((r) => r.message), ['warn line', 'error line']);
    });

    test('isEnabled reflects the same filter used by log()', () {
      final logger = ChatLogger(
        sink: BufferChatLogSink(),
        minLevel: ChatLogLevel.info,
      );
      expect(logger.isEnabled(ChatLogLevel.debug, ChatLogTag.ws), isFalse);
      expect(logger.isEnabled(ChatLogLevel.info, ChatLogTag.ws), isTrue);
      expect(logger.isEnabled(ChatLogLevel.error, ChatLogTag.ws), isTrue);
    });

    test('restricts to the given tags when provided', () {
      final buffer = BufferChatLogSink();
      final logger = ChatLogger(
        sink: buffer,
        minLevel: ChatLogLevel.debug,
        tags: {ChatLogTag.ws, ChatLogTag.cache},
      );

      logger.log(ChatLogLevel.debug, ChatLogTag.ws, 'ws line');
      logger.log(ChatLogLevel.debug, ChatLogTag.cache, 'cache line');
      logger.log(ChatLogLevel.debug, ChatLogTag.attachments, 'attach line');

      expect(buffer.records.map((r) => r.message), ['ws line', 'cache line']);
    });

    test('null tags means every tag passes', () {
      final buffer = BufferChatLogSink();
      final logger = ChatLogger(sink: buffer, minLevel: ChatLogLevel.debug);

      logger.log(ChatLogLevel.debug, ChatLogTag.general, 'general');
      logger.attach(ChatLogLevel.debug, 'attach');
      logger.presence(ChatLogLevel.debug, 'presence');

      expect(buffer.records, hasLength(3));
    });

    test('per-tag shortcuts route to the matching ChatLogTag', () {
      final buffer = BufferChatLogSink();
      final logger = ChatLogger(sink: buffer, minLevel: ChatLogLevel.debug);

      logger.ws(ChatLogLevel.debug, 'a');
      logger.cache(ChatLogLevel.debug, 'b');
      logger.attach(ChatLogLevel.debug, 'c');
      logger.receipts(ChatLogLevel.debug, 'd');
      logger.lifecycle(ChatLogLevel.debug, 'e');

      expect(buffer.records.map((r) => r.tag), [
        ChatLogTag.ws,
        ChatLogTag.cache,
        ChatLogTag.attachments,
        ChatLogTag.receipts,
        ChatLogTag.lifecycle,
      ]);
    });
  });

  group('ChatLogger.content redaction', () {
    test('redacts by default (logMessageContent: false)', () {
      final logger = ChatLogger(sink: BufferChatLogSink());
      expect(logger.content('hello world'), isNot('hello world'));
      expect(logger.content('hello world'), contains('redacted'));
    });

    test('returns raw text when logMessageContent is true', () {
      final logger = ChatLogger(
        sink: BufferChatLogSink(),
        logMessageContent: true,
      );
      expect(logger.content('hello world'), 'hello world');
    });

    test('null text renders as a placeholder either way', () {
      final redacting = ChatLogger(sink: BufferChatLogSink());
      final verbose = ChatLogger(
        sink: BufferChatLogSink(),
        logMessageContent: true,
      );
      expect(redacting.content(null), '<null>');
      expect(verbose.content(null), '<null>');
    });
  });

  group('ChatLogRecord.format', () {
    test('includes level, tag, fields and message', () {
      final record = ChatLogRecord(
        timestamp: DateTime(2026, 1, 1, 12, 0, 1, 234),
        level: ChatLogLevel.warn,
        tag: ChatLogTag.ws,
        message: 'auth timeout',
        fields: const {'connId': 7},
      );
      final formatted = record.format();
      expect(formatted, contains('W'));
      expect(formatted, contains('[ws]'));
      expect(formatted, contains('connId: 7'));
      expect(formatted, contains('auth timeout'));
    });
  });

  group('BufferChatLogSink', () {
    test('caps at capacity, dropping the oldest records', () {
      final buffer = BufferChatLogSink(capacity: 3);
      for (var i = 0; i < 5; i++) {
        buffer.add(
          ChatLogRecord(
            timestamp: DateTime.now(),
            level: ChatLogLevel.info,
            tag: ChatLogTag.general,
            message: 'line$i',
          ),
        );
      }
      expect(buffer.records, hasLength(3));
      expect(buffer.records.map((r) => r.message), ['line2', 'line3', 'line4']);
    });

    test('export filters by minLevel and tags', () {
      final buffer = BufferChatLogSink();
      buffer.add(
        ChatLogRecord(
          timestamp: DateTime.now(),
          level: ChatLogLevel.debug,
          tag: ChatLogTag.ws,
          message: 'debug ws',
        ),
      );
      buffer.add(
        ChatLogRecord(
          timestamp: DateTime.now(),
          level: ChatLogLevel.error,
          tag: ChatLogTag.cache,
          message: 'error cache',
        ),
      );
      buffer.add(
        ChatLogRecord(
          timestamp: DateTime.now(),
          level: ChatLogLevel.error,
          tag: ChatLogTag.ws,
          message: 'error ws',
        ),
      );

      final onlyErrors = buffer.export(minLevel: ChatLogLevel.error);
      expect(onlyErrors, isNot(contains('debug ws')));
      expect(onlyErrors, contains('error cache'));
      expect(onlyErrors, contains('error ws'));

      final onlyWs = buffer.export(tags: {ChatLogTag.ws});
      expect(onlyWs, contains('debug ws'));
      expect(onlyWs, contains('error ws'));
      expect(onlyWs, isNot(contains('error cache')));
    });

    test('clear empties the buffer', () {
      final buffer = BufferChatLogSink();
      buffer.add(
        ChatLogRecord(
          timestamp: DateTime.now(),
          level: ChatLogLevel.info,
          tag: ChatLogTag.general,
          message: 'x',
        ),
      );
      expect(buffer.records, hasLength(1));
      buffer.clear();
      expect(buffer.records, isEmpty);
    });
  });

  group('CallbackChatLogSink', () {
    test('bridges records to a (level, message) callback', () {
      final calls = <(String, String)>[];
      final sink = CallbackChatLogSink((level, message) {
        calls.add((level, message));
      });
      final logger = ChatLogger(sink: sink, minLevel: ChatLogLevel.debug);

      logger.log(ChatLogLevel.warn, ChatLogTag.ws, 'auth timeout');

      expect(calls, hasLength(1));
      expect(calls.single.$1, 'warn');
      expect(calls.single.$2, contains('auth timeout'));
    });
  });

  group('MultiChatLogSink', () {
    test('fans a record out to every composed sink', () {
      final a = BufferChatLogSink();
      final b = BufferChatLogSink();
      final logger = ChatLogger(
        sink: MultiChatLogSink([a, b]),
        minLevel: ChatLogLevel.debug,
      );

      logger.log(ChatLogLevel.info, ChatLogTag.general, 'fan out');

      expect(a.records, hasLength(1));
      expect(b.records, hasLength(1));
    });

    test('a throwing sink does not block its siblings', () {
      final good = BufferChatLogSink();
      final logger = ChatLogger(
        sink: MultiChatLogSink([_ThrowingSink(), good]),
        minLevel: ChatLogLevel.debug,
      );

      logger.log(ChatLogLevel.info, ChatLogTag.general, 'still arrives');

      expect(good.records, hasLength(1));
    });
  });
}

class _ThrowingSink implements ChatLogSink {
  @override
  void add(ChatLogRecord record) => throw StateError('boom');

  @override
  Future<void> flush() async => throw StateError('boom');

  @override
  Future<void> close() async => throw StateError('boom');
}
