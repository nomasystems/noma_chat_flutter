import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  // A timestamp on the current day renders as a stable "04:05" instead of a
  // date whose formatting depends on the year the suite runs in.
  final today = DateTime.now();
  final message = ChatMessage(
    id: 'msg1',
    from: 'u1',
    timestamp: DateTime(today.year, today.month, today.day, 4, 5),
    text: 'The quick brown fox',
  );

  MessageSearchController hitController() => MessageSearchController(
    searchFn: (q, r, {pagination}) async =>
        ChatSuccess(ChatPaginatedResponse(items: [message], hasMore: false)),
  );

  MessageSearchController emptyController() => MessageSearchController(
    searchFn: (q, r, {pagination}) async =>
        const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false)),
  );

  TextStyle? spanStyle(WidgetTester tester, String text) {
    TextStyle? found;
    void visit(InlineSpan span) {
      if (span is TextSpan) {
        if (span.text == text) found ??= span.style;
        span.children?.forEach(visit);
      }
    }

    for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
      visit(rt.text);
    }
    return found;
  }

  group('MessageSearchView theming — query field', () {
    testWidgets('applies text, hint, fill, cursor, border and icon slots', (
      tester,
    ) async {
      final controller = emptyController();
      const theme = ChatTheme(
        messageSearchFieldTextStyle: TextStyle(fontSize: 21),
        messageSearchFieldHintStyle: TextStyle(fontSize: 19),
        messageSearchFieldFillColor: Color(0xFF010203),
        messageSearchFieldCursorColor: Color(0xFF040506),
        messageSearchFieldBorderColor: Color(0xFF070809),
        messageSearchFieldBorderRadius: BorderRadius.all(Radius.circular(18)),
        messageSearchFieldIconColor: Color(0xFF0A0B0C),
      );

      await tester.pumpWidget(
        wrap(
          MessageSearchView(
            controller: controller,
            roomId: 'room1',
            theme: theme,
          ),
        ),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.style?.fontSize, 21);
      expect(field.cursorColor, const Color(0xFF040506));

      final decoration = field.decoration!;
      expect(decoration.hintStyle?.fontSize, 19);
      expect(decoration.filled, isTrue);
      expect(decoration.fillColor, const Color(0xFF010203));

      final border = decoration.enabledBorder! as OutlineInputBorder;
      expect(border.borderSide.color, const Color(0xFF070809));
      expect(border.borderSide.width, 1);
      expect(border.borderRadius, BorderRadius.circular(18));

      // The focus ring is not just the enabled border repainted: it widens
      // and tints towards the field's cursor colour (the preset's accent)
      // so a focused query field is still visibly distinct from an idle one.
      final focused = decoration.focusedBorder! as OutlineInputBorder;
      expect(focused.borderSide.color, const Color(0xFF040506));
      expect(focused.borderSide.width, 2);
      expect(focused.borderRadius, BorderRadius.circular(18));

      final searchIcon = tester.widget<Icon>(find.byIcon(Icons.search));
      expect(searchIcon.color, const Color(0xFF0A0B0C));

      controller.dispose();
    });

    testWidgets('tints the clear button with the field icon slot', (
      tester,
    ) async {
      final controller = emptyController();
      const theme = ChatTheme(messageSearchFieldIconColor: Color(0xFF0A0B0C));

      await tester.pumpWidget(
        wrap(
          MessageSearchView(
            controller: controller,
            roomId: 'room1',
            theme: theme,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'fox');
      await tester.pump();

      final clearIcon = tester.widget<Icon>(find.byIcon(Icons.close));
      expect(clearIcon.color, const Color(0xFF0A0B0C));

      controller.dispose();
    });

    testWidgets('leaves the field to Material defaults when unthemed', (
      tester,
    ) async {
      final controller = emptyController();

      await tester.pumpWidget(
        wrap(MessageSearchView(controller: controller, roomId: 'room1')),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.style, isNull);
      expect(field.cursorColor, isNull);

      final decoration = field.decoration!;
      expect(decoration.hintStyle, isNull);
      expect(
        decoration.filled,
        isNull,
        reason: 'an explicit false would override an ambient filled: true',
      );
      expect(decoration.fillColor, isNull);
      expect(decoration.enabledBorder, isNull);
      expect(decoration.focusedBorder, isNull);
      expect(decoration.border, isA<OutlineInputBorder>());
      expect(tester.widget<Icon>(find.byIcon(Icons.search)).color, isNull);

      controller.dispose();
    });

    testWidgets(
      'a radius on its own shapes the field without painting a border the '
      'host never asked for',
      (tester) async {
        final controller = emptyController();
        const theme = ChatTheme(
          messageSearchFieldBorderRadius: BorderRadius.all(Radius.circular(9)),
        );

        await tester.pumpWidget(
          wrap(
            MessageSearchView(
              controller: controller,
              roomId: 'room1',
              theme: theme,
            ),
          ),
        );

        final decoration = tester
            .widget<TextField>(find.byType(TextField))
            .decoration!;
        expect(
          decoration.enabledBorder,
          isNull,
          reason:
              'InputDecorator takes this slot verbatim — filling it in '
              'with a default BorderSide paints a black outline',
        );
        expect(decoration.focusedBorder, isNull);
        final border = decoration.border! as OutlineInputBorder;
        expect(border.borderRadius, BorderRadius.circular(9));
        expect(
          border.borderSide,
          const BorderSide(),
          reason:
              'the default side is the sentinel Material recolours from '
              'the ambient theme',
        );

        controller.dispose();
      },
    );

    testWidgets('a radius on its own rides on the border the host\'s own '
        'InputDecorationTheme draws, keeping its colour', (tester) async {
      final controller = emptyController();
      const theme = ChatTheme(
        messageSearchFieldBorderRadius: BorderRadius.all(Radius.circular(9)),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            inputDecorationTheme: const InputDecorationTheme(
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF00AA00), width: 3),
              ),
            ),
          ),
          home: Scaffold(
            body: MessageSearchView(
              controller: controller,
              roomId: 'room1',
              theme: theme,
            ),
          ),
        ),
      );

      final border =
          tester
                  .widget<TextField>(find.byType(TextField))
                  .decoration!
                  .enabledBorder!
              as OutlineInputBorder;
      expect(border.borderSide.color, const Color(0xFF00AA00));
      expect(border.borderSide.width, 3);
      expect(border.borderRadius, BorderRadius.circular(9));

      controller.dispose();
    });

    testWidgets('a radius on its own rides on the base border the host\'s own '
        'InputDecorationTheme draws, keeping its colour', (tester) async {
      final controller = emptyController();
      const theme = ChatTheme(
        messageSearchFieldBorderRadius: BorderRadius.all(Radius.circular(9)),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            inputDecorationTheme: const InputDecorationTheme(
              border: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF0000AA), width: 2),
              ),
            ),
          ),
          home: Scaffold(
            body: MessageSearchView(
              controller: controller,
              roomId: 'room1',
              theme: theme,
            ),
          ),
        ),
      );

      final decoration = tester
          .widget<TextField>(find.byType(TextField))
          .decoration!;
      // Only the base `border` slot was themed on the ambient side, so
      // enabled/focused stay unset and fall through to it, same as
      // `InputDecorator` would resolve them.
      expect(decoration.enabledBorder, isNull);
      expect(decoration.focusedBorder, isNull);
      final border = decoration.border! as OutlineInputBorder;
      expect(border.borderSide.color, const Color(0xFF0000AA));
      expect(border.borderSide.width, 2);
      expect(border.borderRadius, BorderRadius.circular(9));

      controller.dispose();
    });

    testWidgets('the focus ring widens on its own when the theme has no cursor '
        'colour to tint towards', (tester) async {
      final controller = emptyController();
      const theme = ChatTheme(messageSearchFieldBorderColor: Color(0xFF334455));

      await tester.pumpWidget(
        wrap(
          MessageSearchView(
            controller: controller,
            roomId: 'room1',
            theme: theme,
          ),
        ),
      );

      final decoration = tester
          .widget<TextField>(find.byType(TextField))
          .decoration!;
      final enabled = decoration.enabledBorder! as OutlineInputBorder;
      final focused = decoration.focusedBorder! as OutlineInputBorder;
      expect(enabled.borderSide.color, const Color(0xFF334455));
      expect(enabled.borderSide.width, 1);
      expect(focused.borderSide.color, const Color(0xFF334455));
      expect(focused.borderSide.width, 2);
      expect(
        focused.borderSide,
        isNot(enabled.borderSide),
        reason: 'a themed border colour must not read as focused == enabled',
      );

      controller.dispose();
    });

    testWidgets('an explicit ambient focusedBorder wins over the derived focus '
        'treatment even when the theme also colours the border', (
      tester,
    ) async {
      final controller = emptyController();
      const theme = ChatTheme(
        messageSearchFieldBorderColor: Color(0xFF334455),
        messageSearchFieldCursorColor: Color(0xFF00FF00),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            inputDecorationTheme: const InputDecorationTheme(
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFAA00AA), width: 5),
              ),
            ),
          ),
          home: Scaffold(
            body: MessageSearchView(
              controller: controller,
              roomId: 'room1',
              theme: theme,
            ),
          ),
        ),
      );

      final decoration = tester
          .widget<TextField>(find.byType(TextField))
          .decoration!;
      final focused = decoration.focusedBorder! as OutlineInputBorder;
      expect(focused.borderSide.color, const Color(0xFFAA00AA));
      expect(focused.borderSide.width, 5);

      // The enabled state is untouched by the host's focused-only
      // override and still gets the theme's own colour.
      final enabled = decoration.enabledBorder! as OutlineInputBorder;
      expect(enabled.borderSide.color, const Color(0xFF334455));
      expect(enabled.borderSide.width, 1);

      controller.dispose();
    });

    testWidgets(
      'the light preset gives the query field a visibly distinct focus ring',
      (tester) async {
        final controller = emptyController();

        await tester.pumpWidget(
          wrap(
            MessageSearchView(
              controller: controller,
              roomId: 'room1',
              theme: ChatTheme.lightPreset(),
            ),
          ),
        );

        final decoration = tester
            .widget<TextField>(find.byType(TextField))
            .decoration!;
        final enabled = decoration.enabledBorder! as OutlineInputBorder;
        final focused = decoration.focusedBorder! as OutlineInputBorder;
        expect(
          focused.borderSide,
          isNot(enabled.borderSide),
          reason:
              'wiring messageSearchFieldBorderColor into the preset '
              'must not erase the focus indicator',
        );

        controller.dispose();
      },
    );

    testWidgets(
      'an ambient filled InputDecorationTheme survives an unthemed fill slot',
      (tester) async {
        final controller = emptyController();

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              inputDecorationTheme: const InputDecorationTheme(
                filled: true,
                fillColor: Color(0xFFEEEEFF),
              ),
            ),
            home: Scaffold(
              body: MessageSearchView(controller: controller, roomId: 'room1'),
            ),
          ),
        );

        // What the field is actually decorated with, ambient defaults and
        // all — the merge `TextField` does before handing it to Material.
        final effective = tester
            .widget<InputDecorator>(find.byType(InputDecorator))
            .decoration;
        expect(effective.filled, isTrue);
        expect(effective.fillColor, const Color(0xFFEEEEFF));

        controller.dispose();
      },
    );
  });

  group('MessageSearchView theming — surface', () {
    testWidgets('paints the themed background behind the whole view', (
      tester,
    ) async {
      final controller = emptyController();
      const theme = ChatTheme(messageSearchBackgroundColor: Color(0xFFFDFEFF));

      await tester.pumpWidget(
        wrap(
          MessageSearchView(
            controller: controller,
            roomId: 'room1',
            theme: theme,
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == const Color(0xFFFDFEFF),
        ),
        findsOneWidget,
      );

      controller.dispose();
    });

    testWidgets('adds no surface of its own when the slot is unset', (
      tester,
    ) async {
      final controller = emptyController();

      await tester.pumpWidget(
        wrap(MessageSearchView(controller: controller, roomId: 'room1')),
      );

      expect(
        find.descendant(
          of: find.byType(MessageSearchView),
          matching: find.byType(ColoredBox),
        ),
        findsNothing,
      );

      controller.dispose();
    });
  });

  group('MessageSearchView theming — results', () {
    testWidgets('applies title, snippet, highlight and timestamp slots', (
      tester,
    ) async {
      final controller = hitController();
      const theme = ChatTheme(
        messageSearchResultTitleStyle: TextStyle(fontSize: 22),
        messageSearchResultSnippetStyle: TextStyle(
          fontSize: 15,
          color: Color(0xFF112233),
        ),
        messageSearchResultHighlightStyle: TextStyle(
          fontSize: 15,
          color: Color(0xFF445566),
          fontWeight: FontWeight.w900,
        ),
        messageSearchResultTimestampStyle: TextStyle(fontSize: 9),
      );

      await tester.pumpWidget(
        wrap(
          MessageSearchView(
            controller: controller,
            roomId: 'room1',
            theme: theme,
            senderNameResolver: (id) => 'Alice',
          ),
        ),
      );

      await controller.search('quick', 'room1');
      await tester.pump();

      expect(tester.widget<Text>(find.text('Alice')).style?.fontSize, 22);
      expect(spanStyle(tester, 'The ')?.color, const Color(0xFF112233));
      expect(spanStyle(tester, 'quick')?.color, const Color(0xFF445566));
      expect(spanStyle(tester, 'quick')?.fontWeight, FontWeight.w900);

      final trailing = tester.widget<Text>(find.text('04:05'));
      expect(trailing.style?.fontSize, 9);

      controller.dispose();
    });

    testWidgets('derives the highlight from a themed snippet when unset', (
      tester,
    ) async {
      final controller = hitController();
      const theme = ChatTheme(
        messageSearchResultSnippetStyle: TextStyle(
          fontSize: 15,
          color: Color(0xFF112233),
        ),
      );

      await tester.pumpWidget(
        wrap(
          MessageSearchView(
            controller: controller,
            roomId: 'room1',
            theme: theme,
          ),
        ),
      );

      await controller.search('quick', 'room1');
      await tester.pump();

      final highlight = spanStyle(tester, 'quick');
      expect(highlight?.color, const Color(0xFF112233));
      expect(highlight?.fontSize, 15);
      expect(highlight?.fontWeight, FontWeight.w700);

      controller.dispose();
    });

    testWidgets('keeps the legacy result styles when unthemed', (tester) async {
      final controller = hitController();

      await tester.pumpWidget(
        wrap(
          MessageSearchView(
            controller: controller,
            roomId: 'room1',
            senderNameResolver: (id) => 'Alice',
          ),
        ),
      );

      await controller.search('quick', 'room1');
      await tester.pump();

      final title = tester.widget<Text>(find.text('Alice')).style!;
      expect(title.fontSize, 14);
      expect(title.fontWeight, FontWeight.w600);
      expect(spanStyle(tester, 'The ')?.color, const Color(0xFF757575));
      expect(spanStyle(tester, 'quick')?.color, const Color(0xFF212121));
      expect(spanStyle(tester, 'quick')?.fontWeight, FontWeight.w700);
      expect(
        tester.widget<Text>(find.text('04:05')).style?.color,
        const Color(0xFF9E9E9E),
      );

      controller.dispose();
    });
  });

  group('MessageSearchView theming — empty and loading states', () {
    testWidgets('empty copy prefers its own slot over emptyStateTitleStyle', (
      tester,
    ) async {
      final controller = emptyController();
      const theme = ChatTheme(
        emptyStateTitleStyle: TextStyle(fontSize: 30),
        messageSearchEmptyTextStyle: TextStyle(fontSize: 17),
      );

      await tester.pumpWidget(
        wrap(
          MessageSearchView(
            controller: controller,
            roomId: 'room1',
            theme: theme,
          ),
        ),
      );

      await controller.search('nothing', 'room1');
      await tester.pump();

      expect(tester.widget<Text>(find.text('No results')).style?.fontSize, 17);
      controller.dispose();
    });

    testWidgets('empty copy falls back to emptyStateTitleStyle then baseline', (
      tester,
    ) async {
      final shared = emptyController();
      const theme = ChatTheme(emptyStateTitleStyle: TextStyle(fontSize: 30));

      await tester.pumpWidget(
        wrap(
          MessageSearchView(controller: shared, roomId: 'room1', theme: theme),
        ),
      );
      await shared.search('nothing', 'room1');
      await tester.pump();
      expect(tester.widget<Text>(find.text('No results')).style?.fontSize, 30);
      shared.dispose();

      final bare = emptyController();
      await tester.pumpWidget(
        wrap(MessageSearchView(controller: bare, roomId: 'room1')),
      );
      await bare.search('nothing', 'room1');
      await tester.pump();
      final style = tester.widget<Text>(find.text('No results')).style!;
      expect(style.fontSize, 16);
      expect(style.color, const Color(0xFF9E9E9E));
      bare.dispose();
    });

    testWidgets('spinner prefers its slot and falls back to the send button', (
      tester,
    ) async {
      final pending =
          Completer<ChatResult<ChatPaginatedResponse<ChatMessage>>>();
      final controller = MessageSearchController(
        searchFn: (q, r, {pagination}) => pending.future,
      );
      const theme = ChatTheme(
        input: ChatInputTheme(sendButtonColor: Color(0xFF00FF00)),
        messageSearchProgressColor: Color(0xFFFF0000),
      );

      await tester.pumpWidget(
        wrap(
          MessageSearchView(
            controller: controller,
            roomId: 'room1',
            theme: theme,
          ),
        ),
      );

      unawaited(controller.search('quick', 'room1'));
      await tester.pump();

      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .color,
        const Color(0xFFFF0000),
      );

      await tester.pumpWidget(
        wrap(
          MessageSearchView(
            controller: controller,
            roomId: 'room1',
            theme: const ChatTheme(
              input: ChatInputTheme(sendButtonColor: Color(0xFF00FF00)),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .color,
        const Color(0xFF00FF00),
      );

      pending.complete(
        const ChatSuccess(ChatPaginatedResponse(items: [], hasMore: false)),
      );
      await tester.pumpAndSettle();
      controller.dispose();
    });
  });
}
