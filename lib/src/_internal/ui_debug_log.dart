import 'package:flutter/foundation.dart';

/// Debug-only logger for UI widget code paths that don't have access
/// to [ChatConfig.logger] (the SDK-wide structured logger threaded
/// through the client + APIs).
///
/// Why two loggers: domain code (REST/WS/cache/adapter) routes through
/// `ChatConfig.logger` so the host app can wire telemetry. UI widgets
/// are pure leaves with no `ChatConfig` reference — passing the logger
/// through every constructor would bloat the public API for what is
/// strictly debug noise (image load failures, audio playback errors,
/// …). [debugPrint] is *not* a no-op in release builds, so this
/// function gates every call behind [kDebugMode] itself.
///
/// Always tag the source: `uiDebugLog('ImageBubble', 'load failed: …')`
/// so logs are scannable across the example output.
void uiDebugLog(String tag, String message) {
  if (!kDebugMode) return;
  debugPrint('[noma_chat][$tag] $message');
}
