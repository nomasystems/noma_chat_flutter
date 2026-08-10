import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../_internal/cache/cache_manager.dart' show MetricCallback;
import '../../_internal/ui_debug_log.dart';
import '../utils/platform_support.dart';
import 'icc_colour_profile.dart';

/// Rebuilds a picked image from its pixels, so that nothing else survives.
///
/// This exists because `image_picker_android` copies EXIF from the source
/// file unconditionally whenever it resizes (any `imageQuality < 100`), and
/// offers no flag to suppress it. Without this pass, a photo sent to a room
/// would tell every member who downloads the original where it was taken.
///
/// The mechanism is a decode and a re-encode, not a strip. The bytes are
/// decoded to a pixel buffer and a fresh file is written from that buffer
/// alone; not one byte of the container the user picked reaches the output.
/// That is what makes the property structural rather than a list of things
/// somebody remembered to remove: EXIF and its GPS tags, XMP, IPTC, JUMBF /
/// C2PA, MPF, the ICC profile, embedded thumbnails, comments, the quantisation
/// and Huffman tables, the frame headers, any segment hiding under a marker
/// nobody expected, and every trailing byte past the end of the picture (the
/// MP4 a Motion Photo appends, the second JPEG of an MPO) are all absent for
/// the same reason — they were never copied.
///
/// The rotation is baked into the pixels. `image`'s JPEG decoder applies the
/// source EXIF Orientation itself, all eight values, and hands back an image
/// whose orientation tag is already `null`; re-applying it here would rotate
/// twice. So no orientation tag is written and none is needed — the picture
/// is upright as pixels, which is what `image_picker_android` effectively
/// produces when it resizes.
///
/// Colour survives that rebuild the way orientation does — as a value, never
/// as bytes. The decoder is not colour managed, so the pixels of a Display P3
/// capture come out with the numbers they had and need a profile to be read
/// by. The source profile cannot supply it: forwarding it would reopen exactly
/// the channel this closes. So [IccColourProfile] parses it only far enough to
/// name the space, drops it with the rest of the container, and the output
/// carries a profile built here out of published constants. Display P3 is the
/// one space re-issued; an sRGB source is left untagged, which already means
/// sRGB, and anything else is left untagged and said so through the metric.
///
/// Three things this cannot do, all of which are visible rather than silent:
///
/// - **Colour outside those two spaces is not carried.** An Adobe RGB or
///   Rec. 2020 file loses its profile and its pixels are read as sRGB, so it
///   arrives oversaturated. That is the old behaviour, kept deliberately —
///   converting the pixels would need a colour engine this has no room for,
///   and re-issuing a profile this cannot build from its own constants is the
///   thing being avoided. The metric names it `unrecognised_dropped`.
/// - **Only JPEG and PNG are rebuilt.** They are the two formats that can be
///   written back in the format they arrived in, so the caller's MIME type
///   stays true and a PNG keeps its transparency. HEIC (which carries full
///   EXIF, GPS included), WebP, GIF and TIFF have no encoder here and are
///   passed through untouched under `unsupported_format`. The still-image
///   picker paths ask for `imageQuality < 100`, which makes `image_picker` on
///   iOS transcode HEIC captures to JPEG before this pass sees them; a HEIC
///   attached through the generic file picker is not covered.
/// - **A file it cannot decode is returned exactly as it came**, metadata and
///   all, because corrupting a rare odd-but-valid photo is a worse outcome
///   than leaving metadata on it. That is the one remaining way through: a
///   file crafted so the decoder rejects it travels intact. It does not travel
///   quietly — the outcome is `not_stripped` with the reason, never
///   `stripped`.
///
/// What survives, necessarily, is the picture: anything encoded into the
/// pixels themselves is pixel data, and this rebuilds pixel data faithfully.
/// The re-encode is lossy for JPEG, being a second generation over whatever
/// the picker already wrote, and runs on a background isolate everywhere
/// [PlatformSupport.supportsBackgroundIsolates] is true.
///
/// Every call ends in exactly one `image_metadata_strip` metric on the
/// [MetricCallback] the host wired through `ChatConfig.metricCallback`. There
/// is deliberately no "how much metadata was removed" field: what a decoder
/// hands back does not describe the container it came from — an XMP or IPTC
/// block is dropped without ever being recorded — so any such count would
/// under-report, and on a `stripped` outcome the answer is "all of it" anyway.
/// Nothing is emitted when no callback was wired, no image bytes, file names
/// or paths ever reach one, and a callback that throws is swallowed: a host's
/// telemetry must never decide whether a photo gets sent. See `TELEMETRY.md`.
class ImageMetadataScrubber {
  ImageMetadataScrubber._();

