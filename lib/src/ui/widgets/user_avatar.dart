import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

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
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  Color _resolvePresenceColor() {
    if (presenceStatus != null) {
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
    if (presenceStatus != null) {
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
    final avatar = CircleAvatar(
      radius: size / 2,
      backgroundColor: theme.avatarBackgroundColor ?? Colors.grey.shade300,
      backgroundImage: hasImage ? CachedNetworkImageProvider(imageUrl!) : null,
      child: !hasImage
          ? Text(
              _initials(),
              style:
                  theme.avatarInitialsTextStyle ??
                  TextStyle(
                    fontSize: size * 0.38,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
            )
          : null,
    );

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
