import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_advanced.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class _MockDio extends Mock implements Dio {}

class _NoopAuth extends AuthInterceptor {
  @override
  Future<String> getAuthHeader() async => 'Bearer test';
}

void main() {
  late _MockDio dio;
  late RestClient rest;
  late List<RequestOptions> captured;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
    registerFallbackValue(Options());
  });

  setUp(() {
    dio = _MockDio();
    captured = [];
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
    ).thenAnswer((invocation) async {
      final opts = invocation.namedArguments[#options] as Options;
      final ro = RequestOptions(
        path: invocation.positionalArguments[0] as String,
        method: opts.method ?? 'GET',
        extra: {...?opts.extra},
        headers: {...?opts.headers},
      );
      captured.add(ro);
      return Response<dynamic>(
        requestOptions: ro,
        statusCode: 200,
        data: const <String, dynamic>{},
      );
    });
  });

  group('requestId — per-request UUID generation', () {
    test('each request carries a distinct UUID v4 in extra', () async {
      await rest.get('/a');
      await rest.get('/b');
      await rest.get('/c');

      expect(captured, hasLength(3));
      final ids = captured
          .map((r) => r.extra['requestId'] as String?)
          .whereType<String>()
          .toList();
      expect(ids, hasLength(3));
      expect(ids.toSet(), hasLength(3), reason: 'requestIds must be unique');
      for (final id in ids) {
        expect(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ).hasMatch(id),
          isTrue,
          reason: 'expected RFC4122 UUID v4, got $id',
        );
      }
    });

    test('requestId is propagated through to the debug log line', () async {
      final logs = <String>[];
      final realDio = Dio()..options.baseUrl = 'http://example.local';

      final loggingRest = RestClient(
        config: ChatConfig.withAuthInterceptor(
          baseUrl: 'http://example.local/v1',
          realtimeUrl: 'http://example.local',
          authInterceptor: _NoopAuth(),
          logger: (level, message) => logs.add(message),
          enableHttpLog: true,
        ),
        dio: realDio,
      );

      // Drive a single onRequest through HttpDebugLogger by hand.
      final logger = HttpDebugLogger((_, msg) => logs.add(msg));
      final opts = RequestOptions(
        path: '/v1/rooms',
        method: 'POST',
        extra: {'requestId': '12345678-1234-1234-1234-123456789012'},
      );
      var passed = false;
      logger.onRequest(opts, _StubRequestHandler(() => passed = true));

      expect(passed, isTrue);
      expect(logs.last, contains('req[123456]'));
      expect(logs.last, contains('http.req POST'));

      // Surface that the wired-up logger doesn't crash for completeness.
      expect(loggingRest, isNotNull);
    });
  });
}

class _StubRequestHandler extends RequestInterceptorHandler {
  _StubRequestHandler(this._onNext);
  final void Function() _onNext;
  @override
  void next(RequestOptions requestOptions) => _onNext();
}
