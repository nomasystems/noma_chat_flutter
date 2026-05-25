import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

/// Seeds the mock client with a richer demo dataset: three 1-on-1 DMs and
/// two groups (a tennis crew + an engineering team) plus an announcement
/// room. Conversations exercise the full chat surface: replies, reactions,
/// images, voice notes, link previews, edited messages.
///
/// All copy is in English on purpose — the example doubles as a public-
/// facing brochure for the SDK.
void seedDemoData(MockChatClient client) {
  final now = DateTime.now();
  DateTime t(int minutesAgo) => now.subtract(Duration(minutes: minutesAgo));

  // Seed user profiles so any consumer that calls `client.users.get`
  // resolves a friendly displayName instead of the raw id.
  //
  // Avatars: bundled as local assets under `example/assets/avatars/`
  // so the demo renders identically offline — no network, no flaky
  // CDN, no surprise CORS / ATS edge cases on iOS sims. The
  // `asset:` scheme is recognised by `UserAvatar` which routes it
  // through `AssetImage` instead of `Image.network`. Bundled sources:
  // randomuser.me portraits for the humans (gender-correct), the
  // dicebear identicon for the bot, Unsplash thematic photos for
  // the groups.
  client
    ..seedUser(
      const ChatUser(
        id: 'alice',
        displayName: 'Alice',
        avatarUrl: 'asset:assets/avatars/alice.jpg',
      ),
    )
    ..seedUser(
      const ChatUser(
        id: 'bob',
        displayName: 'Bob',
        avatarUrl: 'asset:assets/avatars/bob.jpg',
      ),
    )
    ..seedUser(
      const ChatUser(
        id: 'carol',
        displayName: 'Carol',
        avatarUrl: 'asset:assets/avatars/carol.jpg',
      ),
    )
    ..seedUser(
      const ChatUser(
        id: 'newsroom',
        displayName: 'Newsroom',
        avatarUrl: 'asset:assets/avatars/newsroom.png',
      ),
    );

  // Register the demo peers as roster contacts of `demo-user`. Without
  // this `MockContactsApi.list()` returns an empty list, the suggestion
  // bar has nothing to render and DM resolution can't surface familiar
  // names. CHT mode wires roster via Cognito metadata; in mock we wire
  // it explicitly so the example exercises the same UI surface.
  for (final id in ['alice', 'bob', 'carol']) {
    client.contacts.add(id);
  }

  _seedDmAlice(client, t);
  _seedDmBob(client, t);
  _seedDmCarol(client, t);
  _seedGroupTennis(client, t);
  _seedGroupEngineering(client, t);
  _seedAnnouncements(client, t);

  // Chat-list metadata the real backend computes/stores but the mock
  // `ChatRoom` model doesn't carry. Pin Alice's DM to the top, mute the
  // Announcements channel, and leave a mix of unread/read rooms so the
  // list shows pins, mutes and unread badges — not just titles. (The list
  // now also sorts by last-message time, so DMs and groups interleave
  // naturally instead of grouping all DMs then all groups.)
  client
    ..seedRoomMeta('room-dm-alice', pinned: true)
    ..seedRoomMeta('room-news', muted: true)
    ..seedRoomMeta('room-dm-bob', unread: 2)
    ..seedRoomMeta('room-group-tennis', unread: 5)
    ..seedRoomMeta('room-dm-carol', unread: 1);
}

// ---------------------------------------------------------------------------
// DMs
// ---------------------------------------------------------------------------

