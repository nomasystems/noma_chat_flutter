import 'dart:async';
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

const _permissionChannel = MethodChannel(
  'flutter.baseflow.com/permissions/methods',
);

const _granted = 1;

const _backCamera = CameraDescription(
  name: 'back',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 0,
);

/// The smallest byte sequence the metadata stripper recognises as a JPEG it
/// can walk, so the send path behaves exactly as it does for a real shot.
final Uint8List _jpeg = Uint8List.fromList([
  0xFF, 0xD8, // SOI
  0xFF, 0xDB, 0x00, 0x05, 0x00, 0x10, 0x0B, // a quantisation table
  0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x3F, 0x00, // start of scan
  0xAA, 0xBB, 0xCC, 0xDD,
  0xFF, 0xD9, // EOI
]);

/// Camera platform that hands back a capture the test can watch on disk: the
/// bytes come from memory (a widget test cannot turn the real event loop for
/// file reads), while `path` names a file that really exists.
class _FakeCameraPlatform extends CameraPlatform {
  _FakeCameraPlatform(this.capturePath);

  final String capturePath;
  int takePictureCalls = 0;

  // ignore: close_sinks
  final StreamController<CameraInitializedEvent> _initialized =
      StreamController<CameraInitializedEvent>.broadcast();
  // ignore: close_sinks
  final StreamController<CameraErrorEvent> _errors =
      StreamController<CameraErrorEvent>.broadcast();
  // ignore: close_sinks
  final StreamController<DeviceOrientationChangedEvent> _orientation =
      StreamController<DeviceOrientationChangedEvent>.broadcast();

  int _nextCameraId = 1;

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    _backCamera,
  ];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async => _nextCameraId++;

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    _initialized.add(
      CameraInitializedEvent(
        cameraId,
        1080,
        1920,
        ExposureMode.auto,
        true,
        FocusMode.auto,
        true,
      ),
    );
  }

  @override
  Future<double> getMinZoomLevel(int cameraId) async => 1.0;

  @override
  Future<double> getMaxZoomLevel(int cameraId) async => 1.0;

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _initialized.stream.where((event) => event.cameraId == cameraId);

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => _errors.stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      _orientation.stream;

  @override
  Widget buildPreview(int cameraId) => const SizedBox.expand();

  @override
  Future<XFile> takePicture(int cameraId) async {
    takePictureCalls++;
    return XFile.fromData(_jpeg, path: capturePath, name: 'shot.jpg');
  }

  @override
  Future<void> dispose(int cameraId) async {}
}

void main() {
  late MockChatClient mockClient;
  late ChatUiAdapter adapter;
  late Directory captureDir;
  late File capture;
  late _FakeCameraPlatform camera;

  const currentUser = ChatUser(id: 'u1', displayName: 'Me');

  setUp(() {
    mockClient = MockChatClient(currentUserId: 'u1');
    adapter = ChatUiAdapter(client: mockClient, currentUser: currentUser);
    adapter.roomListController.addRoom(
      const RoomListItem(id: 'room1', name: 'Alice'),
    );
    captureDir = Directory.systemTemp.createTempSync('noma_capture_test');
    capture = File('${captureDir.path}/shot.jpg')..writeAsBytesSync(_jpeg);
    camera = _FakeCameraPlatform(capture.path);
    CameraPlatform.instance = camera;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_permissionChannel, (call) async {
          switch (call.method) {
            case 'requestPermissions':
              return {
                for (final permission
                    in (call.arguments as List<dynamic>).cast<int>())
                  permission: _granted,
              };
            case 'checkPermissionStatus':
              return _granted;
            default:
              return null;
          }
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_permissionChannel, null);
    await adapter.dispose();
    await mockClient.dispose();
    if (captureDir.existsSync()) captureDir.deleteSync(recursive: true);
  });

  Future<void> pumpRoom(
    WidgetTester tester, {
    AttachmentPolicy? attachmentPolicy,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NomaChatView(
          roomId: 'room1',
          adapter: adapter,
          hydrateGroupMembers: false,
          attachmentPolicy: attachmentPolicy,
        ),
      ),
    );
    await tester.pump();
  }

  /// Lets the real event loop turn so the `dart:io` calls the send path makes
  /// can actually complete, then hands control back to the fake clock.
  Future<void> drain(WidgetTester tester, [int rounds = 6]) async {
    for (var round = 0; round < rounds; round++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  Future<void> shoot(WidgetTester tester) async {
    tester.widget<ChatView>(find.byType(ChatView)).callbacks.onPickCamera!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(
      find.byType(CameraCaptureButton),
      findsOneWidget,
      reason: 'the capture screen has to be up before the shutter is tapped',
    );
    await tester.tap(find.byType(CameraCaptureButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await drain(tester);
  }

  testWidgets(
    'an accepted capture is sent and its file is not left behind',
    (tester) async {
      await pumpRoom(tester);

      await shoot(tester);

      expect(camera.takePictureCalls, 1);
      expect(
        mockClient.attachments.uploadCount,
        1,
        reason: 'the shot is on its way to the room',
      );
      expect(
        capture.existsSync(),
        isFalse,
        reason: 'nothing else ever collects the app cache the camera writes to',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'a capture the host policy refuses is neither sent nor left on disk',
    (tester) async {
      await pumpRoom(
        tester,
        attachmentPolicy: const AttachmentPolicy(maxBytes: 1),
      );

      await shoot(tester);

      expect(
        mockClient.attachments.uploadCount,
        0,
        reason: 'the host policy has to reach the SDK capture path too',
      );
      expect(
        capture.existsSync(),
        isFalse,
        reason: 'a rejected clip is exactly the one nobody would clean up',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('the default policy is the one the view documents, not the '
      '25 MB an unconfigured picker would apply', (tester) async {
    expect(
      NomaChatView.defaultAttachmentPolicy.maxBytesFor('video/mp4'),
      32 * 1024 * 1024,
    );
    expect(
      NomaChatView.defaultAttachmentPolicy.maxBytesFor('image/jpeg'),
      16 * 1024 * 1024,
    );
    expect(
      NomaChatView.defaultAttachmentPolicy.maxBytesFor('text/plain'),
      32 * 1024 * 1024,
    );
  });
}
