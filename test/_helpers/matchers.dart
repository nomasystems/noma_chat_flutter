/// Shared matcher for asserting a `ChangeNotifier`/`ValueNotifier` throws
/// after disposal. Older Flutter SDKs throw `FlutterError`; newer SDKs moved
/// the disposed-notifier assertion to `package:listen` and throw
/// `StateError` instead. This matcher accepts either so the same test keeps
/// working across SDKs.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

final Matcher throwsDisposedNotifierError = throwsA(
  anyOf(isA<FlutterError>(), isA<StateError>()),
);