void _seedDmAlice(MockChatClient client, DateTime Function(int) t) {
  // DM rooms intentionally have no `name`: the SDK's `_isDmDetail`
  // classifies a 2-member room as a DM only when the room has no
  // user-assigned name, and once classified the DM-aware title resolver
  // pulls the peer's `displayName` + `avatarUrl` (so the row reads
  // "Alice" with her portrait instead of a generic group tile).
  // Seeding `name: 'Alice'` would mis-classify the room as a 2-person
  // group, skipping `_doResolveDmContact` and leaving the avatar empty.
  client.seedRoom(
    const ChatRoom(
      id: 'room-dm-alice',
      audience: RoomAudience.contacts,
      members: ['demo-user', 'alice'],
    ),
  );

  client.addMessage(
    'room-dm-alice',
    ChatMessage(
      id: 'dm-alice-1',
      from: 'alice',
      timestamp: t(180),
      text: 'Hey, did you catch the final last night?',
    ),
  );
  client.addMessage(
    'room-dm-alice',
    ChatMessage(
      id: 'dm-alice-2',
      from: 'demo-user',
      timestamp: t(178),
      text: 'Yes! Five sets, what a match 🎾',
      receipt: ReceiptStatus.read,
    ),
  );
  client.addMessage(
    'room-dm-alice',
    ChatMessage(
      id: 'dm-alice-3',
      from: 'alice',
      timestamp: t(176),
      text: 'That drop shot at 5-4 in the fourth was insane.',
      metadata: const {
        '_reactions': {'🔥': 1},
        '_reactionUsers': {
          '🔥': ['demo-user'],
        },
      },
    ),
  );
  client.addMessage(
    'room-dm-alice',
    ChatMessage(
      id: 'dm-alice-4',
      from: 'demo-user',
      timestamp: t(170),
      text: 'Honestly the cleanest forehand I have seen all season.',
      receipt: ReceiptStatus.read,
    ),
  );
  client.addMessage(
    'room-dm-alice',
    ChatMessage(
      id: 'dm-alice-5',
      from: 'alice',
      timestamp: t(160),
      text: 'Slow-motion frame from the trophy ceremony, look at this:',
    ),
  );
  client.addMessage(
    'room-dm-alice',
    ChatMessage(
      id: 'dm-alice-6',
      from: 'alice',
      timestamp: t(159),
      text: '',
      messageType: MessageType.attachment,
      attachmentUrl: 'https://picsum.photos/seed/tennis-trophy/720/540',
      mimeType: 'image/jpeg',
    ),
  );
  client.addMessage(
    'room-dm-alice',
    ChatMessage(
      id: 'dm-alice-7',
      from: 'demo-user',
      timestamp: t(155),
      text: 'That shot belongs on a poster.',
      referencedMessageId: 'dm-alice-6',
      messageType: MessageType.reply,
      receipt: ReceiptStatus.read,
    ),
  );
  client.addMessage(
    'room-dm-alice',
    ChatMessage(
      id: 'dm-alice-8',
      from: 'alice',
      timestamp: t(120),
      text: '',
      messageType: MessageType.audio,
      // TTS clip generated by `tools/gen_mock_audios.sh` (`say -v
      // Samantha`). `asset:` URLs are routed through `AssetSource`
      // by the SDK so playback works offline. Waveform values come
      // from the RMS-bucket extractor in the same script — they
      // mirror the actual clip envelope so the bubble graph and the
      // audible content are in lockstep.
      attachmentUrl: 'asset:assets/audio/dm-alice-8.wav',
      mimeType: 'audio/wav',
      metadata: const {
        'duration': 4594,
        'waveform': [
          65,
          65,
          58,
          74,
          52,
          91,
          98,
          42,
          85,
          41,
          77,
          68,
          49,
          67,
          46,
          76,
          24,
          2,
          53,
          100,
          67,
          15,
          87,
          80,
          82,
          54,
          70,
          74,
          64,
          94,
          79,
          33,
        ],
      },
    ),
  );
  client.addMessage(
    'room-dm-alice',
    ChatMessage(
      id: 'dm-alice-9',
      from: 'demo-user',
      timestamp: t(115),
      text: 'Highlights from ATP: https://www.atptour.com/en/news',
      metadata: const {
        'linkUrl': 'https://www.atptour.com/en/news',
        'linkTitle': 'ATP Tour — Latest News',
        'linkDescription':
            'Official ATP news, match recaps and player interviews.',
        'linkImage': 'https://picsum.photos/seed/atp-news/600/315',
      },
      receipt: ReceiptStatus.read,
    ),
  );
  client.addMessage(
    'room-dm-alice',
    ChatMessage(
      id: 'dm-alice-10',
      from: 'alice',
      timestamp: t(8),
      text: 'See you on court Saturday?',
    ),
  );
}

