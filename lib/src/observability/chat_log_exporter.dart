import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'chat_logger.dart';

/// Writes a [BufferChatLogSink]'s records to a shareable file.
///
/// Intended for the "export log" button of a diagnostics build: the host
/// app calls [exportToFile], gets back an absolute path in the temp
/// directory, and hands it to a share sheet (`share_plus`, `Share.shareXFiles`,
/// …) so the user can send the log with one tap. The SDK deliberately does
/// not depend on a share package itself — writing the file is the SDK's
/// job, presenting the share sheet is the host's.
class ChatLogExporter {
  const ChatLogExporter._();

  /// Renders [buffer]'s records (optionally filtered by [minLevel]/[tags])
  /// to plain text and writes them to [fileName] inside the platform temp
  /// directory. Returns the absolute file path.
  static Future<String> exportToFile(
    BufferChatLogSink buffer, {
    String fileName = 'noma_chat_log.txt',
    ChatLogLevel? minLevel,
    Set<ChatLogTag>? tags,
  }) async {
    final text = buffer.export(minLevel: minLevel, tags: tags);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(text, flush: true);
    return file.path;
  }
}
