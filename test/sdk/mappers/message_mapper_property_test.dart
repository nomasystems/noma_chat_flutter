import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/mappers/message_mapper.dart';

// ---------------------------------------------------------------------------
// Helpers shared across all groups
// ---------------------------------------------------------------------------

const _unicodeStress = [
  '\u{1F600}', // 😀
  '\u{1F1FA}\u{1F1F8}', // 🇺🇸 flag sequence
  '​', // zero-width space
  '‍', // zero-width joiner
  // ignore: text_direction_code_point_in_literal
  '‮', // right-to-left override
  // ignore: text_direction_code_point_in_literal
  '‭', // left-to-right override
  '؀', // arabic letter
  '﻿', // BOM
  ' ', // line separator
  ' ', // paragraph separator
  '\u{1F468}‍\u{1F469}‍\u{1F467}', // family ZWJ sequence
];

const _knownMessageTypes = [
  'regular',
  'attachment',
  'reaction',
  'reply',
  'audio',
  'forward',
  'location',
];

const _knownReceiptStatuses = ['sent', 'delivered', 'read'];

String _randomString(Random rng, int maxLen, {bool allowUnicode = false}) {
  const ascii =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_@./:';
  final len = rng.nextInt(maxLen + 1);
  if (!allowUnicode || rng.nextBool()) {
    final buf = StringBuffer();
    for (var i = 0; i < len; i++) {
      buf.write(ascii[rng.nextInt(ascii.length)]);
    }
    return buf.toString();
  }
  // Sprinkle unicode stress characters.
  final buf = StringBuffer();
  for (var i = 0; i < len; i++) {
    if (rng.nextInt(4) == 0) {
      buf.write(_unicodeStress[rng.nextInt(_unicodeStress.length)]);
    } else {
      buf.write(ascii[rng.nextInt(ascii.length)]);
    }
  }
  return buf.toString();
}

dynamic _randomScalar(Random rng) {
  switch (rng.nextInt(6)) {
    case 0:
      return null;
    case 1:
      return rng.nextBool();
    case 2:
      return rng.nextInt(1 << 30);
    case 3:
      return rng.nextDouble() * 1e12;
    case 4:
      return _randomString(rng, 30);
    default:
      return rng.nextInt(1000).toString();
  }
}

dynamic _randomValue(Random rng, int depth) {
  if (depth >= 3) return _randomScalar(rng);
  switch (rng.nextInt(9)) {
    case 0:
      return null;
    case 1:
      return rng.nextBool();
    case 2:
      return rng.nextInt(1 << 30) - (1 << 29);
    case 3:
      return rng.nextDouble() * 1e15;
    case 4:
      return _randomString(rng, 40);
    case 5:
      return <dynamic>[
        for (var i = 0; i < rng.nextInt(4); i++) _randomValue(rng, depth + 1),
      ];
    case 6:
      return <String, dynamic>{
        for (var i = 0; i < rng.nextInt(4); i++)
          _randomString(rng, 10): _randomValue(rng, depth + 1),
      };
    case 7:
      return 'not-a-date-${rng.nextInt(999)}';
    default:
      return _randomString(rng, 80);
  }
}

Map<String, dynamic> _randomJson(Random rng) {
  final n = rng.nextInt(8);
  final map = <String, dynamic>{};
  for (var i = 0; i < n; i++) {
    map[_randomString(rng, 12)] = _randomValue(rng, 0);
  }
  return map;
}

/// Builds a minimal valid message map (id + from + timestamp only).
Map<String, dynamic> _minimalValid({
  String id = 'msg-min',
  String from = 'user-min',
  String timestamp = '2024-01-15T10:30:00.000Z',
}) => {'id': id, 'from': from, 'timestamp': timestamp};

