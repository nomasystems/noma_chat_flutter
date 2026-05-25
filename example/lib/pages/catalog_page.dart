import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

final _kTs = DateTime(2025, 6, 1, 14, 30);

/// Storybook-style visual catalog of noma_chat UI components.
///
/// Renders each major widget with representative hardcoded data so
/// designers and contributors can inspect look-and-feel without
/// running a live chat session.
class CatalogPage extends StatelessWidget {
  const CatalogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Widget Catalog')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: const [
          _SectionHeader('MessageStatusIcon'),
          _StatusIconSection(),
          _SectionHeader('DateSeparator'),
          _DateSeparatorSection(),
          _SectionHeader('UnreadDivider'),
          _UnreadDividerSection(),
          _SectionHeader('UserAvatar'),
          _UserAvatarSection(),
          _SectionHeader('MessageBubble — outgoing'),
          _OutgoingBubblesSection(),
          _SectionHeader('MessageBubble — incoming'),
          _IncomingBubblesSection(),
          _SectionHeader('MessageBubble — special states'),
          _SpecialBubblesSection(),
          _SectionHeader('MessageBubble — dark theme'),
          _DarkThemeBubblesSection(),
          SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Divider(height: 8),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// MessageStatusIcon
// ---------------------------------------------------------------------------

class _StatusIconSection extends StatelessWidget {
  const _StatusIconSection();

