import 'package:flutter/widgets.dart';
import 'package:noma_chat/noma_chat.dart';

import 'strings/example_strings.dart';

/// Exposes the active `ChatUiLocalizations` plus the parallel
/// [ExampleStrings] bundle (and a setter to change them) to every
/// widget below. Always present at the root so both the onboarding
/// (pre-login) and the home page (post-login) can read from it.
///
/// State is owned by the root [State] of the example app — this
/// widget is just the InheritedWidget that publishes it. The
/// setter is wired so changes persist to `ExampleSettings.languageCode`
/// and propagate via `setState` on the root.
class LocaleProvider extends InheritedWidget {
  const LocaleProvider({
    super.key,
    required this.l10n,
    required this.strings,
    required this.languageCode,
    required this.setLanguageCode,
    required super.child,
  });

  /// Current resolved SDK localisation instance. Always one of the
  /// `ChatUiLocalizations.supportedLanguageCodes`-keyed statics —
  /// never a custom or null value.
  final ChatUiLocalizations l10n;

  /// Example-app strings, matched to the active language code so the
  /// onboarding form, suggestion bar, language picker and error toast
  /// stay in sync with the SDK surfaces above.
  final ExampleStrings strings;

  /// The ISO 639-1 code currently in use (matches a value in
  /// `ChatUiLocalizations.supportedLanguageCodes`).
  final String languageCode;

  /// Persists [newCode] (normalised to a supported code) and
  /// rebuilds the app under the new locale. Re-entrant — safe to
  /// call from any descendant via
  /// `LocaleProvider.of(context).setLanguageCode(...)`.
  final Future<void> Function(String newCode) setLanguageCode;

  static LocaleProvider of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<LocaleProvider>();
    assert(widget != null, 'No LocaleProvider ancestor in widget tree');
    return widget!;
  }

  @override
  bool updateShouldNotify(LocaleProvider oldWidget) =>
      languageCode != oldWidget.languageCode;
}
