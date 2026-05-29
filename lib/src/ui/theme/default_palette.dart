import 'package:flutter/material.dart';

/// Hardcoded fallback colors used when a [ChatTheme] field is left as
/// `null`. Centralized here so the look-and-feel stays consistent
/// across widgets that don't share a theme field (banners, separators,
/// muted UI rows).
///
/// Apps that want a different baseline should override the relevant
/// fields in [ChatTheme] — `??`-ing through to these constants is the
/// last-resort default, NOT the recommended way to theme the SDK.
abstract final class DefaultPalette {
  /// Light grey used as background for read-only banners and other
  /// non-interactive surfaces. WhatsApp-equivalent "muted row" tone.
  static const Color mutedSurface = Color(0xFFF5F5F5);

  /// Slightly darker grey used as border between banner and content
  /// area, separating an "advisory" surface from the active chat area.
  static const Color mutedBorder = Color(0xFFE0E0E0);

  /// Default text color used inside [mutedSurface] banners. Neutral
  /// dark grey readable against [mutedSurface] without sRGB warnings.
  static const Color mutedSurfaceText = Color(0xFF333333);

  /// Sender-name accent color used in incoming bubbles when a per-user
  /// color hasn't been resolved. Avoids the "everyone is the same
  /// blue" look in group chats while keeping the default neutral.
  static const Color defaultSenderAccent = Color(0xFF455A64);

  /// Tint of the camera-overlay badge that sits at the bottom-right of
  /// the avatar in [AvatarPickerField]. Falls back to
  /// `Theme.of(context).colorScheme.primary` when consumers want the
  /// brand color instead.
  static const Color avatarBadgeBackground = Color(0xFF1976D2);

  /// Soft red used by [BlockedChatBanner] and other "you are restricted"
  /// surfaces. WhatsApp-equivalent warning tone.
  static const Color warningSurface = Color(0xFFFFEBEE);

  /// Text color used inside [warningSurface] banners.
  static const Color warningSurfaceText = Color(0xFFC62828);
}
