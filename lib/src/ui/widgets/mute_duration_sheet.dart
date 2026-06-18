import 'package:flutter/material.dart';

import '../l10n/chat_ui_localizations.dart';
import '../theme/chat_theme.dart';

/// WhatsApp-style mute durations offered by [MuteDurationSheet].
enum MuteDuration {
  eightHours,
  oneWeek,

  /// Permanent mute — no expiry ([until] returns `null`).
  always;

  /// The absolute expiry instant for this choice given [now], or `null`
  /// for [always]. Feed it straight to `adapter.rooms.mute(roomId,
  /// until: choice.until(DateTime.now()))`.
  DateTime? until(DateTime now) => switch (this) {
    MuteDuration.eightHours => now.add(const Duration(hours: 8)),
    MuteDuration.oneWeek => now.add(const Duration(days: 7)),
    MuteDuration.always => null,
  };

  /// Localized row label.
  String label(ChatUiLocalizations l10n) => switch (this) {
    MuteDuration.eightHours => l10n.mute8Hours,
    MuteDuration.oneWeek => l10n.mute1Week,
    MuteDuration.always => l10n.muteAlways,
  };
}

/// Bottom sheet that asks the user how long to mute a chat (8 hours / 1
/// week / always), mirroring WhatsApp's timed-mute picker.
///
/// Returns the chosen [MuteDuration], or `null` if the user dismissed the
/// sheet without choosing. Wired automatically by
/// [ChatRoomOption.muteRoom]; call it directly only for a custom mute flow.
class MuteDurationSheet {
  MuteDurationSheet._();

  static Future<MuteDuration?> show(
    BuildContext context, {
    required ChatUiLocalizations l10n,
    ChatTheme theme = ChatTheme.defaults,
  }) {
    return showModalBottomSheet<MuteDuration>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  l10n.muteDuration,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
            ),
            for (final duration in MuteDuration.values)
              ListTile(
                leading: const Icon(Icons.volume_off_outlined),
                title: Text(duration.label(l10n)),
                onTap: () => Navigator.of(sheetContext).pop(duration),
              ),
          ],
        ),
      ),
    );
  }
}
