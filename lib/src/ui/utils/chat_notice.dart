import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Presents a package notice the host's own way — a top banner, a toast
/// of its own design system, an analytics hop, anything.
///
/// Return `true` when the notice has been handled and the SDK should not
/// show its own snackbar; return `false` to let it fall through to the
/// default. Returning `false` for the kinds you don't care about is how a
/// host takes over only part of the surface.
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
/// takes the notice.
void showChatNotice(
  BuildContext context,
  String message, {
  SnackBar Function(BuildContext context, String message)? snackBarBuilder,
}) {
  if (message.isEmpty) return;
  final presenter = ChatNoticeScope.maybeOf(context);
  if (presenter != null && presenter(context, message)) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final snackBar =
      snackBarBuilder?.call(context, message) ??
      SnackBar(content: Text(message));
  final phase = SchedulerBinding.instance.schedulerPhase;
  final midFrame =
      phase != SchedulerPhase.idle &&
      phase != SchedulerPhase.postFrameCallbacks;
  if (midFrame) {
    _afterFrame(() => _publish(messenger, snackBar, retry: false));
    return;
  }
  _publish(messenger, snackBar, retry: true);
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
