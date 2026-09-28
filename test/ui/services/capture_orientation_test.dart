import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

import '../../_helpers/fake_sensors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CaptureOrientation.fromGravity', () {
    for (final (name, x, y, z, expected) in const [
      ('upright', 0.2, 9.8, 0.4, DeviceOrientation.portraitUp),
      ('upside down', -0.2, -9.7, 0.4, DeviceOrientation.portraitDown),
      (
        'turned counterclockwise',
        9.8,
        0.3,
        0.2,
        DeviceOrientation.landscapeLeft,
      ),
      ('turned clockwise', -9.8, -0.3, 0.2, DeviceOrientation.landscapeRight),
      (
        'tilted back but still readable',
        0.1,
        6.0,
        7.5,
        DeviceOrientation.portraitUp,
      ),
    ]) {
      test('$name reads as $expected', () {
        expect(CaptureOrientation.fromGravity(x, y, z), expected);
      });
    }

    for (final (name, x, y, z) in const [
      ('flat on a table', 0.3, 0.4, 9.8),
      ('on the 45 degree diagonal', 6.9, 6.9, 0.2),
      ('in free fall', 0.0, 0.0, 0.0),
    ]) {
      test('$name cannot tell', () {
        expect(CaptureOrientation.fromGravity(x, y, z), isNull);
      });
    }
  });

  group('CaptureOrientation.stillRotation', () {
    const up = DeviceOrientation.portraitUp;
    const left = DeviceOrientation.landscapeLeft;
    const down = DeviceOrientation.portraitDown;
    const right = DeviceOrientation.landscapeRight;

    for (final (capturedIn, heldIn, degrees) in const [
      (up, up, 0),
      (up, left, 270),
      (up, right, 90),
      (up, down, 180),
      (left, left, 0),
      (left, up, 90),
      (right, left, 180),
      (down, up, 180),
    ]) {
      test('framed $capturedIn, held $heldIn turns $degrees clockwise', () {
        expect(
          CaptureOrientation.stillRotation(
            capturedIn: capturedIn,
            heldIn: heldIn,
          ),
          degrees,
        );
      });
    }
  });

  group('CaptureOrientation.accelerometer', () {
    final sensors = FakeSensors();
    setUp(sensors.install);
    tearDown(sensors.uninstall);

    test('reports changes only, and skips readings that cannot tell', () async {
      final seen = <DeviceOrientation>[];
      final subscription = CaptureOrientation.accelerometer().listen(seen.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      expect(sensors.listening, isTrue);

      sensors
        ..emitGravity(0.1, 9.8, 0.2)
        ..emitGravity(0.2, 9.7, 0.2)
        ..emitGravity(0.3, 0.4, 9.8)
        ..emitGravity(9.8, 0.2, 0.2)
        ..emitGravity(-9.8, 0.2, 0.2);
      await pumpEventQueue();

      expect(seen, [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    });
  });
}
