/// Broad payload kinds the SDK distinguishes when previewing or grouping
/// attachments. Resolved from the MIME type — see [classifyMime].
///
/// The set is deliberately narrow: the UI Kit only needs to know which
/// renderer / icon / fallback string to pick. Apps wanting finer
/// distinctions (e.g. PDF vs spreadsheet) should branch on `mimeType`
/// directly downstream of this enum.
enum MimeKind {
  /// `image/*` except `image/gif` — still pictures.
  image,

  /// `image/gif` — broken out because GIFs animate and previews label
  /// them differently from regular pictures.
  gif,

  /// `video/*` — typically rendered with a play overlay.
  video,

  /// `audio/*` — voice notes, music, etc. Distinct from [file] so the
  /// audio bubble + media gallery's audio tab can route them together.
  audio,

  /// Anything else (PDF, docs, archives, plain text, application/*,
  /// missing MIME, ...). The default `file_bubble` renderer handles it.
  file,
}

/// Classifies a MIME type string into one of [MimeKind]. Centralised so
/// `MessageList` previews, the room-list last-message preview and the
/// media gallery all use the same buckets instead of re-implementing
/// `startsWith('image/')` checks at each call site.
///
/// `null` and empty / unrecognised inputs fall back to [MimeKind.file]
/// so the caller can rely on a non-null result. Comparisons are
/// case-insensitive (the MIME standard is case-insensitive even though
/// servers usually emit lowercase).
MimeKind classifyMime(String? mime) {
  if (mime == null || mime.isEmpty) return MimeKind.file;
  final lower = mime.toLowerCase();
  if (lower == 'image/gif') return MimeKind.gif;
  if (lower.startsWith('image/')) return MimeKind.image;
  if (lower.startsWith('video/')) return MimeKind.video;
  if (lower.startsWith('audio/')) return MimeKind.audio;
  return MimeKind.file;
}
