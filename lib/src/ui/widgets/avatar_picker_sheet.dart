import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../storage/avatar_storage.dart';
import '../services/attachment_pickers.dart';
import '../theme/chat_theme.dart';
import 'avatar_crop_page.dart';
import 'image_viewer.dart';

/// Outcome surfaced by [AvatarPickerSheet.show]. `Picked` carries the
/// post-crop bytes ready for upload; `Removed` is the "clear photo"
/// signal; `Cancelled` is the dismissal default.
sealed class AvatarPickerOutcome {
  const AvatarPickerOutcome();
}

final class AvatarPicked extends AvatarPickerOutcome {
  final AvatarSnapshot snapshot;
  const AvatarPicked(this.snapshot);
}

final class AvatarRemoved extends AvatarPickerOutcome {
  const AvatarRemoved();
}

final class AvatarPickerCancelled extends AvatarPickerOutcome {
  const AvatarPickerCancelled();
}

/// In-memory image bytes plus mime type, ready for upload through
/// [AvatarStorage]. Produced by [AvatarPickerSheet] after the user crops
/// their selection.
class AvatarSnapshot {
  final Uint8List bytes;
  final String mimeType;
  const AvatarSnapshot({required this.bytes, required this.mimeType});
}

/// WhatsApp-style bottom sheet for selecting a profile or group photo.
/// Shows Camera / Gallery / View / Remove rows; the last two appear only
/// when [initialAvatarUrl] is non-null. Selections from camera or
/// gallery are routed through [AvatarCropPage] for a square crop before
/// returning. Cancelling at any step yields [AvatarPickerCancelled].
class AvatarPickerSheet {
  AvatarPickerSheet._();

  static Future<AvatarPickerOutcome> show({
    required BuildContext context,
    required AvatarKind kind,
    String? initialAvatarUrl,
    bool allowRemove = true,
    ChatTheme theme = ChatTheme.defaults,
  }) async {
    final source = await showModalBottomSheet<_Source>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        final errorColor = Theme.of(sheetCtx).colorScheme.error;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Text(
                      kind == AvatarKind.user
                          ? theme.l10n.profilePhoto
                          : theme.l10n.groupPhoto,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(theme.l10n.takePhoto),
                onTap: () => Navigator.of(sheetCtx).pop(_Source.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(theme.l10n.chooseFromGallery),
                onTap: () => Navigator.of(sheetCtx).pop(_Source.gallery),
              ),
              if (initialAvatarUrl != null && initialAvatarUrl.isNotEmpty) ...[
                ListTile(
                  leading: const Icon(Icons.visibility_outlined),
                  title: Text(theme.l10n.viewPhoto),
                  onTap: () => Navigator.of(sheetCtx).pop(_Source.view),
                ),
                if (allowRemove)
                  ListTile(
                    leading: Icon(Icons.delete_outline, color: errorColor),
                    title: Text(
                      theme.l10n.removePhoto,
                      style: TextStyle(color: errorColor),
                    ),
                    onTap: () => Navigator.of(sheetCtx).pop(_Source.remove),
                  ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!context.mounted || source == null) {
      return const AvatarPickerCancelled();
    }
    switch (source) {
      case _Source.camera:
      case _Source.gallery:
        final picked = source == _Source.camera
            ? await AttachmentPickers.pickImageFromCamera()
            : await AttachmentPickers.pickImageFromGallery();
        if (picked == null) return const AvatarPickerCancelled();
        if (!context.mounted) return const AvatarPickerCancelled();
        final cropped = await AvatarCropPage.show(
          context: context,
          sourceBytes: picked.bytes,
          theme: theme,
        );
        if (cropped == null) return const AvatarPickerCancelled();
        return AvatarPicked(
          AvatarSnapshot(bytes: cropped, mimeType: 'image/jpeg'),
        );
      case _Source.view:
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                ImageViewer(imageUrl: initialAvatarUrl!, theme: theme),
          ),
        );
        return const AvatarPickerCancelled();
      case _Source.remove:
        return const AvatarRemoved();
    }
  }
}

enum _Source { camera, gallery, view, remove }
