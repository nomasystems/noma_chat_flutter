import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../client/chat_client.dart';
import '../../core/result.dart';

/// Default "open this attachment" handler the SDK wires when the consumer
/// does not supply its own `onTapFile` / `onTapDoc`.
///
/// Downloads the attachment bytes from [url] (the value the backend put on
/// `ChatMessage.attachmentUrl` / `MediaItem.url`), writes them to a temp file
/// named with the correct extension, and hands the path to the OS via
/// `open_filex`. Opening keys off the on-disk extension, so it works even when
/// the server omits or mislabels the HTTP `Content-Type`.
///
/// Failures never throw into the UI: they are logged through [logger] (when
/// wired) and swallowed, mirroring the SDK's fire-and-forget default callbacks.
Future<void> openAttachmentFile({
  required ChatClient client,
  required String url,
  String? fileName,
  String? mimeType,
  void Function(String level, String message)? logger,
}) async {
  try {
    final result = await client.attachments.downloadFromUrl(url);
    switch (result) {
      case ChatFailureResult(:final failure):
        logger?.call('warn', 'open attachment failed to download: $failure');
        return;
      case ChatSuccess(:final data):
        final dir = await getTemporaryDirectory();
        final name = _tempFileName(fileName: fileName, mimeType: mimeType);
        final file = File('${dir.path}/$name');
        await file.writeAsBytes(data, flush: true);
        final open = await OpenFilex.open(file.path);
        if (open.type != ResultType.done) {
          logger?.call(
            'warn',
            'open attachment failed: ${open.type.name} ${open.message}',
          );
        }
    }
  } catch (e) {
    logger?.call('warn', 'open attachment threw: $e');
  }
}

/// Builds a temp file name with the extension the OS needs to pick a viewer.
///
/// The extension is derived from [fileName] first (it carries the original,
/// most reliable extension); if it has none, it falls back to [mimeType]. The
/// base name is always unique so concurrent opens never collide.
String _tempFileName({String? fileName, String? mimeType}) {
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final fromName = _extensionFromFileName(fileName);
  final ext = fromName ?? _extensionFromMimeType(mimeType);
  return ext == null ? 'noma_attachment_$stamp' : 'noma_attachment_$stamp.$ext';
}

/// Returns the lowercased extension of [fileName] without the dot, or `null`
/// when the name has no usable extension (no dot, trailing dot, or a dot in a
/// leading directory segment only).
String? _extensionFromFileName(String? fileName) {
  final name = fileName?.trim();
  if (name == null || name.isEmpty) return null;
  final base = name.split(RegExp(r'[\\/]')).last;
  final dot = base.lastIndexOf('.');
  if (dot <= 0 || dot == base.length - 1) return null;
  final ext = base.substring(dot + 1).toLowerCase();
  return RegExp(r'^[a-z0-9]+$').hasMatch(ext) ? ext : null;
}

/// Maps a [mimeType] to a file extension for the common attachment types. The
/// subtype is used directly when it already reads like an extension (e.g.
/// `application/pdf` -> `pdf`); a small table covers the cases where it does
/// not. Returns `null` for unknown or empty types so the temp file is written
/// without an extension.
String? _extensionFromMimeType(String? mimeType) {
  final mime = mimeType?.trim().toLowerCase();
  if (mime == null || mime.isEmpty) return null;
  final clean = mime.split(';').first.trim();
  const table = <String, String>{
    'application/pdf': 'pdf',
    'application/msword': 'doc',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        'docx',
    'application/vnd.ms-excel': 'xls',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
    'application/vnd.ms-powerpoint': 'ppt',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation':
        'pptx',
    'application/zip': 'zip',
    'application/x-7z-compressed': '7z',
    'application/x-rar-compressed': 'rar',
    'application/vnd.rar': 'rar',
    'application/gzip': 'gz',
    'application/json': 'json',
    'text/plain': 'txt',
    'text/csv': 'csv',
    'text/html': 'html',
  };
  final mapped = table[clean];
  if (mapped != null) return mapped;
  final slash = clean.indexOf('/');
  if (slash < 0) return null;
  final subtype = clean.substring(slash + 1);
  final candidate = subtype.startsWith('x-')
      ? subtype.substring(2)
      : subtype.replaceAll('+xml', '').replaceAll('+json', '');
  return RegExp(r'^[a-z0-9]{1,8}$').hasMatch(candidate) ? candidate : null;
}
