import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/result.dart' show ContentFilterFailure, ValidationFailure;
import '../adapter/operation_error.dart';
import '../theme/chat_theme.dart';

/// Localized message for a successful operation. Returning `null` (or
/// an empty string) suppresses the snackbar for that event — consumers
/// use this to opt out per-kind without disabling the listener.
typedef OperationSuccessLabelBuilder =
    String? Function(
      BuildContext context,
      OperationSuccess event,
      ChatTheme theme,
    );

/// Localized message for a failed operation. Returning `null` (or an
/// empty string) suppresses the snackbar — the default only speaks up
/// for *expected* failures the bubble cannot express on its own (a
/// content-filter rejection, and a retry refused because the row's file
/// never got uploaded) and stays silent for everything else, so
/// transient/network errors keep surfacing as failed-message bubbles
/// rather than noisy toasts.
typedef OperationErrorLabelBuilder =
    String? Function(
      BuildContext context,
      OperationError event,
      ChatTheme theme,
    );

/// Listens to a `Stream<OperationSuccess>` (typically
/// `chatAdapter.operationSuccesses`) and shows localized SnackBars
/// confirming user-visible operations — pin a message, delete a
/// message, forward, etc.
///
/// **Configurable**:
/// - Pass [enabled] = false to disable feedback entirely without
///   removing the widget.
/// - Pass [labelBuilder] to override the snackbar text per kind, or
///   to suppress it (`return null`). The default uses the strings from
///   `ChatTheme.l10nOf(context)` (`feedbackMessagePinned` /
///   `feedbackMessageDeleted` / …).
/// - Pass [snackBarBuilder] for fully custom widgets (e.g. a top
///   banner instead of a snackbar). Default builds a stock `SnackBar`.
/// - Pass [duration] to change visible time (default 2s).
///
/// Wrap any subtree that contains a `Scaffold` with this widget. The
/// snackbar attaches to `ScaffoldMessenger.maybeOf(context)` so missing
/// scaffolds are silently ignored.
///
/// `NomaChatView` mounts one of these around its own subtree, so the
/// feedback works with no host wiring at all. It first asks
/// [coverageAbove] what a listener of the host's own — mounted *above* the
/// view — already delivers, and adds only the rest: a wrapper wired to
/// both streams leaves it nothing to add, and a wrapper mounted without
/// [errors] keeps its success confirmations while the view covers the
/// failures. Either way no event is announced twice, and no event is
/// swallowed because a listener happened to be in the way. A host feeding
/// `operationSuccesses` / `operationErrors` into a pipeline that is not
/// this widget should pass `ChatViewBehaviors(showOperationFeedback:
/// false)` instead.
class OperationFeedbackListener extends StatefulWidget {
  const OperationFeedbackListener({
    super.key,
    required this.successes,
    required this.child,
    this.errors,
    this.enabled = true,
    this.theme = ChatTheme.defaults,
    this.labelBuilder,
    this.errorLabelBuilder,
    this.snackBarBuilder,
    this.duration = const Duration(seconds: 2),
  });

  final Stream<OperationSuccess> successes;

  /// Optional failure stream (typically `chatAdapter.operationErrors`).
  /// When provided, the listener shows a soft snackbar for the failures
  /// [errorLabelBuilder] returns text for (default: content-filter
  /// rejections, and a `retrySend` refused because the row's file was
  /// never uploaded). Leave null to keep the success-only behaviour.
  ///
  /// Omitting it does not silence failures for a `NomaChatView` below:
  /// this listener then reports [OperationFeedbackCoverage.successesOnly]
  /// and the view mounts a failures-only listener of its own underneath.
  /// Pass the stream to route those failures through this listener's
  /// [errorLabelBuilder] / [snackBarBuilder] instead.
  final Stream<OperationError>? errors;
  final Widget child;
  final bool enabled;
  final ChatTheme theme;
  final OperationSuccessLabelBuilder? labelBuilder;
  final OperationErrorLabelBuilder? errorLabelBuilder;
  final SnackBar Function(BuildContext context, String message)?
  snackBarBuilder;
  final Duration duration;

  /// What an [OperationFeedbackListener] above [context] already delivers
  /// to the user.
  ///
  /// Reports what the ancestor *shows*, not that one exists: a listener
  /// mounted without [errors] is [OperationFeedbackCoverage.successesOnly]
  /// however it was configured otherwise, because failures reach nobody
  /// through it. `NomaChatView` reads this before mounting its own, so
  /// wrapping the view by hand never doubles an event and never suppresses
  /// the half the wrapper left out.
  static OperationFeedbackCoverage coverageAbove(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_OperationFeedbackScope>();
    if (scope == null) return OperationFeedbackCoverage.none;
    return scope.coversErrors
        ? OperationFeedbackCoverage.everything
        : OperationFeedbackCoverage.successesOnly;
  }

  @override
  State<OperationFeedbackListener> createState() =>
      _OperationFeedbackListenerState();
}

