import 'package:flutter/material.dart';

import '../../storage/avatar_storage.dart';
import '../adapter/chat_ui_adapter.dart';
import '../room_defaults.dart';
import '../theme/chat_theme.dart';
import '../utils/initials.dart';
import 'avatar_picker_field.dart';
import 'avatar_picker_sheet.dart';

/// WhatsApp-style "My profile" page: large avatar at the top with
/// edit-on-tap (commits immediately) and a batch-edit form for display
/// name + optional bio/email that surfaces a Save action in the AppBar.
/// The Save button stays disabled until at least one tracked field has
/// pending changes and re-disables itself while the request is in flight.
///
/// Persists through `adapter.profile.update`, which triggers the backend
/// `user_updated` WS fan-out so contacts and rooms with the user see the
/// change automatically — no extra wiring needed on the caller's side.
///
/// `onLogout` is accepted for API compatibility but the SDK no longer
/// renders a logout entry inside the page — render it where it makes
/// sense in your shell (overflow menu, settings list, …).
class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({
    super.key,
    required this.adapter,
    this.theme = ChatTheme.defaults,
    this.onLogout,
    this.showBio = true,
    this.showEmail = false,
    this.minDisplayNameLength = RoomDefaults.minDisplayNameLength,
  });

  final ChatUiAdapter adapter;
  final ChatTheme theme;

  /// Kept for API compatibility — the page used to render a logout list
  /// tile at the bottom that invoked this callback. The tile was removed
  /// (callers usually want logout in their app shell, not buried inside
  /// the profile editor); the field is unused for now and may be removed
  /// in a future major version.
  final VoidCallback? onLogout;
  final bool showBio;
  final bool showEmail;
  final int minDisplayNameLength;

  static Future<void> show({
    required BuildContext context,
    required ChatUiAdapter adapter,
    ChatTheme theme = ChatTheme.defaults,
    VoidCallback? onLogout,
    bool showBio = true,
    bool showEmail = false,
    int minDisplayNameLength = RoomDefaults.minDisplayNameLength,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProfileSettingsPage(
          adapter: adapter,
          theme: theme,
          onLogout: onLogout,
          showBio: showBio,
          showEmail: showEmail,
          minDisplayNameLength: minDisplayNameLength,
        ),
      ),
    );
  }

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _emailController;
  late String _originalName;
  late String _originalBio;
  late String _originalEmail;
  bool _avatarRemoved = false;
  bool _saving = false;
  // Resolved avatarUrl. Starts with whatever the adapter has (could be
  // null right after login when the create/update has not yet
  // propagated to `adapter.currentUser`) and gets refreshed from the
  // backend in `_refreshFromBackend`. Avoids the "no foto al entrar a
  // settings hasta que la cambias" symptom: the adapter's currentUser
  // is built in `chat_session.dart` without avatarUrl/bio because the
  // upload happens after `NomaChat.create()`.
  String? _resolvedAvatarUrl;

  @override
  void initState() {
    super.initState();
    final me = widget.adapter.currentUser;
    _originalName = me.displayName ?? '';
    _originalBio = me.bio ?? '';
    _originalEmail = me.email ?? '';
    _resolvedAvatarUrl = me.avatarUrl;
    _nameController = TextEditingController(text: _originalName)
      ..addListener(_onFieldChanged);
    _bioController = TextEditingController(text: _originalBio)
      ..addListener(_onFieldChanged);
    _emailController = TextEditingController(text: _originalEmail)
      ..addListener(_onFieldChanged);
    _refreshFromBackend();
  }

  Future<void> _refreshFromBackend() async {
    final me = widget.adapter.currentUser;
    final result = await widget.adapter.client.users.get(me.id);
    if (!mounted || result.isFailure) return;
    final fresh = result.dataOrThrow;
    setState(() {
      if (fresh.avatarUrl != null && fresh.avatarUrl!.isNotEmpty) {
        _resolvedAvatarUrl = fresh.avatarUrl;
      }
      final freshBio = fresh.bio ?? '';
      if (_originalBio != freshBio && _bioController.text == _originalBio) {
        _originalBio = freshBio;
        _bioController.text = freshBio;
      }
      final freshEmail = fresh.email ?? '';
      if (_originalEmail != freshEmail &&
          _emailController.text == _originalEmail) {
        _originalEmail = freshEmail;
        _emailController.text = freshEmail;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    // Rebuild so the Save action enables/disables as the user types.
    if (mounted) setState(() {});
  }

  bool get _nameValid =>
      _nameController.text.trim().length >= widget.minDisplayNameLength;

  bool get _isDirty {
    return _nameController.text.trim() != _originalName.trim() ||
        _bioController.text.trim() != _originalBio.trim() ||
        _emailController.text.trim() != _originalEmail.trim();
  }

  bool get _canSave => _isDirty && _nameValid && !_saving;

  Future<void> _saveAll() async {
    if (!_canSave) return;
    final newName = _nameController.text.trim();
    final newBio = _bioController.text.trim();
    final newEmail = _emailController.text.trim();
    final res = await _save(
      displayName: newName != _originalName.trim() ? newName : null,
      bio: widget.showBio && newBio != _originalBio.trim() ? newBio : null,
      email: widget.showEmail && newEmail != _originalEmail.trim()
          ? newEmail
          : null,
      showSuccessToast: true,
    );
    if (!mounted) return;
    if (res) {
      setState(() {
        _originalName = newName;
        _originalBio = newBio;
        _originalEmail = newEmail;
      });
    }
  }

  Future<void> _onAvatarChanged(AvatarSnapshot? snapshot, bool removed) async {
    setState(() => _avatarRemoved = removed);
    await _save(newAvatar: snapshot, removeAvatar: removed);
  }

  Future<bool> _save({
    String? displayName,
    AvatarSnapshot? newAvatar,
    bool removeAvatar = false,
    String? bio,
    String? email,
    bool showSuccessToast = false,
  }) async {
    setState(() => _saving = true);
    final result = await widget.adapter.profile.update(
      displayName: displayName,
      newAvatarBytes: newAvatar?.bytes,
      newAvatarMimeType: newAvatar?.mimeType,
      removeAvatar: removeAvatar,
      bio: bio,
      email: email,
    );
    if (!mounted) return false;
    setState(() {
      _saving = false;
      if (result.isSuccess) {
        _avatarRemoved = false;
      }
    });
    if (result.isFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.theme.l10n.photoUploadFailed)),
      );
      return false;
    }
    if (showSuccessToast) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.theme.l10n.changesSaved),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.theme.l10n;
    final me = widget.adapter.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profile),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: l10n.save,
            onPressed: _canSave ? _saveAll : null,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        children: [
          Center(
            child: AvatarPickerField(
              kind: AvatarKind.user,
              initialAvatarUrl: _avatarRemoved
                  ? null
                  : (_resolvedAvatarUrl ?? me.avatarUrl),
              fallbackInitials: initialsOf(me.displayName),
              size: 140,
              theme: widget.theme,
              onChanged: _onAvatarChanged,
            ),
          ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.yourName,
                helperText: l10n.minCharsTemplate.replaceAll(
                  '{n}',
                  '${widget.minDisplayNameLength}',
                ),
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveAll(),
            ),
          ),
          if (widget.showBio) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: _bioController,
                decoration: InputDecoration(
                  labelText: l10n.about,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _saveAll(),
              ),
            ),
          ],
          if (widget.showEmail) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _saveAll(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
