import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// Names of the tappable rows that are not buttons: a contact suggestion
/// chip, and the three bubbles whose whole surface is the tap target.
///
/// The three bubbles publish both halves only when they are handed the id of
/// the message they render; without it they publish neither, rather than a
/// name every row of the list would answer to.
void main() {
  late SemanticsHandle handle;

  setUp(() => handle = WidgetsBinding.instance.ensureSemantics());
  tearDown(() => handle.dispose());

  SemanticsFinder identifier(String name) => find.semantics.byPredicate(
    (node) => node.identifier == name,
    describeMatch: (_) => 'semantics node with identifier "$name"',
  );

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Future<void> expectBothHalves(WidgetTester tester, String name) async {
    expect(find.byKey(ValueKey(name)), findsOneWidget);
    expect(identifier(name), findsOne);
  }

  testWidgets('a contact suggestion chip is named after the contact', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ContactSuggestionsBar(
          contacts: const [
            SuggestedContact(id: 'u-1', displayName: 'Julio'),
            SuggestedContact(id: 'u-2', displayName: 'Julio'),
          ],
          onTap: (_) {},
        ),
      ),
    );

    await expectBothHalves(tester, contactSuggestionSemanticsId('u-1'));
    await expectBothHalves(tester, contactSuggestionSemanticsId('u-2'));
  });

  testWidgets('a video bubble is named after its message', (tester) async {
    await tester.pumpWidget(
      wrap(
        VideoBubble(
          videoUrl: 'https://example.com/clip.mp4',
          messageId: 'm-1',
          onTap: () {},
        ),
      ),
    );

    await expectBothHalves(tester, videoBubbleSemanticsId('m-1'));
  });

  testWidgets('a file bubble is named after its message', (tester) async {
    await tester.pumpWidget(
      wrap(
        FileBubble(
          fileName: 'contract.pdf',
          mimeType: 'application/pdf',
          messageId: 'm-2',
          onTap: () {},
        ),
      ),
    );

    await expectBothHalves(tester, fileBubbleSemanticsId('m-2'));
  });

  testWidgets('a location bubble is named after its message', (tester) async {
    await tester.pumpWidget(
      wrap(
        LocationBubble(
          latitude: 40.4,
          longitude: -3.7,
          messageId: 'm-3',
          onTap: () {},
        ),
      ),
    );

    await expectBothHalves(tester, locationBubbleSemanticsId('m-3'));
  });

  /// Inside a [MessageBubble] the bubble's own `Semantics` carries
  /// `excludeSemantics: true`, so the `ValueKey` is the half a driver can
  /// reach. Without the id the row publishes neither half, which is what a
  /// missing `messageId:` at the call site looks like from the outside.
  testWidgets('the room hands the location row the id of its message', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 'm-4',
      from: 'u1',
      timestamp: DateTime(2026, 1, 1),
      messageType: MessageType.location,
      metadata: const {'lat': '40.4', 'lng': '-3.7'},
    );

    await tester.pumpWidget(
      wrap(
        MessageBubble(
          message: message,
          isOutgoing: false,
          onTapLocation: () {},
        ),
      ),
    );

    expect(
      find.byKey(ValueKey(locationBubbleSemanticsId('m-4'))),
      findsOneWidget,
    );
  });

  testWidgets('the room hands the link preview the id of its message', (
    tester,
  ) async {
    final message = ChatMessage(
      id: 'm-5',
      from: 'u1',
      timestamp: DateTime(2026, 1, 1),
      text: 'look at https://flutter.dev',
      metadata: const {
        'linkUrl': 'https://flutter.dev',
        'linkTitle': 'Flutter',
      },
    );

    await tester.pumpWidget(
      wrap(MessageBubble(message: message, isOutgoing: false)),
    );

    expect(
      find.byKey(ValueKey(linkPreviewBubbleSemanticsId('m-5'))),
      findsOneWidget,
    );
  });

  testWidgets('the composer preview decorates no message and stays unnamed', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const LinkPreviewBubble(url: 'https://flutter.dev')),
    );

    expect(
      find.semantics.byPredicate((node) => node.identifier.isNotEmpty),
      findsNothing,
    );
  });

  testWidgets('a bubble handed no message id publishes no name', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(LocationBubble(latitude: 40.4, longitude: -3.7, onTap: () {})),
    );

    expect(identifier(locationBubbleSemanticsId('m-3')), findsNothing);
    expect(
      find.semantics.byPredicate((node) => node.identifier.isNotEmpty),
      findsNothing,
    );
    expect(
      tester
          .widget<Semantics>(
            find
                .descendant(
                  of: find.byType(LocationBubble),
                  matching: find.byType(Semantics),
                )
                .first,
          )
          .properties
          .button,
      isTrue,
    );
  });
}
