import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:meta/meta.dart' show experimental;

import 'chat_exception.dart';

/// Skeleton SHA-256 certificate pinning interceptor.
///
/// When [pins] is non-empty, [attach] installs a hook on the Dio
/// instance's HTTP adapter that verifies the leaf certificate's
/// SHA-256 fingerprint against the supplied pins. On a mismatch the
/// request fails with a [CertificatePinningException].
///
/// **Current status — skeleton only.** Wiring the platform-specific
/// `badCertificateCallback` requires `dart:io` on native platforms and
/// is a no-op on web (where the browser handles TLS). The hook itself
/// is not yet attached; the consumer-facing contract is in place so
/// the API stays stable while the platform plumbing matures.
///
/// Limitations:
/// - Web: no-op, pinning has to be enforced at the browser/network
///   layer (HPKP is deprecated; use HSTS + CT logs).
/// - Native: the `IOHttpClientAdapter.createHttpClient` override is
///   not yet wired here — adding the dependency on `dio/io.dart` and
///   the SHA-256 helper is left as a follow-up. Until that lands the
///   interceptor's `onError` path will only convert a Dio-surfaced
///   handshake error into the typed [CertificatePinningException].
@experimental
class CertificatePinningInterceptor extends Interceptor {
  final List<String> _pins;

  CertificatePinningInterceptor(List<String> pins)
    : _pins = pins.map(_normalize).toList(growable: false);

  List<String> get pins => List.unmodifiable(_pins);

  /// Installs the platform-specific verification hook on [dio]. On web
  /// this is a no-op; on native it is currently a placeholder (see
  /// class-level docs).
  void attach(Dio dio) {
    if (kIsWeb) return;
    // Skeleton: a future revision will replace `dio.httpClientAdapter`
    // with an `IOHttpClientAdapter` whose `createHttpClient` returns an
    // `HttpClient` with a `badCertificateCallback` that hashes the
    // presented leaf and compares against [_pins]. Kept out of the
    // initial commit so the SDK does not pull in `dart:io` directly
    // and so the change ships behind a focused review.
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (_pins.isEmpty) return handler.next(err);
    final raw = err.error?.toString() ?? err.message ?? '';
    if (raw.toLowerCase().contains('handshake') ||
        raw.toLowerCase().contains('certificate')) {
      handler.next(
        DioException(
          requestOptions: err.requestOptions,
          error: CertificatePinningException(
            expectedPins: _pins,
            message: err.message ?? 'Certificate pinning validation failed',
          ),
          type: err.type,
          response: err.response,
        ),
      );
      return;
    }
    handler.next(err);
  }

  static String _normalize(String pin) =>
      pin.replaceAll(':', '').replaceAll(' ', '').toLowerCase();
}
