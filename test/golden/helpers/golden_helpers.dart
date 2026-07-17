import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';
import 'package:noma_chat/noma_chat.dart';

/// Call once per test main(): stubs the `path_provider` channel that
/// `CachedNetworkImage` reaches into to cache decoded bytes. Without this,
/// bubbles that contain `CachedNetworkImage` either hang for 10 minutes or
/// fail with `MissingPluginException`. Alchemist's own configuration (CI
/// variant disabled, flat `goldens/<name>.png` paths) lives in
/// `test/flutter_test_config.dart` since it must be set before any test
/// zone starts.
void configureGoldenTests() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '/tmp',
      );
}

/// Light theme used by all golden tests by default.
const ChatTheme goldenLightTheme = ChatTheme.defaults;

/// Dark theme shipped with the SDK. Pinned via this alias so a future rename
/// or split keeps the goldens stable.
final ChatTheme goldenDarkTheme = ChatTheme.darkPreset();

/// Wraps a single widget into a MaterialApp with the given background so the
/// golden snapshot has consistent surroundings regardless of the calling
/// test. [darkBackground] is true for dark-theme goldens.
Widget goldenHost(Widget child, {bool darkBackground = false}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: darkBackground ? const Color(0xFF121212) : Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );
}

/// Registers [description] as an Alchemist golden test comparing [child]
/// (wrapped in [goldenHost]) against `goldens/<name>.png`. [darkBackground]
/// is true for dark-theme goldens; [size] is the fixed surface the widget is
/// rendered at, matching this suite's existing baselines.
@isTest
void goldenBubbleTest(
  String description,
  String name,
  Widget child, {
  bool darkBackground = false,
  Size size = const Size(360, 200),
  bool skip = false,
}) {
  goldenTest(
    description,
    fileName: name,
    constraints: BoxConstraints.tight(size),
    builder: () => goldenHost(child, darkBackground: darkBackground),
    skip: skip,
  );
}
