import 'package:flutter/material.dart';
import '../theme/chat_theme.dart';

/// One row inside [AttachmentPickerSheet]. Used both for the built-in
/// Camera/Gallery/File/Location options and to inject app-specific
/// extras (e.g. "Send contact card", "Send poll", "Share plan").
///
/// The sheet pops itself before invoking [onTap], so the consumer's
/// callback always runs against a "clean" navigation stack.
class AttachmentSheetOption {
  const AttachmentSheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.circleColor,
    this.previewBuilder,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Overrides the theme's `attachmentPickerIconColor` for this row only.
  final Color? iconColor;

  /// Overrides the theme's `attachmentPickerCircleColor` for this row only.
  final Color? circleColor;

  /// Replaces the default icon-in-a-circle visual for this row with a
  /// custom widget — e.g. a thumbnail, an avatar stack, or a badge. Receives
  /// the same [BuildContext] the sheet builds with. Sized to the same
  /// 56x56 slot as the default circle so custom rows line up with built-in
  /// ones in the [Wrap] layout. When `null`, the row falls back to the
  /// default icon/circleColor rendering.
  final WidgetBuilder? previewBuilder;
}

/// Bottom sheet with attach options.
///
/// Defaults to Camera + Gallery + File. The optional [onShareLocation]
/// adds a 4th built-in row (icon: pin), and [extraOptions] appends any
/// number of custom rows after that. Each enabled row only renders
/// when its callback is non-null, so a sheet with only Gallery + Location
/// looks tight and natural.
class AttachmentPickerSheet extends StatelessWidget {
  const AttachmentPickerSheet({
    super.key,
    this.onPickCamera,
    this.onPickGallery,
    this.onPickFile,
    this.onShareLocation,
    this.extraOptions = const [],
    this.cameraLabel = 'Camera',
    this.galleryLabel = 'Gallery',
    this.fileLabel = 'File',
    this.locationLabel = 'Location',
    this.theme = ChatTheme.defaults,
  });

  final VoidCallback? onPickCamera;
  final VoidCallback? onPickGallery;
  final VoidCallback? onPickFile;

  /// When non-null, a "Location" row is rendered alongside the
  /// built-in pickers. Apps that want to wire a maps picker hook it
  /// here and the SDK keeps the sheet visually consistent.
  final VoidCallback? onShareLocation;

  /// Additional rows appended after the built-in options. Useful for
  /// app-specific actions (contact cards, polls, plan attachments, …).
  final List<AttachmentSheetOption> extraOptions;

  final String cameraLabel;
  final String galleryLabel;
  final String fileLabel;
  final String locationLabel;
  final ChatTheme theme;

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onPickCamera,
    VoidCallback? onPickGallery,
    VoidCallback? onPickFile,
    VoidCallback? onShareLocation,
    List<AttachmentSheetOption> extraOptions = const [],
    ChatTheme theme = ChatTheme.defaults,
  }) {
    return showModalBottomSheet(
      context: context,
      // Stretch edge-to-edge so the picker spans the full screen width
      // (the user noticed it was inset). `showDragHandle` + rounded top
      // corners match WhatsApp's attachment picker presentation.
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => AttachmentPickerSheet(
        onPickCamera: onPickCamera,
        onPickGallery: onPickGallery,
        onPickFile: onPickFile,
        onShareLocation: onShareLocation,
        extraOptions: extraOptions,
        cameraLabel: theme.l10n.camera,
        galleryLabel: theme.l10n.gallery,
        fileLabel: theme.l10n.file,
        locationLabel: theme.l10n.location,
        theme: theme,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final builtIn = <AttachmentSheetOption>[
      if (onPickCamera != null)
        AttachmentSheetOption(
          icon: Icons.camera_alt,
          label: cameraLabel,
          onTap: onPickCamera!,
        ),
      if (onPickGallery != null)
        AttachmentSheetOption(
          icon: Icons.photo_library,
          label: galleryLabel,
          onTap: onPickGallery!,
        ),
      if (onPickFile != null)
        AttachmentSheetOption(
          icon: Icons.insert_drive_file,
          label: fileLabel,
          onTap: onPickFile!,
        ),
      if (onShareLocation != null)
        AttachmentSheetOption(
          icon: Icons.location_on,
          label: locationLabel,
          onTap: onShareLocation!,
        ),
    ];
    final all = [...builtIn, ...extraOptions];

    return SafeArea(
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: 16,
            runSpacing: 20,
            children: [
              for (final o in all)
                _PickerOption(
                  icon: o.icon,
                  label: o.label,
                  circleColor:
                      o.circleColor ?? theme.attachmentPickerCircleColor,
                  iconColor: o.iconColor ?? theme.attachmentPickerIconColor,
                  labelStyle: theme.attachmentPickerLabelStyle,
                  previewBuilder: o.previewBuilder,
                  onTap: () {
                    Navigator.pop(context);
                    o.onTap();
                  },
                ),
            ],
          ),
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
    this.previewBuilder,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? circleColor;
  final Color? iconColor;
  final TextStyle? labelStyle;
  final WidgetBuilder? previewBuilder;

  @override
  Widget build(BuildContext context) {
    final builder = previewBuilder;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: builder != null
                ? builder(context)
                : Container(
                    decoration: BoxDecoration(
                      color: circleColor ?? Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 28, color: iconColor),
                  ),
          ),
          const SizedBox(height: 8),
          Text(label, style: labelStyle ?? const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
