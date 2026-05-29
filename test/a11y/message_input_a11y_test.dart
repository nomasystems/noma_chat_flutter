import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

import '../_helpers/fixtures.dart';

void main() {
  late ChatController controller;

  setUp(() {
    controller = ChatController(
      initialMessages: const [],
      currentUser: fixtureUserMe,
    );
  });

  tearDown(() => controller.dispose());

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('MessageInput a11y', () {
    testWidgets('attach button exposes Gallery semantic label', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageInput(controller: controller, onSendMessageRequest: (_) {}),
        ),
      );
      expect(find.bySemanticsLabel('Gallery'), findsOneWidget);
    });

    testWidgets('attach button tap target is at least 48dp', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageInput(controller: controller, onSendMessageRequest: (_) {}),
        ),
      );
      final size = tester.getSize(find.bySemanticsLabel('Gallery'));
      expect(size.width, greaterThanOrEqualTo(48.0));
      expect(size.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('camera button exposes Camera semantic label and is 48dp', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageInput(
            controller: controller,
            onSendMessageRequest: (_) {},
            onPickCamera: () {},
          ),
        ),
      );

      expect(find.bySemanticsLabel('Camera'), findsOneWidget);
      final size = tester.getSize(find.bySemanticsLabel('Camera'));
      expect(size.width, greaterThanOrEqualTo(48.0));
      expect(size.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('send button exposes Send semantic label once text is typed', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageInput(controller: controller, onSendMessageRequest: (_) {}),
        ),
      );
      await tester.enterText(find.byType(TextField), 'hola');
      await tester.pump();

      expect(find.bySemanticsLabel('Send'), findsOneWidget);
    });

    testWidgets('send button tap target is at least 48dp', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageInput(controller: controller, onSendMessageRequest: (_) {}),
        ),
      );
      await tester.enterText(find.byType(TextField), 'hola');
      await tester.pump();

      final size = tester.getSize(find.bySemanticsLabel('Send'));
      expect(size.width, greaterThanOrEqualTo(48.0));
      expect(size.height, greaterThanOrEqualTo(48.0));
    });
  });
}
