import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../l10n/chat_ui_localizations.dart';
import '../theme/chat_theme.dart';

/// Presents a package notice the host's own way — a top banner, a toast
/// of its own design system, an analytics hop, anything.
///
/// Return `true` when the notice has been handled and the SDK should not
/// show its own snackbar; return `false` to let it fall through to the
/// default. Returning `false` for the kinds you don't care about is how a
/// host takes over only part of the surface.
///
/// A presenter that throws counts as one that returned `false`: the SDK
/// swallows the error and shows its own snackbar instead. A notice is
/// best-effort, so a host whose banner pipeline is momentarily unusable
/// still gets the message in front of the user rather than losing it —
/// and the caller's remaining work is not taken down with it.
typedef ChatNoticePresenter =
    bool Function(BuildContext context, String message);

/// Optional host override for every short notice the SDK shows on its own
/// (an unblock that failed, a group that couldn't be created, a role
/// change the server refused…).
///
/// Nothing has to be mounted for the notices to work: without this scope
/// they go to the nearest `ScaffoldMessenger`. Mount it — above
/// `MaterialApp`, or via `MaterialApp.builder`, so the routes the SDK
/// pushes inherit it — only to present them differently:
///
/// ```dart
/// ChatNoticeScope(
///   presenter: (context, message) {
///     myBanners.show(message);
///     return true;
///   },
///   child: MaterialApp(...),
/// );
/// ```
class ChatNoticeScope extends InheritedWidget {
  const ChatNoticeScope({
    super.key,
    required this.presenter,
    required super.child,
  });

  final ChatNoticePresenter presenter;

  static ChatNoticePresenter? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatNoticeScope>()?.presenter;

  @override
  bool updateShouldNotify(ChatNoticeScope oldWidget) =>
      presenter != oldWidget.presenter;
}

/// Shows [message] as a short notice: through the host's
/// [ChatNoticeScope] when there is one, otherwise as a SnackBar on the
/// nearest `ScaffoldMessenger`.
///
/// Every notice the SDK raises goes through here rather than calling
/// `ScaffoldMessenger.of(context).showSnackBar` directly, because that
/// call is not safe while a route is coming down.
/// `ScaffoldMessengerState.showSnackBar` walks *every* `Scaffold`
/// registered with the messenger (`_updateScaffolds` →
/// `findAncestorStateOfType`), and a `Scaffold` only unregisters in
/// `dispose`, never in `deactivate` — so between the frame that removes a
/// route and the end of that same frame, one dying `Scaffold` anywhere
/// under the messenger throws the call of whoever is publishing, and the
/// notice is lost along with the rest of the caller's work. Publishing
/// after the frame instead finds the dead `Scaffold` unmounted and gone.
///
/// [snackBarBuilder] customizes the bar the SDK builds (margins, an
/// action, a duration); it is not called at all when a [ChatNoticeScope]
/// takes the notice. Like the presenter, a builder that throws degrades
/// to the plain default bar instead of losing the notice.
///
/// Every ancestor lookup here runs through [_safely], because [context]
/// may already be deactivated by the time the notice is raised: an
/// operation that fails while its route is coming down resumes on a
/// context whose element is no longer active, and
/// `dependOnInheritedWidgetOfExactType` answers that with *Looking up a
/// deactivated widget's ancestor is unsafe* rather than with `null`. A
/// throw there loses the notice and takes the caller's remaining work
/// with it, which is the opposite of what a best-effort toast should do.
///
/// [messenger] and [presenter] are the caller's own answers to those two
/// lookups, resolved while the context was still active (a `State` reads
/// them in `didChangeDependencies`). They are used only when the live
/// lookup cannot answer, so a caller that keeps them still shows the
/// notice on a context that has gone. [_publish] re-checks
/// `messenger.mounted`, so a stale one publishes nothing rather than
/// publishing on the wrong screen.
void showChatNotice(
  BuildContext context,
  String message, {
  SnackBar Function(BuildContext context, String message)? snackBarBuilder,
  ScaffoldMessengerState? messenger,
  ChatNoticePresenter? presenter,
}) {
  if (message.isEmpty) return;
  final host = _safely(() => ChatNoticeScope.maybeOf(context)) ?? presenter;
  if (host != null && (_safely(() => host(context, message)) ?? false)) return;
  final target = _safely(() => ScaffoldMessenger.maybeOf(context)) ?? messenger;
  if (target == null) return;
  final snackBar =
      _safely(() => snackBarBuilder?.call(context, message)) ??
      SnackBar(content: Text(message));
  final phase = SchedulerBinding.instance.schedulerPhase;
  final midFrame =
      phase != SchedulerPhase.idle &&
      phase != SchedulerPhase.postFrameCallbacks;
  if (midFrame) {
    _afterFrame(() => _publish(target, snackBar, retry: false));
    return;
  }
  _publish(target, snackBar, retry: true);
}