void _seedDmBob(MockChatClient client, DateTime Function(int) t) {
  client.seedRoom(
    const ChatRoom(
      id: 'room-dm-bob',
      audience: RoomAudience.contacts,
      members: ['demo-user', 'bob'],
    ),
  );

  client.addMessage(
    'room-dm-bob',
    ChatMessage(
      id: 'dm-bob-1',
      from: 'bob',
      timestamp: t(240),
      text: 'Practice tomorrow morning?',
    ),
  );
  client.addMessage(
    'room-dm-bob',
    ChatMessage(
      id: 'dm-bob-2',
      from: 'demo-user',
      timestamp: t(238),
      text: '8am as usual?',
      receipt: ReceiptStatus.read,
    ),
  );
  client.addMessage(
    'room-dm-bob',
    ChatMessage(
      id: 'dm-bob-3',
      from: 'bob',
      timestamp: t(236),
      text:
          'Court 3 is booked already. Bring the new strings — mine snapped '
          'on the last rally yesterday.',
    ),
  );
  client.addMessage(
    'room-dm-bob',
    ChatMessage(
      id: 'dm-bob-4',
      from: 'demo-user',
      timestamp: t(234),
      text: 'Got a fresh set, picked them up this morning.',
      referencedMessageId: 'dm-bob-3',
      messageType: MessageType.reply,
      receipt: ReceiptStatus.read,
      metadata: const {
        '_reactions': {'👌': 1},
        '_reactionUsers': {
          '👌': ['bob'],
        },
      },
    ),
  );
  client.addMessage(
    'room-dm-bob',
    ChatMessage(
      id: 'dm-bob-5',
      from: 'bob',
      timestamp: t(220),
      text: 'My racket after last set — RIP main strings.',
    ),
  );
  client.addMessage(
    'room-dm-bob',
    ChatMessage(
      id: 'dm-bob-6',
      from: 'bob',
      timestamp: t(219),
      text: '',
      messageType: MessageType.attachment,
      attachmentUrl: 'https://picsum.photos/seed/racket-broken/800/600',
      mimeType: 'image/jpeg',
    ),
  );
  client.addMessage(
    'room-dm-bob',
    ChatMessage(
      id: 'dm-bob-7',
      from: 'demo-user',
      timestamp: t(218),
      text: 'Ouch. Quick voice note with the warmup plan:',
      receipt: ReceiptStatus.read,
    ),
  );
  client.addMessage(
    'room-dm-bob',
    ChatMessage(
      id: 'dm-bob-8',
      from: 'demo-user',
      timestamp: t(217),
      text: '',
      messageType: MessageType.audio,
      attachmentUrl: 'asset:assets/audio/dm-bob-8.wav',
      mimeType: 'audio/wav',
      metadata: const {
        'duration': 6684,
        'waveform': [
          78,
          90,
          59,
          65,
          95,
          43,
          84,
          83,
          77,
          2,
          77,
          69,
          87,
          87,
          42,
          51,
          94,
          47,
          77,
          91,
          100,
          60,
          2,
          72,
          76,
          64,
          65,
          87,
          36,
          64,
          85,
          36,
        ],
      },
      receipt: ReceiptStatus.read,
    ),
  );
  // Incoming voice note from Bob — exercises the in-bubble sender
  // portrait on a 1:1 chat (no leading avatar to dedupe against, so the
  // large tappable portrait inside the bubble shows Bob's photo).
  client.addMessage(
    'room-dm-bob',
    ChatMessage(
      id: 'dm-bob-8b',
      from: 'bob',
      timestamp: t(120),
      text: '',
      messageType: MessageType.audio,
      attachmentUrl: 'asset:assets/audio/dm-bob-8.wav',
      mimeType: 'audio/wav',
      metadata: const {
        'duration': 4200,
        'waveform': [
          40,
          72,
          88,
          51,
          96,
          30,
          61,
          80,
          74,
          12,
          70,
          66,
          90,
          44,
          58,
          37,
          84,
          53,
          69,
          97,
          88,
          49,
          18,
          63,
          79,
          41,
          71,
          92,
          33,
          60,
          81,
          47,
        ],
      },
      receipt: ReceiptStatus.read,
    ),
  );
  client.addMessage(
    'room-dm-bob',
    ChatMessage(
      id: 'dm-bob-9',
      from: 'bob',
      timestamp: t(35),
      text: 'See you at 7:45 — earlier warmup.',
      isEdited: true,
    ),
  );
}

