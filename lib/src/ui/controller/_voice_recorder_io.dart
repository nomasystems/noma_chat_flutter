// Native filesystem helpers used by [VoiceRecordingController].
//
// This file holds every `dart:io` and `path_provider` call. The controller
// imports it conditionally — see `_voice_recorder_io_web.dart` for the Web
// stub — so the rest of the package stays WASM-compatible (`dart:io` is
// unavailable on Web/WASM and pana penalises any transitive import path
// that hits it).

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Returns the absolute path of the OS temporary directory. Used to stage
/// the in-progress recording file before it is read back as bytes and sent.
Future<String> voiceRecorderTempPath() async =>
    (await getTemporaryDirectory()).path;

/// Deletes every `voice_*.m4a` left over in [dirPath]. Best-effort: any
/// transient filesystem error is swallowed because cleanup is only meant
/// to keep stale recordings from accumulating on disk.
void voiceRecorderCleanupResidualFiles(String dirPath) {
  try {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync()) {
      if (entity is File &&
          entity.path.contains('voice_') &&
          entity.path.endsWith('.m4a')) {
        entity.deleteSync();
      }
    }
  } catch (_) {}
}

/// Deletes a single staged recording. Best-effort (see above).
void voiceRecorderDeleteFile(String path) {
  try {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  } catch (_) {}
}

/// Reads the recorded bytes back as a `Uint8List`. Returns `null` when the
/// file disappeared between staging and reading (e.g. user cancelled).
Future<Uint8List?> voiceRecorderReadBytes(String path) async {
  try {
    return await File(path).readAsBytes();
  } on FileSystemException {
    return null;
  }
}
