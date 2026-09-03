import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// The step between the picker and the send: nothing leaves the device
/// until its Send button is pressed, and what leaves carries the caption
/// written under it.
void main() {
  final png = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8'
      'BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ),
  );

  AttachmentPickResult pick(String name) =>
      AttachmentPickResult(bytes: png, mimeType: 'image/png', fileName: name);

  late List<ReviewedAttachment>? reviewed;
  late int returns;

  setUp(() {
    reviewed = null;
    returns = 0;
  });

  Future<void> open(
    WidgetTester tester,
    List<AttachmentPickResult> attachments,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final result = await AttachmentReviewPage.show(
                    context: context,
                    attachments: attachments,
                  );
                  returns++;
                  reviewed = result;
                },
                child: const Text('open review'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open review'));
    await tester.pumpAndSettle();
  }

  testWidgets('backing out sends nothing at all', (tester) async {
    await open(tester, [pick('a.png')]);

    await tester.tap(find.byKey(const ValueKey('chat_attachment_review_back')));
    await tester.pumpAndSettle();

    expect(returns, 1);
    expect(reviewed, isNull);
  });

  testWidgets('the caption written under the photo travels with it, trimmed', (
    tester,
  ) async {
    await open(tester, [pick('a.png')]);

    await tester.enterText(
      find.byKey(const ValueKey('chat_attachment_review_caption')),
      '  at the top of the hill  ',
    );
    await tester.tap(find.byKey(const ValueKey('chat_attachment_review_send')));
    await tester.pumpAndSettle();

    expect(reviewed, hasLength(1));
    expect(reviewed!.single.caption, 'at the top of the hill');
    expect(reviewed!.single.attachment.fileName, 'a.png');
  });

  testWidgets('an untouched caption field sends no caption', (tester) async {
    await open(tester, [pick('a.png')]);

    await tester.tap(find.byKey(const ValueKey('chat_attachment_review_send')));
    await tester.pumpAndSettle();

    expect(reviewed, hasLength(1));
    expect(reviewed!.single.caption, isNull);
  });

  testWidgets('each caption belongs to the photo it was written under, not '
      'to the batch', (tester) async {
    await open(tester, [pick('a.png'), pick('b.png')]);

    await tester.enterText(
      find.byKey(const ValueKey('chat_attachment_review_caption')),
      'first',
    );
    await tester.tap(
      find.byKey(const ValueKey('chat_attachment_review_thumb_1')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('chat_attachment_review_caption')),
      'second',
    );
    await tester.tap(find.byKey(const ValueKey('chat_attachment_review_send')));
    await tester.pumpAndSettle();

    expect(reviewed, hasLength(2));
    expect(reviewed![0].caption, 'first');
    expect(reviewed![0].attachment.fileName, 'a.png');
    expect(reviewed![1].caption, 'second');
    expect(reviewed![1].attachment.fileName, 'b.png');
  });

  testWidgets('a document with no preview of its own still names itself and '
      'keeps both exits reachable', (tester) async {
    await open(tester, [
      AttachmentPickResult(
        bytes: png,
        mimeType: 'application/pdf',
        fileName: 'contract.pdf',
      ),
    ]);

    expect(find.text('contract.pdf'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat_attachment_review_send')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat_attachment_review_back')),
      findsOneWidget,
    );
  });

  testWidgets('nothing to review resolves without opening a screen', (
    tester,
  ) async {
    await open(tester, const []);

    expect(returns, 1);
    expect(reviewed, isNull);
    expect(find.byType(AttachmentReviewPage), findsNothing);
  });
}
