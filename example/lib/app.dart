import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

import 'chat_provider.dart';
import 'chat_session.dart';
import 'locale_provider.dart';
import 'onboarding_page.dart';
import 'pages/home_page.dart';
import 'settings/example_settings.dart';
import 'settings/settings_storage.dart';
import 'strings/example_strings.dart';
import 'widgets/global_error_banner.dart';

class NomaChatExampleApp extends StatefulWidget {
  const NomaChatExampleApp({super.key});

  @override
  State<NomaChatExampleApp> createState() => _NomaChatExampleAppState();
}

/// Top-level messenger key. Hosted on the example's [MaterialApp] so any
/// non-widget code (SDK adapter callbacks) can surface snackbars without
/// needing a BuildContext. Kept module-private to mirror what production
/// hosts typically do — a single key owned by the root.
final GlobalKey<ScaffoldMessengerState> exampleScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

class _NomaChatExampleAppState extends State<NomaChatExampleApp> {
  final _storage = SettingsStorage();
  ExampleSettings _settings = const ExampleSettings();
  NomaChat? _chat;
  bool _bootstrapping = true;
  // True after the user explicitly logs out within this session. Suppresses
  // AUTOLOGIN_AS auto-submit so the user can actually see (and edit) the
  // form instead of getting silently relog-ed with the same harness fixture.

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    var stored = await _storage.load();
    // Defensive migration: older builds persisted the SDK generic `/ws` or a
    // stale SSE path (`/events`, `/v1/events`). CHT serves WS at `/v1/ws` and
    // SSE at `/eventsource` (NRTE); refresh stale persisted paths to current.
    if (stored.wsPath == '/ws' ||
        stored.ssePath == '/events' ||
        stored.ssePath == '/v1/events') {
      const fresh = ExampleSettings();
      stored = stored.copyWith(wsPath: fresh.wsPath, ssePath: fresh.ssePath);
      await _storage.save(stored);
    }
    // First-launch locale detection. When the persisted settings have
    // no `languageCode` yet, sniff the device's primary locale via the
    // platform dispatcher (works pre-MaterialApp because we read the
    // raw platform value, not the `Localizations.localeOf(context)`).
    // `forLanguageCode` normalises to one of the SDK-shipped codes
    // (fallback en), and we persist the resolved value so subsequent
    // boots skip detection entirely. Users can override later from
    // the in-app picker.
    if (stored.languageCode == null) {
      final deviceLocale =
          WidgetsBinding.instance.platformDispatcher.locale.languageCode;
      final resolved = ChatUiLocalizations.forLanguageCode(deviceLocale);
      // `resolved` is one of the static instances; we recover its code
      // by reverse-mapping. Simplest: match against the supported
      // list using `==` against each canonical instance.
      final resolvedCode = _codeForInstance(resolved);
      stored = stored.copyWith(languageCode: resolvedCode);
      await _storage.save(stored);
    }
    var s = stored;
    if (stored == const ExampleSettings()) {
      s = stored.copyWith(mode: chatModeFromEnv());
    }
    s = applySseEnvOverride(s);
    setState(() => _settings = s);

