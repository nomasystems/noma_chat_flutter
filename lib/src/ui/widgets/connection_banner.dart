import 'dart:async';

import 'package:flutter/material.dart';

import '../../events/chat_event.dart';
import '../theme/chat_theme.dart';

/// Horizontal banner showing the current connection state (connecting, reconnecting, disconnected, error).
///
/// [ChatConnectionState.error] is not painted as a hard failure on arrival:
/// a transport reports `error` the instant a socket drops and only moves to
/// `connecting` once its backoff timer fires (`WsTransport._onError` ->
/// `_scheduleReconnect`, base delay 2s and up to 60s), so the raw state says
/// "broken" during a retry the user never needed to know about. The red
/// treatment is held back until the link has been down for
/// [sustainedErrorDelay]; until then the banner wears the discreet
/// `reconnecting` presentation.
class ConnectionBanner extends StatefulWidget {
  const ConnectionBanner({
    super.key,
    required this.state,
    this.theme = ChatTheme.defaults,
    this.labels = const {},
    this.sustainedErrorDelay = defaultSustainedErrorDelay,
  });

  /// Default value of [sustainedErrorDelay], long enough to cover the first
  /// reconnect attempts of the bundled transports.
  static const Duration defaultSustainedErrorDelay = Duration(seconds: 8);

  final ChatConnectionState state;
  final ChatTheme theme;
  final Map<ChatConnectionState, String> labels;

  /// How long the link has to stay down before [ChatConnectionState.error]
  /// escalates from the `reconnecting` presentation to the red one.
  ///
  /// The countdown starts when the link stops being
  /// [ChatConnectionState.connected] and is only restarted by the next
  /// `connected`, so a retry loop that keeps failing — `error` ->
  /// `connecting` -> `error` — still escalates instead of resetting itself
  /// forever. [Duration.zero] escalates immediately.
  final Duration sustainedErrorDelay;

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner> {
  Timer? _sustainedTimer;
  bool _sustained = false;

  @override
  void initState() {
    super.initState();
    _trackDowntime();
  }

  @override
  void didUpdateWidget(ConnectionBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state ||
        oldWidget.sustainedErrorDelay != widget.sustainedErrorDelay) {
      _trackDowntime();
    }
  }

  @override
  void dispose() {
    _sustainedTimer?.cancel();
    super.dispose();
  }

  void _trackDowntime() {
    if (widget.state == ChatConnectionState.connected) {
      _sustainedTimer?.cancel();
      _sustainedTimer = null;
      _sustained = false;
      return;
    }
    if (widget.sustainedErrorDelay == Duration.zero) {
      _sustainedTimer?.cancel();
      _sustainedTimer = null;
      _sustained = true;
      return;
    }
    if (_sustained || _sustainedTimer != null) return;
    _sustainedTimer = Timer(widget.sustainedErrorDelay, () {
      _sustainedTimer = null;
      if (!mounted) return;
      setState(() => _sustained = true);
    });
  }

  ChatConnectionState get _displayState =>
      widget.state == ChatConnectionState.error && !_sustained
      ? ChatConnectionState.reconnecting
      : widget.state;

  String _defaultLabel(BuildContext context, ChatConnectionState state) {
    switch (state) {
      case ChatConnectionState.connecting:
      case ChatConnectionState.authenticating:
        return widget.theme.l10nOf(context).connecting;
      case ChatConnectionState.reconnecting:
        return widget.theme.l10nOf(context).reconnecting;
      case ChatConnectionState.disconnected:
        return widget.theme.l10nOf(context).disconnected;
      case ChatConnectionState.error:
        return widget.theme.l10nOf(context).connectionError;
      case ChatConnectionState.connected:
        return '';
    }
  }

  Color _defaultColor(ChatConnectionState state) {
    switch (state) {
      case ChatConnectionState.connecting:
      case ChatConnectionState.authenticating:
      case ChatConnectionState.reconnecting:
        return Colors.orange.shade100;
      case ChatConnectionState.disconnected:
        return Colors.grey.shade300;
      case ChatConnectionState.error:
        return Colors.red.shade100;
      case ChatConnectionState.connected:
        return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _displayState;
    if (state == ChatConnectionState.connected) return const SizedBox.shrink();

    final label = widget.labels[state] ?? _defaultLabel(context, state);
    final theme = widget.theme;

    return Semantics(
      liveRegion: true,
      label: label,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: theme.connectionBannerColor ?? _defaultColor(state),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state == ChatConnectionState.connecting ||
                state == ChatConnectionState.authenticating ||
                state == ChatConnectionState.reconnecting)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (state == ChatConnectionState.error)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.error_outline,
                  size: 16,
                  color: theme.connectionBannerErrorIconColor ?? Colors.red,
                ),
              ),
            Text(
              label,
              style:
                  theme.connectionBannerTextStyle ??
                  const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
