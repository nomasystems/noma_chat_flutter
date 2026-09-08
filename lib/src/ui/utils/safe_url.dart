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

final RegExp _emailPath = RegExp(
  r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9]([A-Za-z0-9\-]*[A-Za-z0-9])?'
  r'(\.[A-Za-z0-9]([A-Za-z0-9\-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,}$',
);

final RegExp _telPath = RegExp(r'^\+?[0-9][0-9 \-.()]{6,20}$');

/// Returns [raw] as a [Uri] the platform is allowed to open on a tap in the
/// message body: a web address, an email address or a phone number.
///
/// A superset of [webUrlOrNull] by exactly two schemes, and no more. The
/// bubble linkifies `chiara@example.com` and `+34655000011` as well as web
/// addresses, and a blue underline that does nothing when tapped is worse
/// than no underline at all — so `mailto:` and `tel:` are launchable, while
/// `javascript:`, `file:`, `intent:` and host deep links stay out for the
/// same reason they are out of [webUrlOrNull]: the string was written by
/// whoever sent the message.
///
/// Both extra schemes are validated by shape, not just by prefix: a
/// `mailto:` has to carry something that looks like an address and a `tel:`
/// something that looks like a number, so a crafted `tel:` cannot smuggle
/// arbitrary payload past the launcher.
Uri? launchableUrlOrNull(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return webUrlOrNull(trimmed);
  switch (uri.scheme.toLowerCase()) {
    case 'mailto':
      return _emailPath.hasMatch(uri.path) ? uri : null;
    case 'tel':
      return _telPath.hasMatch(uri.path) ? uri : null;
    default:
      return webUrlOrNull(trimmed);
  }
}

/// Fallback link handler shared by every view that renders message text:
/// hands [url] to the platform, and only when [launchableUrlOrNull] accepts
/// it as a web, mail or phone address. Best effort — bad URLs and schemes
/// outside that allowlist are silently skipped. Views take it as the `??`
/// default so a host that passes its own handler (in-app webview,
/// deep-link router, confirmation dialog) always wins and owns the
/// filtering from there.
Future<void> openWebUrl(String url) async {
  final uri = launchableUrlOrNull(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