  @override
  Widget build(BuildContext context) {
    const theme = ChatTheme.defaults;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _LabelledWidget(
            label: 'sent',
            child: MessageStatusIcon(
              status: ReceiptStatus.sent,
              theme: theme,
              size: 20,
            ),
          ),
          _LabelledWidget(
            label: 'delivered',
            child: MessageStatusIcon(
              status: ReceiptStatus.delivered,
              theme: theme,
              size: 20,
            ),
          ),
          _LabelledWidget(
            label: 'read',
            child: MessageStatusIcon(
              status: ReceiptStatus.read,
              theme: theme,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// DateSeparator
// ---------------------------------------------------------------------------

class _DateSeparatorSection extends StatelessWidget {
  const _DateSeparatorSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DateSeparator(
          date: DateTime(2025, 3, 15),
          theme: ChatTheme.lightPreset(),
        ),
        DateSeparator(date: DateTime.now(), theme: ChatTheme.lightPreset()),
        DateSeparator(
          date: DateTime.now().subtract(const Duration(days: 1)),
          theme: ChatTheme.lightPreset(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// UnreadDivider
// ---------------------------------------------------------------------------

class _UnreadDividerSection extends StatelessWidget {
  const _UnreadDividerSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        UnreadDivider(count: 1, theme: ChatTheme.lightPreset()),
        UnreadDivider(count: 5, theme: ChatTheme.lightPreset()),
        UnreadDivider(count: 42, theme: ChatTheme.lightPreset()),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// UserAvatar
// ---------------------------------------------------------------------------

class _UserAvatarSection extends StatelessWidget {
  const _UserAvatarSection();

  @override
  Widget build(BuildContext context) {
    const theme = ChatTheme.defaults;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        children: [
          _LabelledWidget(
            label: 'initials',
            child: const UserAvatar(
              displayName: 'Alice Smith',
              size: 40,
              theme: theme,
            ),
          ),
          _LabelledWidget(
            label: 'online',
            child: const UserAvatar(
              displayName: 'Bob',
              size: 40,
              isOnline: true,
              theme: theme,
            ),
          ),
          _LabelledWidget(
            label: 'offline',
            child: const UserAvatar(
              displayName: 'Carol',
              size: 40,
              isOnline: false,
              theme: theme,
            ),
          ),
          _LabelledWidget(
            label: 'presence: busy',
            child: const UserAvatar(
              displayName: 'Dave',
              size: 40,
              presenceStatus: PresenceStatus.busy,
              theme: theme,
            ),
          ),
          _LabelledWidget(
            label: 'presence: away',
            child: const UserAvatar(
              displayName: 'Eve',
              size: 40,
              presenceStatus: PresenceStatus.away,
              theme: theme,
            ),
          ),
          _LabelledWidget(
            label: 'large',
            child: const UserAvatar(
              displayName: 'Frank',
              size: 64,
              isOnline: true,
              theme: theme,
            ),
          ),
          _LabelledWidget(
            label: 'emoji name',
            child: const UserAvatar(
              displayName: '🎉 Party',
              size: 40,
              theme: theme,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// MessageBubble — outgoing
// ---------------------------------------------------------------------------

class _OutgoingBubblesSection extends StatelessWidget {
  const _OutgoingBubblesSection();

  @override
  Widget build(BuildContext context) {
    final theme = ChatTheme.lightPreset();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MessageBubble(
          message: ChatMessage(
            id: 'out-1',
            from: 'me',
            timestamp: _kTs,
            text: 'Hey, how are you?',
          ),
          isOutgoing: true,
          status: ReceiptStatus.sent,
          theme: theme,
        ),
        MessageBubble(
          message: ChatMessage(
            id: 'out-2',
            from: 'me',
            timestamp: _kTs,
            text: 'This is a delivered message.',
          ),
          isOutgoing: true,
          status: ReceiptStatus.delivered,
          theme: theme,
        ),
        MessageBubble(
          message: ChatMessage(
            id: 'out-3',
            from: 'me',
            timestamp: _kTs,
            text: 'Read! Both ticks turn blue.',
          ),
          isOutgoing: true,
          status: ReceiptStatus.read,
          theme: theme,
        ),
        MessageBubble(
          message: ChatMessage(
            id: 'out-4',
            from: 'me',
            timestamp: _kTs,
            text: 'Pending — clock icon.',
          ),
          isOutgoing: true,
          isPending: true,
          theme: theme,
        ),
        MessageBubble(
          message: ChatMessage(
            id: 'out-5',
            from: 'me',
            timestamp: _kTs,
            text: 'Failed to send — tap to retry.',
          ),
          isOutgoing: true,
          isFailed: true,
          theme: theme,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// MessageBubble — incoming
// ---------------------------------------------------------------------------

class _IncomingBubblesSection extends StatelessWidget {
  const _IncomingBubblesSection();

  @override
  Widget build(BuildContext context) {
    final theme = ChatTheme.lightPreset();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MessageBubble(
          message: ChatMessage(
            id: 'in-1',
            from: 'alice',
            timestamp: _kTs,
            text: 'Hi there!',
          ),
          isOutgoing: false,
          senderName: 'Alice',
          theme: theme,
        ),
        MessageBubble(
          message: ChatMessage(
            id: 'in-2',
            from: 'alice',
            timestamp: _kTs,
            text: 'A second message from the same sender — no name repeat.',
            isEdited: true,
          ),
          isOutgoing: false,
          senderName: 'Alice',
          isFirstInGroup: false,
          theme: theme,
        ),
        MessageBubble(
          message: ChatMessage(
            id: 'in-3',
            from: 'alice',
            timestamp: _kTs,
            text: 'Pinned message with the pin badge.',
          ),
          isOutgoing: false,
          senderName: 'Alice',
          isPinned: true,
          theme: theme,
        ),
        MessageBubble(
          message: ChatMessage(
            id: 'in-4',
            from: 'alice',
            timestamp: _kTs,
            text: 'Message with inline avatar.',
          ),
          isOutgoing: false,
          senderName: 'Alice',
          avatarWidget: const CircleAvatar(
            radius: 14,
            child: Text('A', style: TextStyle(fontSize: 10)),
          ),
          theme: theme,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// MessageBubble — special states
// ---------------------------------------------------------------------------

class _SpecialBubblesSection extends StatelessWidget {
  const _SpecialBubblesSection();

  @override
  Widget build(BuildContext context) {
    final theme = ChatTheme.lightPreset();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MessageBubble(
          message: ChatMessage(
            id: 'sp-1',
            from: 'alice',
            timestamp: _kTs,
            isDeleted: true,
          ),
          isOutgoing: false,
          senderName: 'Alice',
          theme: theme,
        ),
        MessageBubble(
          message: ChatMessage(
            id: 'sp-2',
            from: 'me',
            timestamp: _kTs,
            isDeleted: true,
          ),
          isOutgoing: true,
          theme: theme,
        ),
        MessageBubble(
          message: ChatMessage(
            id: 'sp-3',
            from: 'system',
            timestamp: _kTs,
            text: 'Alice joined the group.',
            isSystem: true,
          ),
          isOutgoing: false,
          theme: theme,
        ),
        MessageBubble(
          message: ChatMessage(
            id: 'sp-4',
            from: 'alice',
            timestamp: _kTs,
            text: 'Message with reactions.',
          ),
          isOutgoing: false,
          senderName: 'Alice',
          reactions: const {'👍': 3, '❤️': 1},
          theme: theme,
        ),
        MessageBubble(
          message: ChatMessage(
            id: 'sp-5',
            from: 'me',
            timestamp: _kTs,
            text: 'Highlighted message (e.g. search result).',
          ),
          isOutgoing: true,
          isHighlighted: true,
          status: ReceiptStatus.read,
          theme: theme,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// MessageBubble — dark theme
// ---------------------------------------------------------------------------

class _DarkThemeBubblesSection extends StatelessWidget {
  const _DarkThemeBubblesSection();

  @override
  Widget build(BuildContext context) {
    final darkTheme = ChatTheme.darkPreset();
    return ColoredBox(
      color: const Color(0xFF121212),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MessageBubble(
            message: ChatMessage(
              id: 'dk-1',
              from: 'alice',
              timestamp: _kTs,
              text: 'Incoming — dark theme.',
            ),
            isOutgoing: false,
            senderName: 'Alice',
            theme: darkTheme,
          ),
          MessageBubble(
            message: ChatMessage(
              id: 'dk-2',
              from: 'me',
              timestamp: _kTs,
              text: 'Outgoing — dark theme.',
            ),
            isOutgoing: true,
            status: ReceiptStatus.read,
            theme: darkTheme,
          ),
          MessageBubble(
            message: ChatMessage(
              id: 'dk-3',
              from: 'system',
              timestamp: _kTs,
              text: 'System message — dark theme.',
              isSystem: true,
            ),
            isOutgoing: false,
            theme: darkTheme,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _LabelledWidget extends StatelessWidget {
  const _LabelledWidget({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}
