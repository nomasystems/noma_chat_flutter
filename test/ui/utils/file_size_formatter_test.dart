import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/ui/utils/file_size_formatter.dart';

void main() {
  group('formatFileSize — raw byte counts, as the uploader writes them', () {
    // `messages_controller` stores `bytes.length.toString()`, so these are
    // the exact strings a bubble receives.
    test('keeps small counts in bytes', () {
      expect(formatFileSize('387'), '387 B');
      expect(formatFileSize('4'), '4 B');
      expect(formatFileSize('0'), '0 B');
      expect(formatFileSize('999'), '999 B');
    });

    test('scales to KB from a thousand bytes up', () {
      expect(formatFileSize('1000'), '1.0 KB');
      expect(formatFileSize('243000'), '243.0 KB');
    });

    test('scales to MB and GB', () {
      expect(formatFileSize('1500000'), '1.5 MB');
      expect(formatFileSize('2400000'), '2.4 MB');
      expect(formatFileSize('3221225472'), '3.2 GB');
    });

    test('promotes to the next unit when rounding reaches a thousand', () {
      expect(formatFileSize('999999'), '1.0 MB');
    });
  });

  group('formatFileSize — locale decimal separator', () {
    test('uses a comma for the comma-decimal locales the SDK ships', () {
      expect(formatFileSize('1500000', localeCode: 'es'), '1,5 MB');
      expect(formatFileSize('1500000', localeCode: 'de'), '1,5 MB');
      expect(formatFileSize('1500000', localeCode: 'pt_BR'), '1,5 MB');
    });

    test('uses a dot for English and for unknown codes', () {
      expect(formatFileSize('1500000', localeCode: 'en'), '1.5 MB');
      expect(formatFileSize('1500000', localeCode: 'en-GB'), '1.5 MB');
      expect(formatFileSize('1500000', localeCode: 'zz'), '1.5 MB');
      expect(formatFileSize('1500000', localeCode: ''), '1.5 MB');
    });

    test('never appends a separator to a byte count', () {
      expect(formatFileSize('387', localeCode: 'es'), '387 B');
    });
  });

  group('formatFileSize — values the SDK did not produce', () {
    test('returns already formatted text verbatim', () {
      expect(formatFileSize('2.4 MB'), '2.4 MB');
      expect(formatFileSize('128 KB'), '128 KB');
      expect(formatFileSize('unknown'), 'unknown');
      expect(formatFileSize(''), '');
    });

    test('returns negative counts verbatim', () {
      expect(formatFileSize('-5'), '-5');
    });

    test('tolerates surrounding whitespace on a byte count', () {
      expect(formatFileSize(' 387 '), '387 B');
    });
  });
}
