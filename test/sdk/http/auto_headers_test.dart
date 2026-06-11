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
  late List<Map<String, dynamic>> capturedHeaders;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
    registerFallbackValue(Options());
  });

  setUp(() {
    dio = _MockDio();
    capturedHeaders = [];
    when(() => dio.options).thenReturn(BaseOptions());
    when(() => dio.interceptors).thenReturn(Interceptors());

    rest = RestClient(
      config: ChatConfig.withAuthInterceptor(
        baseUrl: 'http://h/v1',
        realtimeUrl: 'http://h',
        authInterceptor: _NoopAuth(),
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
      capturedHeaders.add({...?opts.headers});
      return Response<dynamic>(
        requestOptions: RequestOptions(
          path: invocation.positionalArguments[0] as String,
        ),
        statusCode: 200,
        data: const <String, dynamic>{},
      );
    });
  });

  group('Automatic SDK headers', () {
    test('X-Noma-Chat-Version is set to the package version', () async {
      await rest.get('/foo');
      expect(capturedHeaders, hasLength(1));
      expect(capturedHeaders.first['X-Noma-Chat-Version'], nomaChatSdkVersion);
    });

    test('User-Agent contains the package name and version', () async {
      await rest.get('/foo');
      final ua = capturedHeaders.first['User-Agent'] as String?;
      expect(ua, isNotNull);
      expect(ua, contains('noma_chat/$nomaChatSdkVersion'));
    });

    test('consumer-provided User-Agent wins over the SDK default '
        '(case-insensitive)', () async {
      await rest.get('/foo', headers: {'User-Agent': 'WB-Mobile/1.2.3'});

      final ua = capturedHeaders.first['User-Agent'] as String?;
      expect(ua, 'WB-Mobile/1.2.3');
    });

    test(
      'consumer-provided X-Noma-Chat-Version wins over the SDK default',
      () async {
        await rest.get('/foo', headers: {'X-Noma-Chat-Version': '99.99.99'});

        expect(capturedHeaders.first['X-Noma-Chat-Version'], '99.99.99');
      },
    );

    test('X-From-User-Id is injected when actAsUserId is configured', () async {
      final delegating = RestClient(
        config: ChatConfig.withAuthInterceptor(
          baseUrl: 'http://h/v1',
          realtimeUrl: 'http://h',
          authInterceptor: _NoopAuth(),
          actAsUserId: 'managed-1',
        ),
        dio: dio,
      );
      await delegating.get('/foo');
      expect(capturedHeaders.first['X-From-User-Id'], 'managed-1');
    });

    test('X-From-User-Id is absent without actAsUserId', () async {
      await rest.get('/foo');
      expect(capturedHeaders.first.containsKey('X-From-User-Id'), isFalse);
    });

    test(
      'consumer-provided X-From-User-Id wins over the configured one',
      () async {
        final delegating = RestClient(
          config: ChatConfig.withAuthInterceptor(
            baseUrl: 'http://h/v1',
            realtimeUrl: 'http://h',
            authInterceptor: _NoopAuth(),
            actAsUserId: 'managed-1',
          ),
          dio: dio,
        );
        await delegating.get('/foo', headers: {'X-From-User-Id': 'override'});
        expect(capturedHeaders.first['X-From-User-Id'], 'override');
      },
    );

    test('lowercase user-agent in caller headers still wins', () async {
      await rest.get('/foo', headers: {'user-agent': 'mobile/1.0'});

      // Both names may be present, but the SDK MUST NOT have overridden
      // the consumer-supplied one. The merged map keeps the lowercase
      // key the consumer used.
      expect(capturedHeaders.first['user-agent'], 'mobile/1.0');
      expect(
        capturedHeaders.first.containsKey('User-Agent'),
        isFalse,
        reason:
            'SDK auto-header must not be added when the consumer '
            'already provided one (case-insensitive)',
      );
    });
  });
}