class _OperationFeedbackListenerState extends State<OperationFeedbackListener> {
  StreamSubscription<OperationSuccess>? _sub;
  StreamSubscription<OperationError>? _errorSub;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(covariant OperationFeedbackListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.successes != widget.successes ||
        oldWidget.errors != widget.errors ||
        oldWidget.enabled != widget.enabled) {
      _sub?.cancel();
      _errorSub?.cancel();
      _attach();
    }
  }

  void _attach() {
    if (!widget.enabled) return;
    _sub = widget.successes.listen(_handle);
    _errorSub = widget.errors?.listen(_handleError);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }

  void _handleError(OperationError event) {
    if (!mounted) return;
    final label = (widget.errorLabelBuilder ?? _defaultErrorLabel)(
      context,
      event,
      widget.theme,
    );
    if (label == null || label.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final snackBar =
        widget.snackBarBuilder?.call(context, label) ??
        SnackBar(
          content: Text(label),
          duration: widget.duration,
          behavior: SnackBarBehavior.floating,
        );
    messenger.showSnackBar(snackBar);
  }

  String? _defaultErrorLabel(
    BuildContext context,
    OperationError event,
    ChatTheme theme,
  ) {
    // Only the failures the bubble itself cannot express get a soft toast:
    // the content-filter rejection, and a retry refused because the file
    // never made it up (tapping retry again does nothing). A 403 "muted"
    // is handled by the read-only banner (the composer locks), and every
    // other failure stays a retryable failed bubble — toasting those
    // would just be noise.
    final failure = event.failure;
    if (failure is ContentFilterFailure) {
      return theme.l10nOf(context).messageBlockedByModeration;
    }
    if (failure is ValidationFailure &&
        failure.errors?['reason'] == 'attachment_never_uploaded') {
      return theme.l10nOf(context).attachmentNeverUploaded;
    }
    return null;
  }

  void _handle(OperationSuccess event) {
    if (!mounted) return;
    final label = (widget.labelBuilder ?? _defaultLabel)(
      context,
      event,
      widget.theme,
    );
    if (label == null || label.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final snackBar =
        widget.snackBarBuilder?.call(context, label) ??
        SnackBar(
          content: Text(label),
          duration: widget.duration,
          behavior: SnackBarBehavior.floating,
        );
    messenger.showSnackBar(snackBar);
  }

  String? _defaultLabel(
    BuildContext context,
    OperationSuccess event,
    ChatTheme theme,
  ) {
    final l10n = theme.l10nOf(context);
    switch (event.kind) {
      case OperationKind.pinMessage:
        return l10n.feedbackMessagePinned;
      case OperationKind.unpinMessage:
        return l10n.feedbackMessageUnpinned;
      case OperationKind.deleteMessage:
        return l10n.feedbackMessageDeleted;
      case OperationKind.forwardMessage:
        // Forward count piggybacks on `event.messageId` (see
        // `ChatUiAdapter.forwardMessage`). Falls back to 1 when the
        // payload is missing or malformed.
        final count = int.tryParse(event.messageId ?? '') ?? 1;
        return l10n.feedbackForwarded(count);
      default:
        // No built-in label for other kinds (mute/pin room/etc).
        // Consumers wanting feedback for those should provide a
        // custom `labelBuilder`.
        return null;
    }
  }

  @override
  Widget build(BuildContext context) => _OperationFeedbackScope(
    coversErrors: !widget.enabled || widget.errors != null,
    child: widget.child,
  );
}

/// How much of the operation feedback an [OperationFeedbackListener]
/// mounted above a given context already delivers. A widget below it —
/// `NomaChatView` — reads it through
/// [OperationFeedbackListener.coverageAbove] and mounts exactly the part
/// nobody is showing yet, rather than inferring from the mere presence of
/// a listener.
enum OperationFeedbackCoverage {
  /// Nothing above shows operation feedback: whoever asks owns both
  /// streams.
  none,

  /// A listener above confirms successes but was mounted without an
  /// `errors` stream. The failures a failed bubble cannot express — a
  /// moderation rejection, a retry refused because the file was never
  /// uploaded — still reach nobody, so a widget below covers those and
  /// leaves the successes to the listener above.
  successesOnly,

  /// A listener above covers successes and failures alike, or was mounted
  /// with `enabled: false` — silencing your own listener is a request for
  /// silence, and that switch would be dead if the widget below spoke
  /// over it. Nothing below adds anything either way.
  everything,
}

/// Marker an [OperationFeedbackListener] plants over its subtree so a
/// widget below it — `NomaChatView` — can tell how much of the operation
/// feedback is already taken care of. [coversErrors] is what decides it:
/// `true` when the listener was handed an `errors` stream, and also when
/// it was disabled outright.
class _OperationFeedbackScope extends InheritedWidget {
  const _OperationFeedbackScope({
    required super.child,
    required this.coversErrors,
  });

  final bool coversErrors;

  @override
  bool updateShouldNotify(_OperationFeedbackScope oldWidget) =>
      oldWidget.coversErrors != coversErrors;
}
