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

/// Deletes the recordings left staged in [dirPath] by an earlier session,
/// keeping [except] (the file the live capture is being written to) and
/// anything younger than [minimumAge] untouched.
///
/// The age floor is what makes this safe to run unawaited. The scan is
/// fired off while a capture is already live, so it can still be draining
/// when a LATER capture stages its own file — and [except] only knows the
/// path that was live when the scan started, which would leave the newer
/// capture to be deleted from under the recorder. Callers pass the longest
/// recording they allow, which covers every capture that ends when it is
/// supposed to, whatever the interleaving and whoever staged it. It also
/// sidesteps comparing paths built by the caller against the ones
/// [Directory.list] emits.
///
/// Not an absolute guarantee: a locked capture keeps writing past the
/// duration cap (the cap only freezes the timer), so one left running for
/// longer than the floor can still be swept by a second composer's scan.
/// Closing that hole means capping the capture itself, not the floor.
///
/// Fully asynchronous on purpose: the caller fires it off once the
/// platform recorder is already armed, so neither the directory scan nor
/// the deletes can stall the frame that paints the recording row.
/// Best-effort — any transient filesystem error is swallowed because
/// cleanup is only meant to keep stale recordings from accumulating on
/// disk.
Future<void> voiceRecorderCleanupResidualFiles(
  String dirPath, {
  String? except,
  Duration minimumAge = const Duration(minutes: 5),
}) async {
  try {
    final cutoffMs = DateTime.now().subtract(minimumAge).millisecondsSinceEpoch;
    final residual = await Directory(dirPath)
        .list()
        .where(
          (entity) =>
              entity is File &&
              entity.path != except &&
              _isStagedRecordingOlderThan(entity.path, cutoffMs),
        )
        .toList();
    for (final entity in residual) {
      await entity.delete();
    }
  } catch (_) {}
}

/// Dates a staged recording by its own name — captures are staged as
/// `voice_<millisSinceEpoch>.m4a`, so no `stat` round-trip is needed (and
/// `stat` is exactly what `avoid_slow_async_io` tells us not to await).
/// A name that carries no readable timestamp cannot belong to a capture
/// this build staged, so it counts as stale.
bool _isStagedRecordingOlderThan(String path, int cutoffMs) {
  final name = path.split(Platform.pathSeparator).last;
  if (!name.startsWith('voice_') || !name.endsWith('.m4a')) return false;
  final stamp = int.tryParse(name.substring('voice_'.length, name.length - 4));
  return stamp == null || stamp < cutoffMs;
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
