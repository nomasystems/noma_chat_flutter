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
/// can walk, so the capture path behaves as it does for a real shot.
final Uint8List _jpeg = Uint8List.fromList([
  0xFF, 0xD8, // SOI
  0xFF, 0xDB, 0x00, 0x05, 0x00, 0x10, 0x0B, // a quantisation table
  0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x3F, 0x00, // start of scan
  0xAA, 0xBB, 0xCC, 0xDD,
  0xFF, 0xD9, // EOI
]);

/// Stands in for a hold-to-record clip: far too heavy for the caps these
/// tests set, and nothing a shrinker could ever make lighter.
final Uint8List _clip = Uint8List(4096);

/// Camera platform that hands back a capture the test can watch on disk: the
/// bytes come from memory (a widget test cannot turn the real event loop for
/// file reads), while `path` names a file that really exists.
class _FakeCameraPlatform extends CameraPlatform {
  _FakeCameraPlatform(this.capturePath, this.clipPath);

  final String capturePath;

  final String clipPath;

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
  Future<XFile> takePicture(int cameraId) async =>
      XFile.fromData(_jpeg, path: capturePath, name: 'shot.jpg');

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {}

  @override
  Future<XFile> stopVideoRecording(int cameraId) async => XFile(clipPath);

  @override
  Future<void> dispose(int cameraId) async {}
}

