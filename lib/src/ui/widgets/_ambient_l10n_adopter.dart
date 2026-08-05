import 'package:flutter/widgets.dart';

import '../adapter/chat_ui_adapter.dart';
import '../theme/chat_theme.dart';

/// Hands [adapter] the localizations resolved for this position in the tree,
/// once on mount and again whenever they change, then gets out of the way.
///
/// Stateful because the hand-off mutates the adapter, which a `build` must
/// never do. Wrap a subtree in this wherever a view is handed an adapter but
/// has no `State` of its own to hook.
class AmbientL10nAdopter extends StatefulWidget {
  const AmbientL10nAdopter({
    super.key,
    required this.adapter,
    required this.theme,
    required this.child,
  });

  final ChatUiAdapter adapter;
  final ChatTheme theme;
  final Widget child;

  @override
  State<AmbientL10nAdopter> createState() => _AmbientL10nAdopterState();
}

class _AmbientL10nAdopterState extends State<AmbientL10nAdopter> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    adoptAmbientL10nAfterFrame(widget.adapter, widget.theme, context);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Hands [adapter] the bundle [theme] resolves for [context], at the end of
/// the frame rather than inside it.
///
/// The hand-off can re-stamp room rows, and a room list is exactly what a
/// host is likely to be listening to elsewhere in the tree; notifying those
/// listeners from `didChangeDependencies` would mark widgets dirty in the
/// middle of a build. The bundle is in place before anything can compose
/// with it, and the one string the swap rewrites is stored rather than
/// painted, so a frame's delay is invisible.
void adoptAmbientL10nAfterFrame(
  ChatUiAdapter adapter,
  ChatTheme theme,
  BuildContext context,
) {
  final resolved = theme.l10nOf(context);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    adapter.adoptAmbientL10n(resolved);
  });
}
