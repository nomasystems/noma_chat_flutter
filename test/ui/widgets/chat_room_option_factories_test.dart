import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';

/// `ChatRoomOption` named factories.
///
/// One smoke test per factory: label, destructive flag,
/// confirmation dialog, and the `onAfterX` hook where applicable.
void main() {
  const l10n = ChatUiLocalizations.en;

  group('ChatRoomOption factories', () {
    test('clearChat: destructive + has confirmation', () {
      final opt = ChatRoomOption.clearChat(l10n: l10n, onConfirm: () {});
      expect(opt.label, l10n.clearChat);
      expect(opt.destructive, isTrue);
      expect(opt.confirmation, isNotNull);
      expect(opt.confirmation!.title, l10n.clearChatConfirmTitle);
    });

    test('deleteChat: destructive + has confirmation', () {
      final opt = ChatRoomOption.deleteChat(l10n: l10n, onConfirm: () {});
      expect(opt.label, l10n.deleteChat);
      expect(opt.destructive, isTrue);
      expect(opt.confirmation, isNotNull);
    });

    test('blockUser: personalizes the label when otherUserName given', () {
      final opt = ChatRoomOption.blockUser(
        l10n: l10n,
        otherUserName: 'Alice',
        onConfirm: () {},
      );
      expect(opt.label, l10n.blockUserName('Alice'));
      expect(opt.destructive, isTrue);
    });

    test('blockUser: falls back to the generic label when name is empty', () {
      final opt = ChatRoomOption.blockUser(l10n: l10n, onConfirm: () {});
      expect(opt.label, l10n.blockUser);
    });

    test('leaveGroup: destructive + has confirmation', () {
      final opt = ChatRoomOption.leaveGroup(l10n: l10n, onConfirm: () {});
      expect(opt.label, l10n.leaveGroup);
      expect(opt.destructive, isTrue);
      expect(opt.confirmation, isNotNull);
    });

    test('addMembers / viewMembers / editGroupInfo: non-destructive, '
        'no confirmation', () {
      final add = ChatRoomOption.addMembers(l10n: l10n, onTap: () {});
      final view = ChatRoomOption.viewMembers(l10n: l10n, onTap: () {});
      final edit = ChatRoomOption.editGroupInfo(l10n: l10n, onTap: () {});
      for (final opt in [add, view, edit]) {
        expect(opt.destructive, isFalse);
        expect(opt.confirmation, isNull);
      }
    });

    test('muteRoom: label and icon flip based on `muted`', () {
      final muted = ChatRoomOption.muteRoom(
        l10n: l10n,
        muted: true,
        onMute: (_) {},
        onUnmute: () {},
      );
      final unmuted = ChatRoomOption.muteRoom(
        l10n: l10n,
        muted: false,
        onMute: (_) {},
        onUnmute: () {},
      );
      expect(muted.label, l10n.unmute);
      expect(unmuted.label, l10n.mute);
    });

    test('pinRoom toggle: label flips based on `pinned`', () {
      final pinned = ChatRoomOption.pinRoom(
        l10n: l10n,
        pinned: true,
        onToggle: () {},
      );
      final unpinned = ChatRoomOption.pinRoom(
        l10n: l10n,
        pinned: false,
        onToggle: () {},
      );
      expect(pinned.label, l10n.unpin);
      expect(unpinned.label, l10n.pin);
    });

    test('reportUser personalizes label when otherUserName given', () {
      final opt = ChatRoomOption.reportUser(
        l10n: l10n,
        otherUserName: 'Bob',
        onTap: () {},
      );
      expect(opt.label, contains('Bob'));
      expect(opt.destructive, isTrue);
    });

    test(
      'inviteViaLink: builds the deep link and hands it to onInvite',
      () async {
        Uri? captured;
        final opt = ChatRoomOption.inviteViaLink(
          l10n: l10n,
          roomId: 'r1',
          token: 'tok',
          linkBase: Uri.parse('https://app.example.com/invite'),
          onInvite: (link) => captured = link,
        );
        expect(opt.label, l10n.inviteViaLink);
        expect(opt.destructive, isFalse);
        await opt.onTap();
        expect(captured, isNotNull);
        expect(captured!.queryParameters['room'], 'r1');
        expect(captured!.queryParameters['token'], 'tok');
      },
    );

    test('exportChat: non-destructive row that fires onTap', () async {
      var tapped = false;
      final opt = ChatRoomOption.exportChat(
        l10n: l10n,
        onTap: () => tapped = true,
      );
      expect(opt.label, l10n.exportChat);
      expect(opt.destructive, isFalse);
      await opt.onTap();
      expect(tapped, isTrue);
    });

    test(
      'archiveChat / unarchiveChat: non-destructive rows that fire onTap',
      () async {
        var archived = false;
        var unarchived = false;
        final archive = ChatRoomOption.archiveChat(
          l10n: l10n,
          onTap: () => archived = true,
        );
        final unarchive = ChatRoomOption.unarchiveChat(
          l10n: l10n,
          onTap: () => unarchived = true,
        );
        expect(archive.label, l10n.archiveChat);
        expect(unarchive.label, l10n.unarchiveChat);
        expect(archive.destructive, isFalse);
        expect(archive.confirmation, isNull);
        await archive.onTap();
        await unarchive.onTap();
        expect(archived, isTrue);
        expect(unarchived, isTrue);
      },
    );
  });

  group('ChatRoomOptionsMenu.showConfirmation', () {
    testWidgets('Tap on the accept button resolves the confirmation as true', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  ChatRoomOptionsMenu.showConfirmation(
                    context: context,
                    confirmation: const ChatRoomOptionConfirmation(
                      title: 'Title',
                      body: 'Body',
                      acceptLabel: 'Yes',
                      cancelLabel: 'No',
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Body'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
    });
  });

  group('blockUser onAfterBlock hook', () {
    test('onAfterBlock fires after onConfirm', () async {
      final order = <String>[];
      final opt = ChatRoomOption.blockUser(
        l10n: l10n,
        onConfirm: () async {
          order.add('confirm');
        },
        onAfterBlock: () => order.add('after'),
      );
      await opt.onTap();
      expect(order, ['confirm', 'after']);
    });
  });
}