void _seedDmCarol(MockChatClient client, DateTime Function(int) t) {
  client.seedRoom(
    const ChatRoom(
      id: 'room-dm-carol',
      audience: RoomAudience.contacts,
      members: ['demo-user', 'carol'],
    ),
  );

  client.addMessage(
    'room-dm-carol',
    ChatMessage(
      id: 'dm-carol-1',
      from: 'carol',
      timestamp: t(360),
      text: "Hey! Haven't seen you at the club in ages.",
    ),
  );
  client.addMessage(
    'room-dm-carol',
    ChatMessage(
      id: 'dm-carol-2',
      from: 'demo-user',
      timestamp: t(358),
      text: 'I was traveling for work. How is the league going?',
      receipt: ReceiptStatus.read,
    ),
  );
  client.addMessage(
    'room-dm-carol',
    ChatMessage(
      id: 'dm-carol-3',
      from: 'carol',
      timestamp: t(355),
      text:
          'Top 3 in singles after last weekend. Long interview I did, '
          'in case you want to read it: https://example.com/interview',
      metadata: const {
        'linkUrl': 'https://example.com/interview',
        'linkTitle': 'Carol — Club League Top 3',
        'linkDescription':
            'A conversation with one of our most consistent players about '
            'the season ahead.',
        'linkImage': 'https://picsum.photos/seed/carol-interview/600/315',
      },
    ),
  );
  client.addMessage(
    'room-dm-carol',
    ChatMessage(
      id: 'dm-carol-4',
      from: 'demo-user',
      timestamp: t(350),
      text: 'Reading it right now ☕',
      receipt: ReceiptStatus.read,
      metadata: const {
        '_reactions': {'❤️': 1},
        '_reactionUsers': {
          '❤️': ['carol'],
        },
      },
    ),
  );
  client.addMessage(
    'room-dm-carol',
    ChatMessage(
      id: 'dm-carol-5',
      from: 'carol',
      timestamp: t(340),
      text: 'A shot from the trophy run, the courts at sunset are unreal:',
    ),
  );
  client.addMessage(
    'room-dm-carol',
    ChatMessage(
      id: 'dm-carol-6',
      from: 'carol',
      timestamp: t(339),
      text: '',
      messageType: MessageType.attachment,
      attachmentUrl: 'https://picsum.photos/seed/court-sunset/720/540',
      mimeType: 'image/jpeg',
    ),
  );
  client.addMessage(
    'room-dm-carol',
    ChatMessage(
      id: 'dm-carol-7',
      from: 'demo-user',
      timestamp: t(335),
      text: 'Beautiful. Let me know when you next play — I want to come watch.',
      referencedMessageId: 'dm-carol-6',
      messageType: MessageType.reply,
      receipt: ReceiptStatus.read,
    ),
  );
  client.addMessage(
    'room-dm-carol',
    ChatMessage(
      id: 'dm-carol-8',
      from: 'carol',
      timestamp: t(110),
      text: 'Saturday quarterfinal at 10am. Bring coffee.',
    ),
  );
}

