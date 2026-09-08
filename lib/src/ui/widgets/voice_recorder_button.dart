import 'package:flutter/material.dart';
import '../models/voice_message_data.dart';
import '../theme/chat_theme.dart';

/// Visual mic button for chat composers. Recording itself is owned by the
/// composer (see [MessageInput]), which starts recording as soon as the
/// finger touches this button and delivers the resulting
/// [VoiceMessageData] via its `onVoiceMessageReady` callback. This widget
/// is purely a circular mic icon with semantics.
class VoiceRecorderButton extends StatelessWidget {
  const VoiceRecorderButton({super.key, this.theme = ChatTheme.defaults});

  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('chat_voice_button'),
      identifier: 'chat_voice_button',
      label: theme.l10nOf(context).recordVoice,
      button: true,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.input.voiceButtonColor ?? Colors.grey.shade200,
          shape: BoxShape.circle,
        ),
        child: Center(
          child:
              theme.input.voiceIconBuilder?.call(context) ??
              Icon(
                theme.input.voiceButtonIcon ?? Icons.mic,
                size: 20,
                color:
                    theme.input.voiceButtonIdleIconColor ??
                    Colors.grey.shade700,
              ),
        ),
      ),
    );
  }
}
