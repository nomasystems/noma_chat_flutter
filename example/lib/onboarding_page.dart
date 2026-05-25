import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chat_session.dart';
import 'locale_provider.dart';
import 'settings/example_settings.dart';
import 'strings/example_strings.dart';
import 'widgets/language_picker_row.dart';

/// Pre-login screen. Lets the user pick mode (mock/cht), enter a name and
/// tweak backend config. On submit, calls [onSubmit] with the resolved
/// [ExampleSettings]; the caller is responsible for persisting them and
/// opening the chat session.
///
/// When [initialSettings.username] is non-empty (typically restored from
/// storage) the form is pre-filled with those values.
///
/// When [autoSubmitOnLoad] is true AND the form is valid on first frame,
/// submission is triggered automatically. Used by the harness via
/// `--dart-define=AUTOLOGIN_AS=...` so non-interactive runs skip the form.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.initialSettings,
    required this.autoSubmitOnLoad,
    required this.onSubmit,
  });

  final ExampleSettings initialSettings;
  final bool autoSubmitOnLoad;

  /// Returns null on success (the parent navigates away), or a human-readable
  /// error string to surface in a SnackBar so the user can retry. The
  /// second arg carries the avatar the user picked (null when none).
  final Future<String?> Function(
    ExampleSettings settings,
    AvatarSnapshot? avatar,
  )
  onSubmit;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  late ChatMode _mode;
  late TextEditingController _username;
  AvatarSnapshot? _pickedAvatar;
  late TextEditingController _baseUrl;
  // surface three full URLs in onboarding — Base (REST),
  // WS URL and SSE URL — instead of base + realtime + paths. The
  // SDK still consumes `realtimeUrl + wsPath` internally, but we
  // split the input URLs on submit so the user only types complete
  // endpoints. The Advanced section no longer carries the WS/SSE
  // path fields.
  late TextEditingController _wsUrl;
  late TextEditingController _sseUrl;
  late TextEditingController _requestTimeout;
  late TextEditingController _wsReconnectDelay;
  late TextEditingController _maxReconnect;
  late TextEditingController _eventBuffer;
  late RealtimeMode _realtimeMode;
  late TextEditingController _pollingInterval;
  late bool _pollUnreadOnly;
  late bool _pollOpenRoomMessages;
  late TextEditingController _pollingMaxRoomsPerTick;
  late TextEditingController _sseIdleTimeout;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final s = widget.initialSettings;
    _mode = s.mode;
    _username = TextEditingController(text: s.username);
    _baseUrl = TextEditingController(text: s.baseUrl);
    _wsUrl = TextEditingController(text: _joinUrlPath(s.realtimeUrl, s.wsPath));
    _sseUrl = TextEditingController(
      text: _joinUrlPath(s.sseUrl ?? s.realtimeUrl, s.ssePath),
    );
    _requestTimeout = TextEditingController(
      text: s.requestTimeoutSeconds.toString(),
    );
    _wsReconnectDelay = TextEditingController(
      text: s.wsReconnectDelaySeconds.toString(),
    );
    _maxReconnect = TextEditingController(
      text: s.maxReconnectAttempts?.toString() ?? '',
    );
    _eventBuffer = TextEditingController(text: s.eventBufferSize.toString());
    _realtimeMode = s.realtimeMode;
    _pollingInterval = TextEditingController(
      text: s.pollingIntervalSeconds.toString(),
    );
    _pollUnreadOnly = s.pollUnreadOnly;
    _pollOpenRoomMessages = s.pollOpenRoomMessages;
    _pollingMaxRoomsPerTick = TextEditingController(
      text: s.pollingMaxRoomsPerTick.toString(),
    );
    _sseIdleTimeout = TextEditingController(
      text: s.sseIdleTimeoutSeconds.toString(),
    );

    if (widget.autoSubmitOnLoad && _canSubmit()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _submit());
    }
  }

  /// Joins `realtimeUrl` (`http://host:port`) with a path (`/v1/ws`) into a
  /// single full URL (`http://host:port/v1/ws`). Tolerates trailing slash
  /// in the URL and missing leading slash in the path.
  static String _joinUrlPath(String url, String path) {
    final trimmedUrl = url.replaceFirst(RegExp(r'/+$'), '');
    if (path.isEmpty) return trimmedUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$trimmedUrl$normalizedPath';
  }

  /// Splits a full URL (`http://host:port/v1/ws`) back into `(base, path)`
  /// — `('http://host:port', '/v1/ws')`. Falls back to defaults when the
  /// URL doesn't parse cleanly. Defensive against the user typing a host
  /// without a scheme or with double slashes.
  static (String, String) _splitUrl(String url, {required String defaultPath}) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return ('', defaultPath);
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
      return (trimmed, defaultPath);
    }
    final base = '${uri.scheme}://${uri.authority}';
    final path = uri.path.isEmpty ? defaultPath : uri.path;
    return (base, path);
  }

  @override
  void dispose() {
    _username.dispose();
    _baseUrl.dispose();
    _wsUrl.dispose();
    _sseUrl.dispose();
    _requestTimeout.dispose();
    _wsReconnectDelay.dispose();
    _maxReconnect.dispose();
    _eventBuffer.dispose();
    _pollingInterval.dispose();
    _pollingMaxRoomsPerTick.dispose();
    _sseIdleTimeout.dispose();
    super.dispose();
  }

  /// Minimum number of characters the typed display name must have for the
  /// "Enter chat" button to enable. Kept at 3 so single-letter (and likely
  /// typos) cannot register a user — CHT user ids are otherwise case-
  /// insensitive once normalised below but otherwise unvalidated.
  static const int _kMinUsernameLength = 3;

  bool _canSubmit() {
    if (_mode == ChatMode.mock) return true;
    if (_username.text.trim().length < _kMinUsernameLength) return false;
    if (_baseUrl.text.trim().isEmpty) return false;
    if (_wsUrl.text.trim().isEmpty) return false;
    return true;
  }

  String _normalizedUsername() {
    // Force lowercase so 'Alice' and 'alice' resolve to the same user. CHT
    // user_ids are otherwise case-sensitive — without this, "Alice" creates
    // a second user that shadows the lowercase one and appears in your own
    // suggestion bar.
    return _username.text.trim().toLowerCase();
  }

  ExampleSettings _build() {
    // Split the full WS/SSE URLs back into the (realtimeUrl, path) pair
    // that ChatConfig consumes. Default paths follow the backend's
    // `/v1/ws` and `/v1/events` mounts.
    final (wsBase, wsPath) = _splitUrl(_wsUrl.text, defaultPath: '/v1/ws');
    final (sseBase, ssePath) = _splitUrl(
      _sseUrl.text,
      defaultPath: '/v1/events',
    );
    final sseUrlOverride = sseBase.isEmpty || sseBase == wsBase
        ? null
        : sseBase;
    return ExampleSettings(
      username: _normalizedUsername(),
      mode: _mode,
      baseUrl: _baseUrl.text.trim(),
      realtimeUrl: wsBase,
      realtimeMode: _realtimeMode,
      pollingIntervalSeconds:
          int.tryParse(_pollingInterval.text.trim()) ??
          widget.initialSettings.pollingIntervalSeconds,
      pollUnreadOnly: _pollUnreadOnly,
      pollOpenRoomMessages: _pollOpenRoomMessages,
      pollingMaxRoomsPerTick:
          int.tryParse(_pollingMaxRoomsPerTick.text.trim()) ??
          widget.initialSettings.pollingMaxRoomsPerTick,
      sseIdleTimeoutSeconds:
          int.tryParse(_sseIdleTimeout.text.trim()) ??
          widget.initialSettings.sseIdleTimeoutSeconds,
      requestTimeoutSeconds:
          int.tryParse(_requestTimeout.text.trim()) ??
          widget.initialSettings.requestTimeoutSeconds,
      wsReconnectDelaySeconds:
          int.tryParse(_wsReconnectDelay.text.trim()) ??
          widget.initialSettings.wsReconnectDelaySeconds,
      sseUrl: sseUrlOverride,
      wsPath: wsPath,
      ssePath: ssePath,
      maxReconnectAttempts: _maxReconnect.text.trim().isEmpty
          ? null
          : int.tryParse(_maxReconnect.text.trim()),
      eventBufferSize:
          int.tryParse(_eventBuffer.text.trim()) ??
          widget.initialSettings.eventBufferSize,
    );
  }

  Future<void> _submit() async {
    if (_submitting || !_canSubmit()) return;
    setState(() => _submitting = true);
    final built = _build();
    final error = await widget.onSubmit(built, _pickedAvatar);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
      );
      setState(() => _submitting = false);
    }
    // On success the parent rebuilds into the chat home and this state is
    // disposed — no need to reset _submitting.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final divider = theme.dividerColor.withValues(alpha: 0.3);
    final strings = LocaleProvider.of(context).strings;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            // Column splits the screen in two: a scrollable upper area
            // for the form and a fixed footer that always carries the
            // CTA. Lets long forms (CHT mode) scroll without ever
            // hiding "Enter chat" off-screen — important on small
            // viewports where the keyboard already eats half the
            // canvas.
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    children: [
                      const SizedBox(height: 16),
                      const Text(
                        'Noma Chat',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        strings.onboardingSubtitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      const LanguagePickerRow(),
                      const SizedBox(height: 24),

                      _ModeSelector(
                        mode: _mode,
                        onChanged: _submitting
                            ? null
                            : (m) => setState(() => _mode = m),
                      ),

                      if (_mode == ChatMode.mock) ...[
                        const SizedBox(height: 24),
                        const _MockModeCard(),
                      ],

                      if (_mode == ChatMode.cht) ...[
                        const SizedBox(height: 24),
                        const _RealModeIntro(),
                        const SizedBox(height: 16),
                        Center(
                          child: AvatarPickerField(
                            kind: AvatarKind.user,
                            size: 120,
                            fallbackInitials: _username.text.trim(),
                            // Inject the active locale's ChatUiLocalizations
                            // into the SDK widget — without this it falls
                            // back to ChatTheme.defaults whose l10n is
                            // hardcoded to English, leaving the bottom
                            // sheet (Take photo / Gallery / Remove / …)
                            // untranslated regardless of the example's
                            // language picker.
                            theme: ChatTheme.defaults.copyWith(
                              l10n: LocaleProvider.of(context).l10n,
                            ),
                            onChanged: (snap, _) =>
                                setState(() => _pickedAvatar = snap),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _username,
                          enabled: !_submitting,
                          autofocus:
                              widget.initialSettings.username.isEmpty &&
                              !widget.autoSubmitOnLoad,
                          decoration: InputDecoration(
                            labelText: strings.usernameLabel,
                            border: const OutlineInputBorder(),
                            helperText: strings.usernameHelper,
                          ),
                          textInputAction: TextInputAction.next,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 16),
                        _BackendSection(
                          baseUrl: _baseUrl,
                          wsUrl: _wsUrl,
                          sseUrl: _sseUrl,
                          enabled: !_submitting,
                          onChanged: () => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        _AdvancedSection(
                          realtimeMode: _realtimeMode,
                          pollingInterval: _pollingInterval,
                          pollUnreadOnly: _pollUnreadOnly,
                          pollOpenRoomMessages: _pollOpenRoomMessages,
                          pollingMaxRoomsPerTick: _pollingMaxRoomsPerTick,
                          sseIdleTimeout: _sseIdleTimeout,
                          requestTimeout: _requestTimeout,
                          wsReconnectDelay: _wsReconnectDelay,
                          maxReconnect: _maxReconnect,
                          eventBuffer: _eventBuffer,
                          enabled: !_submitting,
                          onRealtimeModeChanged: (m) =>
                              setState(() => _realtimeMode = m),
                          onPollUnreadOnlyChanged: (v) =>
                              setState(() => _pollUnreadOnly = v),
                          onPollOpenRoomsChanged: (v) =>
                              setState(() => _pollOpenRoomMessages = v),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    border: Border(top: BorderSide(color: divider)),
                  ),
                  child: FilledButton(
                    onPressed: _submitting || !_canSubmit() ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(strings.enterChat),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Short intro that surfaces above the username field when the user
/// picks Real mode. Sets expectations — this isn't an in-memory demo,
/// it's a live connection to a Nomasystems chat backend, and to see the
/// chat features in action you need multiple instances logged in as
/// different users so they can talk to each other.
class _RealModeIntro extends StatelessWidget {
  const _RealModeIntro();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = LocaleProvider.of(context).strings;
    final body = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.4,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.dns_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(strings.realIntroBackend, style: body)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.devices_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(strings.realIntroMultiInstance, style: body),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Sales pitch surface for Mock mode. This is THE shop window — the
/// user that lands here might not even know what Noma sells, so we
/// invest in hero + feature bullets + a prominent "talk to us" CTA.
/// Mock mode itself ("enter chat" button below) is the live taste of
/// the SDK on top of a self-contained MockChatClient.
class _MockModeCard extends StatelessWidget {
  const _MockModeCard();

  static const _supportEmail = 'info@nomasystems.es';

  Future<void> _openMail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      query: 'subject=${Uri.encodeComponent("Noma Chat — information")}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = LocaleProvider.of(context).strings;
    final subtle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.45,
    );
    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.demoModeBodyTechnical,
              style: subtle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Feature bullets — short, scannable.
            _FeatureBullet(
              icon: Icons.bolt,
              text: strings.demoModeFeatureRealtime,
            ),
            _FeatureBullet(
              icon: Icons.cloud_off,
              text: strings.demoModeFeatureOffline,
            ),
            _FeatureBullet(
              icon: Icons.admin_panel_settings,
              text: strings.demoModeFeatureAdmin,
            ),
            _FeatureBullet(
              icon: Icons.phone_iphone,
              text: strings.demoModeFeatureSdk,
            ),
            const SizedBox(height: 20),
            // Unified CTA: action label + email shown together inside
            // the same button so the user has a single tappable
            // surface (the previous split FilledButton + TextButton
            // duplicated the affordance).
            FilledButton(
              onPressed: _openMail,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.mail_outline, size: 20),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        strings.demoModeCtaLabel,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _supportEmail,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onPrimary.withValues(
                            alpha: 0.85,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureBullet extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureBullet({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});

  final ChatMode mode;
  final ValueChanged<ChatMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = LocaleProvider.of(context).strings;
    // "Real" is intentionally generic — "CHT" leaked the internal
    // backend code name into the UI and only made sense to insiders.
    // The enum value stays `ChatMode.cht` so persisted settings + the
    // dev harness env vars keep working without a migration.
    return SegmentedButton<ChatMode>(
      segments: [
        ButtonSegment(
          value: ChatMode.mock,
          label: Text(strings.modeMock),
          icon: const Icon(Icons.science_outlined),
        ),
        ButtonSegment(
          value: ChatMode.cht,
          label: Text(strings.modeReal),
          icon: const Icon(Icons.dns_outlined),
        ),
      ],
      selected: {mode},
      onSelectionChanged: onChanged == null
          ? null
          : (sel) => onChanged!(sel.first),
    );
  }
}

class _BackendSection extends StatelessWidget {
  const _BackendSection({
    required this.baseUrl,
    required this.wsUrl,
    required this.sseUrl,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController baseUrl;
  final TextEditingController wsUrl;
  final TextEditingController sseUrl;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = LocaleProvider.of(context).strings;
    // Backend mirrors Advanced's collapsible Card pattern. Most users
    // run the harness defaults (localhost:8077) — surface the URLs only
    // when they actually need to point at a remote instance. Same
    // empty-Border trick as Advanced to drop the default top/bottom
    // divider lines that bleed through the Card.
    return Card(
      child: ExpansionTile(
        title: Text(strings.backendTitle),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        shape: const Border(),
        collapsedShape: const Border(),
        children: [
          TextField(
            controller: baseUrl,
            enabled: enabled,
            decoration: InputDecoration(
              labelText: strings.baseUrlLabel,
              hintText: 'http://localhost:8077/v1',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: TextInputType.url,
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: wsUrl,
            enabled: enabled,
            decoration: InputDecoration(
              labelText: strings.wsUrlLabel,
              hintText: 'http://localhost:8077/v1/ws',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: TextInputType.url,
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: sseUrl,
            enabled: enabled,
            decoration: InputDecoration(
              labelText: strings.sseUrlLabel,
              hintText: 'http://localhost:8077/v1/events',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: TextInputType.url,
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }
}

class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection({
    required this.realtimeMode,
    required this.pollingInterval,
    required this.pollUnreadOnly,
    required this.pollOpenRoomMessages,
    required this.pollingMaxRoomsPerTick,
    required this.sseIdleTimeout,
    required this.requestTimeout,
    required this.wsReconnectDelay,
    required this.maxReconnect,
    required this.eventBuffer,
    required this.enabled,
    required this.onRealtimeModeChanged,
    required this.onPollUnreadOnlyChanged,
    required this.onPollOpenRoomsChanged,
  });

  final RealtimeMode realtimeMode;
  final TextEditingController pollingInterval;
  final bool pollUnreadOnly;
  final bool pollOpenRoomMessages;
  final TextEditingController pollingMaxRoomsPerTick;
  final TextEditingController sseIdleTimeout;
  final TextEditingController requestTimeout;
  final TextEditingController wsReconnectDelay;
  final TextEditingController maxReconnect;
  final TextEditingController eventBuffer;
  final bool enabled;
  final ValueChanged<RealtimeMode> onRealtimeModeChanged;
  final ValueChanged<bool> onPollUnreadOnlyChanged;
  final ValueChanged<bool> onPollOpenRoomsChanged;

  @override
  Widget build(BuildContext context) {
    final strings = LocaleProvider.of(context).strings;
    return Card(
      child: ExpansionTile(
        title: Text(strings.advancedTitle),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        // Material's default `ExpansionTile.shape` renders a top + bottom
        // BorderSide when expanded, which leaks horizontal black lines
        // through the Card's rounded shape. Empty `Border()` for both
        // states drops the dividers entirely — the Card outline already
        // bounds the section.
        shape: const Border(),
        collapsedShape: const Border(),
        children: [
          // ── Global ────────────────────────────────────────────────
          // Settings that apply regardless of the realtime mode.
          _SubsectionHeader(title: strings.advSectionGlobal),
          _AdvancedRow(
            title: strings.advRequestTimeout,
            tooltip: strings.advRequestTimeoutTip,
            trailing: _RowNumberInput(
              controller: requestTimeout,
              enabled: enabled,
            ),
          ),
          _AdvancedRow(
            title: strings.advEventBuffer,
            tooltip: strings.advEventBufferTip,
            trailing: _RowNumberInput(
              controller: eventBuffer,
              enabled: enabled,
            ),
          ),

          // ── Realtime mode + per-mode sub-form ────────────────────
          _SubsectionHeader(title: strings.advSectionRealtime),
          _AdvancedRow(
            title: strings.advRealtimeMode,
            tooltip: strings.advRealtimeModeTip,
            trailingFlex: true,
            trailing: DropdownButton<RealtimeMode>(
              value: realtimeMode,
              onChanged: enabled
                  ? (m) {
                      if (m != null) onRealtimeModeChanged(m);
                    }
                  : null,
              items: const [
                DropdownMenuItem(
                  value: RealtimeMode.auto,
                  child: Text('Auto (WS → SSE)'),
                ),
                DropdownMenuItem(
                  value: RealtimeMode.webSocketOnly,
                  child: Text('WebSocket'),
                ),
                DropdownMenuItem(
                  value: RealtimeMode.serverSentEventsOnly,
                  child: Text('SSE'),
                ),
                DropdownMenuItem(
                  value: RealtimeMode.polling,
                  child: Text('Polling'),
                ),
                DropdownMenuItem(
                  value: RealtimeMode.manual,
                  child: Text('Manual'),
                ),
              ],
              isDense: true,
            ),
          ),
          ..._modeSpecificRows(context, strings),
        ],
      ),
    );
  }

  /// Returns the per-mode sub-form: every mode shows exactly the
  /// tunables that are meaningful for it. The other settings stay
  /// folded away so the panel doesn't grow with noise.
  List<Widget> _modeSpecificRows(BuildContext context, ExampleStrings strings) {
    switch (realtimeMode) {
      case RealtimeMode.auto:
        return [
          _AdvancedRow(
            title: strings.advWsReconnectDelay,
            tooltip: strings.advWsReconnectDelayTip,
            trailing: _RowNumberInput(
              controller: wsReconnectDelay,
              enabled: enabled,
            ),
          ),
          _AdvancedRow(
            title: strings.advMaxReconnect,
            tooltip: strings.advMaxReconnectTip,
            trailing: _RowNumberInput(
              controller: maxReconnect,
              enabled: enabled,
              hintText: '∞',
            ),
          ),
          _AdvancedRow(
            title: strings.advSseIdleTimeout,
            tooltip: strings.advSseIdleTimeoutTip,
            trailing: _RowNumberInput(
              controller: sseIdleTimeout,
              enabled: enabled,
              hintText: '0=off',
            ),
          ),
        ];
      case RealtimeMode.webSocketOnly:
        return [
          _AdvancedRow(
            title: strings.advWsReconnectDelay,
            tooltip: strings.advWsReconnectDelayTip,
            trailing: _RowNumberInput(
              controller: wsReconnectDelay,
              enabled: enabled,
            ),
          ),
          _AdvancedRow(
            title: strings.advMaxReconnect,
            tooltip: strings.advMaxReconnectTip,
            trailing: _RowNumberInput(
              controller: maxReconnect,
              enabled: enabled,
              hintText: '∞',
            ),
          ),
        ];
      case RealtimeMode.serverSentEventsOnly:
        return [
          _AdvancedRow(
            title: strings.advSseIdleTimeout,
            tooltip: strings.advSseIdleTimeoutTip,
            trailing: _RowNumberInput(
              controller: sseIdleTimeout,
              enabled: enabled,
              hintText: '0=off',
            ),
          ),
          _AdvancedRow(
            title: strings.advMaxReconnect,
            tooltip: strings.advMaxReconnectTip,
            trailing: _RowNumberInput(
              controller: maxReconnect,
              enabled: enabled,
              hintText: '∞',
            ),
          ),
        ];
      case RealtimeMode.polling:
        return [
          _AdvancedRow(
            title: strings.advPollingInterval,
            tooltip: strings.advPollingIntervalTip,
            trailing: _RowNumberInput(
              controller: pollingInterval,
              enabled: enabled,
            ),
          ),
          _AdvancedRow(
            title: strings.advPollUnreadOnly,
            tooltip: strings.advPollUnreadOnlyTip,
            trailing: Switch(
              value: pollUnreadOnly,
              onChanged: enabled ? onPollUnreadOnlyChanged : null,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          _AdvancedRow(
            title: strings.advPollOpenRooms,
            tooltip: strings.advPollOpenRoomsTip,
            trailing: Switch(
              value: pollOpenRoomMessages,
              onChanged: enabled ? onPollOpenRoomsChanged : null,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          _AdvancedRow(
            title: strings.advPollMaxRoomsPerTick,
            tooltip: strings.advPollMaxRoomsPerTickTip,
            trailing: _RowNumberInput(
              controller: pollingMaxRoomsPerTick,
              enabled: enabled,
            ),
          ),
        ];
      case RealtimeMode.manual:
        return [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              strings.advManualHint,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ];
    }
  }
}

/// Mini-subheader inside Advanced: a small uppercase label that groups
/// the rows below it (Global / Realtime mode).
class _SubsectionHeader extends StatelessWidget {
  final String title;
  const _SubsectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Single row inside Advanced: `[title  ⓘ] ........... [trailing]`.
/// Title + tooltip flex on the left (ellipsizes after 2 lines to guard
/// against overflow on narrow viewports); the trailing widget is pinned
/// to a fixed 96-px slot on the right so all rows align vertically even
/// when labels differ wildly in length.
class _AdvancedRow extends StatelessWidget {
  const _AdvancedRow({
    required this.title,
    required this.tooltip,
    required this.trailing,
    this.trailingFlex = false,
  });

  final String title;
  final String tooltip;
  final Widget trailing;

  /// When `false` (default), the trailing slot is pinned to a fixed
  /// 96 px so that all the numeric inputs and switches line up
  /// vertically across rows. When `true`, the trailing widget gets
  /// to claim whatever space it needs (used by the realtime-mode
  /// dropdown whose "Auto (WS → SSE)" label overflows the fixed
  /// slot by ~17 px).
  final bool trailingFlex;

  static const double _trailingWidth = 96;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Title fills the leftover space; the ⓘ tip is pinned to the
          // right edge of the title column via `Expanded` on the Text.
          // Because every fixed-width row uses the same
          // `_trailingWidth` slot, the tooltip icons end up at the
          // same x position across rows — visually aligned vertically.
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _InfoTip(message: tooltip),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (trailingFlex)
            trailing
          else
            SizedBox(
              width: _trailingWidth,
              child: Align(alignment: Alignment.centerRight, child: trailing),
            ),
        ],
      ),
    );
  }
}

/// Compact numeric input trailing widget. Fixed visual height matches the
/// Switch siblings so toggle/input rows never jump vertically.
class _RowNumberInput extends StatelessWidget {
  const _RowNumberInput({
    required this.controller,
    required this.enabled,
    this.hintText,
  });

  final TextEditingController controller;
  final bool enabled;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        isDense: true,
        hintText: hintText,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    );
  }
}

/// Reusable info icon → Material Tooltip. Tap to reveal (works on both
/// mobile and desktop) with a generous show window so admins have time to
/// read longer explanations. Internal padding + outer margin give the
/// popup breathing room: previous version rendered the text flush
/// against the rounded border.
class _InfoTip extends StatelessWidget {
  const _InfoTip({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      preferBelow: true,
      waitDuration: const Duration(milliseconds: 200),
      showDuration: const Duration(seconds: 8),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      textStyle: TextStyle(
        color: theme.colorScheme.onInverseSurface,
        fontSize: 12,
        height: 1.4,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      // Pad the hit area so the icon is comfortable to tap even when
      // it sits in a dense row next to the trailing Switch / TextField.
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          Icons.info_outline,
          size: 16,
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }
}
