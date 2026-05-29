/// Convenience builders for the most common mock objects used across the
/// test suite. New tests should reach for these instead of hand-rolling a
/// `MockChatClient` + `ChatUiAdapter` pair every time.
///
/// Heavier fakes (HTTP responses, transport simulators, audio recorders)
/// live alongside the tests that exercise them — keeping this file tiny
/// keeps the import surface small and avoids leaking optional deps.
library;

import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/noma_chat_testing.dart';

import 'fixtures.dart';

/// Builds and returns a `MockChatClient` configured for the [fixtureUserMe]
/// identity. Caller is responsible for calling `dispose()`.
MockChatClient buildMockClient({String currentUserId = 'u1'}) {
  return MockChatClient(currentUserId: currentUserId);
}

/// Builds a `ChatUiAdapter` wired to a fresh `MockChatClient`. Returns
/// both so the caller can interact with either side. Pass to
/// `addTearDown(adapter.dispose); addTearDown(client.dispose);`.
({MockChatClient client, ChatUiAdapter adapter}) buildAdapterWithMockClient({
  ChatUser currentUser = fixtureUserMe,
}) {
  final client = buildMockClient(currentUserId: currentUser.id);
  final adapter = ChatUiAdapter(client: client, currentUser: currentUser);
  return (client: client, adapter: adapter);
}
