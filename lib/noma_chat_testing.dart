/// Testing utilities for `noma_chat`.
///
/// Import this barrel only from tests / development tools — production
/// apps should depend on `package:noma_chat/noma_chat.dart` alone, which
/// no longer re-exports the in-memory mock client.
///
/// ```dart
/// import 'package:noma_chat/noma_chat.dart';
/// import 'package:noma_chat/noma_chat_testing.dart';
///
/// void main() {
///   final client = MockChatClient();
///   client.seedUser(ChatUser(id: 'u1', displayName: 'Alice'));
///   // ...
/// }
/// ```
///
/// Keeping the mock out of the primary barrel keeps autocomplete and the
/// public surface clean for production consumers.
library;

export 'src/mock/mock_chat_client.dart';
