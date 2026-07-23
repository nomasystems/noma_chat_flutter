import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

ChatConfig _config({
  ChatLogSink? logSink,
  void Function(String level, String message)? logger,
  ChatLogLevel logLevel = ChatLogLevel.warn,
  bool logMessageContent = false,
}) => ChatConfig(
  baseUrl: 'http://localhost:8077/v1',
  realtimeUrl: 'http://localhost:8077',
  tokenProvider: () async => 'test-token',
  logSink: logSink,
  logger: logger,
  logLevel: logLevel,
  logMessageContent: logMessageContent,
);

void main() {
  group('ChatConfig.logs derivation', () {
    test('uses logSink verbatim when provided, ignoring logger', () {
      final sink = BufferChatLogSink();
      final loggerCalls = <String>[];
      final config = _config(
        logSink: sink,
        logger: (level, message) => loggerCalls.add(message),
        logLevel: ChatLogLevel.debug,
      );

      config.logs.log(ChatLogLevel.debug, ChatLogTag.general, 'hello');

      expect(sink.records, hasLength(1));
      expect(loggerCalls, isEmpty);
    });

    test('bridges to logger via CallbackChatLogSink when logSink is null', () {
      final loggerCalls = <(String, String)>[];
      final config = _config(
        logger: (level, message) => loggerCalls.add((level, message)),
        logLevel: ChatLogLevel.debug,
      );

      config.logs.log(ChatLogLevel.warn, ChatLogTag.ws, 'auth timeout');

      expect(loggerCalls, hasLength(1));
      expect(loggerCalls.single.$1, 'warn');
      expect(loggerCalls.single.$2, contains('auth timeout'));
    });

    test('is a no-op-safe default when neither is set (release-mode '
        'no-op / debug-mode console — must not throw)', () {
      final config = _config(logLevel: ChatLogLevel.debug);
      expect(
        () => config.logs.log(ChatLogLevel.debug, ChatLogTag.general, 'x'),
        returnsNormally,
      );
    });

    test('logs getter is memoised (same instance across calls)', () {
      final config = _config();
      expect(identical(config.logs, config.logs), isTrue);
    });

    test('honours logMessageContent through the derived logger', () {
      final redacted = _config();
      expect(redacted.logs.content('secret'), isNot('secret'));

      final verbose = _config(logMessageContent: true);
      expect(verbose.logs.content('secret'), 'secret');
    });

    test('log(level, message) legacy API delegates through logs as '
        'ChatLogTag.general', () {
      final buffer = BufferChatLogSink();
      final config = _config(logSink: buffer, logLevel: ChatLogLevel.debug);

      config.log('warn', 'legacy call site');

      expect(buffer.records, hasLength(1));
      expect(buffer.records.single.tag, ChatLogTag.general);
      expect(buffer.records.single.level, ChatLogLevel.warn);
      expect(buffer.records.single.message, 'legacy call site');
    });
  });
}
