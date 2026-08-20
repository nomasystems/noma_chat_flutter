import 'dart:collection';
import 'dart:typed_data';

import '../../../models/message.dart';

/// The file behind a failed outgoing media row, kept so a retry can put the
/// same bytes back on the wire.
class RetainedUpload {
  const RetainedUpload({
    required this.roomId,
    required this.bytes,
    required this.mimeType,
    required this.messageType,
    this.fileName,
  });

  /// Room the send was addressed to. A retry re-reads it from here rather
  /// than from the caller, so a row retried from a re-opened chat still
  /// goes where it was headed.
  final String roomId;
  final Uint8List bytes;
  final String mimeType;

  /// [MessageType.attachment] or [MessageType.audio] — decides which send
  /// path the retry re-enters.
  final MessageType messageType;
  final String? fileName;
}

/// Holds the bytes of uploads that failed, keyed by the optimistic row's
/// id, so "Retry" on a failed media bubble means something.
///
/// Without this the only recoverable case is the one the offline queue
/// covers — a connectivity failure, replayed on reconnect. Every other
/// upload failure (a 5xx, a proxy timing the request out, a rejected
/// content type) leaves a failed bubble whose file exists nowhere: the
/// picker handed the bytes over once and the SDK dropped them the moment
/// the upload returned. Retry then has nothing to send and refuses, which
/// is what a user reads as a dead button.
///
/// Deliberately memory-only and deliberately bounded. Raw media on the
/// heap is the expensive kind of state, and a queue of it that survives
/// restarts is the offline queue's job, not this one's — this only has to
/// outlive the failure long enough for the user to look at the red bubble
/// and tap it.
class FailedUploadRegistry {
  FailedUploadRegistry({
    this.maxEntries = 8,
    this.maxBytesPerEntry = 12 * 1024 * 1024,
  });

  /// How many failed uploads are held at once. Past it the oldest is
  /// dropped — its bubble stays failed and its retry falls back to asking
  /// for the file again, exactly as before this registry existed.
  int maxEntries;

  /// Largest single file retained. A bigger one is not held at all: the
  /// heap cost of a long video outweighs saving one re-pick, and the
  /// offline queue applies the same reasoning with its own cap.
  int maxBytesPerEntry;

  final LinkedHashMap<String, RetainedUpload> _entries =
      LinkedHashMap<String, RetainedUpload>();

  /// Retains [upload] under the optimistic row's [tempId]. No-op when the
  /// file is over [maxBytesPerEntry].
  void remember(String tempId, RetainedUpload upload) {
    if (upload.bytes.length > maxBytesPerEntry) return;
    if (maxEntries <= 0) return;
    _entries.remove(tempId);
    _entries[tempId] = upload;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// The file retained for [tempId], or `null` when there is none.
  RetainedUpload? peek(String tempId) => _entries[tempId];

  /// Releases [tempId] — the row was retried, discarded, or confirmed.
  void drop(String tempId) {
    _entries.remove(tempId);
  }

  /// Releases everything. Called when the session ends: bytes belonging to
  /// a signed-out user must not outlive them.
  void clear() {
    _entries.clear();
  }

  /// Ids currently retained. Test/diagnostics seam.
  Iterable<String> get retainedIds => _entries.keys;
}
