import 'package:noma_chat/noma_chat.dart';

/// Seeds the mock client with a small set of rooms and messages, enough to
/// exercise the room list, chat view, search, pins and most bubble types.
void seedDemoData(MockChatClient client) {
  final now = DateTime.now();
  DateTime t(int minutesAgo) => now.subtract(Duration(minutes: minutesAgo));

  // --- Direct message ---------------------------------------------------
  client.seedRoom(
    const ChatRoom(
      id: 'room-dm',
      name: 'Alice',
      audience: RoomAudience.contacts,
      members: ['demo-user', 'alice'],
    ),
  );
  client.addMessage(
    'room-dm',
    ChatMessage(
      id: 'dm-1',
      from: 'alice',
      timestamp: t(60),
      text: 'Hey! ¿Has visto el plan de mañana?',
    ),
  );
  client.addMessage(
    'room-dm',
    ChatMessage(
      id: 'dm-2',
      from: 'demo-user',
      timestamp: t(58),
      text: 'Sí, voy a apuntarme. ¿Tú?',
    ),
  );
  client.addMessage(
    'room-dm',
    ChatMessage(
      id: 'dm-3',
      from: 'alice',
      timestamp: t(55),
      text: 'Confirmado, nos vemos allí ✌️',
      receipt: ReceiptStatus.read,
    ),
  );

  // --- Group ------------------------------------------------------------
  client.seedRoom(
    const ChatRoom(
      id: 'room-group',
      name: 'Equipo cervecero',
      audience: RoomAudience.contacts,
      members: ['demo-user', 'alice', 'bob', 'carol'],
    ),
  );
  client.addMessage(
    'room-group',
    ChatMessage(
      id: 'g-1',
      from: 'bob',
      timestamp: t(120),
      text: 'Quedamos a las 20:00 en el bar de siempre.',
    ),
  );
  client.addMessage(
    'room-group',
    ChatMessage(
      id: 'g-2',
      from: 'carol',
      timestamp: t(115),
      text: 'Llevo yo las **patatas bravas** 🍟',
    ),
  );
  client.addMessage(
    'room-group',
    ChatMessage(
      id: 'g-3',
      from: 'demo-user',
      timestamp: t(110),
      text: 'Perfecto, hasta luego.',
      receipt: ReceiptStatus.read,
    ),
  );
  client.addMessage(
    'room-group',
    ChatMessage(
      id: 'g-4',
      from: 'alice',
      timestamp: t(90),
      text: '',
      messageType: MessageType.attachment,
      attachmentUrl: 'https://picsum.photos/seed/beers/600/400',
      mimeType: 'image/jpeg',
    ),
  );
  client.addMessage(
    'room-group',
    ChatMessage(
      id: 'g-5',
      from: 'bob',
      timestamp: t(80),
      text: '¡Qué pinta!',
      referencedMessageId: 'g-4',
      messageType: MessageType.reply,
    ),
  );

  // --- Announcement -----------------------------------------------------
  client.seedRoom(
    const ChatRoom(
      id: 'room-news',
      name: 'Anuncios',
      audience: RoomAudience.public,
      members: ['demo-user', 'newsroom'],
      custom: {'type': 'announcement'},
    ),
  );
  client.addMessage(
    'room-news',
    ChatMessage(
      id: 'n-1',
      from: 'newsroom',
      timestamp: t(60 * 24),
      text: 'Bienvenidos al canal de anuncios. Aquí solo postean admins.',
    ),
  );
  client.addMessage(
    'room-news',
    ChatMessage(
      id: 'n-2',
      from: 'newsroom',
      timestamp: t(30),
      text: 'Mantenimiento programado: viernes 03:00-04:00.',
    ),
  );
}
