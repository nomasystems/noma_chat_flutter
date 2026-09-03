import 'package:flutter/material.dart';

import '../../cache/cache_policy.dart';
import '../../core/result.dart';
import '../../models/room.dart';
import '../../models/room_user.dart';
import '../../storage/avatar_storage.dart';
import '../adapter/chat_ui_adapter.dart';
import '../room_defaults.dart';
import '../theme/chat_theme.dart';
import '../utils/chat_notice.dart';
import '../utils/initials.dart';
import '../utils/text_selection_menu.dart';
import 'avatar_picker_field.dart';
import 'avatar_picker_sheet.dart';
import 'group_members_view.dart';
import 'member_picker_sheet.dart';

/// WhatsApp-style unified "Group info" page. Replaces the older
/// `GroupInfoEditSheet` (avatar+name only) and `GroupMembersView`
/// (members only) by stacking both in a single full-screen flow:
///
///   - Avatar (tap to change, admin only)
///   - Name (inline edit, admin only)
///   - Members section (read for everyone, add/remove for admins)
///   - Bottom actions: leave group, mute, clear chat, delete chat
class GroupInfoPage extends StatefulWidget {
  const GroupInfoPage({
    super.key,
    required this.adapter,
    required this.roomId,
    this.theme = ChatTheme.defaults,
    this.minNameLength = RoomDefaults.minGroupNameLength,
  });

  final ChatUiAdapter adapter;
  final String roomId;
  final ChatTheme theme;
  final int minNameLength;

