import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/http/chat_exception.dart';
import 'package:noma_chat/src/_internal/http/rest_client.dart';

class MockRestClient extends Mock implements RestClient {}

void main() {
  late MockRestClient rest;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    rest = MockRestClient();
  });

  Map<String, dynamic> messageJson({
    String id = 'msg-1',
    String from = 'user-1',
    String timestamp = '2025-01-01T00:00:00Z',
    String? text = 'hello',
    String messageType = 'regular',
  }) => {
    'id': id,
    'from': from,
    'timestamp': timestamp,
    if (text != null) 'text': text,
    'messageType': messageType,
  };

  group('AttachmentsApi', () {
    late AttachmentsApi api;

    setUp(() {
      api = AttachmentsApi(rest: rest);
    });

    test('upload() returns AttachmentUploadResult with attachmentId', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      when(
        () => rest.uploadBinary(
          '/attachments',
          bytes,
          'image/png',
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer(
        (_) async => {
          'attachmentId': 'att-123',
          'url': 'https://cdn.example.com/att-123.png',
        },
      );

      final result = await api.upload(bytes, 'image/png');

      expect(result.isSuccess, isTrue);
      final upload = result.dataOrNull!;
      expect(upload.attachmentId, 'att-123');
      expect(upload.url, 'https://cdn.example.com/att-123.png');
      expect(upload.raw['attachmentId'], 'att-123');
    });

    test(
      'upload() falls back to id field when attachmentId is absent',
      () async {
        final bytes = Uint8List.fromList([1, 2, 3]);
        when(
          () => rest.uploadBinary(
            any(),
            any(),
            any(),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer(
          (_) async => {
            'id': 'att-456',
            'url': 'https://cdn.example.com/att-456.png',
          },
        );

        final result = await api.upload(bytes, 'image/png');

        expect(result.dataOrNull!.attachmentId, 'att-456');
      },
    );

    test('upload() encodes metadata map as JSON string', () async {
      final bytes = Uint8List.fromList([1]);
      when(
        () => rest.uploadBinary(
          any(),
          any(),
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer(
        (_) async => {
          'attachmentId': 'att-1',
          'metadata': {'width': 100, 'height': 200},
        },
      );

      final result = await api.upload(bytes, 'image/png');

      expect(result.dataOrNull!.metadata, isNotNull);
      expect(result.dataOrNull!.metadata, contains('width'));
    });

    test('download() gets binary with optional metadata header', () async {
      final expectedBytes = Uint8List.fromList([10, 20, 30]);
      when(
        () => rest.downloadBinary(
          '/attachments/att-1',
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) async => expectedBytes);

      final result = await api.download('att-1', metadata: 'some-meta');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, expectedBytes);
      final captured =
          verify(
                () => rest.downloadBinary(
                  '/attachments/att-1',
                  headers: captureAny(named: 'headers'),
                ),
              ).captured.single
              as Map<String, String>;
      expect(captured['x-attachment-metadata'], 'some-meta');
    });

    test('download() sends empty headers when no metadata', () async {
      when(
        () => rest.downloadBinary(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => Uint8List(0));

      await api.download('att-1');

      final captured =
          verify(
                () => rest.downloadBinary(
                  '/attachments/att-1',
                  headers: captureAny(named: 'headers'),
                ),
              ).captured.single
              as Map<String, String>;
      expect(captured.isEmpty, isTrue);
    });

    test('upload() returns ChatFailureResult on API exception', () async {
      when(
        () => rest.uploadBinary(
          any(),
          any(),
          any(),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenThrow(
        const ChatApiException(statusCode: 413, message: 'Too large'),
      );

      final result = await api.upload(Uint8List(0), 'image/png');

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull, isA<ServerFailure>());
    });
  });

  group('Signed-URL attachment access', () {
    late AttachmentsApi api;

    setUp(() {
      api = AttachmentsApi(rest: rest);
      when(
        () => rest.resolveUrl(any()),
      ).thenAnswer((inv) => inv.positionalArguments.first as String);
    });

    test(
      'signedUrl() gets /signed-url with roomId and resolves the url',
      () async {
        when(
          () => rest.get(
            '/attachments/att-1/signed-url',
            queryParams: any(named: 'queryParams'),
          ),
        ).thenAnswer(
          (_) async => {'url': 'https://cdn.example.com/att-1?sig=abc&exp=123'},
        );

        final result = await api.signedUrl('att-1', roomId: 'r1');

        expect(result.isSuccess, isTrue);
        expect(
          result.dataOrThrow.url,
          'https://cdn.example.com/att-1?sig=abc&exp=123',
        );
        final captured =
            verify(
                  () => rest.get(
                    '/attachments/att-1/signed-url',
                    queryParams: captureAny(named: 'queryParams'),
                  ),
                ).captured.single
                as Map<String, dynamic>;
        expect(captured['roomId'], 'r1');
      },
    );

    test('signedUrl() accepts the downloadUrl alias', () async {
      when(
        () => rest.get(any(), queryParams: any(named: 'queryParams')),
      ).thenAnswer((_) async => {'downloadUrl': 'https://cdn.example.com/dl'});

      final result = await api.signedUrl('att-1', roomId: 'r1');

      expect(result.dataOrThrow.url, 'https://cdn.example.com/dl');
    });

    test('signedUrl() fails when the response carries no url', () async {
      when(
        () => rest.get(any(), queryParams: any(named: 'queryParams')),
      ).thenAnswer((_) async => <String, dynamic>{});

      final result = await api.signedUrl('att-1', roomId: 'r1');

      expect(result.isFailure, isTrue);
    });

    test(
      'signedUrl() surfaces a 403 not_a_room_member as ForbiddenFailure',
      () async {
        when(
          () => rest.get(any(), queryParams: any(named: 'queryParams')),
        ).thenThrow(
          const ChatForbiddenException(
            message: 'Not a room member',
            errorToken: ChatErrorTokens.notARoomMember,
          ),
        );

        final result = await api.signedUrl('att-1', roomId: 'r1');

        expect(result.isFailure, isTrue);
        final failure = result.failureOrThrow;
        expect(failure, isA<ForbiddenFailure>());
        expect(failure.errorToken, ChatErrorTokens.notARoomMember);
      },
    );

    test(
      'download(roomId:) resolves a signed url then fetches its bytes',
      () async {
        final expectedBytes = Uint8List.fromList([1, 2, 3, 4]);
        when(
          () => rest.get(
            '/attachments/att-1/signed-url',
            queryParams: any(named: 'queryParams'),
          ),
        ).thenAnswer(
          (_) async => {'url': 'https://cdn.example.com/att-1?sig=abc'},
        );
        when(
          () => rest.downloadBinary(
            'https://cdn.example.com/att-1?sig=abc',
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer((_) async => expectedBytes);

        final result = await api.download('att-1', roomId: 'r1');

        expect(result.isSuccess, isTrue);
        expect(result.dataOrThrow, expectedBytes);
        verify(
          () => rest.downloadBinary(
            'https://cdn.example.com/att-1?sig=abc',
            onProgress: any(named: 'onProgress'),
          ),
        ).called(1);
      },
    );

    test('download(roomId:) falls back to the membership-checked path when '
        'no signed url is returned', () async {
      final expectedBytes = Uint8List.fromList([9, 9]);
      when(
        () => rest.get(
          '/attachments/att-1/signed-url',
          queryParams: any(named: 'queryParams'),
        ),
      ).thenAnswer((_) async => <String, dynamic>{});
      when(
        () => rest.downloadBinary(
          '/attachments/att-1',
          queryParams: any(named: 'queryParams'),
          headers: any(named: 'headers'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => expectedBytes);

      final result = await api.download('att-1', roomId: 'r1');

      expect(result.isSuccess, isTrue);
      expect(result.dataOrThrow, expectedBytes);
      final captured =
          verify(
                () => rest.downloadBinary(
                  '/attachments/att-1',
                  queryParams: captureAny(named: 'queryParams'),
                  headers: any(named: 'headers'),
                  onProgress: any(named: 'onProgress'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['roomId'], 'r1');
    });
  });

  group('Attachments extended', () {
    late AttachmentsApi api;

    setUp(() {
      api = AttachmentsApi(rest: rest);
    });

    test('listInRoom() gets /rooms/{roomId}/attachments', () async {
      when(
        () => rest.get(
          '/rooms/r1/attachments',
          queryParams: any(named: 'queryParams'),
        ),
      ).thenAnswer(
        (_) async => {
          'attachments': [messageJson(messageType: 'attachment')],
          'hasMore': true,
        },
      );

      final result = await api.listInRoom('r1');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.items.length, 1);
      expect(result.dataOrNull!.hasMore, isTrue);
    });

    test('listInRoom() parses next/prev cursors so the gallery paginates '
        'older pages', () async {
      // Regression: the media gallery anchors older-history loads on
      // `prevCursor`. If listInRoom drops the `prev`/`next` tokens the gallery
      // stops after the first page even when hasMore is true.
      when(
        () => rest.get(
          '/rooms/r1/attachments',
          queryParams: any(named: 'queryParams'),
        ),
      ).thenAnswer(
        (_) async => {
          'attachments': [messageJson(messageType: 'attachment')],
          'hasMore': true,
          'next': 'cursor-next-1',
          'prev': 'cursor-prev-1',
        },
      );

      final result = await api.listInRoom('r1');
      expect(result.isSuccess, isTrue);
      final page = result.dataOrNull!;
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, 'cursor-next-1');
      expect(page.prevCursor, 'cursor-prev-1');
    });

    test('listInRoom() leaves cursors null when absent', () async {
      when(
        () => rest.get(
          '/rooms/r1/attachments',
          queryParams: any(named: 'queryParams'),
        ),
      ).thenAnswer(
        (_) async => {
          'attachments': [messageJson(messageType: 'attachment')],
          'hasMore': false,
        },
      );

      final result = await api.listInRoom('r1');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.nextCursor, isNull);
      expect(result.dataOrNull!.prevCursor, isNull);
    });

    test(
      'deleteInRoom() deletes /rooms/{roomId}/attachments/{messageId}',
      () async {
        when(
          () => rest.delete('/rooms/r1/attachments/msg-1'),
        ).thenAnswer((_) async {});

        final result = await api.deleteInRoom('r1', 'msg-1');
        expect(result.isSuccess, isTrue);
        verify(() => rest.delete('/rooms/r1/attachments/msg-1')).called(1);
      },
    );
  });
}