    // Session persistence: if the user logged in on a previous run (and did
    // not log out — logout clears the saved username), restore that session on
    // cold start so they stay logged in. On failure (e.g. backend unreachable)
    // fall through to the onboarding, pre-filled, so they can retry.
    if (s.username.isNotEmpty &&
        s.baseUrl.isNotEmpty &&
        s.realtimeUrl.isNotEmpty) {
      final outcome = await openChatSession(s, onAuthFailure: _onAuthFailure);
      if (!mounted) return;
      if (outcome is LoginSuccess) {
        _wireRoomRemovedSnackbar(outcome.chat);
        setState(() {
          _chat = outcome.chat;
          _bootstrapping = false;
        });
        return;
      }
    }
    if (mounted) setState(() => _bootstrapping = false);
  }

  Future<String?> _onOnboardingSubmit(
    ExampleSettings settings,
    AvatarSnapshot? pickedAvatar,
  ) async {
    final merged = settings.copyWith(
      languageCode: settings.languageCode ?? _settings.languageCode,
    );
    await _storage.save(merged);
    final outcome = await openChatSession(
      merged,
      onAuthFailure: _onAuthFailure,
      pickedAvatar: pickedAvatar,
    );
    if (!mounted) return null;
    switch (outcome) {
      case LoginSuccess(:final chat):
        _wireRoomRemovedSnackbar(chat);
        setState(() {
          _settings = merged;
          _chat = chat;
        });
        return null;
      case LoginAuthFailed(:final message):
        return 'Authentication failed: $message';
      case LoginNetworkFailed(:final message):
        return 'Network error: $message';
      case LoginUnexpected(:final message):
        return message;
    }
  }

  /// Triggered by the SDK when the server signals the account is no
  /// longer valid (401, or 403 with `user_deactivated`). Forces the
  /// example back to onboarding, mirroring how a host app would surface
  /// the login flow.
  bool _authFailureHandling = false;
  void _onAuthFailure() {
    if (_authFailureHandling) return;
    _authFailureHandling = true;
    // Schedule on a microtask so we don't mutate state during a dio
    // interceptor callback (which would risk re-entry).
    Future.microtask(() async {
      try {
        await _onLogout();
      } finally {
        _authFailureHandling = false;
      }
    });
  }

  /// Hooks the SDK's `onRoomRemoved` callback to surface a snackbar when
  /// the user is kicked / banned from a room. The SDK already pops the
  /// chat view (`ChatRoomPage` listens to `roomListController`) and
  /// disposes the controller before this fires, so this is purely the
  /// "tell the user why their room just vanished" hook.
  void _wireRoomRemovedSnackbar(NomaChat chat) {
    chat.adapter.onRoomRemoved = (roomId, reason, adminReason) {
      // Organic deletions (owner deleted the room, etc.) ship null
      // reason — stay silent in that case to avoid noise; the room
      // simply disappears as before.
      if (reason == null) return;
      final detail = (adminReason ?? '').trim();
      // Resolve strings from the persisted language. Done on every
      // invocation rather than captured once because the user can
      // switch language between snackbars.
      final strings = ExampleStrings.forLanguageCode(_settings.languageCode);
      final message = switch (reason) {
        'banned' =>
          detail.isNotEmpty
              ? strings.bannedFromRoomWithReasonTemplate.replaceAll(
                  '{reason}',
                  detail,
                )
              : strings.bannedFromRoom,
        _ =>
          detail.isNotEmpty
              ? strings.leftRoomWithReasonTemplate.replaceAll(
                  '{reason}',
                  detail,
                )
              : strings.leftRoomReasonTemplate.replaceAll('{reason}', reason),
      };
      exampleScaffoldMessengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
    };
  }

  /// Reverse lookup: given a resolved [ChatUiLocalizations] instance,
  /// return the canonical ISO 639-1 code we should persist. Done by
  /// identity against the SDK's static instances — keeps us robust
  /// to future additions: a new locale just needs its code added to
  /// the switch. Falls back to `en`.
  String _codeForInstance(ChatUiLocalizations l10n) {
    if (identical(l10n, ChatUiLocalizations.es)) return 'es';
    if (identical(l10n, ChatUiLocalizations.fr)) return 'fr';
    if (identical(l10n, ChatUiLocalizations.de)) return 'de';
    if (identical(l10n, ChatUiLocalizations.it)) return 'it';
    if (identical(l10n, ChatUiLocalizations.pt)) return 'pt';
    if (identical(l10n, ChatUiLocalizations.ca)) return 'ca';
    return 'en';
  }

  /// Setter exposed via [LocaleProvider.setLanguageCode]. Persists
  /// and triggers a top-level rebuild so the new locale propagates
  /// to every page below — both the chat UI (`l10n` baked into the
  /// theme) and Material widgets (`MaterialApp.locale`).
  Future<void> _setLanguageCode(String newCode) async {
    final resolved = ChatUiLocalizations.forLanguageCode(newCode);
    final canonical = _codeForInstance(resolved);
    if (canonical == _settings.languageCode) return;
    final updated = _settings.copyWith(languageCode: canonical);
    await _storage.save(updated);
    if (!mounted) return;
    setState(() => _settings = updated);
  }

  Future<void> _onLogout() async {
    final current = _chat;
    final cleared = _settings.copyWith(username: '');
    setState(() {
      _chat = null;
      _settings = cleared;
    });
    await _storage.save(cleared);
    await current?.dispose();
  }

  @override
  void dispose() {
    _chat?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo);
    final title = 'Noma Chat — Example';

    // Resolve the active l10n once per build from the persisted code
    // (defaults to en when not yet set — only possible during the
    // very first frames of the cold boot before `_bootstrap` ran).
    final activeCode = _settings.languageCode ?? 'en';
    final activeL10n = ChatUiLocalizations.forLanguageCode(activeCode);
    final activeStrings = ExampleStrings.forLanguageCode(activeCode);

    Widget wrapLocale(Widget child) => LocaleProvider(
      l10n: activeL10n,
      strings: activeStrings,
      languageCode: activeCode,
      setLanguageCode: _setLanguageCode,
      child: child,
    );

    if (_bootstrapping) {
      return wrapLocale(
        MaterialApp(
          title: title,
          theme: theme,
          locale: Locale(activeCode),
          home: const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    }

    final chat = _chat;
    if (chat == null) {
      final prefill = _settings.username.isEmpty
          ? autologinAs()
          : _settings.username;
      final hydratedSettings = _settings.username.isEmpty && prefill.isNotEmpty
          ? _settings.copyWith(username: prefill)
          : _settings;
      return wrapLocale(
        MaterialApp(
          title: title,
          theme: theme,
          locale: Locale(activeCode),
          home: OnboardingPage(
            initialSettings: hydratedSettings,
            autoSubmitOnLoad: false,
            onSubmit: _onOnboardingSubmit,
          ),
        ),
      );
    }

    return wrapLocale(
      ChatProvider(
        chat: chat,
        child: MaterialApp(
          title: title,
          theme: theme,
          locale: Locale(activeCode),
          scaffoldMessengerKey: exampleScaffoldMessengerKey,
          builder: (context, child) => GlobalErrorBanner(child: child!),
          home: HomePage(mode: _settings.mode, onLogout: _onLogout),
        ),
      ),
    );
  }
}
