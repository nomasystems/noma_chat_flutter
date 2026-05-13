/// Plug & play chat package for Flutter, backed by the Noma Chat backend.
///
/// Exposes three layers, each usable independently:
///
/// - **SDK**: REST + real-time client ([ChatClient] / [NomaChatClient]),
///   sub-APIs per domain (users, rooms, members, messages, contacts,
///   presence, attachments), data models, and offline cache.
/// - **UI Adapter**: [ChatUiAdapter] glues the SDK to UI controllers
///   ([ChatController], [RoomListController], [MessageSearchController]),
///   exposing reactive state ready for widgets.
/// - **UI Kit**: ready-to-use widgets ([ChatView], [MessageList],
///   [RoomListView], pickers, bubbles…) themed via [ChatTheme].
///
/// The typical entry point is [NomaChat.create], which wires all three:
///
/// ```dart
/// final chat = await NomaChat.create(
///   baseUrl: 'https://chat.myapp.com/v1',
///   realtimeUrl: 'https://chat.myapp.com',
///   tokenProvider: () => authService.getToken(),
///   currentUser: ChatUser(id: userId, displayName: name),
/// );
/// await chat.connect();
/// ```
library;

// === SDK: Client ===
export 'src/client/chat_client.dart';
export 'src/client/noma_chat_client.dart';
export 'src/client/noma_chat_facade.dart';

// === SDK: Cache cipher (re-export for plug & play encryption) ===
// ignore: depend_on_referenced_packages
export 'package:hive_ce/hive_ce.dart' show HiveAesCipher, HiveCipher;

// === SDK: Config ===
export 'src/config/chat_config.dart';

// === SDK: Sub-APIs ===
export 'src/api/auth_api.dart';
export 'src/api/users_api.dart';
export 'src/api/rooms_api.dart';
export 'src/api/members_api.dart';
export 'src/api/messages_api.dart';
export 'src/api/contacts_api.dart';
export 'src/api/presence_api.dart';
export 'src/api/attachments_api.dart';

// === SDK: Core ===
export 'src/core/result.dart';
export 'src/core/pagination.dart';

// === SDK: Models ===
export 'src/models/attachment.dart';
export 'src/models/user.dart';
export 'src/models/room.dart';
export 'src/models/message.dart';
export 'src/models/presence.dart';
export 'src/models/contact.dart';
export 'src/models/user_rooms.dart';
export 'src/models/unread_room.dart';
export 'src/models/invited_room.dart';
export 'src/models/read_receipt.dart';
export 'src/models/scheduled_message.dart';
export 'src/models/health_status.dart';
export 'src/models/room_user.dart';
export 'src/models/reaction.dart';
export 'src/models/pin.dart';
export 'src/models/report.dart';
export 'src/models/managed_user_config.dart';
export 'src/models/forward_info.dart';

// === SDK: Events ===
export 'src/events/chat_event.dart';

// === SDK: Auth interceptors (for custom auth) ===
export 'src/_internal/http/auth_interceptor.dart';
export 'src/_internal/http/bearer_auth_interceptor.dart';
export 'src/_internal/http/basic_auth_interceptor.dart';

// === SDK: Advanced configuration ===
export 'src/_internal/cache/cache_config.dart';
export 'src/_internal/cache/cache_policy.dart';
export 'src/_internal/cache/local_datasource.dart';
export 'src/_internal/cache/memory_datasource.dart';
export 'src/_internal/http/retry_config.dart';

// === SDK: Mock ===
export 'src/mock/mock_chat_client.dart';

// === Cache: Hive implementation ===
export 'src/cache/hive_chat_datasource.dart';

// === UI: Models ===
export 'src/ui/models/reaction_user.dart';
export 'src/ui/models/room_list_item.dart';
export 'src/ui/models/suggested_contact.dart';
export 'src/ui/models/voice_message_data.dart';

// === UI: Adapter ===
export 'src/ui/adapter/chat_ui_adapter.dart';
export 'src/ui/adapter/operation_error.dart';

