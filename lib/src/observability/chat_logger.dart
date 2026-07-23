/// Structured logging pipeline for the SDK.
///
/// Complements (does not replace) the plain `void Function(String level,
/// String message)? logger` callback that [ChatConfig] has always taken —
/// that callback keeps working unchanged (see [CallbackChatLogSink]). This
/// pipeline adds subsystem tags ([ChatLogTag]), a real level enum
/// ([ChatLogLevel]) instead of a raw string, structured [ChatLogRecord.fields]
/// alongside the message, pluggable [ChatLogSink]s (console, callback,
/// in-memory ring buffer, or several composed via [MultiChatLogSink]), and a
/// content-redaction toggle ([ChatLogger.content]) so message text is not
/// captured by default.
///
/// Typical wiring for a diagnostics session:
///
/// ```dart
/// final buffer = BufferChatLogSink();
/// final config = ChatConfig(
///   ...,
///   logSink: MultiChatLogSink([const ConsoleChatLogSink(), buffer]),
///   logLevel: ChatLogLevel.info,
/// );
/// // Later, to share a log file with support:
/// final path = await ChatLogExporter.exportToFile(buffer);
/// ```
library;

import 'package:flutter/foundation.dart' show debugPrint;

/// Severity of a [ChatLogRecord]. Ordered `debug < info < warn < error`;
/// [ChatLogger] compares a record's level against its configured minimum
/// with [operator >=].
enum ChatLogLevel {
  debug,
  info,
  warn,
  error;

  /// `true` when this level is at least as severe as [other] — i.e. it
  /// would pass a `minLevel: other` filter.
  bool operator >=(ChatLogLevel other) => index >= other.index;
}

/// Subsystem a [ChatLogRecord] originates from. Lets a sink (or a filtered
/// [BufferChatLogSink.export]) narrow down to just the area under
/// investigation instead of the whole firehose.
enum ChatLogTag {
  ws,
  sse,
  polling,
  cache,
  api,
  http,
  attachments,
  presence,
  receipts,
  lifecycle,
  connection,
  room,
  message,
  auth,
  general,
}

/// A single structured log entry.
class ChatLogRecord {
  const ChatLogRecord({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.fields,
    this.error,
    this.stackTrace,
  });

  final DateTime timestamp;
  final ChatLogLevel level;
  final ChatLogTag tag;
  final String message;

  /// Structured context — e.g. `{'roomId': roomId, 'connId': 7}`. Kept as a
  /// side map (rather than string-interpolated into [message]) so a sink
  /// that forwards to structured telemetry (Datadog, Firebase, …) can
  /// attach it as tags/attributes instead of re-parsing a formatted line.
  final Map<String, Object?>? fields;
  final Object? error;
  final StackTrace? stackTrace;

  static const _levelChar = {
    ChatLogLevel.debug: 'D',
    ChatLogLevel.info: 'I',
    ChatLogLevel.warn: 'W',
    ChatLogLevel.error: 'E',
  };

  /// Renders a single human-readable line, e.g.
  /// `12:00:01.234 W [ws] {connId: 7} auth timeout`.
  String format() {
    final t = timestamp;
    String two(int v) => v.toString().padLeft(2, '0');
    final time =
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
        '${t.millisecond.toString().padLeft(3, '0')}';
    final fieldsMap = fields;
    final fieldsStr = fieldsMap != null && fieldsMap.isNotEmpty
        ? ' {${fieldsMap.entries.map((e) => '${e.key}: ${e.value}').join(', ')}}'
        : '';
    final errStr = error != null ? ' error=$error' : '';
    return '$time ${_levelChar[level]} [${tag.name}]$fieldsStr $message$errStr';
  }

  @override
  String toString() => format();
}

/// Destination for [ChatLogRecord]s. Implementations must not throw from
/// [add] — a logging sink must never be the reason a request fails.
abstract class ChatLogSink {
  /// Receives one record. Called synchronously from [ChatLogger.log].
  void add(ChatLogRecord record);

  /// Flushes any buffered output. No-op unless overridden.
  Future<void> flush() async {}

  /// Releases resources held by this sink. No-op unless overridden.
  Future<void> close() async {}
}

