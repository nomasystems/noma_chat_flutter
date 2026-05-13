import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

/// Horizontal banner showing the current connection state (connecting, reconnecting, disconnected, error).
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({
    super.key,
    required this.state,
    this.theme = ChatTheme.defaults,
    this.labels = const {},
  });

  final ChatConnectionState state;
  final ChatTheme theme;
  final Map<ChatConnectionState, String> labels;

  String _defaultLabel() {
    switch (state) {
      case ChatConnectionState.connecting:
        return theme.l10n.connecting;
      case ChatConnectionState.reconnecting:
        return theme.l10n.reconnecting;
      case ChatConnectionState.disconnected:
        return theme.l10n.disconnected;
      case ChatConnectionState.error:
        return theme.l10n.connectionError;
      case ChatConnectionState.connected:
        return '';
    }
  }

  Color _defaultColor() {
    switch (state) {
      case ChatConnectionState.connecting:
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
    if (state == ChatConnectionState.connected) return const SizedBox.shrink();

    final label = labels[state] ?? _defaultLabel();

    return Semantics(
      liveRegion: true,
      label: label,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: theme.connectionBannerColor ?? _defaultColor(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state == ChatConnectionState.connecting ||
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