/// The 0.34 surface a host writes against: the directory hook, the
/// bootstrap switch, the send-retry policy, the read-only notice, and the
/// write policy a room's config carries.
///
/// What is pinned here is the *contract* — what a host gets when it says
/// nothing, what survives when it does say something, and how the wire
/// values decode. Not the machinery behind it, which lands piece by piece.
void main() {
  const me = ChatUser(id: 'me', displayName: 'Me');

  late MockChatClient client;

  setUp(() {
    client = MockChatClient(currentUserId: me.id);
  });

  tearDown(() async {
    await client.dispose();
  });

  ChatUiAdapter adapterWith({
    UserDirectoryResolver? userDirectoryResolver,
    Duration? userDirectoryTtl,
    bool? bootstrapCurrentUser,
    SendRetryPolicy? sendRetryPolicy,
  }) {
    final adapter = ChatUiAdapter(
      client: client,
      currentUser: me,
      manageAppLifecycle: false,
      userDirectoryResolver: userDirectoryResolver,
      userDirectoryTtl: userDirectoryTtl ?? const Duration(hours: 12),
      bootstrapCurrentUser: bootstrapCurrentUser ?? false,
      sendRetryPolicy: sendRetryPolicy ?? const SendRetryPolicy.firstSendOnly(),
    );
    addTearDown(adapter.dispose);
    return adapter;
  }

  group('ChatUiAdapter defaults', () {
    test('a host that says nothing keeps asking chat and nobody else', () {
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: me,
        manageAppLifecycle: false,
      );
      addTearDown(adapter.dispose);

      expect(adapter.userDirectoryResolver, isNull);
      expect(adapter.bootstrapCurrentUser, isFalse);
      expect(
        adapter.userDirectoryTtl,
        const Duration(hours: 12),
        reason: 'a name is good for an afternoon, not for a round trip',
      );
      expect(adapter.sendRetryPolicy, const SendRetryPolicy.firstSendOnly());
    });

    test('what the host passes is what the adapter holds', () async {
      Future<Map<String, HostUser>> resolver(Set<String> ids) async =>
          const <String, HostUser>{};
      final adapter = adapterWith(
        userDirectoryResolver: resolver,
        userDirectoryTtl: const Duration(minutes: 5),
        bootstrapCurrentUser: true,
        sendRetryPolicy: const SendRetryPolicy.none(),
      );

      expect(adapter.userDirectoryResolver, same(resolver));
      expect(adapter.userDirectoryTtl, const Duration(minutes: 5));
      expect(adapter.bootstrapCurrentUser, isTrue);
      expect(adapter.sendRetryPolicy, const SendRetryPolicy.none());
    });
  });

  group('HostUser', () {
    test('an id nobody is behind answers, instead of staying silent', () {
      const answer = HostUser.missing('u404');

      expect(answer.id, 'u404');
      expect(answer.gone, isTrue);
      expect(answer.displayName, isNull);
      expect(answer.hasDisplayName, isFalse);
    });

    test('a name made of spaces is not a name', () {
      const blank = HostUser(id: 'u1', displayName: '   ');

      expect(blank.hasDisplayName, isFalse);
      expect(const HostUser(id: 'u1', displayName: 'Ana').hasDisplayName, true);
    });

    test('two answers about the same person are the same value', () {
      const a = HostUser(id: 'u1', displayName: 'Ana', avatarUrl: 'https://a');
      const b = HostUser(id: 'u1', displayName: 'Ana', avatarUrl: 'https://a');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.copyWith(gone: true), isNot(a));
      expect(a.copyWith(displayName: 'Ana B').displayName, 'Ana B');
    });
  });

  group('SendRetryPolicy', () {
    test('the default backs off three times and then stops', () {
      const policy = SendRetryPolicy.firstSendOnly();

      expect(policy.mode, SendRetryMode.firstSendOnly);
      expect(policy.delays, SendRetryPolicy.defaultDelays);
      expect(policy.maxAttempts, 3);
      expect(policy.delayFor(0), const Duration(milliseconds: 400));
      expect(policy.delayFor(2), const Duration(milliseconds: 1500));
      expect(policy.delayFor(3), isNull);
      expect(policy.delayFor(-1), isNull);
    });

    test('none never retries', () {
      const policy = SendRetryPolicy.none();

      expect(policy.mode, SendRetryMode.none);
      expect(policy.maxAttempts, 0);
      expect(policy.delays, isEmpty);
      expect(policy.delayFor(0), isNull);
    });

    test('a host can pick its own backoff', () {
      const policy = SendRetryPolicy.firstSendOnly(
        delays: [Duration(milliseconds: 50)],
      );

      expect(policy.maxAttempts, 1);
      expect(policy.delayFor(0), const Duration(milliseconds: 50));
      expect(policy, isNot(const SendRetryPolicy.firstSendOnly()));
      expect(
        policy,
        const SendRetryPolicy.firstSendOnly(
          delays: [Duration(milliseconds: 50)],
        ),
      );
    });
  });

  group('RoomWritePolicy on the wire', () {
    test('only the exact owner-only value closes a room', () {
      expect(
        RoomWritePolicyWire.fromWire('owner_only'),
        RoomWritePolicy.ownerOnly,
      );
      expect(RoomWritePolicy.ownerOnly.wireValue, 'owner_only');
      expect(RoomWritePolicy.members.wireValue, 'members');
    });

    test('anything the SDK does not know fails open', () {
      for (final raw in <Object?>[
        null,
        'members',
        'moderators',
        'OWNER_ONLY',
        'ownerOnly',
        42,
        <String, dynamic>{},
      ]) {
        expect(
          RoomWritePolicyWire.fromWire(raw),
          RoomWritePolicy.members,
          reason: 'a room nobody can write to is worse than a missed policy',
        );
      }
    });
  });

  group('ChatViewBuilders', () {
    test('the read-only notice is the SDK default until a host says so', () {
      expect(const ChatViewBuilders().readOnlyNoticeBuilder, isNull);
    });

    testWidgets('NomaChatView hands the read-only notice down to ChatView', (
      tester,
    ) async {
      final adapter = adapterWith();
      adapter.roomListController.addRoom(const RoomListItem(id: 'r1'));
      Widget? notice(BuildContext context, ReadOnlyReason reason) =>
          const SizedBox.shrink();

      await tester.pumpWidget(
        MaterialApp(
          home: NomaChatView(
            roomId: 'r1',
            adapter: adapter,
            hydrateGroupMembers: false,
            builders: ChatViewBuilders(readOnlyNoticeBuilder: notice),
          ),
        ),
      );
      await tester.pump();

      final view = tester.widget<ChatView>(find.byType(ChatView));
      expect(view.builders.readOnlyNoticeBuilder, same(notice));
    });

    testWidgets('the delivery-tick override is not dropped on the way down', (
      tester,
    ) async {
      // `ChatView` reads `builders.statusIconBuilder`, but `NomaChatView`
      // rebuilds the whole `ChatViewBuilders` before handing it over and
      // used to forget this one field: a host that redrew its ticks got the
      // SDK's back and no error anywhere.
      final adapter = adapterWith();
      adapter.roomListController.addRoom(const RoomListItem(id: 'r1'));
      Widget? tick(BuildContext context, MessageStatusIconData data) =>
          const SizedBox.shrink();

      await tester.pumpWidget(
        MaterialApp(
          home: NomaChatView(
            roomId: 'r1',
            adapter: adapter,
            hydrateGroupMembers: false,
            builders: ChatViewBuilders(statusIconBuilder: tick),
          ),
        ),
      );
      await tester.pump();

      final view = tester.widget<ChatView>(find.byType(ChatView));
      expect(view.builders.statusIconBuilder, same(tick));
    });
  });

  group('the image shrinker hook', () {
    test('is inert until the host supplies an engine', () async {
      final adapter = adapterWith();

      expect(adapter.attachmentShrinker, isA<NoAttachmentShrinker>());
      expect(
        await adapter.attachmentShrinker.fit(
          Uint8List.fromList(const [1, 2, 3]),
          mimeType: 'image/png',
          maxBytes: 1,
          fileName: 'shot.png',
        ),
        isNull,
        reason: 'the default sends the bytes the user picked, untouched',
      );
    });

    test('is the host engine once one is supplied', () async {
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: me,
        manageAppLifecycle: false,
        attachmentShrinker: _TruncatingShrinker(),
      );
      addTearDown(adapter.dispose);

      final shrunk = await adapter.attachmentShrinker.fit(
        Uint8List.fromList(List<int>.filled(8, 7)),
        mimeType: 'image/heic',
        maxBytes: 4,
        fileName: 'shot.heic',
      );

      expect(shrunk, isNotNull);
      expect(shrunk!.bytes, hasLength(4));
      expect(
        shrunk.mimeType,
        'image/jpeg',
        reason: 're-encoding changes the type the blob must be stored under',
      );
      expect(shrunk.fileName, 'shot.jpg');
    });

    test('reaches the payload the size cap is measured on', () async {
      const policy = AttachmentPolicy(maxBytes: 4);
      final oversized = AttachmentPickResult(
        bytes: Uint8List.fromList(List<int>.filled(12, 7)),
        mimeType: 'image/heic',
        fileName: 'shot.heic',
      );

      expect(
        policy.validate(
          mimeType: oversized.mimeType,
          sizeBytes: oversized.size,
        ),
        isNotNull,
        reason: 'what the camera handed over is over the cap as it stands',
      );

      final payload = await AttachmentPickers.shrinkToPolicy(
        oversized,
        policy: policy,
        shrinker: _TruncatingShrinker(),
      );

      expect(payload.size, lessThanOrEqualTo(4));
      expect(payload.mimeType, 'image/jpeg');
      expect(payload.fileName, 'shot.jpg');
      expect(
        policy.validate(mimeType: payload.mimeType, sizeBytes: payload.size),
        isNull,
        reason: 'a capture above the cap is reduced and sent, not refused',
      );
    });

    test('leaves the refusal in place when no engine is wired', () async {
      const policy = AttachmentPolicy(maxBytes: 4);
      final oversized = AttachmentPickResult(
        bytes: Uint8List.fromList(List<int>.filled(12, 7)),
        mimeType: 'image/heic',
        fileName: 'shot.heic',
      );

      final payload = await AttachmentPickers.shrinkToPolicy(
        oversized,
        policy: policy,
        shrinker: const NoAttachmentShrinker(),
      );

      expect(payload, same(oversized));
      expect(
        policy
            .validate(mimeType: payload.mimeType, sizeBytes: payload.size)
            ?.kind,
        AttachmentPolicyViolationKind.tooLarge,
      );
    });
  });

  group('the shrinker on the SDK capture path', () {
    late Directory captureDir;
    late File capture;
    late File clip;

    setUp(() {
      captureDir = Directory.systemTemp.createTempSync('noma_0340_capture');
      capture = File('${captureDir.path}/shot.jpg')..writeAsBytesSync(_jpeg);
      clip = File('${captureDir.path}/clip.mp4')..writeAsBytesSync(_clip);
      CameraPlatform.instance = _FakeCameraPlatform(capture.path, clip.path);

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

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_permissionChannel, null);
      if (captureDir.existsSync()) captureDir.deleteSync(recursive: true);
    });

    Future<void> pumpRoom(
      WidgetTester tester, {
      required AttachmentPolicy policy,
      required AttachmentShrinker shrinker,
    }) async {
      final adapter = ChatUiAdapter(
        client: client,
        currentUser: me,
        manageAppLifecycle: false,
        attachmentShrinker: shrinker,
      );
      addTearDown(adapter.dispose);
      adapter.roomListController.addRoom(const RoomListItem(id: 'r1'));

      await tester.pumpWidget(
        MaterialApp(
          home: NomaChatView(
            roomId: 'r1',
            adapter: adapter,
            hydrateGroupMembers: false,
            attachmentPolicy: policy,
            builders: ChatViewBuilders(
              videoPreviewBuilder: (context, file, theme) =>
                  const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    /// Lets the real event loop turn so the `dart:io` calls the send path
    /// makes can complete, then hands control back to the fake clock.
    Future<void> drain(WidgetTester tester) async {
      for (var round = 0; round < 6; round++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
    }

    Future<void> openCamera(WidgetTester tester) async {
      tester.widget<ChatView>(find.byType(ChatView)).callbacks.onPickCamera!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      expect(find.byType(CameraCaptureButton), findsOneWidget);
    }

    /// Taps the shutter and stops on the review step, where a still waits
    /// until the user says what to do with it.
    Future<void> shoot(WidgetTester tester) async {
      await openCamera(tester);
      await tester.tap(find.byType(CameraCaptureButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await drain(tester);
      expect(find.byType(CameraCaptureReview), findsOneWidget);
    }

    /// Holds the shutter down and stops on the review step, with a clip.
    Future<void> record(WidgetTester tester) async {
      await openCamera(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CameraCaptureButton)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await drain(tester);
      await gesture.up();
      await drain(tester);
      expect(find.byType(CameraCaptureReview), findsOneWidget);
    }

    /// Confirms whatever waits on the review step.
    Future<void> confirm(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await drain(tester);
    }

    testWidgets(
      'a capture over the cap is reduced and sent, not refused',
      (tester) async {
        final shrinker = _TruncatingShrinker();
        await pumpRoom(
          tester,
          policy: const AttachmentPolicy(maxBytes: 8),
          shrinker: shrinker,
        );

        await shoot(tester);
        await confirm(tester);

        expect(
          shrinker.calls,
          1,
          reason: 'the host engine has to reach the SDK capture path',
        );
        expect(
          client.attachments.uploadCount,
          1,
          reason:
              'the shot fits once reduced, so refusing it measures the '
              'wrong bytes',
        );
        expect(client.attachments.uploadedMimeTypes, ['image/jpeg']);
        expect(capture.existsSync(), isFalse);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'a clip over the cap is weighed on disk, so it is never read in',
      (tester) async {
        final shrinker = _TruncatingShrinker();
        await pumpRoom(
          tester,
          policy: const AttachmentPolicy(maxBytes: 8),
          shrinker: shrinker,
        );

        await record(tester);
        await confirm(tester);

        expect(client.attachments.uploadCount, 0);
        expect(
          shrinker.calls,
          0,
          reason:
              'no engine reduces a video, so nothing downstream of the '
              'read may run: a clip over the cap is refused on its length',
        );
        expect(clip.existsSync(), isFalse);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'a clip whose extension is denied is refused like any other pick',
      (tester) async {
        await pumpRoom(
          tester,
          policy: const AttachmentPolicy(
            maxBytes: 1024 * 1024,
            deniedExtensions: {'mp4'},
          ),
          shrinker: _TruncatingShrinker(),
        );

        await record(tester);
        await confirm(tester);

        expect(client.attachments.uploadCount, 0);
        expect(
          find.text(ChatUiLocalizations.en.attachmentTypeNotAllowed),
          findsWidgets,
          reason:
              'a camera clip carries a name, so the deny list judges it by '
              'the same rule as a picked file — and on the length it is '
              'read from, before the recording is pulled into memory',
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  });

  group('the plug & play entry point', () {
    test('hands the 0.34 wiring straight to the adapter', () async {
      Future<Map<String, HostUser>> resolver(Set<String> ids) async =>
          const <String, HostUser>{};
      final shrinker = _TruncatingShrinker();
      final chat = NomaChat.fromClient(
        client: client,
        currentUser: me,
        manageAppLifecycle: false,
        userDirectoryResolver: resolver,
        userDirectoryTtl: const Duration(minutes: 5),
        bootstrapCurrentUser: true,
        sendRetryPolicy: const SendRetryPolicy.none(),
        attachmentShrinker: shrinker,
      );
      addTearDown(chat.dispose);

      expect(chat.adapter.userDirectoryResolver, same(resolver));
      expect(chat.adapter.userDirectoryTtl, const Duration(minutes: 5));
      expect(chat.adapter.bootstrapCurrentUser, isTrue);
      expect(chat.adapter.sendRetryPolicy, const SendRetryPolicy.none());
      expect(chat.adapter.attachmentShrinker, same(shrinker));
    });

    test('keeps the sane defaults when the host says nothing', () async {
      final chat = NomaChat.fromClient(
        client: client,
        currentUser: me,
        manageAppLifecycle: false,
      );
      addTearDown(chat.dispose);

      expect(chat.adapter.userDirectoryResolver, isNull);
      expect(chat.adapter.userDirectoryTtl, const Duration(hours: 12));
      expect(chat.adapter.bootstrapCurrentUser, isFalse);
      expect(
        chat.adapter.sendRetryPolicy,
        const SendRetryPolicy.firstSendOnly(),
      );
      expect(chat.adapter.attachmentShrinker, isA<NoAttachmentShrinker>());
    });
  });
}

/// Stand-in for the real encoder: cuts the payload down to the cap and
/// renames it, which is all the surface under test has to carry.
class _TruncatingShrinker implements AttachmentShrinker {
  /// How many payloads reached the engine. A path that refuses an
  /// attachment before reading it never gets this far.
  int calls = 0;

  @override
  Future<ShrunkAttachment?> fit(
    Uint8List bytes, {
    required String mimeType,
    required int maxBytes,
    required String fileName,
  }) async {
    calls++;
    if (bytes.length <= maxBytes) return null;
    return ShrunkAttachment(
      bytes: Uint8List.fromList(bytes.sublist(0, maxBytes)),
      mimeType: 'image/jpeg',
      fileName: '${fileName.split('.').first}.jpg',
    );
  }
}
