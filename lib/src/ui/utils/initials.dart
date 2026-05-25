import 'package:characters/characters.dart';

/// Returns up to [maxChars] initial letters of [name]. Uses Unicode-aware
/// character iteration (via `String.characters`) so multi-code-unit
/// graphemes (emoji, combining marks) stay intact.
///
/// Empty/null name returns the empty string. The result is upper-cased.
///
/// ```dart
/// initialsOf('Alice');                 // → 'A'
/// initialsOf('Alice');         …max=2  // → 'A'
/// initialsOf('Alice Cooper');          // → 'AC'
/// initialsOf('alice cooper bow');      // → 'AC'  (still capped at maxChars)
/// initialsOf('  ');                    // → ''
/// initialsOf(null);                    // → ''
/// ```
String initialsOf(String? name, {int maxChars = 2}) {
  if (name == null) return '';
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '';
  final parts = trimmed.split(RegExp(r'\s+'));
  final buf = StringBuffer();
  for (final part in parts) {
    if (buf.length >= maxChars) break;
    if (part.isEmpty) continue;
    buf.write(part.characters.first);
  }
  return buf.toString().toUpperCase();
}