// ---------------------------------------------------------------------------
// Groups
// ---------------------------------------------------------------------------

void _seedGroupTennis(MockChatClient client, DateTime Function(int) t) {
  client.seedRoom(
    const ChatRoom(
      id: 'room-group-tennis',
      name: 'Tennis crew',
      audience: RoomAudience.contacts,
      members: ['demo-user', 'alice', 'bob', 'carol'],
      avatarUrl: 'asset:assets/avatars/tennis.jpg',
    ),
  );

  client.addMessage(
    'room-group-tennis',
    ChatMessage(
      id: 'tn-1',
      from: 'bob',
      timestamp: t(300),
      text: 'Doubles match this Saturday at 9am — who is in?',
    ),
  );
  client.addMessage(
    'room-group-tennis',
    ChatMessage(
      id: 'tn-2',
      from: 'carol',
      timestamp: t(295),
      text: 'In!',
      referencedMessageId: 'tn-1',
      messageType: MessageType.reply,
      metadata: const {
        '_reactions': {'👍': 2},
        '_reactionUsers': {
          '👍': ['demo-user', 'alice'],
        },
      },
    ),
  );
  client.addMessage(
    'room-group-tennis',
    ChatMessage(
      id: 'tn-3',
      from: 'alice',
      timestamp: t(292),
      text: 'Also in. Bringing the new racket, finally restrung it.',
    ),
  );
  client.addMessage(
    'room-group-tennis',
    ChatMessage(
      id: 'tn-4',
      from: 'demo-user',
      timestamp: t(290),
      text: 'Court 3 should be free at that time. Booked it.',
      receipt: ReceiptStatus.read,
    ),
  );
  client.addMessage(
    'room-group-tennis',
    ChatMessage(
      id: 'tn-5',
      from: 'alice',
      timestamp: t(280),
      text: '',
      messageType: MessageType.attachment,
      attachmentUrl: 'https://picsum.photos/seed/new-racket/720/540',
      mimeType: 'image/jpeg',
    ),
  );
  client.addMessage(
    'room-group-tennis',
    ChatMessage(
      id: 'tn-6',
      from: 'bob',
      timestamp: t(278),
      text: 'Looks heavy. Wider beam too?',
      referencedMessageId: 'tn-5',
      messageType: MessageType.reply,
    ),
  );
  client.addMessage(
    'room-group-tennis',
    ChatMessage(
      id: 'tn-7',
      from: 'alice',
      timestamp: t(275),
      text: '305g unstrung, 16x19. Plays heavier than it weighs, honestly.',
    ),
  );
  client.addMessage(
    'room-group-tennis',
    ChatMessage(
      id: 'tn-8',
      from: 'carol',
      timestamp: t(260),
      text: '',
      messageType: MessageType.audio,
      attachmentUrl: 'asset:assets/audio/tn-8.wav',
      mimeType: 'audio/wav',
      metadata: const {
        'duration': 4071,
        'waveform': [
          82,
          52,
          100,
          89,
          33,
          89,
          41,
          82,
          69,
          26,
          96,
          79,
          84,
          74,
          80,
          70,
          77,
          68,
          17,
          2,
          40,
          89,
          98,
          97,
          97,
          86,
          47,
          81,
          24,
          90,
          79,
          41,
        ],
      },
    ),
  );
  client.addMessage(
    'room-group-tennis',
    ChatMessage(
      id: 'tn-9',
      from: 'demo-user',
      timestamp: t(250),
      text:
          'Stats from the last club tournament: '
          'https://www.atptour.com/en/stats',
      metadata: const {
        'linkUrl': 'https://www.atptour.com/en/stats',
        'linkTitle': 'ATP Tour — Stats Leaderboard',
        'linkDescription':
            'Season-long stats: aces, return points won, break points '
            'converted. Useful for setting realistic targets.',
        'linkImage': 'https://picsum.photos/seed/atp-stats/600/315',
      },
      receipt: ReceiptStatus.read,
    ),
  );
  client.addMessage(
    'room-group-tennis',
    ChatMessage(
      id: 'tn-10',
      from: 'bob',
      timestamp: t(240),
      // `@alice` triggers the SDK's mention parser (see
      // `markdown_parser.dart`): the token is highlighted with
      // `theme.bubble.mentionColor` and can be tapped via
      // `onTapMention`. Kept on a real conversational message so
      // the demo shows mentions without dedicating a paragraph to
      // them.
      text: '@alice practice on Wednesday before the match?',
    ),
  );
  client.addMessage(
    'room-group-tennis',
    ChatMessage(
      id: 'tn-11',
      from: 'alice',
      timestamp: t(235),
      text: 'Tuesday works better for me — coaching session on Wednesday.',
    ),
  );
  client.addMessage(
    'room-group-tennis',
    ChatMessage(
      id: 'tn-12',
      from: 'carol',
      timestamp: t(230),
      text: 'Tuesday 7pm, court 5?',
      metadata: const {
        '_reactions': {'✅': 3},
        '_reactionUsers': {
          '✅': ['demo-user', 'alice', 'bob'],
        },
      },
    ),
  );
  client.addMessage(
    'room-group-tennis',
    ChatMessage(
      id: 'tn-13',
      from: 'demo-user',
      timestamp: t(55),
      text: 'Done. See you all Tuesday.',
      receipt: ReceiptStatus.read,
    ),
  );
}