  static Future<void> show({
    required BuildContext context,
    required ChatUiAdapter adapter,
    required String roomId,
    ChatTheme theme = ChatTheme.defaults,
    int minNameLength = RoomDefaults.minGroupNameLength,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => GroupInfoPage(
          adapter: adapter,
          roomId: roomId,
          theme: theme,
          minNameLength: minNameLength,
        ),
      ),
    );
  }

  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage>
    with ChatNoticeAnchor<GroupInfoPage> {
  @override
  ChatTheme get noticeTheme => widget.theme;

  RoomDetail? _detail;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final FocusNode _nameFocusNode;
  late final FocusNode _descriptionFocusNode;
  bool _editingName = false;
  bool _editingDescription = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _descriptionController = TextEditingController();
    _nameFocusNode = FocusNode();
    _descriptionFocusNode = FocusNode();
    _loadDetail();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _nameFocusNode.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.adapter.client.rooms.get(
      widget.roomId,
      cachePolicy: CachePolicy.networkFirst,
    );
    if (!mounted) return;
    if (result.isFailure) {
      setState(() {
        _loading = false;
        _error = result.failureOrNull?.message;
      });
      return;
    }
    final detail = result.dataOrThrow;
    setState(() {
      _detail = detail;
      _nameController.text = detail.name ?? '';
      _descriptionController.text = detail.subject ?? '';
      _loading = false;
    });
  }

  Future<void> _commitDescription() async {
    final newDesc = _descriptionController.text.trim();
    if (newDesc == (_detail?.subject ?? '')) {
      _descriptionFocusNode.unfocus();
      setState(() => _editingDescription = false);
      return;
    }
    setState(() => _saving = true);
    final result = await widget.adapter.rooms.updateConfig(
      widget.roomId,
      subject: newDesc.isEmpty ? '' : newDesc,
    );
    if (!mounted) return;
    _descriptionFocusNode.unfocus();
    setState(() {
      _saving = false;
      _editingDescription = false;
    });
    if (result.isSuccess) {
      await _loadDetail();
    } else {
      showNotice(_failureMessage(result));
    }
  }

  bool get _canManage =>
      _detail?.userRole == RoomRole.owner ||
      _detail?.userRole == RoomRole.admin;

  /// Opens the reusable [MemberPickerSheet] to add people to the group.
  /// Excludes the current members (and self) so they can't be re-picked,
  /// then calls `addMembers(..., inviteAndJoin)` and reloads the detail so
  /// the new participants + count show immediately.
  Future<void> _onAddMembers() async {
    final membersRes = await widget.adapter.client.members.list(widget.roomId);
    if (!mounted) return;
    final excludeIds = <String>{
      widget.adapter.currentUser.id,
      ...?membersRes.dataOrNull?.items.map((m) => m.userId),
    };
    await MemberPickerSheet.show(
      context: context,
      client: widget.adapter.client,
      excludeIds: excludeIds,
      theme: widget.theme,
      displayNameResolver: (id) =>
          widget.adapter.findCachedUser(id)?.displayName,
      avatarUrlResolver: (id) => widget.adapter.findCachedUser(id)?.avatarUrl,
      onConfirm: (selected) async {
        if (selected.isEmpty) return;
        final res = await widget.adapter.addMembers(
          widget.roomId,
          selected.toList(),
          mode: RoomUserMode.inviteAndJoin,
        );
        if (res.isSuccess && mounted) {
          await _loadDetail();
        }
      },
    );
  }

  Future<void> _onAvatarChanged(AvatarSnapshot? snapshot, bool removed) async {
    if (snapshot == null && !removed) return;
    setState(() => _saving = true);
    String? avatarUrl;
    if (snapshot != null) {
      final uploadRes = await widget.adapter.profile.uploadAvatar(
        snapshot.bytes,
        snapshot.mimeType,
        AvatarKind.room,
      );
      if (uploadRes.isFailure) {
        if (!mounted) return;
        setState(() => _saving = false);
        showNotice(noticeL10n.photoUploadFailed);
        return;
      }
      avatarUrl = uploadRes.dataOrNull;
    }
    final result = await widget.adapter.rooms.updateConfig(
      widget.roomId,
      avatarUrl: avatarUrl,
      // When the user clears the photo (removed=true with no snapshot),
      // an explicit `clearAvatar` is required: without it the SDK wire
      // omitted `avatarUrl` from the body and the backend kept the old one.
      clearAvatar: removed && snapshot == null,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.isSuccess) {
      await _loadDetail();
    } else {
      showNotice(noticeL10n.photoUploadFailed);
    }
  }

  Future<void> _commitName() async {
    final newName = _nameController.text.trim();
    if (newName.length < widget.minNameLength) return;
    if (newName == _detail?.name) {
      _nameFocusNode.unfocus();
      setState(() => _editingName = false);
      return;
    }
    setState(() => _saving = true);
    final result = await widget.adapter.rooms.updateConfig(
      widget.roomId,
      name: newName,
    );
    if (!mounted) return;
    _nameFocusNode.unfocus();
    setState(() {
      _saving = false;
      _editingName = false;
    });
    if (result.isSuccess) {
      await _loadDetail();
    } else {
      showNotice(_failureMessage(result));
    }
  }

  String _failureMessage(ChatResult<void> r) =>
      r.failureOrNull?.message ?? noticeL10n.photoUploadFailed;

  /// The edit fields stay mounted and are only hidden, so [Visibility]
  /// keeps them out of the focus tree until the row is on screen again.
  /// Claim the focus once that frame has been laid out.
  void _focusOnNextFrame(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) node.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.theme.l10nOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.groupInfo)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _detail == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 24),
              children: [
                Center(
                  child: AvatarPickerField(
                    kind: AvatarKind.room,
                    initialAvatarUrl: _detail!.avatarUrl,
                    fallbackInitials: initialsOf(_detail!.name),
                    size: 160,
                    theme: widget.theme,
                    onMetric: widget.adapter.metricCallback,
                    onChanged: _canManage ? _onAvatarChanged : null,
                  ),
                ),
                const SizedBox(height: 24),
                _buildNameRow(),
                const SizedBox(height: 16),
                _buildDescriptionRow(),
                const Divider(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    '${l10n.groupMembers} (${_detail!.memberCount})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                // Owner/admin entry point to add people. WhatsApp-style
                // "Add members" row at the top of the participant list,
                // opening the reusable [MemberPickerSheet].
                if (_canManage)
                  ListTile(
                    // Match the 40px avatar footprint of the member
                    // rows below so the icon is centered on the avatar
                    // column and the label lines up with the names.
                    leading: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(child: Icon(Icons.person_add_alt_1)),
                    ),
                    title: Text(l10n.addMembers),
                    onTap: _onAddMembers,
                  ),
                GroupMembersView(
                  adapter: widget.adapter,
                  roomId: widget.roomId,
                  currentUserRole: _detail!.userRole,
                  theme: widget.theme,
                  embedded: true,
                  displayNameResolver: (id) =>
                      widget.adapter.findCachedUser(id)?.displayName,
                  avatarUrlResolver: (id) =>
                      widget.adapter.findCachedUser(id)?.avatarUrl,
                  onMemberRemoved: (_) => _loadDetail(),
                  onRoleChanged: (_, __) => _loadDetail(),
                ),
              ],
            ),
    );
  }

  Widget _buildDescriptionRow() {
    final l10n = widget.theme.l10nOf(context);
    final raw = _detail?.subject?.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Visibility(
          visible: !_editingDescription,
          maintainState: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.groupDescription,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        raw.isEmpty ? '—' : raw,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
                if (_canManage)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: l10n.edit,
                    onPressed: () {
                      setState(() => _editingDescription = true);
                      _focusOnNextFrame(_descriptionFocusNode);
                    },
                  ),
              ],
            ),
          ),
        ),
        Visibility(
          visible: _editingDescription,
          maintainState: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _descriptionController,
              focusNode: _descriptionFocusNode,
              contextMenuBuilder: buildTextSelectionMenu,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.groupDescription,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check),
                  tooltip: l10n.save,
                  onPressed: _saving ? null : _commitDescription,
                ),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _commitDescription(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNameRow() {
    final l10n = widget.theme.l10nOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Visibility(
          visible: !_editingName,
          maintainState: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _detail!.name?.isNotEmpty == true ? _detail!.name! : '',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (_canManage)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: l10n.edit,
                    onPressed: () {
                      setState(() => _editingName = true);
                      _focusOnNextFrame(_nameFocusNode);
                    },
                  ),
              ],
            ),
          ),
        ),
        Visibility(
          visible: _editingName,
          maintainState: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _nameController,
              focusNode: _nameFocusNode,
              contextMenuBuilder: buildTextSelectionMenu,
              decoration: InputDecoration(
                labelText: l10n.groupName,
                helperText: l10n.minCharsTemplate.replaceAll(
                  '{n}',
                  '${widget.minNameLength}',
                ),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check),
                  tooltip: l10n.save,
                  onPressed: _saving ? null : _commitName,
                ),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _commitName(),
            ),
          ),
        ),
      ],
    );
  }
}
