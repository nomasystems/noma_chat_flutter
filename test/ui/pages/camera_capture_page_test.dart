import 'dart:async';

import 'package:camera/camera.dart' show CameraPreview;
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:permission_handler/permission_handler.dart';

const _permissionChannel = MethodChannel(
  'flutter.baseflow.com/permissions/methods',
);

const _denied = 0;
const _granted = 1;
const _permanentlyDenied = 4;

const _cameraUnavailableMessage = 'Could not start the camera';
const _microphoneDeniedMessage = 'Microphone permission denied';
const _cameraPermissionMessage = 'You need to allow camera access';
const _openSettingsLabel = 'Open settings';
const _tapForPhotoHint = 'Tap for photo, hold for video';

const _backCamera = CameraDescription(
  name: 'back',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 0,
);
const _frontCamera = CameraDescription(
  name: 'front',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 0,
);

class _FakeCameraPlatform extends CameraPlatform {
  final List<bool> createdWithAudio = <bool>[];
  final List<int> startedRecordings = <int>[];
  final List<int> stoppedRecordings = <int>[];
  final List<int> disposedCameras = <int>[];

  /// Held open to keep `startVideoRecording()` in flight while the test
  /// interrupts the session underneath it.
  Completer<void>? startVideoGate;

  /// Held open to stretch the window in which a bind is still in flight.
  Completer<void>? initializeGate;

  /// Camera ids whose native `dispose` blows up — an already-closed session.
  final Set<int> disposeFailures = <int>{};

  double minZoom = 1.0;
  bool failMaxZoom = false;

  /// Native sessions whose `initializeCamera` blew up after the session had
  /// already been created — the ones that leak unless the half-built
  /// controller is disposed.
  final List<int> failedInitializeCameraIds = <int>[];
  final List<double> setZoomLevels = <double>[];
  int availableCamerasCalls = 0;
  bool failNextInitialize = false;
  int failInitializeTimes = 0;
  List<CameraDescription> cameras = const <CameraDescription>[_backCamera];

  // Never closed on purpose: `CameraController` keeps a `.first` subscription
  // on the error stream, and closing it would surface as an unhandled
  // `StateError` after the test body finished.
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
  Future<List<CameraDescription>> availableCameras() async {
    availableCamerasCalls++;
    return cameras;
  }

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async {
    createdWithAudio.add(mediaSettings.enableAudio);
    return _nextCameraId++;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    await initializeGate?.future;
    if (failNextInitialize) {
      failNextInitialize = false;
      failedInitializeCameraIds.add(cameraId);
      throw CameraException('CameraAccessDenied', 'lens unavailable');
    }
    if (failInitializeTimes > 0) {
      failInitializeTimes--;
      failedInitializeCameraIds.add(cameraId);
      throw CameraException('CameraAccessDenied', 'lens unavailable');
    }
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
  Future<double> getMinZoomLevel(int cameraId) async => minZoom;

  @override
  Future<double> getMaxZoomLevel(int cameraId) async {
    if (failMaxZoom) {
      throw CameraException('zoomFailed', 'lens will not report a zoom range');
    }
    return 8.0;
  }

  @override
  Future<void> setZoomLevel(int cameraId, double zoom) async {
    setZoomLevels.add(zoom);
  }

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
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    await startVideoGate?.future;
    startedRecordings.add(options.cameraId);
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    stoppedRecordings.add(cameraId);
    return XFile('/tmp/clip.mp4');
  }

  @override
  Future<XFile> takePicture(int cameraId) async => XFile('/tmp/shot.jpg');

  @override
  Future<void> dispose(int cameraId) async {
    disposedCameras.add(cameraId);
    if (disposeFailures.contains(cameraId)) {
      throw CameraException('cameraNotFound', 'session already closed');
    }
  }
}