// === UI: Controllers ===
export 'src/ui/controller/audio_playback_coordinator.dart';
export 'src/ui/controller/chat_controller.dart';
export 'src/ui/controller/room_list_controller.dart';
export 'src/ui/controller/message_search_controller.dart';
export 'src/ui/controller/voice_recording_controller.dart';

// === UI: Theme ===
export 'src/ui/theme/chat_theme.dart';

// === UI: Localization ===
export 'src/ui/l10n/chat_ui_localizations.dart';

// === UI: Utils ===
export 'src/ui/utils/date_formatter.dart';
export 'src/ui/utils/last_message_preview.dart';
export 'src/ui/utils/url_detector.dart';
export 'src/ui/utils/markdown_parser.dart';
export 'src/ui/utils/read_receipts_helper.dart';

// === UI: Chat view widgets ===
export 'src/ui/widgets/chat_view.dart';
export 'src/ui/widgets/message_list.dart';
export 'src/ui/widgets/message_input.dart';
export 'src/ui/widgets/message_bubble.dart';
export 'src/ui/widgets/bubbles/text_bubble.dart';
export 'src/ui/widgets/bubbles/image_bubble.dart';
export 'src/ui/widgets/bubbles/audio_bubble.dart';
export 'src/ui/widgets/bubbles/video_bubble.dart';
export 'src/ui/widgets/bubbles/file_bubble.dart';
export 'src/ui/widgets/bubbles/location_bubble.dart';
export 'src/ui/models/link_preview_metadata.dart';
export 'src/ui/services/link_preview_fetcher.dart';
export 'src/ui/widgets/bubbles/link_preview_bubble.dart';
export 'src/ui/widgets/bubbles/forwarded_bubble.dart';
export 'src/ui/widgets/message_status_icon.dart';
export 'src/ui/widgets/date_separator.dart';
export 'src/ui/widgets/reply_preview.dart';
export 'src/ui/widgets/floating_reaction_picker.dart';
export 'src/ui/widgets/full_emoji_picker.dart';
export 'src/ui/widgets/reaction_bar.dart';
export 'src/ui/widgets/reaction_detail_sheet.dart';
export 'src/ui/widgets/reaction_picker.dart';
export 'src/ui/widgets/typing_indicator.dart';
export 'src/ui/widgets/image_viewer.dart';
export 'src/ui/widgets/attachment_picker_sheet.dart';
export 'src/ui/widgets/voice_recorder_button.dart';
export 'src/ui/widgets/voice_recorder_overlay.dart';
export 'src/ui/widgets/waveform_display.dart';
export 'src/ui/widgets/message_context_menu.dart';
export 'src/ui/widgets/scroll_to_bottom_button.dart';
export 'src/ui/widgets/thread_view.dart';
export 'src/ui/widgets/message_search_delegate.dart';
export 'src/ui/widgets/read_receipt_avatars.dart';
export 'src/ui/widgets/pinned_messages_banner.dart';

// === UI: Room list widgets ===
export 'src/ui/widgets/contact_suggestions_bar.dart';
export 'src/ui/widgets/room_list_view.dart';
export 'src/ui/widgets/room_tile.dart';
export 'src/ui/widgets/unread_badge.dart';
export 'src/ui/widgets/room_search_bar.dart';
export 'src/ui/widgets/room_context_menu.dart';
export 'src/ui/widgets/room_list_header.dart';

// === UI: Shared widgets ===
export 'src/ui/widgets/user_avatar.dart';
export 'src/ui/widgets/connection_banner.dart';
export 'src/ui/widgets/docs_list_view.dart';
export 'src/ui/widgets/empty_state.dart';
export 'src/ui/widgets/links_list_view.dart';
export 'src/ui/widgets/member_list_view.dart';
export 'src/ui/widgets/user_profile_view.dart';
export 'src/ui/widgets/mention_overlay.dart';
export 'src/ui/widgets/media_gallery_view.dart';
export 'src/ui/widgets/swipe_to_reply.dart';
export 'src/ui/widgets/typing_status_text.dart';

// === UI: Pages ===
export 'src/ui/pages/media_gallery_page.dart';