  /// The one metric this class emits. Documented in `TELEMETRY.md`.
  static const String _metric = 'image_metadata_strip';

  /// Every picker path here asks `image_picker` for `imageQuality: 85`, so
  /// these bytes have already been through one lossy pass. Re-encoding at the
  /// same number compounds that loss on a picture that only ever gets
  /// re-shared; 90 buys the headroom back for about 20% more bytes, measured
  /// over a 1200x900 capture.
  static const int _quality = 90;

  /// The chroma sampling phone cameras and `image_picker`'s resize already
  /// write. 4:4:4 would spend ~8% more bytes on colour resolution the source
  /// no longer carries.
  static const img.JpegChroma _chroma = img.JpegChroma.yuv420;

  /// Roughly 150 MB of RGB once decoded: above every phone camera in
  /// circulation and below the dimensions a file crafted to exhaust memory
  /// declares. Read from the header, before any pixel is allocated.
  static const int _maxPixels = 50000000;

  /// Returns [bytes] rebuilt from its pixels alone, or [bytes] itself when the
  /// format is not one this rebuilds or the image cannot be decoded.
  ///
  /// [onMetric] is the host's telemetry sink — pass
  /// `ChatUiAdapter.metricCallback` (which the SDK wires from
  /// `ChatConfig.metricCallback`) so a send that could not be cleaned stops
  /// looking exactly like one that was.
  static Future<Uint8List> scrub(
    Uint8List bytes, {
    MetricCallback? onMetric,
  }) async {
    _ScrubResult result;
    try {
      result = PlatformSupport.supportsBackgroundIsolates
          ? await compute(_rebuild, bytes, debugLabel: 'noma_chat image scrub')
          : _rebuild(bytes);
    } on Object catch (error) {
      uiDebugLog('ImageMetadataScrubber', 'could not run: $error');
      result = const _ScrubResult(null, {
        'outcome': 'not_stripped',
        'reason': 'isolate_failed',
      });
    }
    if (result.bytes == null && result.metric['outcome'] == 'not_stripped') {
      uiDebugLog(
        'ImageMetadataScrubber',
        'left as-is (${result.metric['reason']})',
      );
    }
    _report(onMetric, result.metric);
    return result.bytes ?? bytes;
  }

  /// Hands the outcome to the host without letting the host decide the
  /// outcome: a sink that throws would otherwise surface as an unhandled
  /// async error on the capture path, or as "your photo is unreadable" on the
  /// picker paths.
  static void _report(MetricCallback? onMetric, Map<String, dynamic> data) {
    if (onMetric == null) return;
    try {
      onMetric(_metric, data);
    } on Object catch (error) {
      uiDebugLog('ImageMetadataScrubber', 'metric sink threw: $error');
    }
  }