void main() {
  late List<List<int>> requestedPermissions;
  late List<int> checkedPermissions;
  late _FakeCameraPlatform camera;
  late int microphoneStatus;
  late int microphoneRequestResult;
  late int cameraStatus;
  late int cameraRequestResult;
  Completer<void>? microphoneRequestGate;

  setUp(() {
    requestedPermissions = [];
    checkedPermissions = [];
    camera = _FakeCameraPlatform();
    microphoneStatus = _granted;
    microphoneRequestResult = _granted;
    cameraStatus = _granted;
    cameraRequestResult = _granted;
    microphoneRequestGate = null;
    CameraPlatform.instance = camera;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_permissionChannel, (call) async {
          switch (call.method) {
            case 'requestPermissions':
              final requested = (call.arguments as List<dynamic>).cast<int>();
              requestedPermissions.add(requested);
              if (requested.contains(Permission.microphone.value)) {
                await microphoneRequestGate?.future;
              }
              return {
                for (final permission in requested)
                  permission: permission == Permission.microphone.value
                      ? microphoneRequestResult
                      : permission == Permission.camera.value
                      ? cameraRequestResult
                      : _granted,
              };
            case 'checkPermissionStatus':
              final permission = call.arguments as int;
              checkedPermissions.add(permission);
              if (permission == Permission.microphone.value) {
                return microphoneStatus;
              }
              if (permission == Permission.camera.value) return cameraStatus;
              return _granted;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_permissionChannel, null);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CameraCapturePage()));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  /// Presses and holds the shutter long enough for the long-press recogniser
  /// to fire, leaving the pointer down.
  Future<TestGesture> holdShutter(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CameraCaptureButton)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    return gesture;
  }

  Future<void> settle(WidgetTester tester, [int frames = 8]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump();
    }
  }

  CameraCaptureButton shutter(WidgetTester tester) =>
      tester.widget<CameraCaptureButton>(find.byType(CameraCaptureButton));

  IconButton flipButton(WidgetTester tester) => tester.widget<IconButton>(
    find.widgetWithIcon(IconButton, Icons.flip_camera_ios),
  );

  testWidgets(
    'capture button exposes a semantic label so a screen reader user can '
    'trigger the shutter',
    (tester) async {
      await pumpPage(tester);

      expect(
        find.descendant(
          of: find.byType(CameraCaptureButton),
          matching: find.bySemanticsLabel('Tap for photo, hold for video'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'the shutter stays round while recording, only its colour changes',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CameraCaptureButton(ready: true, isRecording: true),
          ),
        ),
      );
      await tester.pump();

      final decoration =
          tester
                  .widgetList<Container>(
                    find.descendant(
                      of: find.byType(CameraCaptureButton),
                      matching: find.byType(Container),
                    ),
                  )
                  .last
                  .decoration!
              as BoxDecoration;

      expect(decoration.shape, BoxShape.circle);
      expect(decoration.borderRadius, isNull);
    },
  );

  testWidgets(
    'the shutter honours the theme instead of hardcoding the recording red',
    (tester) async {
      const brandRed = Color(0xFFAA0000);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CameraCaptureButton(
              ready: true,
              isRecording: true,
              theme: ChatTheme(cameraCaptureRecordingColor: brandRed),
            ),
          ),
        ),
      );
      await tester.pump();

      final decoration =
          tester
                  .widgetList<Container>(
                    find.descendant(
                      of: find.byType(CameraCaptureButton),
                      matching: find.byType(Container),
                    ),
                  )
                  .last
                  .decoration!
              as BoxDecoration;

      expect(decoration.color, brandRed);
    },
  );

  testWidgets(
    'opening the camera prompts for the camera only, so a user who already '
    'granted it while registering is not asked again',
    (tester) async {
      await pumpPage(tester);

      expect(requestedPermissions, [
        [Permission.camera.value],
      ]);
      expect(
        requestedPermissions.expand((e) => e),
        isNot(contains(Permission.microphone.value)),
        reason: 'a still photo must not trigger the microphone prompt',
      );
      expect(
        checkedPermissions,
        contains(Permission.microphone.value),
        reason: 'the microphone is read without a dialog to decide on audio',
      );
    },
  );

  testWidgets(
    'the preview binds without audio while the microphone is not granted, so '
    'creating the camera cannot raise the microphone prompt (nor fail on iOS '
    'when it was denied before)',
    (tester) async {
      microphoneStatus = _denied;

      await pumpPage(tester);

      expect(camera.createdWithAudio, [false]);
    },
  );

  testWidgets(
    'the preview binds with audio when the microphone is already granted, so '
    'a hold records sound from the first frame',
    (tester) async {
      microphoneStatus = _granted;

      await pumpPage(tester);

      expect(camera.createdWithAudio, [true]);
    },
  );

  testWidgets(
    'holding the shutter without the microphone asks for it, warns when it is '
    'refused and records nothing',
    (tester) async {
      microphoneStatus = _denied;
      microphoneRequestResult = _denied;
      await pumpPage(tester);

      final gesture = await holdShutter(tester);
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }

      expect(
        requestedPermissions.expand((e) => e),
        contains(Permission.microphone.value),
      );
      expect(find.text(_microphoneDeniedMessage), findsOneWidget);
      expect(camera.startedRecordings, isEmpty);
      expect(camera.createdWithAudio, [
        false,
      ], reason: 'a refusal must not rebind the preview');

      await gesture.up();
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'granting the microphone mid-hold rebinds the preview with audio, and the '
    'press the dialog cancelled does not start a recording nobody is holding',
    (tester) async {
      microphoneStatus = _denied;
      microphoneRequestResult = _granted;
      final gate = Completer<void>();
      microphoneRequestGate = gate;
      await pumpPage(tester);

      final gesture = await holdShutter(tester);
      await tester.pump();

      // The system dialog steals the touch: Flutter delivers a cancel, never
      // an `onLongPressEnd`.
      await gesture.cancel();
      gate.complete();
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }

      expect(
        camera.createdWithAudio,
        [false, true],
        reason: 'granting the microphone must rebind the camera with audio',
      );
      expect(
        camera.startedRecordings,
        isEmpty,
        reason: 'the finger was already off the shutter when the grant landed',
      );
    },
  );

  testWidgets(
    'a recording cut short by an incoming call keeps telling the user the '
    'clip was lost after the preview comes back',
    (tester) async {
      microphoneStatus = _granted;
      await pumpPage(tester);

      final gesture = await holdShutter(tester);
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(camera.startedRecordings, isNotEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await gesture.cancel();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }

      expect(
        camera.createdWithAudio.length,
        2,
        reason: 'the preview must be rebound after the interruption',
      );
      expect(
        find.text(_cameraUnavailableMessage),
        findsOneWidget,
        reason: 'the lost clip must survive the rebind',
      );
    },
  );

  testWidgets(
    'returning to the foreground rebinds the camera off the cached list, '
    'without re-enumerating or re-prompting',
    (tester) async {
      await pumpPage(tester);
      final requestsAfterSetup = requestedPermissions.length;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }

      expect(
        camera.createdWithAudio.length,
        2,
        reason: 'resuming must rebind the camera',
      );
      expect(
        camera.availableCamerasCalls,
        1,
        reason: 'the camera list is cached, resuming must not re-enumerate',
      );
      expect(
        requestedPermissions.length,
        requestsAfterSetup,
        reason: 'resuming must not raise a new permission dialog',
      );
    },
  );

  testWidgets(
    'a permanently denied camera permission offers a way to open settings '
    'instead of a dead end',
    (tester) async {
      cameraRequestResult = _permanentlyDenied;

      await pumpPage(tester);

      expect(find.text(_cameraPermissionMessage), findsOneWidget);
      expect(find.text(_openSettingsLabel), findsOneWidget);
    },
  );

  testWidgets(
    'a plain camera denial does not offer to open settings, since the '
    'system can still prompt again',
    (tester) async {
      cameraRequestResult = _denied;

      await pumpPage(tester);

      expect(find.text(_cameraPermissionMessage), findsOneWidget);
      expect(find.text(_openSettingsLabel), findsNothing);
    },
  );

  testWidgets(
    'coming back from settings with the camera now allowed recovers the '
    'preview without leaving the screen',
    (tester) async {
      cameraRequestResult = _permanentlyDenied;
      await pumpPage(tester);
      expect(find.text(_cameraPermissionMessage), findsOneWidget);

      cameraStatus = _granted;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }

      expect(find.text(_cameraPermissionMessage), findsNothing);
      expect(find.text(_openSettingsLabel), findsNothing);
      expect(camera.createdWithAudio, isNotEmpty);
    },
  );

  testWidgets(
    'a failed camera switch recovers by rebinding the previous camera fresh, '
    'instead of trusting a controller that may already be natively dead',
    (tester) async {
      camera.cameras = const [_backCamera, _frontCamera];
      await pumpPage(tester);
      expect(camera.createdWithAudio, hasLength(1));

      camera.failNextInitialize = true;
      await tester.tap(find.byIcon(Icons.flip_camera_ios));
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }

      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'a failed switch must not leave the screen stuck on a spinner',
      );
      expect(
        camera.createdWithAudio,
        hasLength(3),
        reason:
            'the failed front-camera attempt and the recovery rebind of '
            'the back camera each create a fresh native session',
      );
      expect(
        camera.disposedCameras,
        containsAll(camera.failedInitializeCameraIds),
        reason:
            'the candidate whose initialize threw already owns a native '
            'session; leaving it undisposed leaks the lens',
      );
      expect(
        camera.disposedCameras,
        hasLength(2),
        reason:
            'exactly two sessions go: the failed candidate and the stale '
            'previous controller, whose own session may already be gone',
      );
      expect(
        tester
            .widget<CameraCaptureButton>(find.byType(CameraCaptureButton))
            .ready,
        isTrue,
        reason: 'recovery must leave a real, working preview behind',
      );
      expect(find.text(_cameraUnavailableMessage), findsOneWidget);
    },
  );

  testWidgets(
    'a failed camera switch whose recovery also fails lands on the fatal '
    'error screen instead of retrying forever',
    (tester) async {
      camera.cameras = const [_backCamera, _frontCamera];
      await pumpPage(tester);
      expect(camera.createdWithAudio, hasLength(1));

      camera.failInitializeTimes = 2;
      await tester.tap(find.byIcon(Icons.flip_camera_ios));
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }

      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason:
            'an unrecoverable switch must not leave the screen stuck on a '
            'spinner',
      );
      expect(
        camera.createdWithAudio,
        hasLength(3),
        reason: 'exactly one recovery attempt is made, not an endless retry',
      );
      expect(
        camera.disposedCameras,
        containsAll(camera.failedInitializeCameraIds),
        reason: 'both half-built candidates are released, not leaked',
      );
      expect(
        camera.disposedCameras,
        hasLength(3),
        reason:
            'the stale previous controller goes too, even though the '
            'recovery bind failed as well',
      );
      expect(
        tester
            .widget<CameraCaptureButton>(find.byType(CameraCaptureButton))
            .ready,
        isFalse,
        reason: 'a fatal recovery failure leaves no controller to shoot with',
      );
      expect(find.text(_cameraUnavailableMessage), findsOneWidget);
      expect(find.text(_openSettingsLabel), findsNothing);
    },
  );

  testWidgets(
    'a call that lands while startVideoRecording is in flight leaves the '
    'shutter disarmed instead of running a recording nobody can stop',
    (tester) async {
      microphoneStatus = _granted;
      await pumpPage(tester);

      final startGate = Completer<void>();
      camera.startVideoGate = startGate;
      final gesture = await holdShutter(tester);
      await tester.pump();

      // The interruption tears the controller down mid-start; the start call
      // then resolves against a session that no longer exists.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      startGate.complete();
      camera.startVideoGate = null;
      await settle(tester);

      expect(
        shutter(tester).isRecording,
        isFalse,
        reason: 'the retired start must not re-arm the gate',
      );
      expect(
        find.byIcon(Icons.fiber_manual_record),
        findsNothing,
        reason: 'no red pill and no elapsed timer for a dead session',
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester, 10);
      // The finger finally lifts, against the camera that came back.
      await gesture.up();
      await settle(tester, 4);

      expect(
        shutter(tester).isRecording,
        isFalse,
        reason: 'the release must not find a gate still armed',
      );
      expect(
        camera.stoppedRecordings,
        isEmpty,
        reason:
            'stopVideoRecording on a controller that is not recording throws '
            'and paints the fatal error over a working camera',
      );
      expect(
        find.text(_tapForPhotoHint),
        findsOneWidget,
        reason: 'the shutter hint only renders while there is no fatal error',
      );
      expect(
        shutter(tester).ready,
        isTrue,
        reason: 'the screen has to be usable again after the interruption',
      );
    },
  );

  testWidgets(
    'holding the shutter during a lens switch cannot record on the camera '
    'the switch is about to dispose',
    (tester) async {
      camera.cameras = const [_backCamera, _frontCamera];
      microphoneStatus = _granted;
      await pumpPage(tester);

      final bindGate = Completer<void>();
      camera.initializeGate = bindGate;
      await tester.tap(find.byIcon(Icons.flip_camera_ios));
      await tester.pump();

      expect(
        shutter(tester).ready,
        isFalse,
        reason: 'the shutter must not act on a controller being replaced',
      );
      expect(
        flipButton(tester).onPressed,
        isNull,
        reason: 'a second tap must not queue a second switch',
      );

      final gesture = await holdShutter(tester);
      await settle(tester, 4);
      expect(
        camera.startedRecordings,
        isEmpty,
        reason: 'the outgoing session is already on its way out',
      );

      bindGate.complete();
      camera.initializeGate = null;
      await settle(tester, 10);
      await gesture.up();
      await settle(tester, 4);

      expect(camera.createdWithAudio, hasLength(2));
      expect(
        camera.disposedCameras,
        contains(1),
        reason: 'the outgoing lens is released, not leaked',
      );
      expect(
        camera.startedRecordings,
        isEmpty,
        reason: 'the hold that raced the switch never becomes a recording',
      );
      expect(camera.stoppedRecordings, isEmpty);
      expect(
        shutter(tester).ready,
        isTrue,
        reason: 'the new lens is live and the shutter works again',
      );
      expect(find.text(_tapForPhotoHint), findsOneWidget);
    },
  );

  testWidgets(
    'the flip button is inert while a recording start is in flight, so the '
    'lens cannot be swapped out from under it',
    (tester) async {
      camera.cameras = const [_backCamera, _frontCamera];
      microphoneStatus = _granted;
      await pumpPage(tester);

      final startGate = Completer<void>();
      camera.startVideoGate = startGate;
      final gesture = await holdShutter(tester);
      await tester.pump();

      expect(flipButton(tester).onPressed, isNull);
      await tester.tap(find.byIcon(Icons.flip_camera_ios), warnIfMissed: false);
      await settle(tester, 4);

      expect(
        camera.createdWithAudio,
        hasLength(1),
        reason: 'no rebind may begin while the start is still in flight',
      );

      startGate.complete();
      camera.startVideoGate = null;
      await settle(tester, 4);

      expect(camera.startedRecordings, hasLength(1));
      expect(shutter(tester).isRecording, isTrue);

      // Torn down instead of released, so the clip never has to be delivered.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await gesture.up();
      await settle(tester, 4);
      expect(shutter(tester).isRecording, isFalse);
    },
  );

  testWidgets(
    'a lens switch whose outgoing session refuses to close is still a '
    'successful switch, not a camera failure',
    (tester) async {
      camera.cameras = const [_backCamera, _frontCamera];
      await pumpPage(tester);
      expect(camera.createdWithAudio, hasLength(1));

      // The back camera's native session is already gone by the time we let
      // go of it — routine on Android once the new lens is bound.
      camera.disposeFailures.add(1);
      await tester.tap(find.byIcon(Icons.flip_camera_ios));
      await settle(tester);

      expect(
        camera.createdWithAudio,
        hasLength(2),
        reason:
            'a teardown that throws must not be read as a failed switch and '
            'trigger a recovery rebind of the lens we just left',
      );
      expect(
        find.text(_cameraUnavailableMessage),
        findsNothing,
        reason: 'the front camera came up fine; nothing failed for the user',
      );
      expect(find.text(_tapForPhotoHint), findsOneWidget);
      expect(shutter(tester).ready, isTrue);
    },
  );

  testWidgets(
    'a preview rebind whose old session refuses to close still lands on the '
    'new controller',
    (tester) async {
      microphoneStatus = _denied;
      microphoneRequestResult = _granted;
      final gate = Completer<void>();
      microphoneRequestGate = gate;
      camera.disposeFailures.add(1);
      await pumpPage(tester);

      final gesture = await holdShutter(tester);
      await tester.pump();
      await gesture.cancel();
      gate.complete();
      await settle(tester);

      expect(
        camera.createdWithAudio,
        [false, true],
        reason: 'the audio rebind must survive a stale session refusing to go',
      );
      expect(find.text(_cameraUnavailableMessage), findsNothing);
      expect(shutter(tester).ready, isTrue);
    },
  );

  testWidgets(
    'a lens that fails halfway through reporting its zoom range keeps the '
    'pinch gesture inert instead of throwing',
    (tester) async {
      // The minimum lands, the maximum does not: the seeded maximum would be
      // left below the minimum, and `clamp` throws an ArgumentError for that.
      camera.minZoom = 2.0;
      camera.failMaxZoom = true;
      await pumpPage(tester);

      final center = tester.getCenter(find.byType(CameraPreview));
      final first = await tester.startGesture(
        center - const Offset(24, 0),
        pointer: 7,
      );
      final second = await tester.startGesture(
        center + const Offset(24, 0),
        pointer: 8,
      );
      await tester.pump();
      await first.moveTo(center - const Offset(80, 0));
      await second.moveTo(center + const Offset(80, 0));
      await tester.pump();
      await first.up();
      await second.up();
      await settle(tester, 4);

      expect(
        tester.takeException(),
        isNull,
        reason: 'an ArgumentError is an Error, so no `on Exception` catches it',
      );
      expect(
        camera.setZoomLevels,
        isEmpty,
        reason: 'a lens with no usable range stays where it is',
      );
      expect(shutter(tester).ready, isTrue);
    },
  );
}
