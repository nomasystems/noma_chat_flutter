// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.tempPath);
  final String tempPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('chat_log_exporter_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('writes the buffered records to a file and returns its path', () async {
    final buffer = BufferChatLogSink();
    buffer.add(
      ChatLogRecord(
        timestamp: DateTime(2026, 1, 1),
        level: ChatLogLevel.warn,
        tag: ChatLogTag.ws,
        message: 'auth timeout',
      ),
    );

    final path = await ChatLogExporter.exportToFile(
      buffer,
      fileName: 'export_test.txt',
    );

    final file = File(path);
    expect(file.existsSync(), isTrue);
    expect(await file.readAsString(), contains('auth timeout'));
    expect(path, endsWith('export_test.txt'));
  });

  test('applies minLevel/tags filters before writing', () async {
    final buffer = BufferChatLogSink();
    buffer.add(
      ChatLogRecord(
        timestamp: DateTime(2026, 1, 1),
        level: ChatLogLevel.debug,
        tag: ChatLogTag.cache,
        message: 'cache hit',
      ),
    );
    buffer.add(
      ChatLogRecord(
        timestamp: DateTime(2026, 1, 1),
        level: ChatLogLevel.error,
        tag: ChatLogTag.ws,
        message: 'ws error',
      ),
    );

    final path = await ChatLogExporter.exportToFile(
      buffer,
      fileName: 'filtered_export_test.txt',
      minLevel: ChatLogLevel.error,
    );

    final content = await File(path).readAsString();
    expect(content, isNot(contains('cache hit')));
    expect(content, contains('ws error'));
  });
}
