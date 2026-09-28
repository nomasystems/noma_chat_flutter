import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _sensorsMethodChannel = MethodChannel(
  'dev.fluttercommunity.plus/sensors/method',
);
const _accelerometerChannel = EventChannel(
  'dev.fluttercommunity.plus/sensors/accelerometer',
);

/// Stands in for `sensors_plus` on the test binary messenger, which has no
/// plugin behind it. The accelerometer stays silent unless a test pushes a
/// reading through [emitGravity].
class FakeSensors {
  MockStreamHandlerEventSink? _sink;

  /// Readings in the Android sensor frame, the one `sensors_plus` reports.
  void emitGravity(double x, double y, double z) {
    _sink?.success(<double>[
      x,
      y,
      z,
      DateTime.now().microsecondsSinceEpoch.toDouble(),
    ]);
  }

  bool get listening => _sink != null;

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      _sensorsMethodChannel,
      (_) async => null,
    );
    messenger.setMockStreamHandler(
      _accelerometerChannel,
      MockStreamHandler.inline(
        onListen: (_, sink) {
          _sink = sink;
        },
        onCancel: (_) {
          _sink = null;
        },
      ),
    );
  }

  void uninstall() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_sensorsMethodChannel, null);
    messenger.setMockStreamHandler(_accelerometerChannel, null);
    _sink = null;
  }
}
