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
  _FakeCameraPlatform(this.capturePath, this.clipPath);

  final String capturePath;

  /// Clip handed back by [stopVideoRecording] — a real file, like the still,
  /// so the page's own cleanup has something to delete.
  final String clipPath;

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
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {}

  @override
  Future<XFile> stopVideoRecording(int cameraId) async => XFile(clipPath);

  @override
  Future<void> dispose(int cameraId) async {}
}

void main() {
  late MockChatClient mockClient;
  late ChatUiAdapter adapter;
  late Directory captureDir;
  late File capture;
  late File clip;
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
    clip = File('${captureDir.path}/clip.mp4')..writeAsBytesSync(_jpeg);
    camera = _FakeCameraPlatform(capture.path, clip.path);
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
    ChatViewBuilders? builders,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NomaChatView(
          roomId: 'room1',
          adapter: adapter,
          hydrateGroupMembers: false,
          attachmentPolicy: attachmentPolicy,
          builders: builders,
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

  /// Opens the camera and taps the shutter, stopping on the review step —
  /// where a capture now waits until the user says what to do with it.
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
    expect(
      find.byType(CameraCaptureReview),
      findsOneWidget,
      reason: 'the shutter confirms nothing on its own',
    );
  }

  /// Opens the camera and holds the shutter down, stopping on the review
  /// step with a clip on it.
  Future<void> record(WidgetTester tester) async {
    tester.widget<ChatView>(find.byType(ChatView)).callbacks.onPickCamera!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CameraCaptureButton)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await drain(tester);
    await gesture.up();
    await drain(tester);
  }

  /// Confirms the capture waiting on the review step.
  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await drain(tester);
  }

  testWidgets(
    'a capture confirmed on the review step is sent and its file is not '
    'left behind',
    (tester) async {
      await pumpRoom(tester);

      await shoot(tester);
      expect(
        mockClient.attachments.uploadCount,
        0,
        reason: 'the review step is the gate: nothing leaves before Send',
      );
      await confirm(tester);

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
      await confirm(tester);

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

  testWidgets(
    'a capture the user throws away on the review step never reaches the '
    'room, and does not stay on disk either',
    (tester) async {
      await pumpRoom(tester);

      await shoot(tester);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await drain(tester);
      // The pop's reverse transition owns the last frames of the flow.
      await tester.pump(const Duration(milliseconds: 400));

      expect(camera.takePictureCalls, 1);
      expect(
        mockClient.attachments.uploadCount,
        0,
        reason: 'a discarded shot is exactly the one that must not be sent',
      );
      expect(
        find.byType(CameraCapturePage),
        findsNothing,
        reason: 'discarding leaves the camera, like cancelling does',
      );
      expect(capture.existsSync(), isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'a capture the user retakes is neither sent nor kept, and the camera '
    'stays open for the next attempt',
    (tester) async {
      await pumpRoom(tester);

      await shoot(tester);
      await tester.tap(find.text('Retake'));
      await tester.pump();
      await drain(tester);

      expect(find.byType(CameraCaptureReview), findsNothing);
      expect(
        find.byType(CameraCaptureButton),
        findsOneWidget,
        reason: 'a retake goes back to the viewfinder, not out of the flow',
      );
      expect(mockClient.attachments.uploadCount, 0);
      expect(capture.existsSync(), isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'a videoPreviewBuilder handed to the view reaches the review step, so a '
    'host can keep video_player out of its build',
    (tester) async {
      XFile? previewed;

      await pumpRoom(
        tester,
        builders: ChatViewBuilders(
          videoPreviewBuilder: (context, file, theme) {
            previewed = file;
            return const Center(child: Text('host clip preview'));
          },
        ),
      );

      await record(tester);

      expect(find.byType(CameraCaptureReview), findsOneWidget);
      expect(
        find.text('host clip preview'),
        findsOneWidget,
        reason: 'the slot is documented as the escape hatch from the '
            'video_player dependency, so it has to be reachable from here',
      );
      expect(find.byType(CameraVideoPreview), findsNothing);
      expect(previewed?.path, clip.path);
      expect(mockClient.attachments.uploadCount, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'without a builder the review falls back to the SDK\'s own clip preview',
    (tester) async {
      await pumpRoom(tester);

      await record(tester);

      expect(find.byType(CameraCaptureReview), findsOneWidget);
      expect(find.byType(CameraVideoPreview), findsOneWidget);
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