/// Sink that prints each record via [debugPrint] — no-op in release builds
/// (same tree-shaking as the rest of the SDK's debug-only logging).
class ConsoleChatLogSink implements ChatLogSink {
  const ConsoleChatLogSink();

  @override
  void add(ChatLogRecord record) {
    debugPrint('[noma_chat] ${record.format()}');
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

/// Bridges a [ChatLogRecord] stream to the legacy
/// `void Function(String level, String message)?` callback that
/// [ChatConfig.logger] has always accepted. Used internally by
/// [ChatConfig]'s sink derivation so a host that only ever wired `logger:`
/// keeps receiving lines unchanged — the structured pipeline is purely
/// additive.
class CallbackChatLogSink implements ChatLogSink {
  CallbackChatLogSink(this._callback);

  final void Function(String level, String message) _callback;

  @override
  void add(ChatLogRecord record) =>
      _callback(record.level.name, record.format());

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

/// In-memory ring buffer sink. Keeps at most [capacity] records (oldest
/// dropped first) so a long-lived session doesn't grow the buffer
/// unbounded. [export] renders the buffered records — optionally filtered
/// — as plain text, ready to write to a file (see `ChatLogExporter`) or
/// copy to the clipboard.
class BufferChatLogSink implements ChatLogSink {
  BufferChatLogSink({int capacity = 2000})
    : assert(capacity > 0, 'capacity must be positive'),
      _capacity = capacity;

  final int _capacity;
  final List<ChatLogRecord> _records = [];

  /// Snapshot of the currently buffered records, oldest first.
  List<ChatLogRecord> get records => List.unmodifiable(_records);

  @override
  void add(ChatLogRecord record) {
    _records.add(record);
    if (_records.length > _capacity) {
      _records.removeRange(0, _records.length - _capacity);
    }
  }

  /// Renders the buffered records as newline-separated text, oldest first.
  /// [minLevel] and [tags] narrow the export down without mutating the
  /// buffer itself.
  String export({ChatLogLevel? minLevel, Set<ChatLogTag>? tags}) {
    final filtered = _records.where((r) {
      if (minLevel != null && !(r.level >= minLevel)) return false;
      if (tags != null && !tags.contains(r.tag)) return false;
      return true;
    });
    return filtered.map((r) => r.format()).join('\n');
  }

  /// Discards every buffered record.
  void clear() => _records.clear();

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

/// Fans a single [add]/[flush]/[close] call out to every sink in [sinks].
/// Lets a host combine, e.g., a console sink (developer visibility) with a
/// buffer sink (exportable for support) without picking one or the other.
/// A throwing sink is isolated — it does not prevent the others from
/// receiving the record.
class MultiChatLogSink implements ChatLogSink {
  MultiChatLogSink(this.sinks);

  final List<ChatLogSink> sinks;

  @override
  void add(ChatLogRecord record) {
    for (final sink in sinks) {
      try {
        sink.add(record);
      } catch (_) {
        // A sink must never take down logging for its siblings.
      }
    }
  }

  @override
  Future<void> flush() async {
    for (final sink in sinks) {
      try {
        await sink.flush();
      } catch (_) {}
    }
  }

  @override
  Future<void> close() async {
    for (final sink in sinks) {
      try {
        await sink.close();
      } catch (_) {}
    }
  }
}

/// Filters, formats and dispatches [ChatLogRecord]s to a [ChatLogSink].
///
/// Always non-null internally — [ChatConfig] builds one from whatever
/// combination of [ChatConfig.logSink] / [ChatConfig.logger] the host
/// supplied (see `ChatConfig.logs`). Call sites use the tag-specific
/// shortcuts ([ws], [cache], [attach], …) rather than [log] directly so the
/// tag can't be forgotten at the call site.
class ChatLogger {
  ChatLogger({
    required ChatLogSink sink,
    this.minLevel = ChatLogLevel.warn,
    Set<ChatLogTag>? tags,
    bool logMessageContent = false,
  }) : _sink = sink,
       _tags = tags,
       _logMessageContent = logMessageContent;

  final ChatLogSink _sink;
  final Set<ChatLogTag>? _tags;
  final bool _logMessageContent;

  /// Minimum level a record must meet to reach the sink. Records below
  /// this level are dropped before formatting, so a disabled tag/level is
  /// effectively free.
  final ChatLogLevel minLevel;

  /// `true` when a record at [level]/[tag] would be forwarded to the sink.
  bool isEnabled(ChatLogLevel level, ChatLogTag tag) {
    if (!(level >= minLevel)) return false;
    final tags = _tags;
    return tags == null || tags.contains(tag);
  }

  /// Logs one record if [isEnabled] for `(level, tag)`.
  void log(
    ChatLogLevel level,
    ChatLogTag tag,
    String message, {
    Map<String, Object?>? fields,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!isEnabled(level, tag)) return;
    _sink.add(
      ChatLogRecord(
        timestamp: DateTime.now(),
        level: level,
        tag: tag,
        message: message,
        fields: fields,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  /// Redacts [text] unless [ChatConfig.logMessageContent] is `true`. Use at
  /// every call site that would otherwise interpolate raw message/caption
  /// text into a log line (`logs.message(level, 'sent: ${logs.content(text)}')`).
  String content(String? text) {
    if (text == null) return '<null>';
    if (_logMessageContent) return text;
    return '<redacted:${text.length} chars>';
  }

  void ws(ChatLogLevel level, String message, {Map<String, Object?>? fields}) =>
      log(level, ChatLogTag.ws, message, fields: fields);

  void sse(
    ChatLogLevel level,
    String message, {
    Map<String, Object?>? fields,
  }) => log(level, ChatLogTag.sse, message, fields: fields);

  void polling(
    ChatLogLevel level,
    String message, {
    Map<String, Object?>? fields,
  }) => log(level, ChatLogTag.polling, message, fields: fields);

  void cache(
    ChatLogLevel level,
    String message, {
    Map<String, Object?>? fields,
  }) => log(level, ChatLogTag.cache, message, fields: fields);

  void api(
    ChatLogLevel level,
    String message, {
    Map<String, Object?>? fields,
  }) => log(level, ChatLogTag.api, message, fields: fields);

  void http(
    ChatLogLevel level,
    String message, {
    Map<String, Object?>? fields,
  }) => log(level, ChatLogTag.http, message, fields: fields);

  /// Shortcut for [ChatLogTag.attachments].
  void attach(
    ChatLogLevel level,
    String message, {
    Map<String, Object?>? fields,
  }) => log(level, ChatLogTag.attachments, message, fields: fields);

  void presence(
    ChatLogLevel level,
    String message, {
    Map<String, Object?>? fields,
  }) => log(level, ChatLogTag.presence, message, fields: fields);

  void receipts(
    ChatLogLevel level,
    String message, {
    Map<String, Object?>? fields,
  }) => log(level, ChatLogTag.receipts, message, fields: fields);

  void lifecycle(
    ChatLogLevel level,
    String message, {
    Map<String, Object?>? fields,
  }) => log(level, ChatLogTag.lifecycle, message, fields: fields);

  void connection(
    ChatLogLevel level,
    String message, {
    Map<String, Object?>? fields,
  }) => log(level, ChatLogTag.connection, message, fields: fields);

  void room(
    ChatLogLevel level,
    String message, {
    Map<String, Object?>? fields,
  }) => log(level, ChatLogTag.room, message, fields: fields);

  void message(
    ChatLogLevel level,
    String message, {
    Map<String, Object?>? fields,
  }) => log(level, ChatLogTag.message, message, fields: fields);

  void auth(
    ChatLogLevel level,
    String message, {
    Map<String, Object?>? fields,
  }) => log(level, ChatLogTag.auth, message, fields: fields);

  void general(
    ChatLogLevel level,
    String message, {
    Map<String, Object?>? fields,
  }) => log(level, ChatLogTag.general, message, fields: fields);

  /// Flushes the underlying sink — forward this from the client's teardown
  /// path if the sink buffers (e.g. before [ChatLogExporter.exportToFile]).
  Future<void> flush() => _sink.flush();

  /// Releases the underlying sink. Called by `ChatClient.dispose()`.
  Future<void> close() => _sink.close();
}
