import 'package:flutter/material.dart';
import '../../models/presence.dart';
import '../theme/chat_theme.dart';

/// Circular user avatar with initials fallback and optional online/presence indicator dot.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.imageUrl,
    this.displayName,
    this.size = 40,
    this.isOnline,
    this.presenceStatus,
    this.theme = ChatTheme.defaults,
    this.excludeSemantics = false,
  });

  final String? imageUrl;
  final String? displayName;
  final double size;
  final bool? isOnline;
  final PresenceStatus? presenceStatus;
  final ChatTheme theme;

  /// When `true`, skips the inner `Semantics(label: displayName)` wrapper.
  /// Useful when the avatar lives inside a parent widget that already
  /// announces the same name (e.g. a `RoomTile` whose outer `Semantics`
  /// labels the row), to avoid duplicate accessibility nodes.
  final bool excludeSemantics;

  String _initials() {
    final name = displayName?.trim() ?? '';
    if (name.isEmpty) return '?';
    final parts = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    // Use `Characters` (grapheme clusters) instead of UTF-16 code units.
    // `parts[0][0]` returns a single UTF-16 code unit — if the name
    // starts with an emoji or any astral-plane character (surrogate
    // pair), the result is an isolated high-surrogate that Flutter's
    // painter refuses to render: "Invalid argument(s): string is not
    // well-formed UTF-16". Reproducible with displayName="🎉 Alice"
    // or any single-emoji name.
    if (parts.length >= 2) {
      return '${_firstGrapheme(parts[0])}${_firstGrapheme(parts[1])}'
          .toUpperCase();
    }
    return _firstGrapheme(parts[0]).toUpperCase();
  }

  static String _firstGrapheme(String s) {
    if (s.isEmpty) return '';
    final chars = s.characters;
    return chars.isEmpty ? '' : chars.first;
  }

  Color _resolvePresenceColor() {
    // Specific status (busy/away/dnd/available) wins over the connection
    // boolean — a user can be "online but busy" and the red dot is the
    // right signal. `offline` as a status, however, is the default the
    // server emits when the user hasn't picked one (`{"status": null}` in
    // the wire format becomes `PresenceStatus.offline` via the DTO's
    // `?? 'offline'` fallback). Treating that as a hard "offline" would
    // override the `isOnline` flag and paint every connected user grey —
    // exactly the symptom observed 2026-05-20 with `bob` seeing `alice`
    // grey despite both being online. Fall through to the boolean in
    // that case.
    if (presenceStatus != null && presenceStatus != PresenceStatus.offline) {
      return switch (presenceStatus!) {
        PresenceStatus.available =>
          theme.presenceAvailableColor ?? Colors.green,
        PresenceStatus.away => theme.presenceAwayColor ?? Colors.amber,
        PresenceStatus.busy => theme.presenceBusyColor ?? Colors.red,
        PresenceStatus.dnd => theme.presenceDndColor ?? Colors.red.shade900,
        PresenceStatus.offline => theme.avatarOfflineColor ?? Colors.grey,
      };
    }
    return isOnline == true
        ? (theme.avatarOnlineColor ?? Colors.green)
        : (theme.avatarOfflineColor ?? Colors.grey);
  }

  String? _presenceSemanticLabel() {
    if (presenceStatus != null && presenceStatus != PresenceStatus.offline) {
      return switch (presenceStatus!) {
        PresenceStatus.available => 'available',
        PresenceStatus.away => 'away',
        PresenceStatus.busy => 'busy',
        PresenceStatus.dnd => 'do not disturb',
        PresenceStatus.offline => 'offline',
      };
    }
    if (isOnline != null) return isOnline! ? 'online' : 'offline';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final initialsLabel = Text(
      _initials(),
      style:
          theme.avatarInitialsTextStyle ??
          TextStyle(
            fontSize: size * 0.38,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
    );
    final bg = theme.avatarBackgroundColor ?? Colors.grey.shade300;
    final initialsCircle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: initialsLabel,
    );
    // `asset:<path>` routes to bundled `AssetImage` for the mock demo
    // (offline, no flaky CDN). Otherwise treat the value as a network
    // URL via `Image.network` — first-class `loadingBuilder` and
    // `errorBuilder` callbacks fall back to initials when the bytes
    // never arrive. Flutter's standard image cache (in-process LRU)
    // covers the network variant; bundled assets are zero-cost.
    Widget buildImageChild() {
      const assetPrefix = 'asset:';
      if (imageUrl!.startsWith(assetPrefix)) {
        return Image.asset(
          imageUrl!.substring(assetPrefix.length),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => initialsCircle,
        );
      }
      return Image.network(
        imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        loadingBuilder: (ctx, child, progress) {
          if (progress == null) return child;
          return initialsCircle;
        },
        errorBuilder: (_, __, ___) => initialsCircle,
      );
    }

    final avatar = hasImage
        ? ClipOval(child: buildImageChild())
        : initialsCircle;

    final String semanticLabel;
    if (displayName != null && displayName!.isNotEmpty) {
      final presenceLabel = _presenceSemanticLabel();
      semanticLabel = presenceLabel != null
          ? '$displayName, $presenceLabel'
          : displayName!;
    } else {
      semanticLabel = 'Avatar';
    }

    if (isOnline == null && presenceStatus == null) {
      if (excludeSemantics) return avatar;
      return Semantics(label: semanticLabel, child: avatar);
    }

    final dotSize = size * 0.3;
    final dotColor = _resolvePresenceColor();
    // Center the dot on the avatar border at 45° (top-right).
    // For radius R = size/2, inset = R*(1 - cos45°) - dotSize/2.
    final dotInset = (size / 2) * (1 - 0.7071) - dotSize / 2;

    final stack = SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: dotInset,
            top: dotInset,
            child: ExcludeSemantics(
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.avatarOnlineBorderColor ?? Colors.white,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (excludeSemantics) return stack;
    return Semantics(label: semanticLabel, child: stack);
  }
}
