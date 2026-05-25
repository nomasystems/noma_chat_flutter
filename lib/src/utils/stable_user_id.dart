import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Persists a stable opaque id per typed display name.
///
/// In real production, a chat app gets its `userId` from an external
/// auth provider (Cognito `sub`, Firebase `uid`, etc.) — an opaque
/// identifier distinct from the user's display name. Demo / example
/// apps without that infrastructure still need stable ids so the
/// backend can key conversations, history and contacts off the same
/// row across logins.
///
/// [forDisplayName] mints a UUID v4 the first time it sees a name,
/// persists it under `<keyPrefix><name>` in `SharedPreferences`, and
/// returns the same id on subsequent calls. Useful as a drop-in for
/// demo/example apps until they wire real auth.
///
/// ```dart
/// final userId = await StableUserId.forDisplayName('alice');
/// final config = ChatConfig.withBasicAuth(
///   username: userId,
///   ...,
/// );
/// ```
class StableUserId {
  StableUserId._();

  static const _uuid = Uuid();

  static const String defaultKeyPrefix = 'noma_chat:userIdFor:';

  /// Returns the persisted UUID for [displayName], minting a fresh one
  /// when none is stored yet. Whitespace in [displayName] is trimmed
  /// and the lookup is case-sensitive — pass the same canonical form
  /// (typically lowercased) you intend to use across sessions.
  ///
  /// Provide [prefs] when you already hold the `SharedPreferences`
  /// instance; otherwise it's resolved internally via
  /// `SharedPreferences.getInstance()`.
  static Future<String> forDisplayName(
    String displayName, {
    SharedPreferences? prefs,
    String keyPrefix = defaultKeyPrefix,
  }) async {
    final canonical = displayName.trim();
    if (canonical.isEmpty) {
      throw ArgumentError('displayName cannot be empty');
    }
    final store = prefs ?? await SharedPreferences.getInstance();
    final key = '$keyPrefix$canonical';
    final existing = store.getString(key);
    if (existing != null && existing.isNotEmpty) return existing;
    final fresh = _uuid.v4();
    await store.setString(key, fresh);
    return fresh;
  }

  /// Removes the persisted id for [displayName]. The next call to
  /// [forDisplayName] with the same name will mint a fresh UUID.
  /// Useful as part of a "wipe demo data" flow.
  static Future<void> forget(
    String displayName, {
    SharedPreferences? prefs,
    String keyPrefix = defaultKeyPrefix,
  }) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    await store.remove('$keyPrefix${displayName.trim()}');
  }
}
