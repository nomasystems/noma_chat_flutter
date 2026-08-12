import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart'
    show CustomSemanticsAction, SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/ui/widgets/bubbles/_attachment_upload_overlay.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  ChatMessage makeMessage({
    String text = 'Hello',
    Map<String, dynamic>? metadata,
    bool isSystem = false,
    bool isEdited = false,
    bool isForwarded = false,
  }) {
    return ChatMessage(
      id: 'msg1',
      from: 'u1',
      timestamp: DateTime(2026, 1, 1),
      text: text,
      metadata: metadata,
      isSystem: isSystem,
      isEdited: isEdited,
      isForwarded: isForwarded,
    );
  }

  group('MessageBubble', () {
    testWidgets('renders text bubble for regular message', (tester) async {
      await tester.pumpWidget(
        wrap(MessageBubble(message: makeMessage(), isOutgoing: false)),
      );

      expect(find.textContaining('Hello'), findsOneWidget);
    });

    testWidgets('renders system message as centered text', (tester) async {
      final msg = makeMessage(
        text: 'u1 joined',
        isSystem: true,
        metadata: {'event': 'user_joined', 'userId': 'u1'},
      );
      await tester.pumpWidget(
        wrap(MessageBubble(message: msg, isOutgoing: false)),
      );

      expect(find.text('u1 joined'), findsOneWidget);
      expect(find.byType(Center), findsOneWidget);
    });

    testWidgets('shows sender name when provided', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: makeMessage(),
            isOutgoing: false,
            senderName: 'Alice',
          ),
        ),
      );

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows pending icon when isPending=true', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: makeMessage(),
            isOutgoing: true,
            isPending: true,
          ),
        ),
      );

      expect(find.byIcon(Icons.access_time), findsOneWidget);
    });

    testWidgets('shows error icon when isFailed=true', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: makeMessage(),
            isOutgoing: true,
            isFailed: true,
          ),
        ),
      );

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets(
      'suppresses the metadata-row error icon on a failed image bubble once '
      'the media retry arrow takes over, and routes the tap through the '
      'same onRetry',
      (tester) async {
        var retried = false;
        final msg = ChatMessage(
          id: 'img1',
          from: 'u1',
          timestamp: DateTime(2026, 1, 1),
          messageType: MessageType.attachment,
          mimeType: 'image/jpeg',
          attachmentUrl: 'https://example.com/photo.jpg',
        );
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              message: msg,
              isOutgoing: true,
              isFailed: true,
              onRetry: () => retried = true,
            ),
          ),
        );

        expect(find.byIcon(Icons.error_outline), findsNothing);
        expect(find.byIcon(Icons.refresh), findsOneWidget);

        await tester.tap(find.byIcon(Icons.refresh));
        expect(retried, isTrue);
      },
    );

    testWidgets(
      'keeps the metadata-row error icon on a failed image bubble when no '
      'onRetry is wired, and paints no retry arrow',
      (tester) async {
        final msg = ChatMessage(
          id: 'img2',
          from: 'u1',
          timestamp: DateTime(2026, 1, 1),
          messageType: MessageType.attachment,
          mimeType: 'image/jpeg',
          attachmentUrl: 'https://example.com/photo.jpg',
        );
        await tester.pumpWidget(
          wrap(MessageBubble(message: msg, isOutgoing: true, isFailed: true)),
        );

        expect(find.byIcon(Icons.refresh), findsNothing);
        // The media badge plus the metadata-row icon: nothing claims to be
        // a retry the bubble cannot honour.
        expect(find.byIcon(Icons.error_outline), findsNWidgets(2));
      },
    );

    testWidgets('reduced top padding when isFirstInGroup=false', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Column(
            children: [
              MessageBubble(
                message: makeMessage(),
                isOutgoing: false,
                isFirstInGroup: true,
              ),
              MessageBubble(
                message: makeMessage(),
                isOutgoing: false,
                isFirstInGroup: false,
              ),
            ],
          ),
        ),
      );

      final paddings = tester
          .widgetList<Padding>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Padding &&
                  widget.padding is EdgeInsets &&
                  (widget.padding as EdgeInsets).left == 8 &&
                  (widget.padding as EdgeInsets).right == 8,
            ),
          )
          .toList();

      expect(paddings.length, 2);
      final firstTop = (paddings[0].padding as EdgeInsets).top;
      final secondTop = (paddings[1].padding as EdgeInsets).top;

      expect(firstTop, 8.0);
      expect(secondTop, 4.0);
    });

    testWidgets('renders LocationBubble for MessageType.location', (
      tester,
    ) async {
      final msg = ChatMessage(
        id: 'loc1',
        from: 'u1',
        text: '',
        timestamp: DateTime(2026),
        messageType: MessageType.location,
        metadata: const {'lat': '40.4168', 'lng': '-3.7038'},
      );
      await tester.pumpWidget(
        wrap(MessageBubble(message: msg, isOutgoing: false)),
      );

      expect(find.byType(LocationBubble), findsOneWidget);
    });

    testWidgets('falls back when location metadata is missing', (tester) async {
      final msg = ChatMessage(
        id: 'loc1',
        from: 'u1',
        text: '',
        timestamp: DateTime(2026),
        messageType: MessageType.location,
      );
      await tester.pumpWidget(
        wrap(MessageBubble(message: msg, isOutgoing: false)),
      );

      expect(find.byType(LocationBubble), findsNothing);
    });
  });

  group('Read receipt avatars', () {
    testWidgets(
      'renders ReadReceiptAvatars when readReceiptUsers is non-empty',
      (tester) async {
        final msg = makeMessage();
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              message: msg,
              isOutgoing: true,
              status: ReceiptStatus.read,
              readReceiptUsers: const [ChatUser(id: 'bob', displayName: 'Bob')],
              readReceipts: [
                ReadReceipt(userId: 'bob', lastReadAt: DateTime(2026, 1, 2)),
              ],
            ),
          ),
        );

        expect(find.byType(ReadReceiptAvatars), findsOneWidget);
      },
    );

    testWidgets('does not render avatars when readReceiptUsers is empty', (
      tester,
    ) async {
      final msg = makeMessage();
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: msg,
            isOutgoing: true,
            status: ReceiptStatus.read,
          ),
        ),
      );

      expect(find.byType(ReadReceiptAvatars), findsNothing);
    });

    testWidgets('does not render avatars while the message is pending', (
      tester,
    ) async {
      final msg = makeMessage();
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: msg,
            isOutgoing: true,
            isPending: true,
            readReceiptUsers: const [ChatUser(id: 'bob', displayName: 'Bob')],
            readReceipts: [
              ReadReceipt(userId: 'bob', lastReadAt: DateTime(2026, 1, 2)),
            ],
          ),
        ),
      );

      expect(find.byType(ReadReceiptAvatars), findsNothing);
    });
  });

  group('MessageBubble link taps', () {
    const url = 'https://example.com/a';

    /// Finds the recognizer attached to the rendered span whose text is
    /// exactly `url`. `null` means the span was painted as a link but left
    /// unclickable — the shape of the bug this group guards.
    TapGestureRecognizer? linkRecognizer(WidgetTester tester) {
      TapGestureRecognizer? found;
      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        rich.text.visitChildren((span) {
          if (span is TextSpan && span.text == url) {
            final recognizer = span.recognizer;
            if (recognizer is TapGestureRecognizer) found = recognizer;
            return false;
          }
          return true;
        });
        if (found != null) break;
      }
      return found;
    }

    testWidgets('forwards onTapLink to the text bubble it builds', (
      tester,
    ) async {
      String? opened;

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: makeMessage(text: 'see $url now'),
            isOutgoing: false,
            onSwipeToReply: () {},
            onTapLink: (value) => opened = value,
          ),
        ),
      );

      final recognizer = linkRecognizer(tester);
      expect(recognizer, isNotNull);

      recognizer!.onTap!();
      expect(opened, url);
    });

    testWidgets('leaves the url span without a recognizer when unwired', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: makeMessage(text: 'see $url now'),
            isOutgoing: false,
            onSwipeToReply: () {},
          ),
        ),
      );

      expect(linkRecognizer(tester), isNull);
    });
  });

  group('MessageBubble mention taps', () {
    /// The rendered span for a given piece of the message text, reached
    /// through the real chain: `MessageBubble` → `TextBubble` →
    /// `parseMarkdown`.
    TextSpan? spanFor(WidgetTester tester, String needle) {
      TextSpan? found;
      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        rich.text.visitChildren((span) {
          if (span is TextSpan && span.text == needle) {
            found = span;
            return false;
          }
          return true;
        });
        if (found != null) break;
      }
      return found;
    }

    testWidgets('forwards onTapMention to the text bubble it builds', (
      tester,
    ) async {
      String? opened;

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: makeMessage(text: 'hi @alice!'),
            isOutgoing: false,
            onSwipeToReply: () {},
            onTapMention: (value) => opened = value,
          ),
        ),
      );

      final mention = spanFor(tester, '@alice');
      expect(mention, isNotNull);
      expect(mention!.style?.fontWeight, FontWeight.w600);

      (mention.recognizer! as TapGestureRecognizer).onTap!();
      expect(opened, 'alice');
    });

    testWidgets('paints no tappable affordance when unwired', (tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: makeMessage(text: 'hi @alice!'),
            isOutgoing: false,
            onSwipeToReply: () {},
          ),
        ),
      );

      final mention = spanFor(tester, '@alice');
      expect(mention, isNotNull);
      expect(mention!.recognizer, isNull);
      expect(
        mention.style,
        spanFor(tester, 'hi ')?.style,
        reason: 'an unhandled mention reads exactly like the words around it',
      );
    });
  });

  /// Two signals, two jobs, and one rule under both. The bubble decides for
  /// itself whether it is painting a ring — from
  /// [MessageBubble.attachmentUploadProgress] and from the branch its own
  /// content takes — and hands out a cancel callback only then, to the media
  /// bubble and to the screen reader alike. The cancellability signal is
  /// timing on top of that: the bytes land well before the ring retires, and
  /// the X has to go the instant they do. Absent, it withholds nothing — a
  /// host that wires only the callback keeps the X it has always had, and
  /// the worst its absence can cost is lateness.
  group('MessageBubble — upload cancel X', () {
    ChatMessage uploadingPhoto({bool isDeleted = false}) => ChatMessage(
      id: '_pending_1',
      from: 'u1',
      timestamp: DateTime(2026, 1, 1),
      messageType: MessageType.attachment,
      mimeType: 'image/jpeg',
      attachmentUrl: '',
      fileName: 'photo.jpg',
      isDeleted: isDeleted,
    );

    Widget bubbleWith(
      ValueNotifier<double>? progress,
      VoidCallback onCancel, {
      ValueListenable<bool>? cancellable,
      bool isDeleted = false,
    }) => wrap(
      MessageBubble(
        message: uploadingPhoto(isDeleted: isDeleted),
        isOutgoing: true,
        attachmentUploadProgress: progress,
        attachmentUploadCancellable: cancellable,
        onCancelAttachmentUpload: onCancel,
      ),
    );

    /// Custom-action labels reachable from [anchor]. `getSemantics` walks
    /// *up* from the element, so the anchor has to sit under the bubble's
    /// own `Semantics` node, never be the bubble itself.
    Set<String> actionLabelsAt(WidgetTester tester, Finder anchor) {
      final ids =
          tester
              .getSemantics(anchor)
              .getSemanticsData()
              .customSemanticsActionIds ??
          const <int>[];
      return {
        for (final id in ids)
          if (CustomSemanticsAction.getAction(id)?.label case final label?)
            label,
      };
    }

    AttachmentUploadRing ringOf(WidgetTester tester) =>
        tester.widget<AttachmentUploadRing>(find.byType(AttachmentUploadRing));

    testWidgets('is wired while the signal says the upload can be aborted', (
      tester,
    ) async {
      final progress = ValueNotifier<double>(0.4);
      final cancellable = ValueNotifier<bool>(true);
      var cancelled = false;

      await tester.pumpWidget(
        bubbleWith(progress, () => cancelled = true, cancellable: cancellable),
      );

      ringOf(tester).onCancel!();
      expect(cancelled, isTrue);

      progress.dispose();
      cancellable.dispose();
    });

    testWidgets('goes away the instant the signal flips, mid-ring', (
      tester,
    ) async {
      final progress = ValueNotifier<double>(0.9);
      final cancellable = ValueNotifier<bool>(true);
      await tester.pumpWidget(
        bubbleWith(progress, () {}, cancellable: cancellable),
      );
      expect(ringOf(tester).onCancel, isNotNull);

      // No pumpWidget, no unrelated rebuild: the row has to be listening.
      cancellable.value = false;
      await tester.pump();

      expect(ringOf(tester).onCancel, isNull);
      // The ring itself stays — the row still has no URL to render — and
      // keeps its center glyph, just not as a button.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);

      progress.dispose();
      cancellable.dispose();
    });

    testWidgets('survives a host that wires the callback and no signal — '
        'withholding it there would take the X off every hand-wired '
        'ChatView', (tester) async {
      // `MessageBubble`, `MessageList` and `ChatView` all let a host wire
      // `onCancelAttachmentUpload` on its own; only `NomaChatView` fills in
      // the resolver by default. Reading a missing signal as "not
      // cancellable" silently removes a working control from those hosts,
      // which is a behaviour change and not a fix.
      for (final value in [0.0, 0.4, 0.99, 1.0]) {
        final progress = ValueNotifier<double>(value);
        var cancelled = false;

        await tester.pumpWidget(bubbleWith(progress, () => cancelled = true));

        ringOf(tester).onCancel!();
        expect(cancelled, isTrue, reason: 'progress $value keeps its X');

        progress.dispose();
      }
    });

    testWidgets('goes with the ring: no progress notifier, nothing painted '
        'and nothing announced', (tester) async {
      // The row-level half of the rule. A send that ended stops answering
      // `attachmentUploadProgressFor`, and this is what the row does with
      // that `null` — the widget statement, not the controller's, which
      // `send_upload_registration_release_test.dart` owns. A file row, so
      // nothing tries to resolve media once the placeholder is gone.
      final handle = tester.ensureSemantics();
      final uploadingFile = ChatMessage(
        id: '_pending_1',
        from: 'u1',
        timestamp: DateTime(2026, 1, 1),
        messageType: MessageType.attachment,
        mimeType: 'application/pdf',
        attachmentUrl: '',
        fileName: 'report.pdf',
      );
      Widget fileRow(ValueNotifier<double>? progress) => wrap(
        MessageBubble(
          message: uploadingFile,
          isOutgoing: true,
          attachmentUploadProgress: progress,
          onCancelAttachmentUpload: () {},
        ),
      );

      final progress = ValueNotifier<double>(0.4);
      await tester.pumpWidget(fileRow(progress));
      expect(find.byType(AttachmentUploadRing), findsOneWidget);
      expect(
        actionLabelsAt(tester, find.byType(FileBubble)),
        contains('Cancel upload'),
      );

      await tester.pumpWidget(fileRow(null));

      expect(find.byType(AttachmentUploadRing), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(actionLabelsAt(tester, find.byType(FileBubble)), isEmpty);

      handle.dispose();
      progress.dispose();
    });

    testWidgets('goes with the ring: a deleted row paints a tombstone, so a '
        'live upload behind it still gets no X and no announcement', (
      tester,
    ) async {
      // The other half, and the one that made re-deriving "does this row
      // paint an X?" at the announcement site a bug: a deleted message
      // short-circuits to the tombstone before any media bubble is built,
      // so the progress notifier it still carries paints nothing. Reading
      // the type/mime alone offered a screen reader a Cancel upload action
      // for a ring that was not on screen.
      final handle = tester.ensureSemantics();
      final progress = ValueNotifier<double>(0.4);

      await tester.pumpWidget(bubbleWith(progress, () {}, isDeleted: true));

      expect(find.byType(AttachmentUploadRing), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(actionLabelsAt(tester, find.byIcon(Icons.block)), isEmpty);

      handle.dispose();
      progress.dispose();
    });

    testWidgets('goes with the ring: the attachment rows that land on a '
        'bubble with no ring get no X either', (tester) async {
      // The rest of the branch table. An audio-mime attachment renders
      // `AudioBubble`, which has no cancel control at all; an attachment
      // with no URL yet falls through to `TextBubble`. Neither paints a
      // ring, so neither may hand a cancel to a screen reader — the
      // announcement has to follow the branch, not the message type.
      final handle = tester.ensureSemantics();
      final progress = ValueNotifier<double>(0.4);

      Future<void> pumpRow(String? url, String mime) => tester.pumpWidget(
        wrap(
          MessageBubble(
            message: ChatMessage(
              id: '_pending_1',
              from: 'u1',
              timestamp: DateTime(2026, 1, 1),
              messageType: MessageType.attachment,
              mimeType: mime,
              attachmentUrl: url,
              text: 'sending',
            ),
            isOutgoing: true,
            attachmentUploadProgress: progress,
            onCancelAttachmentUpload: () {},
          ),
        ),
      );

      await pumpRow('', 'audio/mp4');
      expect(find.byType(AttachmentUploadRing), findsNothing);
      expect(actionLabelsAt(tester, find.byType(AudioBubble)), isEmpty);

      await pumpRow(null, 'image/jpeg');
      expect(find.byType(AttachmentUploadRing), findsNothing);
      expect(actionLabelsAt(tester, find.byType(TextBubble)), isEmpty);

      handle.dispose();
      progress.dispose();
    });

    testWidgets('is not announced to a screen reader once the signal says '
        'the bytes have landed', (tester) async {
      // Disposed before returning, not via addTearDown: the framework's
      // semantics-handle check runs in _endOfTestVerifications, ahead of
      // any tearDown.
      final handle = tester.ensureSemantics();
      final progress = ValueNotifier<double>(0.9);
      final cancellable = ValueNotifier<bool>(true);

      Set<String> actionLabels() =>
          actionLabelsAt(tester, find.byType(ImageBubble));

      await tester.pumpWidget(
        bubbleWith(progress, () {}, cancellable: cancellable),
      );
      expect(actionLabels(), contains('Cancel upload'));

      cancellable.value = false;
      await tester.pump();
      expect(actionLabels(), isEmpty);

      // With no signal at all the X is painted, so it is announced too —
      // the two have to agree, or a screen reader offers an action the
      // sighted UI does not (or hides one it does).
      await tester.pumpWidget(bubbleWith(progress, () {}));
      expect(actionLabels(), contains('Cancel upload'));

      handle.dispose();
      progress.dispose();
      cancellable.dispose();
    });

    testWidgets('the announced action runs the host callback, the same one '
        'the painted X runs', (tester) async {
      // A label alone would satisfy every other assertion here while doing
      // nothing when invoked. Screen-reader users get the affordance the
      // sighted UI advertises only if the action behind the label is the
      // host's, so this drives it the way the platform does.
      final handle = tester.ensureSemantics();
      final progress = ValueNotifier<double>(0.4);
      var cancelled = 0;

      await tester.pumpWidget(bubbleWith(progress, () => cancelled++));

      final node = tester.getSemantics(find.byType(ImageBubble));
      final actionId = node
          .getSemanticsData()
          .customSemanticsActionIds!
          .singleWhere(
            (id) =>
                CustomSemanticsAction.getAction(id)?.label == 'Cancel upload',
          );
      node.owner!.performAction(
        node.id,
        SemanticsAction.customAction,
        actionId,
      );
      expect(cancelled, 1);

      // And the painted X is that same callback, not a parallel path.
      ringOf(tester).onCancel!();
      expect(cancelled, 2);

      handle.dispose();
      progress.dispose();
    });

    testWidgets('is not announced at all when the host wired no callback — '
        'a label with nothing behind it is worse than no label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final progress = ValueNotifier<double>(0.4);
      final cancellable = ValueNotifier<bool>(true);

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: uploadingPhoto(),
            isOutgoing: true,
            attachmentUploadProgress: progress,
            attachmentUploadCancellable: cancellable,
          ),
        ),
      );

      // Everything that would normally produce the affordance is present:
      // a ring is painted and the signal says the upload can still be
      // aborted. The only thing missing is somebody to call.
      expect(find.byType(AttachmentUploadRing), findsOne);
      expect(ringOf(tester).onCancel, isNull);
      expect(actionLabelsAt(tester, find.byType(ImageBubble)), isEmpty);

      handle.dispose();
      progress.dispose();
      cancellable.dispose();
    });

    testWidgets('the announcement comes from the resolved callback, not '
        'from the raw host one: no ring, no action, even with the host '
        'callback wired', (tester) async {
      final handle = tester.ensureSemantics();
      var cancelled = 0;

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: uploadingPhoto(),
            isOutgoing: true,
            onCancelAttachmentUpload: () => cancelled++,
          ),
        ),
      );

      expect(find.byType(AttachmentUploadRing), findsNothing);
      expect(actionLabelsAt(tester, find.byType(ImageBubble)), isEmpty);
      expect(cancelled, 0);

      handle.dispose();
    });
  });
}
