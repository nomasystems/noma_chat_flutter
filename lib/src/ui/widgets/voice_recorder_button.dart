import 'package:flutter/material.dart';
import '../models/voice_message_data.dart';
import '../theme/chat_theme.dart';

/// Visual mic button for chat composers. Recording itself is owned by the
/// composer (see [MessageInput]), which starts recording as soon as the
/// finger touches this button and delivers the resulting
/// [VoiceMessageData] via its `onVoiceMessageReady` callback. This widget
/// is purely a circular mic icon with semantics.
///
/// The widget's own box is [tapTarget] square while the circle it paints
/// stays [diameter]: the composer hit-tests this box to decide whether a
/// touch started on the mic, so the box is what has to meet the 44pt
/// minimum.
class VoiceRecorderButton extends StatelessWidget {
  const VoiceRecorderButton({super.key, this.theme = ChatTheme.defaults});

  /// Diameter of the mic circle the composer paints.
  static const double diameter = 40;

  /// Side of the square the mic button answers touches on. Larger than
  /// [diameter] so the control clears the 44pt minimum touch target both
  /// platforms ask for without growing the circle the composer was
  /// designed around.
  static const double tapTarget = 44;

  /// How far the touch target reaches past the painted circle on each side.
  /// The composer subtracts it from the button's trailing inset so enlarging
  /// the target leaves the circle exactly where it was.
  static const double tapBleed = (tapTarget - diameter) / 2;

  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('chat_voice_button'),
      identifier: 'chat_voice_button',
      label: theme.l10nOf(context).recordVoice,
      button: true,
      child: SizedBox(
        width: tapTarget,
        height: tapTarget,
        child: Center(
          child: Container(
            width: diameter,
            height: diameter,
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
        ),
      ),
    );
  }
}
