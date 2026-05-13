import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:noma_chat/noma_chat.dart';

/// Call once per test main(): disables `golden_toolkit`'s default image
/// priming and stubs the `path_provider` channel that `CachedNetworkImage`
/// reaches into to cache decoded bytes. Without these, bubbles that contain
/// `CachedNetworkImage` either hang for 10 minutes or fail with
/// `MissingPluginException`.
void configureGoldenTests() {
  // ignore: deprecated_member_use
  GoldenToolkit.configure(
    GoldenToolkitConfiguration(primeAssets: (tester) async {}),
  );
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
final ChatTheme goldenDarkTheme = ChatTheme.dark;

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

/// Pumps [child] in [goldenHost], applies the standard surface size and
/// settles. Use in conjunction with `screenMatchesGolden` from
/// `package:golden_toolkit`.
Future<void> pumpGoldenSurface(
  WidgetTester tester,
  Widget child, {
  bool darkBackground = false,
  Size size = const Size(360, 200),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(goldenHost(child, darkBackground: darkBackground));
  await tester.pump(const Duration(milliseconds: 100));
}