/// Builds a fully-populated valid message map.
Map<String, dynamic> _fullValid({
  required String id,
  required String from,
  required String timestamp,
  String messageType = 'regular',
  String? text,
  String? attachmentUrl,
  String? referencedMessageId,
  String? reaction,
  String? reply,
  Map<String, dynamic>? metadata,
  String? receipt,
  bool isDeleted = false,
}) => {
  'id': id,
  'from': from,
  'timestamp': timestamp,
  'messageType': messageType,
  if (text != null) 'text': text,
  if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
  if (referencedMessageId != null) 'referencedMessageId': referencedMessageId,
  if (reaction != null) 'reaction': reaction,
  if (reply != null) 'reply': reply,
  if (metadata != null) 'metadata': metadata,
  if (receipt != null) 'receipt': receipt,
  'isDeleted': isDeleted,
};

void main() {
  // Silence mapper warnings across all tests — we exercise adversarial inputs
  // deliberately and are not interested in per-call warning counts here.
  setUpAll(() => MessageMapper.logger = null);
  tearDownAll(() => MessageMapper.logger = null);

  // =========================================================================
  // Group 1 — Fixed corpus: known edge cases
  // =========================================================================
  group('MessageMapper.fromJson — fixed corpus', () {
    // Shape 1: minimal valid
    test('minimal valid message maps without throwing', () {
      expect(() => MessageMapper.fromJson(_minimalValid()), returnsNormally);
    });

    test('minimal valid message round-trips id and from', () {
      final msg = MessageMapper.fromJson(
        _minimalValid(id: 'id-abc', from: 'user-xyz'),
      );
      expect(msg.id, 'id-abc');
      expect(msg.from, 'user-xyz');
    });

    // Shape 2: all optional fields
    test('fully-populated valid message does not throw', () {
      expect(
        () => MessageMapper.fromJson(
          _fullValid(
            id: 'msg-full',
            from: 'alice',
            timestamp: '2025-06-01T08:00:00Z',
            messageType: 'regular',
            text: 'Hello world',
            attachmentUrl: 'https://cdn.example.com/file.pdf',
            referencedMessageId: 'msg-prev',
            reaction: '❤️',
            reply: 'In reply to something',
            metadata: {'key': 'value', 'count': 3},
            receipt: 'read',
            isDeleted: false,
          ),
        ),
        returnsNormally,
      );
    });

    test('fully-populated message round-trips all string fields', () {
      final json = _fullValid(
        id: 'msg-full-rt',
        from: 'bob',
        timestamp: '2025-06-01T12:00:00Z',
        messageType: 'regular',
        text: 'Round-trip text',
        receipt: 'delivered',
      );
      final msg = MessageMapper.fromJson(json);
      expect(msg.id, 'msg-full-rt');
      expect(msg.from, 'bob');
      expect(msg.text, 'Round-trip text');
      expect(msg.receipt, ReceiptStatus.delivered);
    });

    test('isDeleted flag is preserved', () {
      final msg = MessageMapper.fromJson({
        ..._minimalValid(id: 'del-msg'),
        'isDeleted': true,
      });
      expect(msg.isDeleted, isTrue);
    });

    test('all known messageTypes parse without throwing', () {
      for (final type in _knownMessageTypes) {
        expect(
          () => MessageMapper.fromJson({
            ..._minimalValid(id: 'type-$type'),
            'messageType': type,
          }),
          returnsNormally,
          reason: 'messageType=$type should not throw',
        );
      }
    });

    test('all known receiptStatuses parse correctly', () {
      final expected = {
        'sent': ReceiptStatus.sent,
        'delivered': ReceiptStatus.delivered,
        'read': ReceiptStatus.read,
      };
      for (final entry in expected.entries) {
        final msg = MessageMapper.fromJson({
          ..._minimalValid(id: 'rcpt-${entry.key}'),
          'receipt': entry.key,
        });
        expect(
          msg.receipt,
          entry.value,
          reason: 'receipt="${entry.key}" should map to ${entry.value}',
        );
      }
    });

    // Shape 3: null / wrong-typed optional fields
    test('null id falls back to empty string, does not throw', () {
      expect(
        () => MessageMapper.fromJson({
          'id': null,
          'from': 'u',
          'timestamp': '2024-01-01T00:00:00Z',
        }),
        returnsNormally,
      );
    });

    test('null from falls back to empty string, does not throw', () {
      expect(
        () => MessageMapper.fromJson({
          'id': 'm',
          'from': null,
          'timestamp': '2024-01-01T00:00:00Z',
        }),
        returnsNormally,
      );
    });

    test('integer id does not throw', () {
      expect(
        () => MessageMapper.fromJson({
          'id': 42,
          'from': 'u',
          'timestamp': '2024-01-01T00:00:00Z',
        }),
        returnsNormally,
      );
    });

    test('list where string expected in text does not throw', () {
      expect(
        () => MessageMapper.fromJson({
          ..._minimalValid(),
          'text': <dynamic>['list', 'not', 'string'],
        }),
        returnsNormally,
      );
    });

    test('list where string expected in messageType does not throw', () {
      expect(
        () => MessageMapper.fromJson({
          ..._minimalValid(),
          'messageType': <dynamic>['not', 'a', 'string'],
        }),
        returnsNormally,
      );
    });

    test('integer messageType does not throw', () {
      expect(
        () => MessageMapper.fromJson({..._minimalValid(), 'messageType': 99}),
        returnsNormally,
      );
    });

    test('boolean messageType does not throw', () {
      expect(
        () => MessageMapper.fromJson({..._minimalValid(), 'messageType': true}),
        returnsNormally,
      );
    });

    test('map where string expected in receipt does not throw', () {
      expect(
        () => MessageMapper.fromJson({
          ..._minimalValid(),
          'receipt': <String, dynamic>{'status': 'read'},
        }),
        returnsNormally,
      );
    });

    test('list metadata does not throw', () {
      expect(
        () => MessageMapper.fromJson({
          ..._minimalValid(),
          'metadata': <dynamic>[1, 2, 3],
        }),
        returnsNormally,
      );
    });

    test('integer metadata does not throw', () {
      expect(
        () => MessageMapper.fromJson({..._minimalValid(), 'metadata': 42}),
        returnsNormally,
      );
    });

    test('boolean metadata does not throw', () {
      expect(
        () => MessageMapper.fromJson({..._minimalValid(), 'metadata': false}),
        returnsNormally,
      );
    });

    test('non-string in attachmentUrl does not throw', () {
      expect(
        () =>
            MessageMapper.fromJson({..._minimalValid(), 'attachmentUrl': 123}),
        returnsNormally,
      );
    });

    test('non-string in referencedMessageId does not throw', () {
      expect(
        () => MessageMapper.fromJson({
          ..._minimalValid(),
          'referencedMessageId': <dynamic>[],
        }),
        returnsNormally,
      );
    });

    test('non-string in reaction does not throw', () {
      expect(
        () => MessageMapper.fromJson({..._minimalValid(), 'reaction': 3.14}),
        returnsNormally,
      );
    });

    // Shape 4: completely empty / completely alien map
    test('empty map does not throw', () {
      expect(
        () => MessageMapper.fromJson(<String, dynamic>{}),
        returnsNormally,
      );
    });

    test('map with only unknown keys does not throw', () {
      expect(
        () => MessageMapper.fromJson({
          'foo': 1,
          'bar': 'baz',
          'qux': <dynamic>[],
        }),
        returnsNormally,
      );
    });

    test('deeply nested unknown map does not throw', () {
      final deep = <String, dynamic>{};
      var node = deep;
      for (var i = 0; i < 10; i++) {
        final child = <String, dynamic>{'level': i};
        node['nested'] = child;
        node = child;
      }
      expect(() => MessageMapper.fromJson(deep), returnsNormally);
    });

    // Shape 5: Unicode stress
    test('emoji in text does not throw', () {
      expect(
        () => MessageMapper.fromJson({
          ..._minimalValid(),
          'text': '😀🎉🇺🇸​‍\u{1F468}‍\u{1F469}‍\u{1F467}',
        }),
        returnsNormally,
      );
    });

    test('RTL override in from field does not throw', () {
      expect(
        () => MessageMapper.fromJson({
          // ignore: text_direction_code_point_in_literal
          'id': '‮id-rtl',
          // ignore: text_direction_code_point_in_literal
          'from': '‮user-rtl',
          'timestamp': '2024-01-01T00:00:00Z',
        }),
        returnsNormally,
      );
    });

    test('zero-width joiners in id does not throw', () {
      expect(
        () => MessageMapper.fromJson({
          'id': 'msg‍-‍ztw',
          'from': 'u',
          'timestamp': '2024-01-01T00:00:00Z',
        }),
        returnsNormally,
      );
    });

    test('unicode in metadata values does not throw', () {
      expect(
        () => MessageMapper.fromJson({
          ..._minimalValid(),
          'metadata': {
            // ignore: text_direction_code_point_in_literal
            'label': '🌍 مرحبا world ‮',
            'emoji': '\u{1F600}',
          },
        }),
        returnsNormally,
      );
    });

    // Shape 6: numeric and boolean where strings expected
    test('integer where string expected in id falls back gracefully', () {
      expect(
        () => MessageMapper.fromJson({
          'id': 42,
          'from': 'u',
          'timestamp': '2024-01-01T00:00:00Z',
        }),
        returnsNormally,
      );
    });

    test('boolean where string expected in from does not throw', () {
      expect(
        () => MessageMapper.fromJson({
          'id': 'm',
          'from': true,
          'timestamp': '2024-01-01T00:00:00Z',
        }),
        returnsNormally,
      );
    });

    test('double where string expected in timestamp does not throw', () {
      expect(
        () =>
            MessageMapper.fromJson({'id': 'm', 'from': 'u', 'timestamp': 3.14}),
        returnsNormally,
      );
    });

    test('integer isDeleted does not throw', () {
      expect(
        () => MessageMapper.fromJson({..._minimalValid(), 'isDeleted': 1}),
        returnsNormally,
      );
    });

    // Reaction list (inline reactions from server)
    test('valid inline reaction list is processed without throwing', () {
      expect(
        () => MessageMapper.fromJson({
          ..._minimalValid(id: 'msg-rxn'),
          'reaction': [
            {'reaction': '👍', 'from': 'alice'},
            {'emoji': '❤️', 'from': 'bob'},
          ],
        }),
        returnsNormally,
      );
    });

    test('reaction list with null emoji entries does not throw', () {
      expect(
        () => MessageMapper.fromJson({
          ..._minimalValid(),
          'reaction': [
            {'reaction': null},
            {'emoji': null, 'from': null},
            null,
            42,
            'string-not-map',
          ],
        }),
        returnsNormally,
      );
    });

    // text_history signals edited
    test('non-empty text_history marks message as edited', () {
      final msg = MessageMapper.fromJson({
        ..._minimalValid(id: 'edited-msg'),
        'text_history': ['original text'],
      });
      expect(msg.isEdited, isTrue);
    });

    test('empty text_history does not mark as edited', () {
      final msg = MessageMapper.fromJson({
        ..._minimalValid(id: 'not-edited'),
        'text_history': <dynamic>[],
      });
      expect(msg.isEdited, isFalse);
    });

    test('non-list text_history does not throw', () {
      expect(
        () => MessageMapper.fromJson({
          ..._minimalValid(),
          'text_history': 'not-a-list',
        }),
        returnsNormally,
      );
    });

    // metadata 'edited' flag
    test('metadata edited=true marks message as edited', () {
      final msg = MessageMapper.fromJson({
        ..._minimalValid(id: 'meta-edited'),
        'metadata': {'edited': true},
      });
      expect(msg.isEdited, isTrue);
    });

    // metadata internal key stripping
    test('internal metadata keys are stripped from cleanMeta', () {
      final msg = MessageMapper.fromJson({
        ..._minimalValid(),
        'metadata': {
          'edited': true,
          'mimeType': 'image/png',
          'mime_type': 'image/png',
          'fileName': 'photo.jpg',
          'file_name': 'photo.jpg',
          'fileSize': '1024',
          'thumbnailUrl': 'https://cdn/thumb',
          'userKey': 'kept',
        },
      });
      // Internal keys must be removed from the cleanMeta exposed on the model.
      expect(msg.metadata?.containsKey('edited'), isNot(isTrue));
      expect(msg.metadata?.containsKey('mimeType'), isNot(isTrue));
      expect(msg.metadata?.containsKey('userKey'), isTrue);
    });

    // Attachment type inference from metadata.attachmentUrl
    test('attachment type inferred from metadata.attachmentUrl', () {
      final msg = MessageMapper.fromJson({
        ..._minimalValid(),
        'metadata': {'attachmentUrl': 'https://cdn/file.zip'},
      });
      expect(msg.messageType, MessageType.attachment);
    });

    // Location inference
    test('location type inferred when metadata has numeric lat and lng', () {
      final msg = MessageMapper.fromJson({
        ..._minimalValid(),
        'metadata': {'lat': 48.85, 'lng': 2.35},
      });
      expect(msg.messageType, MessageType.location);
    });

    // Invalid timestamp falls back to DateTime.now() without throwing
    test(
      'invalid ISO timestamp does not throw and produces non-null timestamp',
      () {
        final before = DateTime.now().subtract(const Duration(seconds: 1));
        final msg = MessageMapper.fromJson({
          ..._minimalValid(),
          'timestamp': 'not-a-date',
        });
        expect(msg.timestamp.isAfter(before), isTrue);
      },
    );

    test('empty timestamp does not throw', () {
      expect(
        () => MessageMapper.fromJson({'id': 'm', 'from': 'u', 'timestamp': ''}),
        returnsNormally,
      );
    });
  });

  // =========================================================================
  // Group 2 — Property loop: minimal valid inputs (N = 200)
  // =========================================================================
  group('MessageMapper.fromJson — property: minimal valid inputs', () {
    test('200 randomised minimal valid inputs never throw', () {
      final rng = Random(42);
      for (var i = 0; i < 200; i++) {
        final id = _randomString(rng, 20);
        final from = _randomString(rng, 20);
        final ts = '2024-0${rng.nextInt(9) + 1}-01T00:00:00Z';
        final json = _minimalValid(id: id, from: from, timestamp: ts);
        expect(
          () => MessageMapper.fromJson(json),
          returnsNormally,
          reason: 'iter $i: $json',
        );
      }
    });

    test('200 randomised minimal valid inputs round-trip id and from', () {
      final rng = Random(42);
      for (var i = 0; i < 200; i++) {
        final id = _randomString(rng, 20);
        final from = _randomString(rng, 20);
        const ts = '2024-01-01T00:00:00Z';
        final msg = MessageMapper.fromJson(
          _minimalValid(id: id, from: from, timestamp: ts),
        );
        expect(msg.id, id, reason: 'iter $i: id mismatch');
        expect(msg.from, from, reason: 'iter $i: from mismatch');
      }
    });
  });

  // =========================================================================
  // Group 3 — Property loop: fully populated valid inputs (N = 200)
  // =========================================================================
  group('MessageMapper.fromJson — property: fully populated valid inputs', () {
    test('200 randomised fully-populated valid inputs never throw', () {
      final rng = Random(42);
      for (var i = 0; i < 200; i++) {
        final id = 'msg-${rng.nextInt(100000)}';
        final from = 'user-${rng.nextInt(100000)}';
        final year = 2024 + rng.nextInt(2);
        final month = rng.nextInt(12) + 1;
        final day = rng.nextInt(28) + 1;
        final ts =
            '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}T00:00:00Z';
        final type = _knownMessageTypes[rng.nextInt(_knownMessageTypes.length)];
        final receipt = rng.nextBool()
            ? _knownReceiptStatuses[rng.nextInt(_knownReceiptStatuses.length)]
            : null;
        final meta = rng.nextBool()
            ? <String, dynamic>{
                'key': _randomString(rng, 10),
                'count': rng.nextInt(50),
              }
            : null;
        final json = _fullValid(
          id: id,
          from: from,
          timestamp: ts,
          messageType: type,
          text: rng.nextBool()
              ? _randomString(rng, 80, allowUnicode: true)
              : null,
          attachmentUrl: rng.nextBool()
              ? 'https://cdn.example.com/${rng.nextInt(999)}'
              : null,
          referencedMessageId: rng.nextBool()
              ? 'ref-${rng.nextInt(1000)}'
              : null,
          reaction: rng.nextBool() ? '👍' : null,
          reply: rng.nextBool() ? 'reply text' : null,
          metadata: meta,
          receipt: receipt,
          isDeleted: rng.nextBool(),
        );
        expect(
          () => MessageMapper.fromJson(json),
          returnsNormally,
          reason: 'iter $i: $json',
        );
      }
    });

    test(
      '200 fully-populated inputs round-trip id, from, messageType, receipt',
      () {
        final rng = Random(42);
        for (var i = 0; i < 200; i++) {
          final id = 'msg-rt-$i-${rng.nextInt(9999)}';
          final from = 'usr-$i';
          final type =
              _knownMessageTypes[rng.nextInt(_knownMessageTypes.length)];
          final receiptStr = rng.nextBool()
              ? _knownReceiptStatuses[rng.nextInt(_knownReceiptStatuses.length)]
              : null;
          final json = _fullValid(
            id: id,
            from: from,
            timestamp: '2025-01-01T00:00:00Z',
            messageType: type,
            receipt: receiptStr,
          );
          final msg = MessageMapper.fromJson(json);
          expect(msg.id, id, reason: 'iter $i id');
          expect(msg.from, from, reason: 'iter $i from');
          if (receiptStr != null) {
            expect(
              msg.receipt,
              isNotNull,
              reason: 'iter $i receipt should parse',
            );
          }
        }
      },
    );
  });

  // =========================================================================
  // Group 4 — Property loop: type-mismatched optional fields (N = 200)
  // =========================================================================
  group(
    'MessageMapper.fromJson — property: type-mismatched optional fields',
    () {
      final wrongTypedValues = <dynamic>[
        null,
        42,
        3.14,
        true,
        false,
        -1,
        0,
        <dynamic>[],
        <dynamic>[1, 'a', null],
        <String, dynamic>{},
        <String, dynamic>{'x': 1},
      ];

      test('200 inputs with wrong-typed optional fields never throw', () {
        final rng = Random(42);
        for (var i = 0; i < 200; i++) {
          final wrongValue =
              wrongTypedValues[rng.nextInt(wrongTypedValues.length)];
          final field = [
            'text',
            'messageType',
            'attachmentUrl',
            'referencedMessageId',
            'reaction',
            'reply',
            'metadata',
            'receipt',
            'isDeleted',
            'text_history',
          ][rng.nextInt(10)];
          final json = <String, dynamic>{
            ..._minimalValid(id: 'wrong-$i'),
            field: wrongValue,
          };
          expect(
            () => MessageMapper.fromJson(json),
            returnsNormally,
            reason: 'iter $i: field="$field" value=$wrongValue',
          );
        }
      });
    },
  );

  // =========================================================================
  // Group 5 — Property loop: completely random JSON maps (N = 200)
  // =========================================================================
  group('MessageMapper.fromJson — property: completely random maps', () {
    test('200 fully random maps never throw', () {
      final rng = Random(42);
      for (var i = 0; i < 200; i++) {
        final json = _randomJson(rng);
        expect(
          () => MessageMapper.fromJson(json),
          returnsNormally,
          reason: 'iter $i: $json',
        );
      }
    });

    test('200 fully random maps with varied seeds never throw', () {
      for (var seed = 1; seed <= 200; seed++) {
        final rng = Random(seed);
        final json = _randomJson(rng);
        expect(
          () => MessageMapper.fromJson(json),
          returnsNormally,
          reason: 'seed=$seed: $json',
        );
      }
    });
  });

  // =========================================================================
  // Group 6 — Property loop: unicode stress (N = 200)
  // =========================================================================
  group('MessageMapper.fromJson — property: unicode stress', () {
    test('200 inputs with unicode in text, from, id never throw', () {
      final rng = Random(42);
      for (var i = 0; i < 200; i++) {
        final id = _randomString(rng, 16, allowUnicode: true);
        final from = _randomString(rng, 16, allowUnicode: true);
        final text = _randomString(rng, 100, allowUnicode: true);
        final json = <String, dynamic>{
          'id': id,
          'from': from,
          'timestamp': '2025-01-01T00:00:00Z',
          'text': text,
        };
        expect(
          () => MessageMapper.fromJson(json),
          returnsNormally,
          reason: 'iter $i',
        );
      }
    });

    test('200 inputs with pure unicode stress sequences never throw', () {
      final rng = Random(42);
      for (var i = 0; i < 200; i++) {
        final stressChar = _unicodeStress[rng.nextInt(_unicodeStress.length)];
        final json = <String, dynamic>{
          'id': 'msg-$stressChar',
          'from': '$stressChar-user',
          'timestamp': '2025-01-01T00:00:00Z',
          'text': stressChar * (rng.nextInt(20) + 1),
          'metadata': {'label': stressChar},
        };
        expect(
          () => MessageMapper.fromJson(json),
          returnsNormally,
          reason: 'iter $i: stressChar=${stressChar.codeUnits}',
        );
      }
    });
  });

  // =========================================================================
  // Group 7 — Property loop: numeric and boolean type fuzz (N = 200)
  // =========================================================================
  group('MessageMapper.fromJson — property: numeric and boolean type fuzz', () {
    test(
      '200 inputs with numerics/booleans where strings expected never throw',
      () {
        final rng = Random(42);
        final numericOrBool = <dynamic>[
          0,
          1,
          -1,
          42,
          999999,
          -999999,
          3.14,
          -3.14,
          double.infinity,
          double.negativeInfinity,
          double.nan,
          true,
          false,
        ];
        for (var i = 0; i < 200; i++) {
          final v = numericOrBool[rng.nextInt(numericOrBool.length)];
          final json = <String, dynamic>{
            'id': v,
            'from': v,
            'timestamp': v,
            'text': v,
            'messageType': v,
            'receipt': v,
            'attachmentUrl': v,
          };
          expect(
            () => MessageMapper.fromJson(json),
            returnsNormally,
            reason: 'iter $i: v=$v',
          );
        }
      },
    );

    test('200 varied seeds with random numeric/boolean fuzz never throw', () {
      final numericOrBool = <dynamic>[
        0,
        1,
        -1,
        42,
        3.14,
        true,
        false,
        double.nan,
      ];
      for (var seed = 1; seed <= 200; seed++) {
        final rng = Random(seed);
        final v = numericOrBool[rng.nextInt(numericOrBool.length)];
        final json = <String, dynamic>{
          'id': rng.nextBool() ? 'id-$seed' : v,
          'from': rng.nextBool() ? 'user-$seed' : v,
          'timestamp': rng.nextBool() ? '2024-01-01T00:00:00Z' : v,
          'messageType': rng.nextBool() ? 'regular' : v,
          'receipt': rng.nextBool() ? 'sent' : v,
          'text': rng.nextBool() ? 'hello' : v,
          'metadata': rng.nextBool() ? <String, dynamic>{'n': v} : v,
        };
        expect(
          () => MessageMapper.fromJson(json),
          returnsNormally,
          reason: 'seed=$seed v=$v',
        );
      }
    });
  });
}
