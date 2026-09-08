import 'package:characters/characters.dart';

/// How many emoji a message may hold and still be painted large.
///
/// Three, the WhatsApp baseline. Past that the enlarged glyphs stop being a
/// reaction and start being a wall, and the row height gets silly.
const int kEmojiOnlyMaxCount = 3;

/// Whether [text] is nothing but emoji — the case a chat paints large,
/// bubble-less, the way WhatsApp does.
///
/// True for `🍺`, `😀😀😀`, `👨‍👩‍👧‍👦` and `🇪🇸`, and for the same with spaces
/// between them. False as soon as one letter, digit or punctuation mark
/// joins in, and false past [kEmojiOnlyMaxCount] glyphs.
bool isEmojiOnlyText(String text) => emojiOnlyCount(text) != null;

/// How many emoji [text] is made of, or `null` when it is not emoji-only
/// (or holds more than [kEmojiOnlyMaxCount]).
///
/// Counted in grapheme clusters, so a family sequence glued with zero-width
/// joiners, a skin-toned hand and a flag each count as the one glyph the
/// reader sees.
int? emojiOnlyCount(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;

  var count = 0;
  for (final cluster in trimmed.characters) {
    if (_isBlank(cluster)) continue;
    if (!_isEmojiCluster(cluster)) return null;
    count++;
    if (count > kEmojiOnlyMaxCount) return null;
  }
  return count == 0 ? null : count;
}

bool _isBlank(String cluster) => cluster.trim().isEmpty;

/// Zero-width joiner, the two presentation selectors, the five skin-tone
/// modifiers and the tag characters that spell out subdivision flags:
/// scaffolding of a sequence, never a glyph of their own.
bool _isSequenceGlue(int rune) =>
    rune == 0x200D ||
    rune == 0xFE0E ||
    rune == 0xFE0F ||
    (rune >= 0x1F3FB && rune <= 0x1F3FF) ||
    (rune >= 0xE0020 && rune <= 0xE007F);

/// Code points that are emoji all by themselves — the pictographic planes
/// plus the handful of older symbols Unicode gives `Emoji_Presentation=Yes`
/// (`✅`, `⌚`, `⭐`, `❗`…), which are drawn as coloured glyphs with no
/// selector asking them to.
bool _isEmojiByDefault(int rune) =>
    (rune >= 0x1F000 && rune <= 0x1FAFF) ||
    (rune >= 0x231A && rune <= 0x231B) ||
    (rune >= 0x23E9 && rune <= 0x23EC) ||
    rune == 0x23F0 ||
    rune == 0x23F3 ||
    (rune >= 0x25FD && rune <= 0x25FE) ||
    (rune >= 0x2614 && rune <= 0x2615) ||
    (rune >= 0x2648 && rune <= 0x2653) ||
    rune == 0x267F ||
    rune == 0x2693 ||
    rune == 0x26A1 ||
    (rune >= 0x26AA && rune <= 0x26AB) ||
    (rune >= 0x26BD && rune <= 0x26BE) ||
    (rune >= 0x26C4 && rune <= 0x26C5) ||
    rune == 0x26CE ||
    rune == 0x26D4 ||
    rune == 0x26EA ||
    (rune >= 0x26F2 && rune <= 0x26F3) ||
    rune == 0x26F5 ||
    rune == 0x26FA ||
    rune == 0x26FD ||
    rune == 0x2705 ||
    (rune >= 0x270A && rune <= 0x270B) ||
    rune == 0x2728 ||
    rune == 0x274C ||
    rune == 0x274E ||
    (rune >= 0x2753 && rune <= 0x2755) ||
    rune == 0x2757 ||
    (rune >= 0x2795 && rune <= 0x2797) ||
    rune == 0x27B0 ||
    rune == 0x27BF ||
    (rune >= 0x2B1B && rune <= 0x2B1C) ||
    rune == 0x2B50 ||
    rune == 0x2B55;

/// Code points that *can* be emoji but are text by default: `❤`, `☺`, `✓`,
/// the arrows, the dingbats. Unicode only paints them as emoji when a
/// variation selector says so, and so do we — otherwise a lone `✓` or a `→`
/// in an ordinary sentence would blow up to 34pt.
bool _isEmojiWithSelector(int rune) =>
    (rune >= 0x231A && rune <= 0x231B) ||
    (rune >= 0x23E9 && rune <= 0x23F3) ||
    (rune >= 0x23F8 && rune <= 0x23FA) ||
    rune == 0x24C2 ||
    (rune >= 0x25AA && rune <= 0x25AB) ||
    rune == 0x25B6 ||
    rune == 0x25C0 ||
    (rune >= 0x25FB && rune <= 0x25FE) ||
    (rune >= 0x2600 && rune <= 0x27BF) ||
    (rune >= 0x2934 && rune <= 0x2935) ||
    (rune >= 0x2B00 && rune <= 0x2BFF) ||
    rune == 0x3030 ||
    rune == 0x303D ||
    rune == 0x3297 ||
    rune == 0x3299;

bool _isEmojiCluster(String cluster) {
  final runes = cluster.runes.toList();
  final hasEmojiSelector = runes.contains(0xFE0F);
  // `1️⃣`, `#️⃣`, `*️⃣`: an ASCII base plus U+20E3. The base is a plain
  // digit or symbol, so the keycap mark is the only thing that makes the
  // cluster an emoji — and without it a bare `1` or `#` must stay small.
  final isKeycap = runes.contains(0x20E3);

  var meaningful = 0;
  for (final rune in runes) {
    if (_isSequenceGlue(rune)) continue;
    if (rune == 0x20E3) continue;
    meaningful++;
    if (_isEmojiByDefault(rune)) continue;
    if (isKeycap && _isKeycapBase(rune)) continue;
    if (hasEmojiSelector && _isEmojiWithSelector(rune)) continue;
    return false;
  }
  return meaningful > 0;
}

bool _isKeycapBase(int rune) =>
    (rune >= 0x30 && rune <= 0x39) || rune == 0x23 || rune == 0x2A;
