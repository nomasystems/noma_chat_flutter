import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/result.dart' show ContentFilterFailure;
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
/// for *expected* moderation failures (content filter) and stays silent
/// for everything else, so transient/network errors keep surfacing as
/// failed-message bubbles rather than noisy toasts.
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
///   to suppress it (`return null`). The default uses `ChatTheme.l10n`
///   strings (`feedbackMessagePinned` / `feedbackMessageDeleted` / …).
/// - Pass [snackBarBuilder] for fully custom widgets (e.g. a top
///   banner instead of a snackbar). Default builds a stock `SnackBar`.
/// - Pass [duration] to change visible time (default 2s).
///
/// Wrap any subtree that contains a `Scaffold` with this widget. The
/// snackbar attaches to `ScaffoldMessenger.maybeOf(context)` so missing
/// scaffolds are silently ignored.
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
  /// rejections only). Leave null to keep the success-only behaviour.
  final Stream<OperationError>? errors;
  final Widget child;
  final bool enabled;
  final ChatTheme theme;
  final OperationSuccessLabelBuilder? labelBuilder;
  final OperationErrorLabelBuilder? errorLabelBuilder;
  final SnackBar Function(BuildContext context, String message)?
  snackBarBuilder;
  final Duration duration;

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
    // Only the content-filter rejection gets a soft toast. A 403 "muted"
    // is handled by the read-only banner (the composer locks), and every
    // other failure stays a retryable failed bubble — toasting those
    // would just be noise.
    if (event.failure is ContentFilterFailure) {
      return theme.l10n.messageBlockedByModeration;
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
    final l10n = theme.l10n;
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
  Widget build(BuildContext context) => widget.child;
}
