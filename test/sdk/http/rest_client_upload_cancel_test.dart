import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/src/_internal/http/chat_exception.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class _MockDio extends Mock implements Dio {}

class _NoopAuth extends AuthInterceptor {
  @override
  Future<String> getAuthHeader() async => 'Bearer test';
}

/// The bridge that makes `UploadCancelToken` an abort instead of a flag.
///
/// Everything above this — the bubble's X, `ChatUiAdapter.cancelAttachmentUpload`,
/// the session teardown's `cancelAll` — ends in `UploadCancelToken.cancel()`,
/// and that call reaches the wire through exactly one line: the
/// `bindOnCancel` in [RestClient.uploadBinary], which cancels the request's
/// own Dio `CancelToken`. Nothing polls `isCancelled`, and nothing can: the
/// upload it has to stop is parked with its body fully written, waiting for
/// a response that has not started arriving. Without the bridge every layer
/// above still behaves — the flag flips, the failure is reported — while the
/// bytes finish going out and land as a blob no message references.
///
/// This file is the ONLY mutant-killer for three lines of `rest_client.dart`,
/// which is why it stays even though no line of any recent diff can turn it
/// red: the `bindOnCancel` bridge inside `uploadBinary` (three tests here go
/// red without it), the `DioExceptionType.cancel` + `_uploadCancelledReason`
/// mapping to `ChatCancelledException` (two), and the `if (cancelToken !=
/// null)` that keeps a caller-less upload from minting a token
/// `cancelPendingRequests` could mistake for a cancelled upload (one). It is
/// a transport contract test, not diff characterisation — read it as such
/// before pruning it.
void main() {
  late _MockDio dio;
  late RestClient rest;

  final payload = Uint8List.fromList(List<int>.filled(32, 7));

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
    registerFallbackValue(Options());
  });

  setUp(() {
    dio = _MockDio();
    when(() => dio.options).thenReturn(BaseOptions());
    when(() => dio.interceptors).thenReturn(Interceptors());
    rest = RestClient(
      config: ChatConfig.withAuthInterceptor(
        baseUrl: 'http://h/v1',
        realtimeUrl: 'http://h',
        authInterceptor: _NoopAuth(),
        userId: 'u1',
      ),
      dio: dio,
    );
  });

  /// Stands in for a real POST that is still on the wire: it never answers on
  /// its own, and fails exactly the way Dio fails a cancelled request — with
  /// the token's own error. Completes [started] with the token the client
  /// handed it, so a test can inspect what the transport actually received.
  Completer<CancelToken> stubInFlightUpload() {
    final started = Completer<CancelToken>();
    when(
      () => dio.request(
        any(),
        data: any(named: 'data'),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
        onSendProgress: any(named: 'onSendProgress'),
        onReceiveProgress: any(named: 'onReceiveProgress'),
      ),
    ).thenAnswer((invocation) async {
      final token = invocation.namedArguments[#cancelToken] as CancelToken;
      started.complete(token);
      throw await token.whenCancel;
    });
    return started;
  }

  test('cancelling the caller token aborts the request on the wire, it does '
      'not merely record the intent', () async {
    final started = stubInFlightUpload();
    final token = UploadCancelToken();

    final upload = rest.uploadBinary(
      '/attachments',
      payload,
      'image/png',
      cancelToken: token,
    );
    final requestToken = await started.future;
    expect(
      requestToken.isCancelled,
      isFalse,
      reason: 'nothing has asked for the abort yet',
    );

    token.cancel();

    // The assertion the whole defence rests on: the caller's token reached
    // the request's own token. A `bindOnCancel` that never ran leaves this
    // false while every layer above still reports a tidy cancellation.
    expect(requestToken.isCancelled, isTrue);
    await expectLater(upload, throwsA(isA<ChatCancelledException>()));
  });

  test('an upload handed an already-cancelled token never gets to write its '
      'body', () async {
    // The teardown-then-send order: `cancelAll` runs while the send is still
    // between `register` and its upload call. Binding has to honour a token
    // that was cancelled before there was anything to bind it to.
    final started = stubInFlightUpload();
    final token = UploadCancelToken()..cancel();

    // Awaited first: this one fails before the test ever gets to look at the
    // token, and an unwatched rejection is an unhandled async error.
    await expectLater(
      rest.uploadBinary(
        '/attachments',
        payload,
        'image/png',
        cancelToken: token,
      ),
      throwsA(isA<ChatCancelledException>()),
    );

    final requestToken = await started.future;
    expect(requestToken.isCancelled, isTrue);
  });

  test('the abort is tagged as an upload cancel, so the send above can tell '
      'it apart from a bulk teardown', () async {
    // `_mapDioException` keys `ChatCancelledException` — and through it the
    // `CancelledFailure` that `sendAttachment` reads to delete a provisional
    // bubble — off this exact reason, not off "any cancelled request".
    // `cancelPendingRequests('disconnect')` cancels tokens too, and must keep
    // mapping to the generic failure.
    final started = stubInFlightUpload();
    final token = UploadCancelToken();

    unawaited(
      rest
          .uploadBinary(
            '/attachments',
            payload,
            'image/png',
            cancelToken: token,
          )
          .catchError((_) => <String, dynamic>{}),
    );
    final requestToken = await started.future;

    token.cancel();

    expect(requestToken.cancelError?.error, 'upload_cancelled');
  });

  test('an upload with no caller token is still cancellable in bulk, but '
      'brings no token of its own', () async {
    // `_request` mints one when the caller passes none, so `cancelPending`
    // still reaches the upload. What must not happen is `uploadBinary`
    // fabricating an upload-cancel tag for a request nobody asked to abort.
    final started = stubInFlightUpload();

    unawaited(
      rest
          .uploadBinary('/attachments', payload, 'image/png')
          .catchError((_) => <String, dynamic>{}),
    );

    final requestToken = await started.future;
    expect(requestToken.isCancelled, isFalse);

    requestToken.cancel('disconnect');
    expect(requestToken.cancelError?.error, isNot('upload_cancelled'));
  });
}
