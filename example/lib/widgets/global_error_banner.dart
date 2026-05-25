import 'dart:async';

import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

import '../chat_provider.dart';
import '../locale_provider.dart';

/// Subscribes to `adapter.operationErrors` once and shows a SnackBar for
/// every failure, demonstrating the F3.4 stream. Mounted as a global
/// `MaterialApp.builder` so it covers every page.
class GlobalErrorBanner extends StatefulWidget {
  const GlobalErrorBanner({super.key, required this.child});

  final Widget child;

  @override
  State<GlobalErrorBanner> createState() => _GlobalErrorBannerState();
}

class _GlobalErrorBannerState extends State<GlobalErrorBanner> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<OperationError>? _sub;
  bool _bound = false;
  // Captured once per build so `_onError` (which runs outside a build
  // phase, from the SDK stream) doesn't need a BuildContext to format
  // the SnackBar text in the active language.
  String _errorTemplate = '{kind} failed: {failure}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _errorTemplate = LocaleProvider.of(context).strings.globalErrorTemplate;
    if (_bound) return;
    _bound = true;
    final chat = ChatProvider.of(context);
    _sub = chat.adapter.operationErrors.listen(_onError);
  }

  void _onError(OperationError err) {
    // The SDK emits these via `adapter.operationErrors` whenever an SDK call
    // from controllers (ChatController.send, RoomListController.refresh, …)
    // fails. Surface each one to the user as a SnackBar.
    final message = _errorTemplate
        .replaceAll('{kind}', err.kind.name)
        .replaceAll('{failure}', err.failure.toString());
    _messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(key: _messengerKey, child: widget.child);
  }
}