  /// The whole of the work, as one pure function over bytes so it can be
  /// handed to an isolate. Never throws.
  static _ScrubResult _rebuild(Uint8List bytes) {
    final format = _formatOf(bytes);
    if (format == null) {
      return const _ScrubResult(null, {'outcome': 'unsupported_format'});
    }

    final img.Image image;
    final SourceColourSpace space;
    try {
      final decoder = format == _Format.jpeg
          ? img.JpegDecoder()
          : img.PngDecoder();
      final info = decoder.startDecode(bytes);
      if (info == null) return _failed(format, 'decode_failed');
      if (info.width * info.height > _maxPixels) {
        return _failed(format, 'too_many_pixels');
      }
      // An animated PNG would come back as a single frame, silently losing
      // every other one.
      if (info.numFrames > 1) return _failed(format, 'multi_frame');

      final decoded = decoder.decode(bytes, frame: 0);
      if (decoded == null) return _failed(format, 'decode_failed');
      image = decoded;
      // The only thing taken from the source profile, before it goes the way
      // of the rest of the container.
      space = IccColourProfile.classify(image.iccProfile);
    } on Object {
      return _failed(format, 'decode_failed');
    }

    image
      ..exif = img.ExifData()
      ..iccProfile = null
      ..textData = null;

    Uint8List? out;
    if (space == SourceColourSpace.displayP3) {
      try {
        out = _encode(format, image, IccColourProfile.displayP3);
      } on Object {
        out = null;
      }
    }
    final reissued = out != null;
    if (out == null) {
      try {
        out = _encode(format, image, null);
      } on Object {
        return _failed(format, 'encode_failed');
      }
      if (out == null) return _failed(format, 'encode_failed');
    }

    return _ScrubResult(out, {
      'outcome': 'stripped',
      'format': format.name,
      'colour_profile': _colourOutcome(space, reissued),
    });
  }

  /// A fresh file from [image]'s pixels, carrying [profile] when there is one.
  /// `null` when the profile could not be attached, which leaves the caller to
  /// write the file untagged rather than lose the strip over a colour tag.
  static Uint8List? _encode(
    _Format format,
    img.Image image,
    Uint8List? profile,
  ) {
    if (format == _Format.png) {
      image.iccProfile = profile == null
          ? null
          : img.IccProfile(
              IccColourProfile.pngProfileName,
              img.IccProfileCompression.none,
              profile,
            );
      return img.PngEncoder().encode(image, singleFrame: true);
    }
    final encoded = img.JpegEncoder(
      quality: _quality,
    ).encode(image, chroma: _chroma, singleFrame: true);
    return profile == null
        ? encoded
        : IccColourProfile.attachToJpeg(encoded, profile);
  }

  /// Documented in `TELEMETRY.md`. Says what the output actually carries, not
  /// what the input had: the one thing this must never do is read `stripped`
  /// on a file whose colour was silently left wrong.
  static String _colourOutcome(SourceColourSpace space, bool reissued) =>
      switch (space) {
        SourceColourSpace.absent => 'absent',
        SourceColourSpace.srgb => 'srgb_dropped',
        SourceColourSpace.displayP3 =>
          reissued ? 'display_p3_reissued' : 'display_p3_not_emitted',
        SourceColourSpace.unrecognised => 'unrecognised_dropped',
        SourceColourSpace.unreadable => 'unreadable_dropped',
      };

  static _ScrubResult _failed(_Format format, String reason) => _ScrubResult(
    null,
    {'outcome': 'not_stripped', 'format': format.name, 'reason': reason},
  );

  static _Format? _formatOf(Uint8List bytes) {
    // The start-of-image marker and nothing more, so that a JPEG the decoder
    // would still read is reported as one it could not read rather than one
    // this does not handle.
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return _Format.jpeg;
    }
    const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (bytes.length >= png.length) {
      for (var i = 0; i < png.length; i++) {
        if (bytes[i] != png[i]) return null;
      }
      return _Format.png;
    }
    return null;
  }
}

enum _Format { jpeg, png }

class _ScrubResult {
  const _ScrubResult(this.bytes, this.metric);

  /// `null` when the input was handed back untouched.
  final Uint8List? bytes;
  final Map<String, dynamic> metric;
}
