import 'package:flutter/material.dart';
import '../pages/camera_capture_page.dart';
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
    this.identifier,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Names this row for automation: it becomes both the row's `ValueKey` and
  /// its `Semantics.identifier`, so a test or a native driver can point at
  /// exactly this option regardless of the locale [label] renders in. `null`
  /// falls back to `chat_attachment_option_extra_<position>`, which is stable
  /// only as long as the host keeps [AttachmentPickerSheet.extraOptions] in
  /// the same order — pass a name of your own when that is not guaranteed.
  final String? identifier;

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
    this.title = 'Attach',
    this.theme = ChatTheme.defaults,
  });

  /// Opens the camera. `null` drops the row entirely.
  ///
  /// `NomaChatView` fills this in for you: on Android / iOS with the SDK's
  /// own [CameraCapturePage] (tap for a still, hold for a clip, then confirm
  /// on its review step) and elsewhere with `image_picker`'s system camera,
  /// both sending the confirmed capture to the room. Set
  /// `ChatViewCallbacks.onPickCamera` to take the flow over.
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

  /// Heading shown above the options. Keep it the same wording as the
  /// composer's attach button so both name the same action.
  final String title;

  final ChatTheme theme;

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onPickCamera,
    VoidCallback? onPickGallery,
    VoidCallback? onPickFile,
    VoidCallback? onShareLocation,
    List<AttachmentSheetOption> extraOptions = const [],
    String? title,
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
        cameraLabel: theme.l10nOf(context).camera,
        galleryLabel: theme.l10nOf(context).gallery,
        fileLabel: theme.l10nOf(context).file,
        locationLabel: theme.l10nOf(context).location,
        title: title ?? theme.l10nOf(context).attach,
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
          identifier: 'chat_attachment_option_camera',
        ),
      if (onPickGallery != null)
        AttachmentSheetOption(
          icon: Icons.photo_library,
          label: galleryLabel,
          onTap: onPickGallery!,
          identifier: 'chat_attachment_option_gallery',
        ),
      if (onPickFile != null)
        AttachmentSheetOption(
          icon: Icons.insert_drive_file,
          label: fileLabel,
          onTap: onPickFile!,
          identifier: 'chat_attachment_option_file',
        ),
      if (onShareLocation != null)
        AttachmentSheetOption(
          icon: Icons.location_on,
          label: locationLabel,
          onTap: onShareLocation!,
          identifier: 'chat_attachment_option_location',
        ),
    ];
    final all = [...builtIn, ...extraOptions];

    return Semantics(
      identifier: 'chat_attachment_sheet',
      child: SafeArea(
        key: const ValueKey('chat_attachment_sheet'),
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title.isNotEmpty) ...[
                  Semantics(
                    header: true,
                    identifier: 'chat_attachment_sheet_title',
                    child: Text(
                      title,
                      key: const ValueKey('chat_attachment_sheet_title'),
                      textAlign: TextAlign.start,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Wrap(
                  alignment: WrapAlignment.spaceEvenly,
                  spacing: 16,
                  runSpacing: 20,
                  children: [
                    for (final (index, o) in all.indexed)
                      _PickerOption(
                        key: ValueKey(_optionId(o, index - builtIn.length)),
                        identifier: _optionId(o, index - builtIn.length),
                        icon: o.icon,
                        label: o.label,
                        circleColor:
                            o.circleColor ?? theme.attachmentPickerCircleColor,
                        iconColor:
                            o.iconColor ?? theme.attachmentPickerIconColor,
                        labelStyle: theme.attachmentPickerLabelStyle,
                        previewBuilder: o.previewBuilder,
                        onTap: () {
                          Navigator.pop(context);
                          o.onTap();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _optionId(AttachmentSheetOption option, int extraIndex) =>
      option.identifier ?? 'chat_attachment_option_extra_$extraIndex';
}

class _PickerOption extends StatelessWidget {
  const _PickerOption({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.identifier,
    super.key,
    this.circleColor,
    this.iconColor,
    this.labelStyle,
    this.previewBuilder,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String identifier;
  final Color? circleColor;
  final Color? iconColor;
  final TextStyle? labelStyle;
  final WidgetBuilder? previewBuilder;

  @override
  Widget build(BuildContext context) {
    final builder = previewBuilder;
    return Semantics(
      identifier: identifier,
      child: GestureDetector(
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
      ),
    );
  }
}
