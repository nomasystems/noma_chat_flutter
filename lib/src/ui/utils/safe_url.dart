import 'package:url_launcher/url_launcher.dart';

/// Returns [raw] as a launchable `http` / `https` [Uri], or `null` when it
/// is anything else.
///
/// Every URL the chat UI can hand to the platform launcher comes from a
/// message: its text, its `metadata`, or a shared-link row built from
/// either. All three are written by the sender, so a third party is free
/// to put `javascript:`, `file:`, `intent:` or a deep link of the host
/// app where a web address is expected. Only the two web schemes are ever
/// launched; everything outside the allowlist resolves to `null` and must
/// be dropped without launching anything.
///
/// A string with no scheme (`example.com/path`) is read as `https`, which
/// is what a bare domain means to whoever typed it. A parse failure, an
/// empty string and a URL with no host also resolve to `null`.
Uri? webUrlOrNull(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  var uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (!uri.hasScheme) {
    uri = Uri.tryParse('https://$trimmed');
    if (uri == null) return null;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  return uri;
}

/// Fallback link handler shared by every view that renders message text:
/// opens [url] in the system browser, and only when [webUrlOrNull] accepts
/// it as a web address. Best effort — bad URLs and non-web schemes are
/// silently skipped. Views take it as the `??` default so a host that
/// passes its own handler (in-app webview, deep-link router, confirmation
/// dialog) always wins and owns the filtering from there.
Future<void> openWebUrl(String url) async {
  final uri = webUrlOrNull(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
