import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../storage/avatar_storage.dart';
import '../theme/chat_theme.dart';
import 'avatar_picker_sheet.dart';

/// Composable circular avatar with an "edit" affordance overlaid. Tapping
/// the avatar opens [AvatarPickerSheet] and, on success, holds the
/// picked bytes in internal state so the caller can read them on submit.
///
/// Pure UI building block — it does NOT upload. Forms (`OnboardingPage`,
/// `GroupSetupPage`, `ProfileSettingsPage`) take the returned snapshot
/// and pass it to `adapter.updateMyProfile` / `adapter.createGroupRoom`
/// at the appropriate moment.
class AvatarPickerField extends StatefulWidget {
  const AvatarPickerField({
    super.key,
    required this.kind,
    this.initialAvatarUrl,
    this.onChanged,
    this.size = 96,
    this.fallbackInitials,
    this.theme = ChatTheme.defaults,
  });

  final AvatarKind kind;

  /// Existing avatar URL (the user is editing). Shown until the user
  /// picks a new one (or removes it).
  final String? initialAvatarUrl;

  /// Notified every time the staged value changes:
  /// - `(snapshot, false)` after a successful pick + crop.
  /// - `(null, true)` when the user explicitly removed the current avatar.
  /// - `(null, false)` when the change is reverted to "no change" (the
  ///   caller should treat this as "leave field alone").
  final void Function(AvatarSnapshot? snapshot, bool removed)? onChanged;

  final double size;

  /// String used to derive the 1-2 letter fallback when no avatar is
  /// available (Material `CircleAvatar` defaults to grey otherwise).
  final String? fallbackInitials;

  final ChatTheme theme;

  @override
  State<AvatarPickerField> createState() => _AvatarPickerFieldState();
}

class _AvatarPickerFieldState extends State<AvatarPickerField> {
  AvatarSnapshot? _picked;
  bool _removed = false;

  bool get _hasInitial =>
      widget.initialAvatarUrl != null && widget.initialAvatarUrl!.isNotEmpty;

  Future<void> _open() async {
    final outcome = await AvatarPickerSheet.show(
      context: context,
      kind: widget.kind,
      initialAvatarUrl: _removed ? null : widget.initialAvatarUrl,
      theme: widget.theme,
    );
    if (!mounted) return;
    switch (outcome) {
      case AvatarPicked(:final snapshot):
        setState(() {
          _picked = snapshot;
          _removed = false;
        });
        widget.onChanged?.call(snapshot, false);
      case AvatarRemoved():
        setState(() {
          _picked = null;
          _removed = true;
        });
        widget.onChanged?.call(null, true);
      case AvatarPickerCancelled():
        // No-op — user dismissed.
        break;
    }
  }

  Widget _buildAvatar() {
    if (_picked != null) {
      return CircleAvatar(
        radius: widget.size / 2,
        backgroundImage: MemoryImage(_picked!.bytes),
      );
    }
    if (!_removed && _hasInitial) {
      // `asset:<path>` routes to a bundled asset (the mock/demo avatars),
      // mirroring `UserAvatar` — otherwise `CachedNetworkImage` would try to
      // fetch "asset:assets/…" as a URL and render nothing. That's why the
      // group avatar showed in the title bar (UserAvatar) but not here.
      const assetPrefix = 'asset:';
      final url = widget.initialAvatarUrl!;
      final Widget image = url.startsWith(assetPrefix)
          ? Image.asset(
              url.substring(assetPrefix.length),
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(),
            )
          : CachedNetworkImage(
              imageUrl: url,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              placeholder: (_, __) => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              errorWidget: (_, __, ___) => _fallback(),
            );
      return CircleAvatar(
        radius: widget.size / 2,
        backgroundColor: Colors.grey.shade300,
        child: ClipOval(child: image),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    final initials = (widget.fallbackInitials ?? '').trim();
    if (initials.isEmpty) {
      return CircleAvatar(
        radius: widget.size / 2,
        backgroundColor: Colors.grey.shade300,
        child: Icon(
          widget.kind == AvatarKind.user ? Icons.person : Icons.group,
          size: widget.size * 0.5,
          color: Colors.white,
        ),
      );
    }
    return CircleAvatar(
      radius: widget.size / 2,
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: Text(
        initials.length > 2 ? initials.substring(0, 2) : initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: widget.size * 0.35,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Read-only when no `onChanged` is wired — e.g. a group member (not
    // owner/admin) viewing a group they can't manage. Render just the
    // avatar: no camera badge, no tap-to-pick. Without this the edit
    // affordance showed for everyone and members could open the picker even
    // though the change never persisted (onChanged was null all along).
    if (widget.onChanged == null) {
      return _buildAvatar();
    }
    return Semantics(
      button: true,
      label: widget.kind == AvatarKind.user
          ? widget.theme.l10n.profilePhoto
          : widget.theme.l10n.groupPhoto,
      child: GestureDetector(
        onTap: _open,
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            _buildAvatar(),
            Container(
              width: widget.size * 0.32,
              height: widget.size * 0.32,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(
                Icons.photo_camera,
                size: widget.size * 0.18,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
