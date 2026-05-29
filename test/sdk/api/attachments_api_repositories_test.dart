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
