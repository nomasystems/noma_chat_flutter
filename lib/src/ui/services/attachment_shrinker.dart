import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../_internal/ui_debug_log.dart';
import '../adapter/chat_ui_adapter.dart'
    show AttachmentShrinker, ShrunkAttachment;
import '../models/attachment_policy.dart' show AttachmentPolicy, ShrinkStep;
import '../utils/platform_support.dart';

/// An [AttachmentShrinker] whose downscale ladder can be swapped for the one
/// an [AttachmentPolicy] carries.
///
/// [AttachmentShrinker.fit] receives only the resolved byte cap, so an
/// engine that wants [AttachmentPolicy.shrinkSteps] to be the source of its
/// cascade implements this and gets re-configured with the policy's list
/// right before it runs. An engine that doesn't implement it keeps its own
/// ladder, which is the right answer for a host wrapping a native encoder
/// with a fixed set of presets.
abstract interface class PolicyConfigurableShrinker {
  /// This engine, configured to try [steps] in order. Implementations
  /// return a new instance rather than mutating, so one shrinker can serve
  /// several policies at once.
  AttachmentShrinker withShrinkSteps(List<ShrinkStep> steps);
}

/// The SDK's own [AttachmentShrinker], built on `package:image` — the same
/// dependency [ImageMetadataScrubber] already carries, so wiring this in
/// adds no new package to a host's dependency tree.
///
/// Every [AttachmentPickers] entry point defaults to it, so a host calling
/// the pickers gets shrinking out of the box; opting out is
/// `AttachmentPolicy.copyWith(shrinkEnabled: false)` for a single policy, or
/// passing `shrinker: const NoAttachmentShrinker()` to send exactly the
/// bytes the user picked.
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
class DefaultAttachmentShrinker
    implements AttachmentShrinker, PolicyConfigurableShrinker {
  const DefaultAttachmentShrinker({
    this.steps = AttachmentPolicy.defaultShrinkSteps,
  });

  /// The downscale ladder tried, in order. Defaults to
  /// [AttachmentPolicy.defaultShrinkSteps].
  ///
  /// On a picker path the policy wins: [AttachmentPickers.shrinkToPolicy]
  /// calls [withShrinkSteps] with [AttachmentPolicy.shrinkSteps] before
  /// running the engine, so a policy cloned with `copyWith(shrinkSteps:
  /// [...])` replaces this list. What is set here is what a host gets when
  /// it calls [fit] itself, since [fit] receives only the resolved
  /// `maxBytes` and never the policy.
  final List<ShrinkStep> steps;

  @override
  DefaultAttachmentShrinker withShrinkSteps(List<ShrinkStep> steps) =>
      identical(steps, this.steps)
      ? this
      : DefaultAttachmentShrinker(steps: steps);

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
  /// format they started as. A name that is nothing but an extension
  /// (`.jpeg`) or that is empty has no base to keep, so it becomes
  /// `attachment.jpg` rather than growing a second extension.
  @visibleForTesting
  static String debugJpgName(String fileName) => _asJpgName(fileName);

  static String _asJpgName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot > 0) return '${fileName.substring(0, dot)}.jpg';
    if (dot == 0 || fileName.isEmpty) return 'attachment.jpg';
    return '$fileName.jpg';
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
