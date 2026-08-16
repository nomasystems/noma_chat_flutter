import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// The gallery is a plain tabbed list, not a chat transcript, so it must not
/// inherit the chat wallpaper — hosts tint that one and it read as a stray
/// grey panel behind the media / documents / links tabs.
void main() {
  const wallpaper = Color(0xFFEFEFEF);
  const surface = Color(0xFFFFFFFF);
  const explicit = Color(0xFF123456);

  Color? resolve(ChatTheme theme) =>
      theme.galleryBackgroundColor ?? theme.galleryAppBarBackgroundColor;

  test('falls back to the gallery app bar, never to the chat wallpaper', () {
    const theme = ChatTheme(
      backgroundColor: wallpaper,
      galleryAppBarBackgroundColor: surface,
    );

    expect(resolve(theme), surface);
    expect(resolve(theme), isNot(wallpaper));
  });

  test('an explicit galleryBackgroundColor wins', () {
    const theme = ChatTheme(
      backgroundColor: wallpaper,
      galleryAppBarBackgroundColor: surface,
      galleryBackgroundColor: explicit,
    );

    expect(resolve(theme), explicit);
  });

  test('stays null so the Scaffold default applies when nothing is themed', () {
    const theme = ChatTheme(backgroundColor: wallpaper);

    expect(resolve(theme), isNull);
  });
}
