import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../_internal/ui_debug_log.dart';
import '../adapter/chat_ui_adapter.dart'
    show AttachmentShrinker, ShrunkAttachment;
import '../models/attachment_policy.dart' show AttachmentPolicy, ShrinkStep;
import '../utils/platform_support.dart';

/// The SDK's own [AttachmentShrinker], built on `package:image` — the same
/// dependency [ImageMetadataScrubber] already carries, so wiring this in
/// adds no new package to a host's dependency tree.
///
/// Not wired by default (`ChatUiAdapter`'s own default is
/// `NoAttachmentShrinker`, so a fresh install sends exactly the bytes the
/// user picked); a host opts in with
/// `ChatUiAdapter(attachmentShrinker: const DefaultAttachmentShrinker())`.
///
/// The algorithm tries [steps] in order — largest [ShrinkStep.maxDimension]
/// first — resizing the decoded image so its longer side is at most that
/// many pixels (never upscaling one that already fits) and re-encoding it
/// as JPEG at that step's quality, stopping at the first result that fits
/// under the `maxBytes` [fit] was called with. A source already under that
/// cap, or a step ladder that runs out without producing a small enough
/// result, both come back as `null` — per [AttachmentShrinker]'s contract,
/// that means "send the original", never "send something still over the
/// cap".
///
/// Three things this never re-encodes, all by design rather than by
/// accident: anything whose `mimeType` doesn't start with `image/` (checked
/// before any byte is decoded, so a non-image is never even opened),
/// anything already at or under the cap, and anything the decoder can't
/// read (a truncated file, a format `package:image` doesn't cover) — the
/// last one comes back as `null` exactly like the other two, so a
/// corrupted-but-small-enough image is never distinguishable from one this
/// class declined to touch.
///
/// The decode/resize/encode pass runs on a background isolate wherever
/// [PlatformSupport.supportsBackgroundIsolates] is `true`; on web it runs
/// inline, same trade-off [ImageMetadataScrubber] makes.
class DefaultAttachmentShrinker implements AttachmentShrinker {
  const DefaultAttachmentShrinker({
    this.steps = AttachmentPolicy.defaultShrinkSteps,
  });

  /// The downscale ladder tried, in order. Defaults to
  /// [AttachmentPolicy.defaultShrinkSteps]; pass a different list to use a
  /// different cascade regardless of what any particular [AttachmentPolicy]
  /// carries — [fit] doesn't receive the policy, only the resolved
  /// `maxBytes`, so this is the one place the ladder is configured.
  final List<ShrinkStep> steps;

  @override
  Future<ShrunkAttachment?> fit(
    Uint8List bytes, {
    required String mimeType,
    required int maxBytes,
    required String fileName,
  }) async {
    if (!mimeType.startsWith('image/')) return null;
    if (bytes.length <= maxBytes) return null;
    if (steps.isEmpty) return null;

    final job = (bytes: bytes, steps: steps, maxBytes: maxBytes);
    Uint8List? out;
    try {
      out = PlatformSupport.supportsBackgroundIsolates
          ? await compute(
              _shrink,
              job,
              debugLabel: 'noma_chat attachment shrink',
            )
          : _shrink(job);
    } on Object catch (error) {
      uiDebugLog('DefaultAttachmentShrinker', 'could not run: $error');
      return null;
    }
    if (out == null) return null;
    return ShrunkAttachment(
      bytes: out,
      mimeType: 'image/jpeg',
      fileName: _asJpgName(fileName),
    );
  }

  /// Swaps whatever extension [fileName] carries (if any) for `.jpg`, since
  /// the bytes coming back are always a JPEG re-encode regardless of what
  /// format they started as.
  static String _asJpgName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final base = (dot > 0) ? fileName.substring(0, dot) : fileName;
    return base.isEmpty ? 'attachment.jpg' : '$base.jpg';
  }
}

/// The single argument [_shrink] runs with, bundled as a record so it
/// crosses the isolate boundary as plain data — no custom class, no
/// closures to reject.
typedef _ShrinkJob = ({Uint8List bytes, List<ShrinkStep> steps, int maxBytes});

/// The whole of the work, as one pure function over bytes so it can be
/// handed to an isolate. Never throws: a decode failure, a resize failure
/// or an encode failure on any given step all fall through to `null` (or
/// the next step), mirroring [ImageMetadataScrubber._rebuild]'s stance that
/// a compression pass must never turn a bad photo into a crash.
Uint8List? _shrink(_ShrinkJob job) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(job.bytes);
  } on Object {
    decoded = null;
  }
  if (decoded == null) return null;

  for (final step in job.steps) {
    try {
      final resized = _resizedToFit(decoded, step.maxDimension);
      final encoded = img.encodeJpg(resized, quality: step.quality);
      if (encoded.length <= job.maxBytes) return encoded;
    } on Object {
      continue;
    }
  }
  return null;
}

/// [source] resized so its longer side is at most [maxDimension] pixels,
/// or [source] itself when it already is — this ladder only ever shrinks,
/// an upscaled re-encode would spend bytes making the image worse.
img.Image _resizedToFit(img.Image source, int maxDimension) {
  final longestSide = source.width >= source.height
      ? source.width
      : source.height;
  if (longestSide <= maxDimension) return source;
  return source.width >= source.height
      ? img.copyResize(
          source,
          width: maxDimension,
          interpolation: img.Interpolation.average,
        )
      : img.copyResize(
          source,
          height: maxDimension,
          interpolation: img.Interpolation.average,
        );
}
