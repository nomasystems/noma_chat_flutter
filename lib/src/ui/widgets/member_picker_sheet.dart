import 'dart:async';

import 'package:flutter/material.dart';

import '../../client/chat_client.dart';
import '../../core/pagination.dart';
import '../../models/contact.dart';
import '../l10n/chat_ui_localizations.dart';
import '../theme/chat_theme.dart';
import 'user_avatar.dart';

/// Bottom-sheet contact picker designed to drive the "Add members" flow
/// of a group room. Multi-select with confirm button.
///
/// Consumer wiring:
/// ```dart
/// await MemberPickerSheet.show(
///   context: context,
///   client: chat.client,
///   excludeIds: currentMemberIds,
///   displayNameResolver: (id) => chat.adapter.findCachedUser(id)?.displayName,
///   avatarUrlResolver: (id) => chat.adapter.findCachedUser(id)?.avatarUrl,
///   onConfirm: (selected) =>
///       chat.adapter.rooms.addMembers(roomId, selected.toList()),
///   theme: theme,
/// );
/// ```
///
/// The picker pulls the current user's contacts via [ChatContactsApi.list]
/// and filters out [excludeIds] (typically the room's current members
/// plus the local user). It does NOT call any room API itself —
/// [onConfirm] is what mutates room state, so apps can choose between
/// `adapter.addMembers`, a domain-specific use case (WB), or any custom
/// path.
class MemberPickerSheet {
  MemberPickerSheet._();

  static Future<void> show({
    required BuildContext context,
    required ChatClient client,
    required Set<String> excludeIds,
    required Future<void> Function(Set<String> selectedUserIds) onConfirm,
    ChatTheme theme = ChatTheme.defaults,
    String? Function(String userId)? displayNameResolver,
    String? Function(String userId)? avatarUrlResolver,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _MemberPickerBody(
        client: client,
        excludeIds: excludeIds,
        onConfirm: onConfirm,
        theme: theme,
        displayNameResolver: displayNameResolver,
        avatarUrlResolver: avatarUrlResolver,
      ),
    );
  }
}

class _MemberPickerBody extends StatefulWidget {
  const _MemberPickerBody({
    required this.client,
    required this.excludeIds,
    required this.onConfirm,
    required this.theme,
    required this.displayNameResolver,
    required this.avatarUrlResolver,
  });

  final ChatClient client;
  final Set<String> excludeIds;
  final Future<void> Function(Set<String>) onConfirm;
  final ChatTheme theme;
  final String? Function(String userId)? displayNameResolver;
  final String? Function(String userId)? avatarUrlResolver;

  @override
  State<_MemberPickerBody> createState() => _MemberPickerBodyState();
}

class _MemberPickerBodyState extends State<_MemberPickerBody> {
  List<ChatContact>? _contacts;
  bool _loading = false;
  bool _submitting = false;
  String? _error;
  final Set<String> _selected = <String>{};
  // Local fallback cache: user profiles we fetched after loading the
  // contact list (because the host resolver couldn't name them). Reads
  // are checked here first so the friendly name appears even when the
  // host's user cache hasn't seen this contact yet.
  final Map<String, String> _resolvedNames = <String, String>{};
  final Map<String, String> _resolvedAvatars = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.client.contacts.list(
      pagination: const ChatPaginationParams(limit: 100),
    );
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _loading = false;
        _error = failure.toString();
      }),
      (paginated) {
        setState(() {
          _loading = false;
          _contacts = paginated.items
              .where(
                (c) =>
                    c.userId.isNotEmpty &&
                    !widget.excludeIds.contains(c.userId),
              )
              .toList();
        });
        unawaited(_warmMissingProfiles());
      },
    );
  }

  /// For every contact whose displayName the host resolver can't name,
  /// fetch the profile via `users.get` and store it locally. Re-renders
  /// once the batch lands so the rows flip from raw id to the friendly
  /// label without forcing the host to re-seed its cache.
  Future<void> _warmMissingProfiles() async {
    final contacts = _contacts;
    if (contacts == null) return;
    final missing = <String>[
      for (final c in contacts)
        if ((widget.displayNameResolver?.call(c.userId)?.trim().isNotEmpty ??
                false) ==
            false)
          c.userId,
    ];
    if (missing.isEmpty) return;
    final fetched = await Future.wait(
      missing.map((id) => widget.client.users.get(id)),
    );
    if (!mounted) return;
    var changed = false;
    for (final res in fetched) {
      final user = res.dataOrNull;
      if (user == null) continue;
      final name = user.displayName?.trim();
      if (name != null && name.isNotEmpty) {
        _resolvedNames[user.id] = name;
        changed = true;
      }
      final avatar = user.avatarUrl?.trim();
      if (avatar != null && avatar.isNotEmpty) {
        _resolvedAvatars[user.id] = avatar;
      }
    }
    if (changed) setState(() {});
  }

  Future<void> _confirm() async {
    if (_selected.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onConfirm(_selected);
    } finally {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.theme.l10n;
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        top: false,
        child: FractionallySizedBox(
          heightFactor: 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.addMembersTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    FilledButton(
                      onPressed: _selected.isEmpty || _submitting
                          ? null
                          : _confirm,
                      child: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.addMembersAction),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildList(l10n)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(ChatUiLocalizations l10n) {
    if (_loading && _contacts == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && (_contacts == null || _contacts!.isEmpty)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    final contacts = _contacts ?? const <ChatContact>[];
    if (contacts.isEmpty) {
      return Center(child: Text(l10n.noContactsAvailable));
    }
    return ListView.separated(
      itemCount: contacts.length,
      separatorBuilder: (_, _) => const Divider(height: 0),
      itemBuilder: (context, index) {
        final contact = contacts[index];
        final userId = contact.userId;
        // Host resolver first (cheap sync read against host's cache);
        // fall back to the local resolved-names map populated by
        // `_warmMissingProfiles` so freshly-fetched profiles flip rows
        // from raw id → friendly name without another host round-trip.
        final resolvedName =
            widget.displayNameResolver?.call(userId) ?? _resolvedNames[userId];
        final displayName =
            (resolvedName != null && resolvedName.trim().isNotEmpty)
            ? resolvedName.trim()
            : userId;
        final avatarUrl =
            widget.avatarUrlResolver?.call(userId) ?? _resolvedAvatars[userId];
        final selected = _selected.contains(userId);
        return CheckboxListTile(
          value: selected,
          onChanged: _submitting
              ? null
              : (v) {
                  setState(() {
                    if (v == true) {
                      _selected.add(userId);
                    } else {
                      _selected.remove(userId);
                    }
                  });
                },
          secondary: UserAvatar(
            imageUrl: avatarUrl,
            displayName: displayName,
            size: 40,
            theme: widget.theme,
            excludeSemantics: true,
          ),
          title: Text(displayName),
          // No `@<uuid>` subtitle. The id is internal — surfacing it
          // looked like a mention-handle but isn't. Mentions resolve
          // via `@<displayName>` in the composer's autocomplete; the
          // id never leaves the SDK.
          subtitle: null,
          controlAffinity: ListTileControlAffinity.trailing,
        );
      },
    );
  }
}
