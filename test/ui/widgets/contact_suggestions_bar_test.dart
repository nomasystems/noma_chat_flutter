import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: child),
  );

  final contacts = [
    const SuggestedContact(id: '1', displayName: 'Julio', isOnline: true),
    const SuggestedContact(id: '2', displayName: 'María', isOnline: false),
    const SuggestedContact(id: '3', displayName: 'David', isOnline: true),
  ];

  group('ContactSuggestionsBar', () {
    testWidgets('renders nothing when contacts is empty', (tester) async {
      await tester.pumpWidget(
        wrap(const ContactSuggestionsBar(contacts: [])),
      );
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('shows title and contact names', (tester) async {
      await tester.pumpWidget(
        wrap(ContactSuggestionsBar(
          contacts: contacts,
          title: 'Sugerencias',
        )),
      );
      expect(find.text('Sugerencias'), findsOneWidget);
      expect(find.text('Julio'), findsOneWidget);
      expect(find.text('María'), findsOneWidget);
      expect(find.text('David'), findsOneWidget);
    });

    testWidgets('calls onTap with correct contact', (tester) async {
      SuggestedContact? tapped;
      await tester.pumpWidget(
        wrap(ContactSuggestionsBar(
          contacts: contacts,
          onTap: (c) => tapped = c,
        )),
      );
      await tester.tap(find.text('María'));
      expect(tapped?.id, '2');
    });

    testWidgets('renders without title', (tester) async {
      await tester.pumpWidget(
        wrap(ContactSuggestionsBar(contacts: contacts)),
      );
      expect(find.text('Julio'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('renders UserAvatar for each contact', (tester) async {
      await tester.pumpWidget(
        wrap(ContactSuggestionsBar(contacts: contacts)),
      );
      expect(find.byType(UserAvatar), findsNWidgets(3));
    });
  });
}