T? _safely<T>(T? Function() read) {
  try {
    return read();
  } catch (_) {
    return null;
  }
}

/// [ChatThemeL10n.l10nOf] for the message of a notice, which is composed
/// on whatever context the failing operation resumed on.
///
/// The lookup behind `l10nOf` is `Localizations.of`, one more
/// `dependOnInheritedWidgetOfExactType`, so it throws on a deactivated
/// element exactly like the two [showChatNotice] guards against — and it
/// runs *before* the call, where those guards cannot reach it. Falling
/// back to [ChatTheme.l10n] loses the ambient locale in that one case and
/// keeps the notice.
ChatUiLocalizations chatNoticeL10n(BuildContext context, ChatTheme theme) =>
    _safely(() => theme.l10nOf(context)) ?? theme.l10n;

/// Everything a `State` needs to still raise a notice once its element
/// has left the tree.
///
/// `didChangeDependencies` is the last moment the three lookups a notice
/// depends on — the host presenter, the `ScaffoldMessenger` and the
/// localizations — are guaranteed to answer. An operation that fails
/// while its route is coming down resumes on a context whose element is
/// no longer active, `mounted` is still `true` there, and each of those
/// lookups answers with *Looking up a deactivated widget's ancestor is
/// unsafe* rather than with `null`. Resolving them while they work and
/// handing them to [showChatNotice] as fallbacks is what keeps the notice
/// on screen instead of dropping it.
mixin ChatNoticeAnchor<T extends StatefulWidget> on State<T> {
  /// The theme [noticeL10n] takes its strings from.
  ChatTheme get noticeTheme;

  ScaffoldMessengerState? _noticeMessenger;
  ChatNoticePresenter? _noticePresenter;
  ChatUiLocalizations? _noticeL10n;

  /// The strings for a notice: from the live context while it still
  /// answers, from the last resolution once it does not.
  ChatUiLocalizations get noticeL10n =>
      _safely(() => noticeTheme.l10nOf(context)) ??
      _noticeL10n ??
      noticeTheme.l10n;

  /// [showChatNotice] with this anchor's fallbacks already filled in.
  void showNotice(
    String message, {
    SnackBar Function(BuildContext context, String message)? snackBarBuilder,
  }) => showChatNotice(
    context,
    message,
    snackBarBuilder: snackBarBuilder,
    messenger: _noticeMessenger,
    presenter: _noticePresenter,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _noticeMessenger = _safely(() => ScaffoldMessenger.maybeOf(context));
    _noticePresenter = _safely(() => ChatNoticeScope.maybeOf(context));
    _noticeL10n = _safely(() => noticeTheme.l10nOf(context));
  }
}

void _publish(
  ScaffoldMessengerState messenger,
  SnackBar snackBar, {
  required bool retry,
}) {
  if (!messenger.mounted) return;
  try {
    messenger.showSnackBar(snackBar);
  } catch (_) {
    if (!retry) return;
    _afterFrame(() {
      if (!messenger.mounted) return;
      // The throw happened *after* the bar was queued, so drop that
      // half-published entry before publishing again — otherwise the
      // user reads the same notice twice.
      messenger.removeCurrentSnackBar();
      _publish(messenger, snackBar, retry: false);
    });
  }
}

void _afterFrame(VoidCallback action) {
  final binding = WidgetsBinding.instance;
  binding.addPostFrameCallback((_) => action());
  binding.ensureVisualUpdate();
}
