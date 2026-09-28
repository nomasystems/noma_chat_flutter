import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Reports which way up the phone is physically being held, as a stream of
/// [DeviceOrientation]. See [CaptureOrientation.accelerometer].
typedef CaptureOrientationSource = Stream<DeviceOrientation> Function();

/// How the in-app camera learns which way up a still was shot, whatever the
/// app's UI or the system rotation lock say.
///
/// Neither camera plugin can tell on its own inside a portrait-only app.
/// Android reports the UI orientation, which never leaves portrait, and iOS
/// reports `UIDevice` orientation, which stops updating while the rotation
/// lock is on. Either way a photo taken with the phone on its side is framed
/// as a portrait one with the scene lying on its side. Gravity does not lie,
/// so the capture screen reads it and turns the still upright.
abstract final class CaptureOrientation {
  /// Gravity readings closer to the screen's normal than this fraction of
  /// their magnitude mean the phone is lying flat, where "which side is up"
  /// has no answer; the last one stands.
  static const double _minTilt = 0.5;

  /// Readings within this fraction of each other on both axes sit on the
  /// 45 degree boundary; the last orientation stands rather than flickering.
  static const double _deadBand = 0.2;

  /// Physical orientation from the accelerometer, sampled at
  /// [SensorInterval.normalInterval]. Emits only on change, and never for
  /// readings where the phone is flat or on a diagonal.
  static Stream<DeviceOrientation> accelerometer() =>
      accelerometerEventStream(samplingPeriod: SensorInterval.normalInterval)
          .map((event) => fromGravity(event.x, event.y, event.z))
          .where((orientation) => orientation != null)
          .cast<DeviceOrientation>()
          .distinct();

  /// The orientation a gravity reading implies, in the Android sensor frame
  /// (`sensors_plus` maps iOS onto it): +y towards the top edge, +x towards
  /// the right edge, a phone held upright reading about +9.8 on y. `null`
  /// when the reading cannot tell — the phone is flat, or on a diagonal.
  static DeviceOrientation? fromGravity(double x, double y, double z) {
    final planar = math.sqrt(x * x + y * y);
    final magnitude = math.sqrt(planar * planar + z * z);
    if (magnitude == 0 || planar < magnitude * _minTilt) return null;
    if ((x.abs() - y.abs()).abs() < planar * _deadBand) return null;
    if (x.abs() > y.abs()) {
      return x > 0
          ? DeviceOrientation.landscapeLeft
          : DeviceOrientation.landscapeRight;
    }
    return y > 0
        ? DeviceOrientation.portraitUp
        : DeviceOrientation.portraitDown;
  }

  /// Quarter turns counterclockwise [orientation] is from
  /// [DeviceOrientation.portraitUp].
  static int counterclockwiseQuarterTurns(DeviceOrientation orientation) =>
      switch (orientation) {
        DeviceOrientation.portraitUp => 0,
        DeviceOrientation.landscapeLeft => 1,
        DeviceOrientation.portraitDown => 2,
        DeviceOrientation.landscapeRight => 3,
      };

  /// Clockwise degrees (0, 90, 180 or 270) that turn a still framed for
  /// [capturedIn] upright for a phone held in [heldIn].
  static int stillRotation({
    required DeviceOrientation capturedIn,
    required DeviceOrientation heldIn,
  }) {
    final turns =
        counterclockwiseQuarterTurns(capturedIn) -
        counterclockwiseQuarterTurns(heldIn);
    return (turns % 4) * 90;
  }
}
