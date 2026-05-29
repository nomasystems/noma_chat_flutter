import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/src/_internal/http/cert_pinning_interceptor.dart';
import 'package:noma_chat/src/_internal/http/chat_exception.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class _MockDio extends Mock implements Dio {}

class _NoopAuth extends AuthInterceptor {
  @override
  Future<String> getAuthHeader() async => 'Bearer test';
}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
    registerFallbackValue(Options());
  });

  group('CertificatePinningInterceptor — skeleton', () {
    test('default (no pins) does not break HTTP traffic', () {
      final dio = _MockDio();
      when(() => dio.options).thenReturn(BaseOptions());
      when(() => dio.interceptors).thenReturn(Interceptors());

      expect(
        () => RestClient(
          config: ChatConfig.withAuthInterceptor(
            baseUrl: 'http://h/v1',
            realtimeUrl: 'http://h',
            authInterceptor: _NoopAuth(),
          ),
          dio: dio,
        ),
        returnsNormally,
      );
    });

    test('pins are normalized (case-insensitive, colon-stripped)', () {
      final interceptor = CertificatePinningInterceptor([
        'AA:BB:CC:DD',
        'aabbccdd',
        'AABBCCDD',
      ]);
      expect(interceptor.pins, ['aabbccdd', 'aabbccdd', 'aabbccdd']);
    });

    test('attach() is a no-op on web; non-throwing on native too', () {
      final interceptor = CertificatePinningInterceptor([
        'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
      ]);
      final dio = Dio();
      expect(() => interceptor.attach(dio), returnsNormally);
    });

    test('onError converts handshake/certificate errors into '
        'CertificatePinningException when pins are configured', () async {
      final interceptor = CertificatePinningInterceptor(['aabbccdd']);
      final dio = Dio();
      dio.interceptors.add(interceptor);

      final err = DioException(
        requestOptions: RequestOptions(path: '/foo'),
        type: DioExceptionType.unknown,
        error: const _FakeHandshakeError(),
        message: 'HandshakeException: certificate verify failed',
      );

      DioException? mapped;
      final handler = _CapturingHandler((e) => mapped = e);
      interceptor.onError(err, handler);

      expect(mapped, isNotNull);
      expect(mapped!.error, isA<CertificatePinningException>());
      expect((mapped!.error as CertificatePinningException).expectedPins, [
        'aabbccdd',
      ]);
    });

    test('onError leaves unrelated errors untouched', () async {
      final interceptor = CertificatePinningInterceptor(['aabbccdd']);

      final err = DioException(
        requestOptions: RequestOptions(path: '/foo'),
        type: DioExceptionType.connectionTimeout,
        error: 'plain timeout',
        message: 'connection timed out',
      );

      DioException? mapped;
      final handler = _CapturingHandler((e) => mapped = e);
      interceptor.onError(err, handler);

      expect(mapped, isNotNull);
      expect(mapped!.error, isNot(isA<CertificatePinningException>()));
    });

    test(
      'when pins are configured, RestClient surfaces handshake errors as '
      'CertificatePinningException (typed ChatException) to the caller',
      () async {
        final dio = _MockDio();
        when(() => dio.options).thenReturn(BaseOptions());
        when(() => dio.interceptors).thenReturn(Interceptors());

        final rest = RestClient(
          config: ChatConfig.withAuthInterceptor(
            baseUrl: 'http://h/v1',
            realtimeUrl: 'http://h',
            authInterceptor: _NoopAuth(),
            certificatePins: const [
              'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
            ],
          ),
          dio: dio,
        );

        when(
          () => dio.request<dynamic>(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
            cancelToken: any(named: 'cancelToken'),
            onSendProgress: any(named: 'onSendProgress'),
            onReceiveProgress: any(named: 'onReceiveProgress'),
          ),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: '/foo'),
            error: const CertificatePinningException(
              expectedPins: ['deadbeef'],
            ),
          ),
        );

        await expectLater(
          rest.get('/foo'),
          throwsA(isA<CertificatePinningException>()),
        );
      },
    );
  });
}

class _FakeHandshakeError {
  const _FakeHandshakeError();
  @override
  String toString() => 'HandshakeException: certificate verify failed';
}

class _CapturingHandler extends ErrorInterceptorHandler {
  _CapturingHandler(this._onNext);
  final void Function(DioException) _onNext;

  @override
  void next(DioException err) => _onNext(err);
}
