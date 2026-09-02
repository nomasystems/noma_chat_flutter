import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// `file_picker`'s native channel — mocked here the same way
/// `noma_chat_view_capture_test.dart` mocks the permission channel, so the
/// generic "File" row can be driven end to end without a real OS file
/// dialog. Name and codec copied from `MethodChannelFilePicker`.
const _filePickerChannel = MethodChannel(
  'miguelruivo.flutter.plugins.filepicker',
);

/// D-13 — the generic file picker is default-allow: any extension goes
/// through unless it is on [AttachmentPolicy.deniedExtensions]. These tests
/// drive that end to end through `NomaChatView`'s built-in File row, the
/// same path a host gets with zero extra wiring.
void main() {
  late MockChatClient mockClient;
  late ChatUiAdapter adapter;

  const currentUser = ChatUser(id: 'u1', displayName: 'Me');

  setUp(() {
    mockClient = MockChatClient(currentUserId: 'u1');
    adapter = ChatUiAdapter(client: mockClient, currentUser: currentUser);
    adapter.roomListController.addRoom(
      const RoomListItem(id: 'room1', name: 'Alice'),
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_filePickerChannel, null);
    await adapter.dispose();
    await mockClient.dispose();
  });

  Future<void> pumpRoom(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NomaChatView(
          roomId: 'room1',
          adapter: adapter,
          hydrateGroupMembers: false,
        ),
      ),
    );
    await tester.pump();
  }

  /// Stands in for the OS file dialog: whatever `type` the picker asked for
  /// (`any` here, since none of these tests pass `allowedExtensions`), hand
  /// back exactly one file.
  void mockPickedFile({required String name, required Uint8List bytes}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_filePickerChannel, (call) async {
          if (call.method != 'any') return null;
          return [
            {
              'name': name,
              'path': null,
              'bytes': bytes,
              'size': bytes.length,
              'identifier': null,
            },
          ];
        });
  }

  /// Taps the File row's action and lets the real event loop turn — the
  /// pick goes through `ImageMetadataScrubber.scrub`, which hops to a
  /// background isolate on every platform these tests run on. An accepted
  /// file lands on `AttachmentReviewPage` next, not on the wire: confirm
  /// that step so the upload this test measures actually fires, exactly
  /// like a real send.
  Future<void> pickFile(WidgetTester tester) async {
    tester.widget<ChatView>(find.byType(ChatView)).callbacks.onPickFile!();
    for (var round = 0; round < 6; round++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final sendButton = find.byKey(
      const ValueKey('chat_attachment_review_send'),
    );
    if (sendButton.evaluate().isNotEmpty) {
      await tester.tap(sendButton);
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    'a dangerous extension is denied: no upload starts and the rejection '
    'reaches the user, not just a warn log',
    (tester) async {
      await pumpRoom(tester);
      mockPickedFile(
        name: 'totally-legit-invoice.exe',
        bytes: Uint8List.fromList([0x4d, 0x5a, 1, 2, 3]),
      );

      await pickFile(tester);

      expect(
        mockClient.attachments.uploadCount,
        0,
        reason: 'a denied extension must never reach the upload path',
      );
      expect(
        find.text(ChatUiLocalizations.en.attachmentTypeNotAllowed),
        findsOneWidget,
        reason:
            'the built-in File row wires onRejected to a SnackBar; a '
            'silent drop would leave the user thinking nothing happened',
      );
    },
  );

  testWidgets('an uncommon-but-safe extension is accepted and uploaded — the '
      'default is allow, not a whitelist', (tester) async {
    await pumpRoom(tester);
    mockPickedFile(
      name: 'checksum-export.xyz',
      bytes: Uint8List.fromList([1, 2, 3, 4]),
    );

    await pickFile(tester);

    expect(
      mockClient.attachments.uploadCount,
      1,
      reason:
          'D-13: an uncommon extension the deny-list does not name must '
          'be sendable, exactly like WhatsApp',
    );
    expect(
      find.text(ChatUiLocalizations.en.attachmentTypeNotAllowed),
      findsNothing,
    );
    // The end-to-end pass above holds as long as nothing upstream narrows
    // the type gate, so pin the shape of the gate itself: `.xyz` reaches
    // `validate` as `application/octet-stream` (the picker's fallback for
    // every extension outside its small mime dictionary), and a mime
    // whitelist creeping back into the default policy would swallow that
    // whole class of file — which is precisely the defect.
    expect(
      NomaChatView.defaultAttachmentPolicy.allowsMimeType(
        'application/octet-stream',
      ),
      isTrue,
      reason:
          'the default policy must stay default-allow; a whitelist here '
          'reintroduces D-13 for every uncommon extension at once',
    );
  });
}