void _seedGroupEngineering(MockChatClient client, DateTime Function(int) t) {
  client.seedRoom(
    const ChatRoom(
      id: 'room-group-engineering',
      name: 'Q4 release',
      audience: RoomAudience.contacts,
      members: ['demo-user', 'alice', 'bob', 'carol'],
      avatarUrl: 'asset:assets/avatars/engineering.jpg',
    ),
  );

  client.addMessage(
    'room-group-engineering',
    ChatMessage(
      id: 'eng-1',
      from: 'bob',
      timestamp: t(720),
      text: 'Demo prep starts today — who can take which surface?',
    ),
  );
  client.addMessage(
    'room-group-engineering',
    ChatMessage(
      id: 'eng-2',
      from: 'demo-user',
      timestamp: t(715),
      text:
          "I'll wrap the chat list polish — mostly avatar + last-message "
          'preview tweaks.',
      receipt: ReceiptStatus.read,
    ),
  );
  client.addMessage(
    'room-group-engineering',
    ChatMessage(
      id: 'eng-3',
      from: 'carol',
      timestamp: t(710),
      text: 'I can own the notifications module + push delivery checks.',
      referencedMessageId: 'eng-1',
      messageType: MessageType.reply,
    ),
  );
  client.addMessage(
    'room-group-engineering',
    ChatMessage(
      id: 'eng-4',
      from: 'alice',
      timestamp: t(705),
      text: "I'll do the integration tests + the demo script.",
    ),
  );
  client.addMessage(
    'room-group-engineering',
    ChatMessage(
      id: 'eng-5',
      from: 'bob',
      timestamp: t(680),
      text: 'Mockup of the new room header — feedback welcome:',
    ),
  );
  client.addMessage(
    'room-group-engineering',
    ChatMessage(
      id: 'eng-6',
      from: 'bob',
      timestamp: t(679),
      text: '',
      messageType: MessageType.attachment,
      attachmentUrl: 'https://picsum.photos/seed/ui-mockup/900/600',
      mimeType: 'image/jpeg',
    ),
  );
  client.addMessage(
    'room-group-engineering',
    ChatMessage(
      id: 'eng-7',
      from: 'demo-user',
      timestamp: t(675),
      text: 'Looks clean. The connection indicator is a nice touch.',
      referencedMessageId: 'eng-6',
      messageType: MessageType.reply,
      receipt: ReceiptStatus.read,
      metadata: const {
        '_reactions': {'🎨': 1, '👍': 2},
        '_reactionUsers': {
          '🎨': ['carol'],
          '👍': ['alice', 'bob'],
        },
      },
    ),
  );
  client.addMessage(
    'room-group-engineering',
    ChatMessage(
      id: 'eng-8',
      from: 'alice',
      timestamp: t(650),
      text: '',
      messageType: MessageType.audio,
      attachmentUrl: 'asset:assets/audio/eng-8.wav',
      mimeType: 'audio/wav',
      metadata: const {
        'duration': 5013,
        'waveform': [
          79,
          54,
          86,
          72,
          62,
          65,
          64,
          56,
          85,
          54,
          2,
          59,
          100,
          78,
          66,
          99,
          65,
          64,
          49,
          60,
          83,
          32,
          2,
          47,
          98,
          82,
          76,
          87,
          56,
          82,
          70,
          19,
        ],
      },
    ),
  );
  client.addMessage(
    'room-group-engineering',
    ChatMessage(
      id: 'eng-9',
      from: 'bob',
      timestamp: t(640),
      text:
          'API reference for tomorrow: '
          'https://docs.example.com/api/v0.4',
      metadata: const {
        'linkUrl': 'https://docs.example.com/api/v0.4',
        'linkTitle': 'Noma Chat — API v0.4 Reference',
        'linkDescription':
            'Endpoint catalog with examples, plus the new realtime event '
            'topology.',
        'linkImage': 'https://picsum.photos/seed/api-docs/600/315',
      },
    ),
  );
  client.addMessage(
    'room-group-engineering',
    ChatMessage(
      id: 'eng-10',
      from: 'carol',
      timestamp: t(60),
      text:
          '@bob @alice standup tomorrow at 10am — please come with a status update.',
      metadata: const {
        '_reactions': {'📌': 3},
        '_reactionUsers': {
          '📌': ['demo-user', 'alice', 'bob'],
        },
      },
    ),
  );
  client.addMessage(
    'room-group-engineering',
    ChatMessage(
      id: 'eng-11',
      from: 'demo-user',
      timestamp: t(20),
      text: 'Tomorrow 10am ✓',
      isEdited: true,
      receipt: ReceiptStatus.read,
    ),
  );
}

