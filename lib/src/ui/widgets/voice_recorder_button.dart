import 'package:flutter/material.dart';
import '../models/voice_message_data.dart';
import '../theme/chat_theme.dart';

/// Visual mic button for chat composers. Recording itself is owned by the
/// composer (see [MessageInput]), which detects long-press gestures and
/// delivers the resulting [VoiceMessageData] via its `onVoiceMessageReady`
/// callback. This widget is purely a circular mic icon with semantics.
class VoiceRecorderButton extends StatelessWidget {
  const VoiceRecorderButton({super.key, this.theme = ChatTheme.defaults});

  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: theme.l10n.recordVoice,
      button: true,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.voiceButtonColor ?? Colors.grey.shade200,
          shape: BoxShape.circle,
        ),
        child: Center(
          child:
              theme.voiceIconBuilder?.call(context) ??
              Icon(
                theme.voiceButtonIcon ?? Icons.mic,
                size: 20,
                color: theme.voiceButtonIdleIconColor ?? Colors.grey.shade700,
              ),
        ),
      ),
    );
  }
}
