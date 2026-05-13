import 'package:flutter/material.dart';
import '../theme/chat_theme.dart';

/// Bottom sheet with attach options (camera / gallery / file / location).
class AttachmentPickerSheet extends StatelessWidget {
  const AttachmentPickerSheet({
    super.key,
    this.onPickCamera,
    this.onPickGallery,
    this.onPickFile,
    this.cameraLabel = 'Camera',
    this.galleryLabel = 'Gallery',
    this.fileLabel = 'File',
    this.theme = ChatTheme.defaults,
  });

  final VoidCallback? onPickCamera;
  final VoidCallback? onPickGallery;
  final VoidCallback? onPickFile;
  final String cameraLabel;
  final String galleryLabel;
  final String fileLabel;
  final ChatTheme theme;

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onPickCamera,
    VoidCallback? onPickGallery,
    VoidCallback? onPickFile,
    ChatTheme theme = ChatTheme.defaults,
  }) {
    return showModalBottomSheet(
      context: context,
      builder: (_) => AttachmentPickerSheet(
        onPickCamera: onPickCamera,
        onPickGallery: onPickGallery,
        onPickFile: onPickFile,
        cameraLabel: theme.l10n.camera,
        galleryLabel: theme.l10n.gallery,
        fileLabel: theme.l10n.file,
        theme: theme,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _PickerOption(
              icon: Icons.camera_alt,
              label: cameraLabel,
              circleColor: theme.attachmentPickerCircleColor,
              iconColor: theme.attachmentPickerIconColor,
              labelStyle: theme.attachmentPickerLabelStyle,
              onTap: () {
                Navigator.pop(context);
                onPickCamera?.call();
              },
            ),
            _PickerOption(
              icon: Icons.photo_library,
              label: galleryLabel,
              circleColor: theme.attachmentPickerCircleColor,
              iconColor: theme.attachmentPickerIconColor,
              labelStyle: theme.attachmentPickerLabelStyle,
              onTap: () {
                Navigator.pop(context);
                onPickGallery?.call();
              },
            ),
            _PickerOption(
              icon: Icons.insert_drive_file,
              label: fileLabel,
              circleColor: theme.attachmentPickerCircleColor,
              iconColor: theme.attachmentPickerIconColor,
              labelStyle: theme.attachmentPickerLabelStyle,
              onTap: () {
                Navigator.pop(context);
                onPickFile?.call();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerOption extends StatelessWidget {
  const _PickerOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.circleColor,
    this.iconColor,
    this.labelStyle,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? circleColor;
  final Color? iconColor;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: circleColor ?? Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: iconColor),
          ),
          const SizedBox(height: 8),
          Text(label, style: labelStyle ?? const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
