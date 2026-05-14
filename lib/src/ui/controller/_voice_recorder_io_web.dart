// Web/WASM stub for the [VoiceRecordingController] filesystem helpers.
//
// Voice recording is currently disabled on Web (the controller's
// `startRecording` short-circuits with `permissionDenied`), so these
// functions are never invoked in practice. They exist so the native
// import path's symbols resolve when the conditional import resolves to
// the web variant — and they avoid touching `dart:io` so the package
// stays WASM-compatible.

import 'dart:typed_data';

/// Throws because Web does not stage recordings on a temp directory; the
/// controller never calls this on Web.
Future<String> voiceRecorderTempPath() async {
  throw UnsupportedError(
    'Voice recording on Web is not implemented yet; '
    'VoiceRecordingController.startRecording returns '
    'StartRecordingResult.permissionDenied before this code runs.',
  );
}

void voiceRecorderCleanupResidualFiles(String dirPath) {
  // No-op on Web.
}

void voiceRecorderDeleteFile(String path) {
  // No-op on Web.
}

Future<Uint8List?> voiceRecorderReadBytes(String path) async => null;
