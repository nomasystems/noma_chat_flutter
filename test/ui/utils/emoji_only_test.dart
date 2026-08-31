import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/ui/utils/emoji_only.dart';

void main() {
  group('what counts as an emoji-only message', () {
    test('a single emoji does', () {
      expect(isEmojiOnlyText('🍺'), isTrue);
      expect(emojiOnlyCount('🍺'), 1);
    });

    test('so do three, spaced or not', () {
      expect(emojiOnlyCount('😀😀😀'), 3);
      expect(emojiOnlyCount('😀 😀 😀'), 3);
      expect(emojiOnlyCount('  🍺  '), 1);
    });

    test('four do not — that is a wall, not a gesture', () {
      expect(isEmojiOnlyText('😀😀😀😀'), isFalse);
      expect(emojiOnlyCount('😀😀😀😀'), isNull);
    });

    test('a sequence glued with joiners counts as the one glyph it draws', () {
      expect(emojiOnlyCount('👨‍👩‍👧‍👦'), 1);
      expect(emojiOnlyCount('👨‍👩‍👧‍👦👨‍👩‍👧‍👦'), 2);
    });

    test('a skin tone modifier does not make it two', () {
      expect(emojiOnlyCount('👍🏽'), 1);
    });

    test('a flag is one glyph, not two letters', () {
      expect(emojiOnlyCount('🇪🇸'), 1);
      expect(emojiOnlyCount('🇪🇸🇮🇹'), 2);
    });

    test('an emoji with any text at all does not', () {
      expect(isEmojiOnlyText('🍺!'), isFalse);
      expect(isEmojiOnlyText('vale 🍺'), isFalse);
      expect(isEmojiOnlyText('🍺?'), isFalse);
    });

    test('nothing, or only blanks, does not', () {
      expect(isEmojiOnlyText(''), isFalse);
      expect(isEmojiOnlyText('   '), isFalse);
      expect(isEmojiOnlyText('\n'), isFalse);
    });
  });

  group('the false positives the review warned about', () {
    test('a bare digit or hash is text, a keycap is an emoji', () {
      expect(isEmojiOnlyText('1'), isFalse);
      expect(isEmojiOnlyText('#'), isFalse);
      expect(isEmojiOnlyText('*'), isFalse);
      expect(isEmojiOnlyText('1️⃣'), isTrue);
      expect(isEmojiOnlyText('#️⃣'), isTrue);
    });

    test('a text-presentation dingbat stays text', () {
      // `✓` and `→` have no emoji presentation of their own; blowing them
      // up to 34pt inside a sentence-less message would be wrong.
      expect(isEmojiOnlyText('✓'), isFalse);
      expect(isEmojiOnlyText('→'), isFalse);
      expect(isEmojiOnlyText('❤'), isFalse);
    });

    test('the same characters with the emoji selector are emoji', () {
      expect(isEmojiOnlyText('❤️'), isTrue);
      expect(isEmojiOnlyText('☺️'), isTrue);
      expect(isEmojiOnlyText('✅'), isTrue);
    });

    test('digits, prices and ordinary punctuation are never emoji-only', () {
      expect(isEmojiOnlyText('20:00'), isFalse);
      expect(isEmojiOnlyText('1.234,56'), isFalse);
      expect(isEmojiOnlyText('...'), isFalse);
      expect(isEmojiOnlyText('ok'), isFalse);
    });
  });
}
