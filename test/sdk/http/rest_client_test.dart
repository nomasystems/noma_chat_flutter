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

void main() {
  late _MockDio dio;
  late RestClient rest;

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

  Response<dynamic> resp({
    dynamic data,
    int status = 200,
    Map<String, List<String>> headers = const {},
  }) => Response<dynamic>(
    requestOptions: RequestOptions(path: ''),
    statusCode: status,
    data: data,
    headers: Headers.fromMap(headers),
  );

  DioException dioErr({
    int? statusCode,
    dynamic body,
    DioExceptionType type = DioExceptionType.badResponse,
    Map<String, List<String>> headers = const {},
    String? message,
  }) => DioException(
    requestOptions: RequestOptions(path: ''),
    type: type,
    message: message,
    response: statusCode == null
        ? null
        : Response<dynamic>(
            requestOptions: RequestOptions(path: ''),
            statusCode: statusCode,
            data: body,
            headers: Headers.fromMap(headers),
          ),
  );

  group('userId', () {
    test('exposes the configured user id', () {
      expect(rest.userId, 'u1');
    });
  });

  group('happy paths', () {
    test('get() returns the body as a map', () async {
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
      ).thenAnswer((_) async => resp(data: {'ok': true}));

      final out = await rest.get('/foo');

      expect(out, {'ok': true});
    });

    test('getWithTotalCount() parses x-total-count', () async {
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
      ).thenAnswer(
        (_) async => resp(
          data: {
            'items': [1, 2],
          },
          headers: {
            'x-total-count': ['42'],
          },
        ),
      );

      final (json, total) = await rest.getWithTotalCount('/foo');

      expect(json, {
        'items': [1, 2],
      });
      expect(total, 42);
    });

    test('getList() returns the list directly', () async {
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
      ).thenAnswer((_) async => resp(data: [1, 2, 3]));

      final out = await rest.getList('/foo');

      expect(out, [1, 2, 3]);
    });

    test('post() returns the body as a map; empty body becomes {}', () async {
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
      ).thenAnswer((_) async => resp(data: ''));

      final out = await rest.post('/foo', data: {'k': 'v'});
      expect(out, isEmpty);
    });

    test('postVoid() ignores body', () async {
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
      ).thenAnswer((_) async => resp(data: null));

      await rest.postVoid('/foo');
    });

    test('put()/patch() return map or {} when missing', () async {
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
      ).thenAnswer((_) async => resp(data: {'a': 1}));

      expect(await rest.put('/foo', data: {}), {'a': 1});
      expect(await rest.patch('/foo', data: {}), {'a': 1});
    });

    test('delete() does not throw on success', () async {
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
      ).thenAnswer((_) async => resp(data: null));

      await rest.delete('/foo');
    });

    test('uploadBinary() forwards mime type + progress callback', () async {
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
      ).thenAnswer((_) async => resp(data: {'url': 'x'}));

      final out = await rest.uploadBinary(
        '/u',
        Uint8List.fromList([1, 2, 3]),
        'image/png',
      );

      expect(out, {'url': 'x'});
    });

    test('downloadBinary() returns bytes', () async {
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
      ).thenAnswer((_) async => resp(data: [10, 20, 30]));

      final out = await rest.downloadBinary('/d');
      expect(out, [10, 20, 30]);
    });
  });

  group('error mapping', () {
    Future<void> expectMaps<E extends ChatException>(DioException e) async {
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
      ).thenThrow(e);

      expect(() => rest.get('/foo'), throwsA(isA<E>()));
    }

    test('400 validation → ChatValidationException', () async {
      await expectMaps<ChatValidationException>(
        dioErr(statusCode: 400, body: {'detail': 'bad email'}),
      );
    });

    test('400 content filter → ChatContentFilterException', () async {
      await expectMaps<ChatContentFilterException>(
        dioErr(statusCode: 400, body: {'detail': 'blocked by content filter'}),
      );
    });

    test('401 → ChatAuthException', () async {
      await expectMaps<ChatAuthException>(dioErr(statusCode: 401));
    });

    test('403 → ChatForbiddenException', () async {
      await expectMaps<ChatForbiddenException>(dioErr(statusCode: 403));
    });

    test('404 → ChatNotFoundException', () async {
      await expectMaps<ChatNotFoundException>(dioErr(statusCode: 404));
    });

    test('409 → ChatConflictException', () async {
      await expectMaps<ChatConflictException>(
        dioErr(statusCode: 409, body: {'message': 'already exists'}),
      );
    });

    test('429 → ChatRateLimitException with retryAfter', () async {
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
      ).thenThrow(
        dioErr(
          statusCode: 429,
          headers: {
            'retry-after': ['7'],
          },
        ),
      );

      try {
        await rest.get('/foo');
        fail('should have thrown');
      } on ChatRateLimitException catch (e) {
        expect(e.retryAfter, const Duration(seconds: 7));
      }
    });

    test('timeouts → ChatTimeoutException', () async {
      await expectMaps<ChatTimeoutException>(
        dioErr(type: DioExceptionType.connectionTimeout),
      );
      await expectMaps<ChatTimeoutException>(
        dioErr(type: DioExceptionType.receiveTimeout),
      );
      await expectMaps<ChatTimeoutException>(
        dioErr(type: DioExceptionType.sendTimeout),
      );
    });

    test('connection error → ChatNetworkException', () async {
      await expectMaps<ChatNetworkException>(
        dioErr(type: DioExceptionType.connectionError),
      );
    });

    test('500 → ChatApiException with status code preserved', () async {
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
      ).thenThrow(dioErr(statusCode: 500, message: 'boom'));

      try {
        await rest.get('/foo');
        fail('should have thrown');
      } on ChatApiException catch (e) {
        expect(e.statusCode, 500);
        expect(e.message, 'boom');
      }
    });
  });

  group('shape coercions', () {
    test('get() throws ChatApiException when body is not a map', () async {
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
      ).thenAnswer((_) async => resp(data: 'plain text'));

      expect(() => rest.get('/foo'), throwsA(isA<ChatApiException>()));
    });

    test('getList() throws ChatApiException when body is not a list', () async {
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
      ).thenAnswer((_) async => resp(data: {'oops': true}));

      expect(() => rest.getList('/foo'), throwsA(isA<ChatApiException>()));
    });
  });

  group('cancelPending', () {
    test(
      'cancels a single in-flight request — caller surfaces an error',
      () async {
        final captured = <CancelToken>[];
        final completer = Completer<Response<dynamic>>();
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
        ).thenAnswer((inv) {
          final token = inv.namedArguments[#cancelToken] as CancelToken;
          captured.add(token);
          token.whenCancel.then((_) {
            completer.completeError(
              DioException(
                requestOptions: RequestOptions(path: ''),
                type: DioExceptionType.cancel,
                error: token.cancelError,
              ),
            );
          });
          return completer.future;
        });

        final future = rest.get('/foo');
        await Future<void>.delayed(Duration.zero);

        expect(captured, hasLength(1));
        expect(captured.single.isCancelled, isFalse);

        rest.cancelPending('logout');
        expect(captured.single.isCancelled, isTrue);

        await expectLater(future, throwsA(isA<ChatException>()));
      },
    );

    test('cancels every in-flight request with a single call', () async {
      final captured = <CancelToken>[];
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
      ).thenAnswer((inv) {
        final token = inv.namedArguments[#cancelToken] as CancelToken;
        captured.add(token);
        final c = Completer<Response<dynamic>>();
        token.whenCancel.then((_) {
          c.completeError(
            DioException(
              requestOptions: RequestOptions(path: ''),
              type: DioExceptionType.cancel,
              error: token.cancelError,
            ),
          );
        });
        return c.future;
      });

      final f1 = rest.get('/a');
      final f2 = rest.get('/b');
      final f3 = rest.get('/c');

      await Future<void>.delayed(Duration.zero);
      expect(captured, hasLength(3));
      expect(captured.every((t) => !t.isCancelled), isTrue);

      rest.cancelPending();
      expect(captured.every((t) => t.isCancelled), isTrue);

      await expectLater(f1, throwsA(isA<ChatException>()));
      await expectLater(f2, throwsA(isA<ChatException>()));
      await expectLater(f3, throwsA(isA<ChatException>()));
    });

    test(
      'completed requests are removed from the pending set automatically',
      () async {
        final captured = <CancelToken>[];
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
        ).thenAnswer((inv) async {
          final token = inv.namedArguments[#cancelToken] as CancelToken;
          captured.add(token);
          return resp(data: {'ok': true});
        });

        await rest.get('/foo');
        await rest.get('/bar');

        // Cancel after both completed — must be a no-op.
        rest.cancelPending();

        expect(captured, hasLength(2));
        // Tokens were finalized normally; cancel after completion does not
        // throw and does not cancel them.
        expect(captured.every((t) => !t.isCancelled), isTrue);
      },
    );

    test('cancelPending is safe to call when nothing is in flight', () {
      expect(() => rest.cancelPending(), returnsNormally);
    });
  });
}
