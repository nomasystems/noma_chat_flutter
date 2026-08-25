import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/mappers/room_mapper.dart';

/// Until when a timed mute holds, on the row and on the room header.
///
/// The expiries here are the ones the system actually produces: the body
/// `PATCH /rooms/{id}/preferences` answers (`chat_engine_room_prefs`
/// projects `{muted, pinned, hidden, muteUntil?}`, with `muteUntil` an
/// ISO-8601 **UTC** string present only while a timed mute is in effect),
/// and the instant the SDK's own [MuteDurationSheet] hands to
/// `adapter.rooms.mute`.
void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  ChatController controller() => ChatController(
    initialMessages: const [],
    currentUser: const ChatUser(id: 'me', displayName: 'Me'),
  );

  /// The row as `RoomEnricher` builds it out of the stored preferences.
  RoomListItem rowOf(RoomPreferences prefs, {int? memberCount}) => RoomListItem(
    id: '9d1c7f36-0b2a-4e58-a3c9-7f1e6d4b2a80',
    name: 'Cañas en Malasaña',
    isGroup: memberCount != null,
    memberCount: memberCount,
    lastMessage: 'voy llegando',
    muted: prefs.muted,
    muteUntil: prefs.muteUntil,
    pinned: prefs.pinned,
    hidden: prefs.hidden,
  );

  String hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  String ddmmyyyy(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}/'
      '${t.month.toString().padLeft(2, '0')}/${t.year}';

  /// A timed mute still running, as the backend answers it.
  final timed = RoomMapper.preferencesFromJson(const {
    'muted': true,
    'pinned': false,
    'hidden': false,
    'muteUntil': '2030-01-01T00:00:00Z',
  });

  /// A permanent mute: the projection drops the field entirely.
  final permanent = RoomMapper.preferencesFromJson(const {
    'muted': true,
    'pinned': false,
    'hidden': false,
  });

  /// A lapsed mute, as a stale cache can still hold it.
  final lapsed = RoomMapper.preferencesFromJson(const {
    'muted': true,
    'pinned': false,
    'hidden': false,
    'muteUntil': '2020-01-01T00:00:00Z',
  });

  group('the row says until when', () {
    test('the backend body carries the expiry as a UTC instant', () {
      expect(timed.muted, isTrue);
      expect(timed.muteUntil, isNotNull);
      expect(timed.muteUntil!.isUtc, isTrue);
      expect(permanent.muteUntil, isNull);
    });

    testWidgets('a running timed mute reads out its local deadline', (
      tester,
    ) async {
      final until = timed.muteUntil!;
      final local = until.toLocal();
      await tester.pumpWidget(wrap(RoomTile(room: rowOf(timed))));

      expect(
        find.text('Muted until ${ddmmyyyy(local)} ${hhmm(local)}'),
        findsOneWidget,
      );
      // The wire time is UTC: a device an hour ahead must not read the
      // deadline out an hour early.
      if (hhmm(local) != hhmm(until)) {
        expect(find.textContaining(hhmm(until)), findsNothing);
      }
    });

    testWidgets('a permanent mute keeps the bell alone', (tester) async {
      await tester.pumpWidget(wrap(RoomTile(room: rowOf(permanent))));

      expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
      expect(find.textContaining('Muted until'), findsNothing);
    });

    testWidgets('an expiry already elapsed is not read out', (tester) async {
      await tester.pumpWidget(wrap(RoomTile(room: rowOf(lapsed))));

      expect(find.textContaining('Muted until'), findsNothing);
    });

    testWidgets('an unmuted room says nothing', (tester) async {
      final room = rowOf(timed).copyWith(muted: false);
      await tester.pumpWidget(wrap(RoomTile(room: room)));

      expect(find.textContaining('Muted until'), findsNothing);
    });

    testWidgets('the deadline the SDK mute sheet produces is read out', (
      tester,
    ) async {
      final until = MuteDuration.eightHours.until(DateTime.now())!;
      final room = rowOf(permanent).copyWith(muteUntil: until);
      await tester.pumpWidget(wrap(RoomTile(room: room)));

      expect(find.textContaining('Muted until'), findsOneWidget);
      expect(find.textContaining(hhmm(until.toLocal())), findsOneWidget);
      expect(MuteDuration.always.until(DateTime.now()), isNull);
    });

    testWidgets('the line is localized', (tester) async {
      final local = timed.muteUntil!.toLocal();
      await tester.pumpWidget(
        wrap(
          RoomTile(
            room: rowOf(timed),
            theme: const ChatTheme(l10n: ChatUiLocalizations.es),
          ),
        ),
      );

      expect(
        find.text('Silenciado hasta ${ddmmyyyy(local)} ${hhmm(local)}'),
        findsOneWidget,
      );
    });
  });

  group('the room header says until when', () {
    Widget bar(RoomListItem room, ChatController c) => MaterialApp(
      home: Scaffold(
        appBar: ChatRoomAppBar(controller: c, room: room),
        body: const SizedBox(),
      ),
    );

    testWidgets('the deadline joins the member count', (tester) async {
      final local = timed.muteUntil!.toLocal();
      await tester.pumpWidget(bar(rowOf(timed, memberCount: 5), controller()));

      expect(
        find.text('5 members · Muted until ${ddmmyyyy(local)} ${hhmm(local)}'),
        findsOneWidget,
      );
    });

    testWidgets('a permanent mute leaves the header untouched', (tester) async {
      await tester.pumpWidget(
        bar(rowOf(permanent, memberCount: 5), controller()),
      );

      expect(find.text('5 members'), findsOneWidget);
    });

    testWidgets('somebody typing still owns the subtitle', (tester) async {
      final c = controller()..setTyping('u1', true);
      await tester.pumpWidget(bar(rowOf(timed, memberCount: 5), c));

      expect(find.textContaining('Muted until'), findsNothing);
      // Cancels the typing timeout the controller scheduled, so the
      // binding does not assert on a pending Timer.
      c.setTyping('u1', false);
      c.dispose();
    });
  });
}