// ---------------------------------------------------------------------------
// Announcements
// ---------------------------------------------------------------------------

void _seedAnnouncements(MockChatClient client, DateTime Function(int) t) {
  client.seedRoom(
    const ChatRoom(
      id: 'room-news',
      name: 'Announcements',
      audience: RoomAudience.public,
      members: ['demo-user', 'newsroom'],
      custom: {'type': 'announcement'},
      avatarUrl: 'asset:assets/avatars/announcements.jpg',
    ),
  );

  client.addMessage(
    'room-news',
    ChatMessage(
      id: 'n-1',
      from: 'newsroom',
      timestamp: t(60 * 36),
      text:
          'Welcome to the announcements channel. Only admins post here — '
          'replies and reactions are open to everyone.',
    ),
  );
  client.addMessage(
    'room-news',
    ChatMessage(
      id: 'n-2',
      from: 'newsroom',
      timestamp: t(60 * 12),
      text:
          'Scheduled maintenance window: Friday 03:00–04:00 UTC. Expect a '
          'brief reconnect blip but no data loss.',
    ),
  );
  client.addMessage(
    'room-news',
    ChatMessage(
      id: 'n-3',
      from: 'newsroom',
      timestamp: t(60 * 6),
      text:
          'v0.4.0 release notes — link preview, voice notes, reactions '
          'rework, broadcast rooms: https://example.com/release-notes-0-4',
      metadata: const {
        'linkUrl': 'https://example.com/release-notes-0-4',
        'linkTitle': 'Noma Chat — Release Notes v0.4.0',
        'linkDescription':
            'Highlights: link preview composer, voice messages, reactions '
            'viewer, and broadcast rooms.',
        'linkImage': 'https://picsum.photos/seed/release-notes/600/315',
      },
    ),
  );
}
