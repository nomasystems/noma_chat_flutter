import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';

import '../theme/chat_theme.dart';

/// Square-aspect-ratio crop using `image_cropper`'s native UIs
/// (TOCropViewController on iOS, UCrop on Android). The picked image is
/// dumped to a temp file because the plugin only operates on file paths,
/// then re-read as bytes for the SDK upload pipeline.
class AvatarCropPage {
  AvatarCropPage._();

  /// Returns the cropped JPEG bytes, or `null` when the user cancels.
  /// `compressQuality` defaults to 85 — visually indistinguishable from
  /// the source on a typical 96-256px avatar render but ~3-5x smaller.
  static Future<Uint8List?> show({
    required BuildContext context,
    required Uint8List sourceBytes,
    int compressQuality = 85,
    ChatTheme theme = ChatTheme.defaults,
  }) async {
    File? tempFile;
    try {
      final tempDir = await getTemporaryDirectory();
      tempFile = File(
        '${tempDir.path}/noma_avatar_${DateTime.now().microsecondsSinceEpoch}',
      );
      await tempFile.writeAsBytes(sourceBytes, flush: true);
      final cropped = await ImageCropper().cropImage(
        sourcePath: tempFile.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: compressQuality,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: theme.l10n.cropPhoto,
            initAspectRatio: CropAspectRatioPreset.square,
            aspectRatioPresets: const [CropAspectRatioPreset.square],
            lockAspectRatio: true,
            hideBottomControls: true,
            cropStyle: CropStyle.circle,
          ),
          IOSUiSettings(
            title: theme.l10n.cropPhoto,
            aspectRatioLockEnabled: true,
            aspectRatioPickerButtonHidden: true,
            resetButtonHidden: true,
            rotateButtonsHidden: false,
            cropStyle: CropStyle.circle,
            minimumAspectRatio: 1.0,
          ),
          // Web settings deliberately left at library defaults: the
          // demo + the WB consumers ship iOS/Android only; the web
          // delegate signature has churned across cropper releases.
        ],
      );
      if (cropped == null) return null;
      return await cropped.readAsBytes();
    } finally {
      try {
        await tempFile?.delete();
      } catch (_) {
        // Best-effort cleanup; the OS will reclaim temp eventually.
      }
    }
  }
}
