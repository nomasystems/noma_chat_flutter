/// Material / Cupertino localization delegates that claim every locale.
///
/// `MaterialApp` only bundles English defaults for its own strings, so a
/// test that drives the app locale to any other language trips
/// `WidgetsApp`'s debug check ("this application's locale is not supported
/// by all of its localization delegates") and fails on the reported error.
/// Real hosts register `flutter_localizations`; the SDK does not depend on
/// it, so tests that only care about [ChatUiLocalizations] pin these
/// stand-ins instead — the Material strings stay English, which no
/// assertion here reads.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Drop into `MaterialApp.localizationsDelegates` next to the delegates
/// under test.
const List<LocalizationsDelegate<dynamic>> anyLocaleMaterialDelegates =
    <LocalizationsDelegate<dynamic>>[
      _AnyLocaleMaterialLocalizationsDelegate(),
      _AnyLocaleCupertinoLocalizationsDelegate(),
    ];

class _AnyLocaleMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _AnyLocaleMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      SynchronousFuture<MaterialLocalizations>(
        const DefaultMaterialLocalizations(),
      );

  @override
  bool shouldReload(_AnyLocaleMaterialLocalizationsDelegate old) => false;
}

class _AnyLocaleCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _AnyLocaleCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      SynchronousFuture<CupertinoLocalizations>(
        const DefaultCupertinoLocalizations(),
      );

  @override
  bool shouldReload(_AnyLocaleCupertinoLocalizationsDelegate old) => false;
}
