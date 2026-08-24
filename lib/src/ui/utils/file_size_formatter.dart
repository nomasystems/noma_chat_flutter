const List<String> _units = <String>['B', 'KB', 'MB', 'GB', 'TB'];

const Set<String> _commaDecimalLanguages = <String>{
  'es',
  'fr',
  'de',
  'it',
  'pt',
  'ca',
  'sv',
  'no',
  'nb',
  'nn',
  'da',
  'pl',
  'cs',
};

/// Formats the raw `fileSize` carried by a message into something readable.
///
/// The SDK's own uploader stores `bytes.length.toString()`, so the value
/// reaching a bubble is normally a plain byte count (`'387'`). It is scaled
/// to B / KB / MB / GB / TB with one decimal from KB up, using decimal
/// (1000-based) units — the convention the platform file pickers show.
///
/// A host is free to hand the SDK an already formatted string instead
/// (`'2.4 MB'`). Anything that does not parse as a non-negative integer is
/// returned verbatim, so those consumers keep the text they chose.
String formatFileSize(String raw, {String localeCode = 'en'}) {
  final bytes = int.tryParse(raw.trim());
  if (bytes == null || bytes < 0) return raw;
  if (bytes < 1000) return '$bytes ${_units.first}';

  var value = bytes / 1000;
  var unit = 1;
  while (value >= 1000 && unit < _units.length - 1) {
    value /= 1000;
    unit++;
  }
  var text = value.toStringAsFixed(1);
  if (double.parse(text) >= 1000 && unit < _units.length - 1) {
    value /= 1000;
    unit++;
    text = value.toStringAsFixed(1);
  }
  return '${text.replaceAll('.', fileSizeDecimalSeparator(localeCode))} '
      '${_units[unit]}';
}

String fileSizeDecimalSeparator(String localeCode) {
  final primary = localeCode.toLowerCase().split(RegExp(r'[_-]')).first;
  return _commaDecimalLanguages.contains(primary) ? ',' : '.';
}
