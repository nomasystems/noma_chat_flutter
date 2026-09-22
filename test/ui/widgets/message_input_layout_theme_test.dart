import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/ui/widgets/_recording_indicators.dart'
    show ActiveRecordingRow;

class _MockVoiceRecordingController extends Mock
    implements VoiceRecordingController {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const user = ChatUser(id: 'u1', displayName: 'Alice');
  late ChatController chat;

  setUp(() {
    chat = ChatController(initialMessages: [], currentUser: user);
  });

  tearDown(() => chat.dispose());

  Widget wrap(ChatTheme theme, {double textScale = 1.0}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 375,
            child: MessageInput(
              controller: chat,
              onSendMessageRequest: (_) => true,
              onVoiceMessageReady: (_) {},
              onPickCamera: () {},
              theme: theme,
            ),
          ),
        ),
      ),
    ),
  );

  /// The spacing WB ships: every gap halved from the SDK defaults.
  final tightTheme = ChatTheme.defaults.copyWith(
    input: ChatTheme.defaults.input.copyWith(
      rowPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      iconGap: 8,
      secondaryIconGap: 8,
      fieldContentPadding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 8,
      ),
      voiceButtonInset: 8,
    ),
  );

  Finder composerRow() => find
      .ancestor(
        of: find.byKey(const ValueKey('chat_message_input')),
        matching: find.byType(Row),
      )
      .first;

  /// Widths of the gaps the composer row puts between its children. The
  /// mic slot is a sized box too, so height tells the two apart: the gaps
  /// only ever constrain the horizontal axis.
  List<double?> gapsOf(WidgetTester tester) => tester
      .widget<Row>(composerRow())
      .children
      .whereType<SizedBox>()
      .where((box) => box.height == null)
      .map((box) => box.width)
      .toList();

  EdgeInsetsGeometry? rowPaddingOf(WidgetTester tester) => tester
      .widget<Padding>(
        find.ancestor(of: composerRow(), matching: find.byType(Padding)).first,
      )
      .padding;

  EdgeInsetsGeometry? fieldPaddingOf(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const ValueKey('chat_message_input')))
      .decoration!
      .contentPadding;

  /// The painted mic circle, the only `Container` the button builds inside
  /// its (wider) touch target.
  Finder micCircle() => find
      .descendant(
        of: find.byType(VoiceRecorderButton),
        matching: find.byType(Container),
      )
      .first;

  EdgeInsetsGeometry? voiceInsetOf(WidgetTester tester) => tester
      .widget<Padding>(
        find
            .ancestor(
              of: find.byType(VoiceRecorderButton),
              matching: find.byType(Padding),
            )
            .first,
      )
      .padding;

  group('MessageInput layout theme', () {
    testWidgets('an untouched theme keeps the spacing the composer had', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(ChatTheme.defaults));

      expect(
        rowPaddingOf(tester),
        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      );
      expect(gapsOf(tester), [16.0, 16.0, 12.0]);
      expect(
        fieldPaddingOf(tester),
        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      );
      // The themed inset is 16; the button carries it minus the bleed its
      // touch target adds on each side, so the circle still lands on 16.
      expect(
        voiceInsetOf(tester),
        const EdgeInsetsDirectional.only(
          end: 16 - VoiceRecorderButton.tapBleed,
        ),
      );
    });

    testWidgets('the theme drives every horizontal gap of the composer', (
      tester,
    ) async {
      final theme = ChatTheme.defaults.copyWith(
        input: ChatTheme.defaults.input.copyWith(
          rowPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          iconGap: 8,
          secondaryIconGap: 8,
          fieldContentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
          voiceButtonInset: 8,
        ),
      );

      await tester.pumpWidget(wrap(theme));

      expect(
        rowPaddingOf(tester),
        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      );
      expect(gapsOf(tester), [8.0, 8.0, 8.0]);
      expect(
        fieldPaddingOf(tester),
        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      );
      expect(
        voiceInsetOf(tester),
        const EdgeInsetsDirectional.only(end: 8 - VoiceRecorderButton.tapBleed),
      );
    });

    testWidgets('the mic circle stays on the slot the row reserves for it, '
        'even though its touch target is wider', (tester) async {
      await tester.pumpWidget(wrap(tightTheme));

      final composer = tester.getRect(find.byType(MessageInput));
      final circle = tester.getRect(micCircle());

      expect(circle.right, moreOrLessEquals(composer.right - 8, epsilon: 0.5));
      expect(circle.width, VoiceRecorderButton.diameter);
    });

    for (final scale in const [1.18, 1.18 * 1.7]) {
      testWidgets('every composer button clears the 44pt minimum touch '
          'target on a 375pt screen (text scale $scale)', (tester) async {
        await tester.pumpWidget(wrap(tightTheme, textScale: scale));

        for (final id in const [
          'chat_attach_button',
          'chat_camera_button',
          'chat_voice_button',
        ]) {
          final size = tester.getSize(find.byKey(ValueKey(id)));
          expect(size.width, greaterThanOrEqualTo(44), reason: id);
          expect(size.height, greaterThanOrEqualTo(44), reason: id);
        }
      });

      testWidgets('the send button clears it too once there is text to send '
          '(text scale $scale)', (tester) async {
        await tester.pumpWidget(wrap(tightTheme, textScale: scale));
        await tester.enterText(
          find.byKey(const ValueKey('chat_message_input')),
          'hi',
        );
        await tester.pump();

        final size = tester.getSize(
          find.byKey(const ValueKey('chat_send_button')),
        );
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      });
    }

    testWidgets('the mic touch target never overlaps the camera one', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(tightTheme));

      final camera = tester.getRect(
        find.byKey(const ValueKey('chat_camera_button')),
      );
      final mic = tester.getRect(find.byType(VoiceRecorderButton));

      expect(mic.left, greaterThanOrEqualTo(camera.right));
    });
  });

  group('recording row layout theme', () {
    Widget wrapRecordingRow(ChatTheme theme) => MaterialApp(
      home: Scaffold(
        body: ActiveRecordingRow(
          controller: _MockVoiceRecordingController(),
          theme: theme,
          voiceButtonSlot: const SizedBox(width: 40, height: 40),
        ),
      ),
    );

    EdgeInsetsGeometry? rowInsetOf(WidgetTester tester) => tester
        .widget<Padding>(
          find
              .descendant(
                of: find.byType(ActiveRecordingRow),
                matching: find.byType(Padding),
              )
              .first,
        )
        .padding;

    testWidgets('an untouched theme keeps the inset the row had', (
      tester,
    ) async {
      await tester.pumpWidget(wrapRecordingRow(ChatTheme.defaults));

      expect(
        rowInsetOf(tester),
        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      );
    });

    testWidgets('the recording row takes the same inset as the idle row, so '
        'the mic slot does not shift when capture starts', (tester) async {
      const tight = EdgeInsets.symmetric(horizontal: 8, vertical: 8);
      final theme = ChatTheme.defaults.copyWith(
        input: ChatTheme.defaults.input.copyWith(rowPadding: tight),
      );

      await tester.pumpWidget(wrapRecordingRow(theme));

      expect(rowInsetOf(tester), tight);
    });
  });
}
