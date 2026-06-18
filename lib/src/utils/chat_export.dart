/// The result of [ChatMessagesController.exportChat]: a room's history
/// rendered to a single WhatsApp-style plain-text transcript.
///
/// [text] is ready to write to a `.txt` file or copy to the clipboard. The
/// SDK does the heavy lifting (paginating the whole history, resolving
/// sender display names, formatting each line); writing the file and
/// surfacing a share sheet is a couple of lines on the consumer side and
/// is left to the host app so the SDK adds no platform share dependency:
///
/// ```dart
/// final res = await chat.adapter.messages.exportChat(roomId);
/// final export = res.dataOrNull;
/// if (export != null) {
///   final file = File('${(await getTemporaryDirectory()).path}/chat.txt');
///   await file.writeAsString(export.text);
///   await Share.shareXFiles([XFile(file.path)]); // host app's share pkg
/// }
/// ```
class ChatExport {
  const ChatExport({
    required this.roomId,
    required this.text,
    required this.messageCount,
  });

  /// The room whose history was exported.
  final String roomId;

  /// The full transcript, one message per line, oldest first. Empty when
  /// the room has no exportable messages.
  final String text;

  /// Number of messages included in [text].
  final int messageCount;

  @override
  String toString() =>
      'ChatExport(roomId: $roomId, messageCount: $messageCount)';
}
