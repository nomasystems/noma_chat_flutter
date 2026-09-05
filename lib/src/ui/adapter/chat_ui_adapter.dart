library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show NetworkImage;
import 'package:intl/intl.dart';
import '../../_internal/cache/cache_manager.dart' show MetricCallback;
import '../../api/members_api.dart' show MembersApi;
import '../../cache/cache_policy.dart';
import '../../cache/local_datasource.dart';
import '../../client/chat_client.dart';
import '../../client/noma_chat_facade.dart';
import '../../config/lifecycle_policy.dart';
import '../../core/pagination.dart';
import '../../core/result.dart';
import '../../events/chat_event.dart';
import '../../models/attachment.dart';
import '../../models/chat_analytics_event.dart';
import '../../models/message.dart';
import '../../models/pin.dart';
import '../../models/presence.dart';
import '../../models/reaction.dart';
import '../../models/read_receipt.dart';
import '../../models/room.dart';
import '../../models/room_user.dart';
import '../../models/starred_message.dart';
import '../../models/user.dart';
import '../../observability/chat_logger.dart';
import '../../storage/avatar_storage.dart';
import '../../utils/chat_export.dart';
import '../controller/chat_controller.dart';
import '../controller/room_list_controller.dart';
import '../l10n/chat_ui_localizations.dart';
import '../models/attachment_policy.dart';
import '../models/room_list_item.dart';
import '../models/send_retry_policy.dart';
import '../room_defaults.dart';
import '../services/attachment_pickers.dart';
import '../services/attachment_bytes_loader.dart';
import '../services/attachment_url_resolver.dart';
import '../services/video_thumbnailer.dart';
import '../utils/last_message_preview.dart';
import '../utils/mime_classifier.dart';
import '../widgets/chat_room_options_menu.dart';
import '../widgets/chat_view.dart';
import 'operation_error.dart';
import 'room_title_resolver.dart';
import 'user_directory_resolver.dart';

import 'handlers/chat_event_router.dart';
import 'handlers/member_event_handler.dart';
import 'handlers/optimistic_handler.dart';
import 'services/presence_registry.dart';
import 'handlers/room_enricher.dart';
import 'handlers/room_list_mutator.dart';
import 'services/attachment_upload_cancel_registry.dart';
import 'services/failed_upload_registry.dart';
import 'services/blocked_users_registry.dart';
import 'services/chat_controller_registry.dart';
import 'services/chat_lifecycle_observer.dart';
import 'services/connection_lifecycle.dart';
import 'services/delivered_confirmation_coordinator.dart';
import 'services/dm_contact_registry.dart';
import 'services/room_roster_registry.dart';
import 'services/host_user_directory.dart';
import 'services/mark_as_read_coordinator.dart';
import 'services/operation_hub.dart';
import 'services/pending_reactions_registry.dart';
import 'services/temp_id_minter.dart';
import 'services/typing_timer_registry.dart';
import 'services/user_cache_service.dart';
import 'services/voice_upload_registry.dart';

part 'api/contacts_controller.dart';
part 'api/dm_controller.dart';
part 'api/messages_controller.dart';
part 'api/profile_controller.dart';
part 'api/rooms_controller.dart';
part 'handlers/adapter_profile_actions.dart';
part 'handlers/adapter_session_lifecycle.dart';

/// Adapter-local helper for best-effort cache writes wrapped in
/// [unawaited]. Returns a [ChatFailureResult] so the new
/// `Future<ChatResult<void>>` signature of [ChatLocalDatasource] mutators
/// is satisfied — `unawaited` still drops the outcome, preserving the
/// previous fire-and-forget semantics. The cache impls bundled with
/// the SDK never throw, but a custom datasource could; this keeps the
/// callsite quiet regardless.
ChatResult<void> _swallowCacheThrow(Object _) =>
    const ChatFailureResult<void>(UnexpectedFailure('cache mutator threw'));

/// Predicate the adapter uses to decide whether a room is a DM and therefore
/// should be tracked in the contact-to-room cache. When `null`, falls back to
/// `detail.type == RoomType.oneToOne`.
typedef IsDmRoomPredicate = bool Function(RoomDetail detail);

/// Host veto over the SDK's own membership banners ("Alice joined",
/// "You removed Bob", "Alice is now an admin").
///
/// Called with the room id and the event flavour — `user_joined`,
/// `user_left` or `user_role_changed` — just before the banner is
/// composed. Return `false` to drop it: the row is not shown and not
/// cached, so it does not reappear on the next open.
///
/// The point of the per-room argument is that the answer is rarely the
/// same everywhere: a host whose backend posts its own membership
/// message into group rooms wants the SDK quiet there and still wants
/// the banner in a one-to-one room, where nothing else announces it.
typedef MembershipBannerFilter = bool Function(String roomId, String eventType);

/// Context handed to a [RoomTitleResolver] when the adapter (re)computes the
/// effective title for a room. [detail] and [otherMembers] may be empty/null
/// during incremental enrichments (e.g. before the DM contact has been
/// resolved) — a robust resolver should tolerate that and either return
/// `null` (to defer) or operate on [currentItem] only.
///
/// [isDm] is the adapter's best current guess of whether this room is a
/// direct message. The adapter precomputes it via the [IsDmRoomPredicate]
/// when [detail] is available, or carries it forward from prior enrichment
/// state when only [otherMembers] is available. A custom resolver can ignore
/// it; the SDK's built-in default only fires when [isDm] is true.
// `RoomTitleContext` + `RoomTitleResolver` typedef were extracted to
// `lib/src/ui/adapter/room_title_resolver.dart` so the standalone
// `RoomEnricher` handler can import them without pulling in the
// entire adapter library.

/// An attachment the SDK re-encoded so it would fit under the size cap its
/// [AttachmentPolicy] sets.
///
/// The name and the type travel with the bytes because shrinking an image
/// changes both: a HEIC or a PNG that comes back as JPEG has to be sent as
/// `image/jpeg` under a `.jpg` name, or the backend stores a blob whose
/// declared content type its own bytes contradict.
@immutable
class ShrunkAttachment {
  const ShrunkAttachment({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
  });

  /// Re-encoded payload, ready to upload as it stands.
  final Uint8List bytes;

  /// MIME type [bytes] are now encoded in.
  final String mimeType;

  /// Name to send [bytes] under, extension included.
  final String fileName;
}

/// Reduces an outgoing image until it fits the size cap that applies to it.
///
/// Every path that sends a picked or captured image *to a room* runs its
/// bytes through this hook after the metadata scrub and before the send, so
/// a full-resolution camera shot leaves the device as a few hundred KB
/// instead of a few MB. An avatar does not: its crop step re-encodes what
/// it returns, and the result is a thumbnail either way.
///
/// The contract:
///
/// - **`null` means "send it untouched".** Not an error: it is the answer
///   for a payload already under the cap, for anything that must not be
///   re-encoded (every type that is not an image), and for a host that
///   turns shrinking off.
/// - **Never throws.** Shrinking is an optimisation; a decoder that fails
///   returns `null` and the original bytes still go out.
/// - **Answers under the cap.** Handing back bytes that are still over it
///   only moves the rejection further down the send.
///
/// Wired by default to [DefaultAttachmentShrinker]; hosts override it
/// through `ChatUiAdapter(attachmentShrinker: …)` when they have an encoder
/// of their own, or with [NoAttachmentShrinker] to send the bytes the user
/// picked untouched.
abstract class AttachmentShrinker {
  /// Re-encodes [bytes] — an attachment of type [mimeType] to be sent as
  /// [fileName] — so the result weighs at most [maxBytes]. Returns `null`
  /// when the payload should travel exactly as it came in.
  Future<ShrunkAttachment?> fit(
    Uint8List bytes, {
    required String mimeType,
    required int maxBytes,
    required String fileName,
  });
}

/// [AttachmentShrinker] that never re-encodes anything — the documented way
/// to upload precisely the bytes the user picked
/// (`ChatUiAdapter(attachmentShrinker: const NoAttachmentShrinker())`).
class NoAttachmentShrinker implements AttachmentShrinker {
  const NoAttachmentShrinker();

  @override
  Future<ShrunkAttachment?> fit(
    Uint8List bytes, {
    required String mimeType,
    required int maxBytes,
    required String fileName,
  }) async => null;
}

/// Bridges the [ChatClient] SDK with the UI components's controllers and widgets.
///
/// Subscribes to real-time events and routes them to the appropriate
/// [ChatController] or [RoomListController]. Provides high-level actions
/// (send, edit, delete, react) with optimistic UI updates.
class ChatUiAdapter {
  ChatUiAdapter({
    required this.client,
    required ChatUser currentUser,
    ChatUiLocalizations l10n = ChatUiLocalizations.en,
    this.onRoomsLoaded,
    this.isDmRoom,
    this.membershipBannerFilter,
    this.roomTitleResolver,
    this.userDirectoryResolver,
    this.userDirectoryTtl = const Duration(hours: 12),
    this.bootstrapCurrentUser = false,
    this.sendRetryPolicy = const SendRetryPolicy.firstSendOnly(),
    this.autoMarkAsRead = true,
    this.autoConfirmDelivery = true,
    this.manageAppLifecycle = true,
    this.lifecyclePolicy = const ChatLifecyclePolicy.standard(),
    this.enableReconnectResync = true,
    this.logLevel = ChatLogLevel.warn,
    this.logMessageContent = false,
    this.metricCallback,
    this.analyticsSink,
    this.roomRevalidateDebounce = const Duration(seconds: 5),
    Duration resyncDebounce = const Duration(seconds: 5),
    ChatLocalDatasource? cache,
    AvatarStorage? avatarStorage,
    VideoThumbnailer? videoThumbnailer,
    AttachmentShrinker? attachmentShrinker,
  }) : _cache = cache,
       _l10n = l10n,
       _l10nPinnedByHost = !identical(l10n, ChatUiLocalizations.en),
       _currentUser = currentUser,
       avatarStorage = avatarStorage ?? DefaultAvatarStorage(client),
       videoThumbnailer = videoThumbnailer ?? const NativeVideoThumbnailer(),
       attachmentShrinker =
           attachmentShrinker ?? const DefaultAttachmentShrinker(),
       roomListController = RoomListController(),
       _lifecycle = ConnectionLifecycle(),
       _resyncDebounce = resyncDebounce {
    roomListController.setParticipantNameResolver(_participantNamesFor);
    if (manageAppLifecycle) {
      _lifecycleObserver = ChatLifecycleObserver(
        policy: lifecyclePolicy,
        onResume: () => unawaited(connect()),
        onPause: () => unawaited(disconnect()),
      )..attach();
    }
  }

  final ChatClient client;

  // -- Sub-APIs -----------------------------------------------------
  //
  // Grouped facets of the adapter. Each one is a thin wrapper that
  // delegates to the corresponding top-level methods on the adapter
  // (which are now considered package-internal even though they are
  // still public Dart-wise). External consumers should always go
  // through these.

  /// Per-message operations — `load`, `send`, `edit`, `delete`,
  /// reactions, attachments, voice, threads, search, pin, etc.
  late final ChatMessagesController messages = ChatMessagesController(this);

  /// Room-level operations — `load`, `mute`/`unmute`, `pin`/`unpin`,
  /// `hide`/`unhide`, `leave`, `addMembers`, `updateConfig`,
  /// `createGroup`, etc.
  late final ChatRoomsController rooms = ChatRoomsController(this);

  /// Contact / blocked-users operations — `block`, `unblock`,
  /// `loadBlocked`, `pruneBlockedRooms`, `blockedUserIds`.
  late final ChatContactsController contacts = ChatContactsController(this);

  /// Current-user profile mutations — `update`, `uploadAvatar`.
  late final ChatProfileController profile = ChatProfileController(this);

  /// Direct-message helpers — `findExisting`, `openDraft`,
  /// `ensureMaterialized`, `draftRoutingKey`.
  late final ChatDmController dm = ChatDmController(this);

  /// Profile of the user this adapter belongs to. Starts as the value
  /// supplied to the constructor; [profile.update] mutates it
  /// optimistically and the WS `user_updated` echo from the backend can
  /// also push fresh values (e.g. a profile change made from a second
  /// device).
  ChatUser get currentUser => _currentUser;
  ChatUser _currentUser;

  /// Reactive view of [currentUser]. Rebuilds via `ValueListenableBuilder`
  /// whenever displayName / avatarUrl / bio / email / custom change —
  /// either from a local `profile.update` (optimistic write) or from a
  /// `user_updated` WS event echoed back when the profile was changed on
  /// another device. Use this in any widget that paints the current
  /// user's avatar / name and must repaint live (composer, app shell
  /// header, settings entry...). Reading `adapter.currentUser` directly
  /// is fine for one-shot reads but does not trigger rebuilds.
  ValueListenable<ChatUser> get currentUserListenable => _currentUserListenable;
  late final ValueNotifier<ChatUser> _currentUserListenable =
      ValueNotifier<ChatUser>(_currentUser);

  /// Coarse notifier that fires every time [cacheUsers] inserts or
  /// updates an entry (displayName or avatarUrl change). Surfaces that
  /// "any user in the cache changed" — consumers that want fine-grained
  /// per-user listening can wrap a `findCachedUser(id)` read in a
  /// `ListenableBuilder(listenable: userCacheListenable, ...)` and
  /// re-resolve on every fire. The push-update on `MessageList` and
  /// `GroupMembersView` uses exactly this to refresh sender avatars in
  /// group bubbles + member-row avatars without a manual reload.
  Listenable get userCacheListenable => _userCacheListenable;
  final _BroadcastNotifier _userCacheListenable = _BroadcastNotifier();

  /// Fires whenever [blockedUserIds] mutates — either via [blockContact]
  /// / [unblockContact] or a wholesale replacement. Consumers (e.g.
  /// [SuggestionBarController]) subscribe to refresh their derived
  /// state immediately instead of waiting for the next poll tick. The
  /// notifier carries no payload; callers read the current snapshot
  /// from [blockedUserIds].
  Listenable get blockedUsersListenable => _blockedUsersListenable;
  final _BroadcastNotifier _blockedUsersListenable = _BroadcastNotifier();

  /// Fires whenever a room's membership changes in realtime (someone was
  /// added or removed via `user_joined` / `user_left`). The notifier
  /// carries no payload; callers read the id of the room that changed
  /// from [lastMembersChangedRoomId] and compare it against the room
  /// they care about. The push-update on `GroupMembersView` uses exactly
  /// this to re-fetch its roster live instead of only on mount /
  /// pull-to-refresh, mirroring the [userCacheListenable] avatar/name
  /// push-update.
  Listenable get roomMembersListenable => _roomMembersListenable;
  final _BroadcastNotifier _roomMembersListenable = _BroadcastNotifier();

  /// Id of the room whose membership most recently changed, set right
  /// before [roomMembersListenable] fires. Consumers compare this to
  /// their own room id inside the listener callback.
  String? get lastMembersChangedRoomId => _lastMembersChangedRoomId;
  String? _lastMembersChangedRoomId;

  /// Records [roomId] as the most recently changed room and fires
  /// [roomMembersListenable]. Invoked by [MemberEventHandler] on every
  /// `user_joined` / `user_left` event, regardless of whether a chat
  /// controller is open for the room, so a roster view that isn't the
  /// active screen still refreshes.
  ///
  /// Also drops the cached roster's TTL entry. This is THE chokepoint for
  /// "the members of this room changed", so putting the invalidation here
  /// rather than at each event site makes it impossible to add a fourth
  /// trigger that forgets it. Only the real [MembersApi] keeps a TTL
  /// ledger — a custom or mock client has nothing to invalidate.
  void notifyRoomMembersChanged(String roomId) {
    if (_disposed) return;
    final membersApi = client.members;
    if (membersApi is MembersApi) membersApi.invalidateRoster(roomId);
    _lastMembersChangedRoomId = roomId;
    _roomMembersListenable.emit();
  }

  /// Strings the adapter composes where no `BuildContext` is in reach:
  /// membership banners and the self-chat title.
  ///
  /// Hot-swappable. Every handler reads it through this getter on each
  /// use, so assigning a new bundle re-points the whole adapter at another
  /// language in place — no teardown, no reconnect, nothing that can fail
  /// and leave the runtime down. Widgets do not go through here at all:
  /// they resolve their own strings with `ChatTheme.l10nOf(context)` and
  /// rebuild themselves when the host's locale changes, and so do the
  /// room-list previews, which `RoomTile` composes on every paint from the
  /// row's structured fields.
  ///
  /// The setter re-stamps the one string a widget cannot recompute for
  /// itself, because it is stored on a room row rather than derived at
  /// paint time: the self-chat title. Only a row whose title is exactly
  /// what the outgoing bundle would have produced is touched, so nothing a
  /// person wrote is ever overwritten.
  ///
  /// Assigning this takes the language of the adapter into the host's own
  /// hands: the SDK stops pushing the ambient bundle in (see
  /// [adoptAmbientL10n]), and the host owns every later change.
  ChatUiLocalizations get l10n => _l10n;

  set l10n(ChatUiLocalizations value) {
    _l10nPinnedByHost = true;
    _setL10n(value);
  }

  /// Points the adapter at the bundle the widget tree resolved, unless the
  /// host has taken the language into its own hands by assigning [l10n]
  /// (or passing a non-default one to the constructor).
  ///
  /// This is what makes registering `ChatUiLocalizations.delegate` enough
  /// on its own: `NomaChatView` and `RoomListView` call it with
  /// `theme.l10nOf(context)` as their dependencies resolve, so the strings
  /// composed off-screen follow the app locale exactly like the on-screen
  /// ones — with the same precedence, an explicit `ChatTheme.l10n` first
  /// and the `Localizations` ancestor otherwise.
  @internal
  void adoptAmbientL10n(ChatUiLocalizations value) {
    if (_l10nPinnedByHost) return;
    _setL10n(value);
  }

  void _setL10n(ChatUiLocalizations value) {
    final previous = _l10n;
    if (identical(previous, value)) return;
    _l10n = value;
    if (_disposed) return;
    _roomListMutator.refreshSelfChatTitles(previous);
  }

  ChatUiLocalizations _l10n;
  bool _l10nPinnedByHost;
  final IsDmRoomPredicate? isDmRoom;

  /// Host veto over the SDK's membership banners. `null` (the default)
  /// keeps every banner, which is what every consumer got before this
  /// hook existed.
  final MembershipBannerFilter? membershipBannerFilter;

  final RoomTitleResolver? roomTitleResolver;

  /// The host's own answer to "who is this id?", used wherever the SDK
  /// would otherwise have nothing to paint for a person: a one-to-one
  /// room's title, the sender prefix in a group, an avatar, the subject
  /// of a system line.
  ///
  /// `null` (the default) keeps the SDK asking chat and nobody else,
  /// which is all it could do before this hook existed.
  final UserDirectoryResolver? userDirectoryResolver;

  /// How long a name resolved through [userDirectoryResolver] stays good
  /// before the SDK asks again.
  ///
  /// Twelve hours by default: people rename themselves rarely, and the
  /// cost of a stale name for an afternoon is far below the cost of a
  /// directory round trip on every room list build.
  final Duration userDirectoryTtl;

  /// Whether [connect] should make sure the current user exists in chat
  /// before anything else runs.
  ///
  /// Off by default: a host that provisions its users elsewhere gets the
  /// behaviour it already had. Turned on, the adapter reads the profile
  /// once and creates it only when chat says it is not there — never
  /// blindly, and never fatal if the read itself fails.
  final bool bootstrapCurrentUser;

  /// Whether the SDK retries, on its own, a message sent into a
  /// conversation the server did not know about yet.
  ///
  /// Defaults to [SendRetryPolicy.firstSendOnly]; the retry reuses the
  /// optimistic row's `tempId`, so the send is idempotent and a message
  /// that did arrive cannot be duplicated by the retry.
  final SendRetryPolicy sendRetryPolicy;

  final ChatLocalDatasource? _cache;

  /// Plugged-in storage for avatar uploads. Defaults to
  /// [DefaultAvatarStorage] which delegates to `client.attachments.upload`.
  /// Consumers wire a custom implementation when avatars must live on
  /// their own backend (Firebase, S3, custom CHT/wb pipeline, …).
  final AvatarStorage avatarStorage;

  /// Extracts the poster frame `sendAttachment` uploads alongside an
  /// outgoing `video/*` attachment, so the bubble shows a real preview
  /// instead of a grey placeholder.
  ///
  /// Defaults to [NativeVideoThumbnailer] — the platform decoder, mobile
  /// only (see `PlatformSupport.supportsVideoThumbnails`). Supply your own
  /// implementation to route generation elsewhere, or
  /// [NoVideoThumbnailer] to turn the feature off entirely. Never blocks a
  /// send: whatever it returns, `null` included, the video goes out.
  final VideoThumbnailer videoThumbnailer;

  /// Shrinks an outgoing image so it fits the cap its [AttachmentPolicy]
  /// sets, on every path that uploads one: the picker, the review step and
  /// the SDK's own camera screen.
  ///
  /// Defaults to [DefaultAttachmentShrinker] — an oversized image is
  /// re-encoded down the policy's ladder until it fits its cap, and
  /// anything else travels untouched. Supply your own to hand the
  /// re-encoding to an engine of your choice, or [NoAttachmentShrinker] to
  /// send exactly the bytes the user picked.
  final AttachmentShrinker attachmentShrinker;

  /// Default [AttachmentUrlResolver] the adapter wires into
  /// `NomaChatView`/`ChatView` when the host doesn't supply its own
  /// `ChatViewBuilders.attachmentUrlResolver`. Backed by a
  /// [SignedAttachmentUrlResolver] over [client] so media bubbles re-mint
  /// expired signed URLs out of the box (default sane: on).
  AttachmentUrlResolver get defaultAttachmentUrlResolver =>
      _attachmentResolver.resolve;
  late final SignedAttachmentUrlResolver _attachmentResolver =
      SignedAttachmentUrlResolver(client: client, logger: logs);

  /// Default [AttachmentMediaLoader] the adapter wires into
  /// `NomaChatView`/`ChatView` when the host doesn't supply its own
  /// `ChatViewBuilders.attachmentMediaLoader`. Media bubbles use this —
  /// not [defaultAttachmentUrlResolver] — to actually render, because the
  /// download endpoints require a Bearer token no plain URL-loading widget
  /// sends; see `AuthenticatedAttachmentLoader`'s doc.
  AttachmentMediaLoader get defaultAttachmentMediaLoader =>
      _attachmentMediaLoader;
  late final AttachmentMediaLoader _attachmentMediaLoader =
      AuthenticatedAttachmentLoader(client: client, logger: logs);

  /// Structured, tagged logger for the adapter's own sub-managers (presence,
  /// attachment resolution, …) — bridges to [logger] via
  /// [CallbackChatLogSink] so a host that only ever wired the plain callback
  /// keeps receiving lines unchanged, filtered by [logLevel] and redacting
  /// message text unless [logMessageContent] is `true` — mirrors the
  /// [ChatConfig.logs] pattern. `null` (like [logger] defaults to) when no
  /// callback was ever set — matches the pre-existing behaviour of
  /// [defaultAttachmentUrlResolver], which built this ad hoc before [logs]
  /// existed. Cached from whatever [logger] holds at first access, same as
  /// [_attachmentResolver] always has — reassigning [logger] afterwards
  /// does not retarget an already-built [logs].
  ChatLogger? get logs => logger == null
      ? null
      : (_logs ??= ChatLogger(
          sink: CallbackChatLogSink(logger!),
          minLevel: logLevel,
          logMessageContent: logMessageContent,
        ));
  ChatLogger? _logs;

  /// When `true` (default), the adapter fires [markAsRead] automatically
  /// on the two boundaries where WhatsApp would: right after [loadMessages]
  /// finishes (we're now displaying the unread tail) and right before the
  /// controller is disposed via [removeChatController] (the user navigated
  /// away — flush the last read pointer). Both calls are fire-and-forget;
  /// failures are surfaced through [onError] like any other API failure.
  ///
  /// Disable when the consumer wants to drive marking-as-read manually
  /// (e.g. tied to message visibility on screen rather than chat entry).
  final bool autoMarkAsRead;

  /// When `true` (default), the adapter confirms message delivery
  /// automatically — the sender's bubbles flip to the double gray tick
  /// without the consumer wiring anything, exactly as WhatsApp behaves.
  /// Confirmations fire on the three boundaries where the client
  /// demonstrably holds the messages: a `new_message` event lands in a
  /// non-active room, a room's messages finish loading (when
  /// [autoMarkAsRead] doesn't already cover it — a read receipt implies
  /// delivery), and the post-login/reconnect room sync finds rooms with
  /// unread messages. All confirmations are consolidated per room
  /// (cursor semantics, at most one in flight) and fire-and-forget.
  ///
  /// Disable when the host wants to drive delivery confirmation
  /// manually via `client.messages.markRoomAsDelivered` (e.g. tie it to
  /// local persistence rather than reception).
  final bool autoConfirmDelivery;

  /// When `true` (default), the adapter registers its own
  /// `WidgetsBindingObserver` and reacts to app foreground/background
  /// transitions per [lifecyclePolicy] — the host no longer has to wire a
  /// separate `AppLifecycleService` for chat. Registration is best-effort:
  /// if no Flutter binding is available yet (e.g. inside a plain unit test
  /// that never called `TestWidgetsFlutterBinding.ensureInitialized()`),
  /// it silently no-ops instead of throwing.
  final bool manageAppLifecycle;

  /// Governs what [manageAppLifecycle] does on pause/resume. Ignored when
  /// [manageAppLifecycle] is `false`. Defaults to
  /// [ChatLifecyclePolicy.standard].
  final ChatLifecyclePolicy lifecyclePolicy;

  /// When `true` (default), every reconnect (whether app-lifecycle-driven
  /// or a bare network drop while foregrounded) triggers [resync] — a full
  /// room-list + active-room + presence refresh — debounced so a burst of
  /// flappy reconnects only resyncs once per 5 seconds. Disable if the host
  /// wants to drive resync itself (e.g. tied to its own connectivity
  /// signal).
  final bool enableReconnectResync;

  /// Minimum spacing between background room-list revalidation passes for
  /// the same `type` (see [RoomEnricher]'s `_backgroundRevalidate`) —
  /// guards against a screen that opens/closes/reopens re-triggering the
  /// full network-fetch-plus-enrichment pass (`members.list` per DM, DM
  /// dedupe, …) on every reopen. Defaults to 5 seconds, matching the
  /// reconnect-resync debounce. Test-overridable so a suite can shrink the
  /// window instead of waiting out the real default.
  final Duration roomRevalidateDebounce;

  /// Registered in the constructor when [manageAppLifecycle] is `true`;
  /// detached in [dispose]. `null` otherwise.
  ChatLifecycleObserver? _lifecycleObserver;

  /// Wall-clock time the current/last [resync] *attempt* started, used to
  /// debounce a fresh (not-already-running) reconnect-triggered resync (see
  /// [enableReconnectResync]). Owned per-attempt: a failing attempt only
  /// clears it when no newer attempt has re-stamped it in the meantime, so a
  /// late failure can never wipe a seal a subsequent attempt already set.
  DateTime? _lastResyncAt;

  /// `true` while a [resync] loop is running its network work. A trigger
  /// that lands during this window is coalesced into [_resyncPending] rather
  /// than dropped on the debounce floor — a reconnect that arrives mid-resync
  /// carries its own disconnected-window backlog to recover.
  bool _resyncInFlight = false;

  /// Set when a [resync] trigger arrives while one is already
  /// [_resyncInFlight]; makes the in-flight loop run one more pass once it
  /// finishes so the later trigger's backlog is not lost.
  bool _resyncPending = false;

  /// Minimum spacing between automatic reconnect-triggered [resync] calls.
  /// Test-overridable via the constructor's `resyncDebounce` parameter so a
  /// suite can shrink the window instead of waiting out the real default.
  final Duration _resyncDebounce;

  /// Set while a trigger dropped by the time debounce (not the in-flight
  /// coalescing above) is waiting to run once the window clears, so a burst
  /// of triggers inside the same window schedules only one deferred pass
  /// instead of stacking timers.
  Timer? _resyncDeferredTimer;

  bool _isDmDetail(RoomDetail detail) {
    if (isDmRoom != null) return isDmRoom!(detail);
    if (detail.type != RoomType.oneToOne) return false;
    // Defense: a real DM never carries a user-assigned name.
    // If the room has a non-empty name it's an intentional 2-person
    // group — don't classify as DM (otherwise the dedupe path would
    // collapse it against an existing DM with the same other user).
    final name = detail.name?.trim();
    if (name != null && name.isNotEmpty) return false;
    return true;
  }

  void Function(String level, String message)? logger;

  /// Minimum level a record must reach to pass through [logs]. Mirrors
  /// [ChatConfig.logLevel] — set it to the same value passed to
  /// [ChatConfig] (or to [NomaChat.create]'s convenience parameter) so the
  /// adapter's sub-managers (presence, attachment resolution, optimistic
  /// send, …) emit at the level the host actually asked for instead of
  /// being silently clamped to `warn`. Defaults to [ChatLogLevel.warn].
  final ChatLogLevel logLevel;

  /// Mirrors [ChatConfig.logMessageContent]: when `true`, [logs] stops
  /// redacting message text (e.g. [OptimisticHandler]'s `sendMessage
  /// confirmed` line). Defaults to `false` — content is redacted unless the
  /// host opts in.
  final bool logMessageContent;

  /// Mirrors [ChatConfig.metricCallback], which `NomaChat.create` and
  /// `NomaChat.fromConfig` wire here for you: the sink the widget layer emits
  /// its own metrics on, the way the client layer already emits HTTP,
  /// transport and cache ones. Used by the composer's attachment paths for
  /// `image_metadata_strip`, which is what tells a photo that was stripped of
  /// its EXIF apart from one the stripper could not parse and sent as it
  /// came. `null` (the default) collects nothing.
  final MetricCallback? metricCallback;

  /// Sink for [ChatAnalyticsEvent]s. Mirrors [ChatConfig.analyticsSink],
  /// which `NomaChat.create` / `NomaChat.fromConfig` wire here for you —
  /// but this constructor param is the one that matters for a host that
  /// builds [ChatUiAdapter] directly (bypassing `NomaChat.create`), since
  /// a callback that only lived on [ChatConfig] would never reach it. `null`
  /// (the default) emits nothing. See `ANALYTICS.md`.
  final ChatAnalyticsSink? analyticsSink;

  /// Publishes [event] on [analyticsSink]. Exposed (rather than private) so
  /// collaborators outside this file — `NomaChatView`'s voice-playback
  /// wiring, in particular — can emit through the same guarded path as the
  /// adapter's own internal emission sites (`setActiveRoom`, the send path,
  /// the incoming-message router). A throwing sink is caught and dropped:
  /// analytics must never be able to break the chat.
  void emitAnalyticsEvent(ChatAnalyticsEvent event) {
    final sink = analyticsSink;
    if (sink == null) return;
    try {
      sink(event);
    } catch (_) {}
  }

  final RoomListController roomListController;

  /// Lifecycle service: owns `connectionStateNotifier`,
  /// `initializedNotifier`, the disposal flag, and the in-flight
  /// `loadRooms` completer.
  final ConnectionLifecycle _lifecycle;

  /// Notifier for the current realtime connection state. Backed by
  /// [_lifecycle] — the getter keeps the public API source-compatible
  /// (`adapter.connectionStateNotifier` still works).
  ValueNotifier<ChatConnectionState> get connectionStateNotifier =>
      _lifecycle.connectionState;

  /// Becomes `true` after the first successful [loadRooms] call.
  ValueNotifier<bool> get initializedNotifier => _lifecycle.initialized;

  /// What the cache (disk) phase of the room load was able to say, so a
  /// host can pick between "still loading", "genuinely empty" and "has
  /// content" without guessing.
  ///
  /// Updated once per [loadRooms] call, immediately after the cache pass
  /// has written to [roomListController] and *before* the network pass is
  /// attempted — which is what makes it usable as the first-paint decision
  /// on a cold, offline or slow start.
  ///
  /// Nothing else on this adapter answers the question. Listening to
  /// [roomListController] does not: its `mergeRooms` skips
  /// `notifyListeners()` when the merge changed nothing, so a warm reopen
  /// whose cache returns exactly the rows already on screen emits no
  /// notification at all. [onRoomsLoaded] does not either: it only fires
  /// after a network pass. And because this is a [ValueListenable] rather
  /// than a stream, a widget that attaches after the cache phase already
  /// ran still reads the outcome instead of having missed it.
  ///
  /// ```dart
  /// ValueListenableBuilder<RoomHydrationStatus>(
  ///   valueListenable: adapter.roomHydrationNotifier,
  ///   builder: (context, status, _) => switch (status.outcome) {
  ///     RoomHydrationOutcome.hydrated => RoomListView(...),
  ///     RoomHydrationOutcome.empty => const NoChatsYet(),
  ///     // pending / unavailable — the cache has not answered (or could
  ///     // not), so "no chats" would be a guess. Keep the skeleton up
  ///     // until the network pass lands.
  ///     _ => const ChatListSkeleton(),
  ///   },
  /// );
  /// ```
  ///
  /// Released by [dispose]; do not listen after that.
  ValueListenable<RoomHydrationStatus> get roomHydrationNotifier =>
      _enricher.hydrationNotifier;

  /// Fires after each [loadRooms] completes with the loaded room list.
  /// Consumers can use this to enrich metadata (e.g. display names, avatars).
  final void Function(List<RoomListItem> rooms)? onRoomsLoaded;

  // -----------------------------------------------------------------
  // STATE
  //
  // Each concern is owned by a dedicated registry/service (below).
  // Teardown never enumerates the maps directly: [_resetConnectionState]
  // wipes the per-connection state and [_resetSessionState] wipes the
  // cross-session caches on top of it, so `disconnect` / `signOut` /
  // `dispose` route through one of the two and cannot forget a field.
  // -----------------------------------------------------------------

  // -- Per-room runtime state --
  /// Per-room [ChatController] registry. The field is typed as
  /// [ChatControllerRegistry] which mirrors the `Map`-shaped API so
  /// existing `_chatControllers[roomId]` callsites work unchanged.
  /// The added value is the `disposeAll()` lifecycle helper used in
  /// `signOut` / `dispose`.
  final ChatControllerRegistry _chatControllers = ChatControllerRegistry();

  /// Bidirectional `contact ↔ room` map plus stashed draft customs.
  /// Backed by [DmContactRegistry]. The legacy `_dmRoomByContact`
  /// callsites in the `part of` collaborators go through the
  /// service.
  final DmContactRegistry _dmContacts = DmContactRegistry();
  final RoomRosterRegistry _roomRosters = RoomRosterRegistry();

  // -- Sub-managers (composition) --
  /// Standalone handler — no `part of` access, fully injected. Lives
  /// in `services/presence_registry.dart`.
  late final PresenceRegistry _presence = PresenceRegistry(
    api: client.presence,
    roomList: roomListController,
    dmContacts: _dmContacts,
    isDisposed: () => _disposed,
    // Arms the registry's network gate: `GET /presence` has no cache tier,
    // so a cold start with no transport would otherwise fire it and wait for
    // it to time out. The event router re-invokes `bootstrap()` on every
    // `connected` transition, so nothing is lost by skipping it while
    // offline.
    connectionState: connectionStateNotifier,
    logs: logs,
  );

  /// Standalone handler — `handlers/room_enricher.dart`. Receives
  /// every dep explicitly so tests can mock individual services
  /// instead of building the full adapter.
  late final RoomEnricher _enricher = RoomEnricher(
    client: client,
    controllers: _chatControllers,
    roomList: roomListController,
    dmContacts: _dmContacts,
    userCache: _userCacheService,
    blockedUsers: _blockedUsers,
    presence: _presence,
    currentUser: () => _currentUser,
    cache: _cache,
    l10n: () => _l10n,
    initializedNotifier: initializedNotifier,
    connectionStateNotifier: connectionStateNotifier,
    isDisposed: () => _disposed,
    isDmDetail: _isDmDetail,
    findCachedUser: findCachedUser,
    cacheUsers: cacheUsers,
    ensureUserCached: _ensureUserCached,
    updateRoomLastMessage: (roomId, message) =>
        _roomListMutator.updateRoomLastMessage(roomId, message),
    removeChatController: removeChatController,
    logger: logger,
    onRoomsLoaded: onRoomsLoaded,
    onDmContactResolved: () => onDmContactResolved,
    roomTitleResolver: roomTitleResolver,
    confirmDelivered: autoConfirmDelivery ? _deliveredCoord.confirm : null,
    revalidateDebounce: roomRevalidateDebounce,
  );

  /// Standalone handler — `handlers/room_list_mutator.dart`. Owns
  /// every mutation to the room-list controller driven by chat
  /// events or optimistic operations (last-message preview, reaction
  /// preview, receipts, unread counts, DM title/avatar refresh,
  /// sender-name backfill and blocked-rooms pruning).
  late final RoomListMutator _roomListMutator = RoomListMutator(
    roomListController: roomListController,
    cache: _cache,
    client: client,
    l10n: () => _l10n,
    currentUser: () => _currentUser,
    findCachedUser: findCachedUser,
    ensureUserCached: _ensureUserCached,
    findChatController: (roomId) => _chatControllers[roomId],
    removeChatController: removeChatController,
    blockedUserIds: () => _blockedUsers.all,
    isUserBlocked: _blockedUsers.isBlocked,
    computeEffectiveTitle:
        ({required currentItem, otherMembers = const [], isDmOverride}) =>
            _enricher.computeEffectiveTitle(
              currentItem: currentItem,
              otherMembers: otherMembers,
              isDmOverride: isDmOverride,
            ),
    isDisposed: () => _disposed,
  );

  /// Standalone handler — `handlers/optimistic_handler.dart`. Wires
  /// every dep explicitly so it can be unit-tested with mocks
  /// instead of building the full adapter.
  late final OptimisticHandler _optimistic = OptimisticHandler(
    client: client,
    controllers: _chatControllers,
    roomList: roomListController,
    pendingReactions: _pendingReactionsRegistry,
    currentUser: () => _currentUser,
    cache: _cache,
    ensureDmRoomMaterialized: ensureDmRoomMaterialized,
    updateRoomLastMessage: (roomId, message) =>
        _roomListMutator.updateRoomLastMessage(roomId, message),
    updateRoomReactionPreview: (roomId, reaction, userId, messageId) =>
        _roomListMutator.updateRoomReactionPreview(
          roomId,
          reaction,
          userId,
          messageId,
        ),
    ensureSentReceipt: _ensureSentReceipt,
    tempIds: _tempIds,
    sendRetryPolicy: sendRetryPolicy,
    isBlockedError: _isBlockedError,
    isMutedError: _isMutedError,
    // 403 "muted" on send → re-fetch the room detail so `selfMuted`
    // propagates and the composer locks behind the read-only banner.
    onModerationLock: _enrichRoomFromDetail,
    emitFailure: <T>(result, kind, {roomId, messageId, userId}) =>
        _emitFailure<T>(
          result,
          kind,
          roomId: roomId,
          messageId: messageId,
          userId: userId,
        ),
    emitOperationSuccess: (kind, {roomId, messageId, userId}) =>
        emitOperationSuccess(
          kind,
          roomId: roomId,
          messageId: messageId,
          userId: userId,
        ),
    swallowCacheThrow: _swallowCacheThrow,
    analyticsEmit: emitAnalyticsEvent,
    logs: logs,
  );

  /// Standalone handler — `handlers/member_event_handler.dart`. Reacts
  /// to membership realtime events (`UserJoinedEvent`, `UserLeftEvent`)
  /// plus the WhatsApp-parity self-rejoin / kick branches; owns the
  /// system-banner counter used to mint synthetic message ids and the
  /// `deleteKickedChat` cache cleanup.
  late final MemberEventHandler _memberEventHandler = MemberEventHandler(
    client: client,
    chatControllers: _chatControllers,
    cache: _cache,
    roomListController: roomListController,
    userCacheService: _userCacheService,
    l10n: () => _l10n,
    currentUser: () => _currentUser,
    displayNameFor: displayNameFor,
    ensureUserCached: _ensureUserCached,
    addRoomFromDetail: _addRoomFromDetail,
    removeChatController: removeChatController,
    notifyRoomMembersChanged: notifyRoomMembersChanged,
    isDisposed: () => _disposed,
    swallowCacheThrow: _swallowCacheThrow,
    membershipBannerFilter: membershipBannerFilter,
    logger: logger,
  );

  // -- Typing throttle & stop-emit timers --
  // Backed by `TypingTimerRegistry`. Adapter wires the auto-stop
  // callback to the actual REST `sendTyping(stopsTyping)` so the
  // registry stays agnostic about the network.
  late final TypingTimerRegistry _typingTimers = TypingTimerRegistry(
    onAutoStopTriggered: (roomId) {
      client.messages.sendTyping(roomId, activity: ChatActivity.stopsTyping);
    },
  );

  // -- User cache (in-memory only; persistent cache lives in [_cache]).
  // Backed by `UserCacheService` which also owns the in-flight fetch
  // dedupe.
  late final UserCacheService _userCacheService = UserCacheService(
    api: client.users,
    isDisposed: () => _disposed,
    directory: HostUserDirectory(
      resolver: userDirectoryResolver,
      cache: _cache,
      ttl: userDirectoryTtl,
      isDisposed: () => _disposed,
      logger: logger,
    ),
  );

  // -- markAsRead backpressure --
  //
  // Bursts of `NewMessageEvent` in an active room would otherwise fan
  // into one HTTP request per message (event_router fires
  // `unawaited(markAsRead(roomId, lastReadMessageId: msg.id))` on every
  // event). The coalescer keeps at most one in-flight markAsRead per
  // room: while a request is running, the latest pending
  // `lastReadMessageId` is queued and only the freshest one is sent
  // when the in-flight call completes — older intermediate ids are
  // discarded (we only care about the high-water mark).
  /// Coalescer for `markRoomAsRead` REST calls — one in flight per
  /// room max, follow-ups stash the latest high-water mark.
  late final MarkAsReadCoordinator _markAsReadCoord = MarkAsReadCoordinator(
    messages: client.messages,
    isDisposed: () => _disposed,
    onMarkedRead: (roomId) => _roomListMutator.updateRoomUnread(roomId, 0),
    emitFailure: <T>(result, kind, {roomId, messageId, userId}) =>
        _emitFailure<T>(
          result,
          kind,
          roomId: roomId,
          messageId: messageId,
          userId: userId,
        ),
  );

  /// Coalescer for delivered-cursor confirmations — one in flight per
  /// room max, follow-ups stash the newest cursor. Used by the event
  /// router (live messages), `messages.load` and the room-sync catch-up
  /// when [autoConfirmDelivery] is on.
  late final DeliveredConfirmationCoordinator _deliveredCoord =
      DeliveredConfirmationCoordinator(
        messages: client.messages,
        isDisposed: () => _disposed,
        // Arms the coordinator's network gate. The room sync fires one
        // confirmation per unread room on its cache pass, which on a cold
        // offline start means N doomed requests racing the first paint. The
        // adapter re-runs the sync on every reconnect, so a dropped offline
        // confirmation is re-sent then.
        connectionState: connectionStateNotifier,
      );
  // Both ARE cancelled, in `_cancelSubscriptions` below, via locals
  // snapshotted from these fields — see that method's doc comment for why
  // the lint's simple direct-field-reference pattern can't see it.
  // ignore: cancel_subscriptions
  StreamSubscription<ChatEvent>? _eventSub;
  // ignore: cancel_subscriptions
  StreamSubscription<ChatConnectionState>? _stateSub;

  /// Convenience accessor for the lifecycle's disposed flag — used in
  /// the ~25 async paths that need to early-out when the adapter has
  /// been torn down mid-flight.
  bool get _disposed => _lifecycle.isDisposed;

  /// Bumped every time the room controllers are wiped — [signOut],
  /// [dispose] and an eager [disconnect] alike. [_disposed] does not cover
  /// the first of those (the adapter stays usable for the next user), yet a
  /// flow that captured a [ChatController] before it has no more right to
  /// touch it, or the cache `signOut` just cleared, than one racing a real
  /// disposal.
  int _sessionEpoch = 0;

  /// `true` when the session that was live at [epoch] has ended — see
  /// [_sessionEpoch]. Long-running optimistic sends capture the epoch up
  /// front and re-check it after every suspension point.
  bool _sessionEndedSince(int epoch) => _disposed || _sessionEpoch != epoch;

  bool _clearingRooms = false;

  /// `true` for the whole of a session teardown — every notification it
  /// emits, not only the one that empties the room list — and from
  /// [dispose] onwards.
  ///
  /// An emptied room list is indistinguishable, from a listener's side, from
  /// "every room you were in has just been removed" — yet
  /// `disconnect(clearRooms: true)`, [signOut] and [dispose] all empty it on
  /// purpose. Anything that reacts to a room disappearing (leaving the room,
  /// popping its route, telling the user the conversation is gone) has to
  /// check this first and stay put while it is `true`: the room did not go
  /// away, the session did. [NomaChatView] does exactly that before calling
  /// `onRoomLeft`.
  ///
  /// Deliberately an explicit signal instead of an inference from the list
  /// going empty: being removed from the only room you had empties it too,
  /// and that one is a real removal the host still has to hear about.
  bool get isTearingDown => _disposed || _clearingRooms;

  void Function(String message)? onBroadcast;
  void Function(ChatEvent event)? onError;
  void Function()? onReconnected;
  void Function(String roomId, String userId)? onDmContactResolved;

  /// Fired whenever a new message lands with `metadata.adminSent == true`
  /// — i.e. it was authored from the admin panel. Hosts use this to
  /// surface a subtle snackbar / banner (`Admin: <text>`) without the
  /// SDK having to ship its own opinionated UI. The bubble itself still
  /// renders with the "admin" microcopy in the meta row regardless of
  /// this callback. Default is `null` (silent fallback).
  void Function(ChatMessage message, String roomId)? onAdminMessage;

  /// Fired when a room the local user belonged to is removed. Receives
  /// the room id plus optional `reason` / `adminReason` metadata — set
  /// to `reason: "banned"` + the admin-supplied free-text reason when
  /// the cause was an admin per-room ban (other organic deletions land
  /// here with both fields null). Hosts wire this to render an
  /// explanatory snackbar / toast; the SDK has already popped the room
  /// from the list and disposed any open controller by the time this
  /// fires.
  void Function(String roomId, String? reason, String? adminReason)?
  onRoomRemoved;

  /// Optional notification fired whenever the set of blocked users
  /// changes — both when the consumer pushes a fresh set via
  /// [blockedUserIds] (e.g. on `/users/me` refresh) and when
  /// [blockContact] mutates the set after a local block. Receives the
  /// full updated set so apps can drive analytics, refresh banners,
  /// invalidate caches, etc. Default is `null` (no-op).
  void Function(Set<String> blockedUserIds)? onBlockedUsersChanged;

  /// Backing service for [blockedUserIds]. The registry owns the set
  /// and fires its own onChange callback on real mutations; the
  /// adapter glues that callback to the room-prune flow + the public
  /// `onBlockedUsersChanged` hook below.
  late final BlockedUsersRegistry _blockedUsers = BlockedUsersRegistry(
    onChanged: (ids) {
      // Blocking keeps the chat (Decision A): the blocked DM stays in the
      // list and renders the read-only "blocked" composer state, matching
      // WhatsApp. We no longer prune the row here.
      // Fan-out to derived state. The Listenable lets the SuggestionBar
      // controller refresh immediately on unblock (otherwise it had to
      // wait for the 10s poll tick before re-displaying the contact).
      _blockedUsersListenable.emit();
      onBlockedUsersChanged?.call(ids);
    },
  );

  /// Snapshot of users blocked by (or blocking, depending on the
  /// consumer's source of truth) the current user. The adapter uses this
  /// set to drop DM rooms whose `otherUserId` matches, both at
  /// resolution time ([_doResolveDmContact]) and when the set itself
  /// changes ([blockedUserIds]= …). Consumers typically push the full set
  /// after their own user-info refresh; [blockContact] also keeps it in
  /// sync for the rooms it touches.
  Set<String> get blockedUserIds => contacts.blockedUserIds;

  /// Replaces the blocked-users set wholesale and prunes any DM rooms
  /// whose `otherUserId` ended up blocked. Emits [onBlockedUsersChanged]
  /// after the prune. Idempotent — passing the same set twice is a no-op
  /// (the prune still runs but finds nothing new to remove).
  set blockedUserIds(Set<String> ids) {
    contacts.blockedUserIds = ids;
  }

  /// Re-runs the blocked-rooms prune. Idempotent — useful when the
  /// consumer reloads rooms (e.g. after `loadRooms` finishes a network
  /// sync) and wants to drop any rows that were materialized for
  /// contacts already known to be blocked. The setter [blockedUserIds]=
  /// already invokes this; expose it standalone so consumers don't need
  /// to reassign the set just to trigger the prune.
  @internal
  void pruneBlockedRooms() => contacts.pruneBlockedRooms();

  /// One-shot bootstrap of the blocked-users set from the server.
  /// Fetches `client.contacts.listBlocked()`, replaces [blockedUserIds]
  /// (which also prunes any DM rows that happened to be materialized for
  /// contacts in the set) and fires [onBlockedUsersChanged].
  ///
  /// Typical usage:
  /// ```dart
  /// await chat.connect();
  /// await chat.adapter.rooms.load();
  /// await chat.adapter.contacts.loadBlocked(); // one-shot, NOT polled
  /// ```
  ///
  /// Subsequent mutations come from [blockContact] / [unblockContact]
  /// (local sources of truth) — no polling needed. Re-invoke this method
  /// only on explicit user-triggered refresh (e.g. entering the blocked
  /// users screen) when you want a server-confirmed snapshot.
  @internal
  Future<ChatResult<void>> loadBlockedUsers() => contacts.loadBlocked();

  /// Owns the failure + success broadcast streams. Adapter delegates
  /// every `_emitFailure(...)` / `emitOperationSuccess(...)` callsite
  /// to this hub so the stream lifecycle + "skip if closed" guard
  /// have a single tested home.
  final OperationHub _operations = OperationHub();

  /// Broadcast stream of failures from any adapter operation. The
  /// original `ChatResult.ChatFailureResult` is still returned to the caller; this
  /// stream is for cross-cutting concerns (global snackbars,
  /// telemetry). Multiple subscribers can listen concurrently.
  Stream<OperationError> get operationErrors => _operations.errors;

  /// Broadcast stream of successful operations that have user-visible
  /// side effects worth confirming (pin/unpin a message, delete a
  /// message, forward, mute/unmute, etc.). [NomaChatView] subscribes
  /// when `ChatViewBehaviors.showOperationFeedback` is true (default)
  /// and shows localized SnackBars. Apps wanting fully custom UI can
  /// listen here directly and pass `showOperationFeedback: false`.
  Stream<OperationSuccess> get operationSuccesses => _operations.successes;

  /// Emit a success event on [operationSuccesses]. No-op when the
  /// controller is closed (post-dispose). Public so collaborator
  /// `part of` files (event router, optimistic handler) can publish
  /// without going through `_emitFailure`-style wrappers.
  void emitOperationSuccess(
    OperationKind kind, {
    String? roomId,
    String? messageId,
    String? userId,
  }) => _operations.emitSuccess(
    kind,
    roomId: roomId,
    messageId: messageId,
    userId: userId,
  );

  ChatResult<T> _emitFailure<T>(
    ChatResult<T> result,
    OperationKind kind, {
    String? roomId,
    String? messageId,
    String? userId,
  }) => _operations.emitFailure(
    result,
    kind,
    roomId: roomId,
    messageId: messageId,
    userId: userId,
  );

  ChatConnectionState get connectionState => client.connectionState;

  /// Returns (or creates) a [ChatController] for the given room.
  ///
  /// When [otherUsers] is supplied it is cached and pushed onto the
  /// controller as before. When it is omitted, the adapter fills the
  /// controller's peer list from what it already knows — the resolved DM
  /// contact (see [DmContactRegistry]) hydrated from the in-memory user
  /// cache. Consumers therefore no longer need the `cacheUsers(...)` +
  /// `setOtherUsers(...)` double-call just to get the DM peer onto a
  /// freshly-opened controller; opening the room is enough.
  ChatController getChatController(
    String roomId, {
    List<ChatMessage> initialMessages = const [],
    List<ChatUser> otherUsers = const [],
  }) {
    if (otherUsers.isNotEmpty) cacheUsers(otherUsers);
    final effectiveOthers = otherUsers.isNotEmpty
        ? otherUsers
        : _cachedOtherUsersForRoom(roomId);
    final existing = _chatControllers[roomId];
    if (existing != null) {
      // Only push when the caller actually supplied users, or when the
      // controller has none yet and we resolved some from cache — never
      // clobber a populated controller with an empty/cache-only list.
      if (otherUsers.isNotEmpty) {
        existing.setOtherUsers(otherUsers);
      } else if (existing.otherUsers.isEmpty && effectiveOthers.isNotEmpty) {
        existing.setOtherUsers(effectiveOthers);
      }
      return existing;
    }
    final controller = ChatController(
      initialMessages: initialMessages,
      currentUser: currentUser,
      otherUsers: effectiveOthers,
    );
    controller.setRoomId(roomId);
    _chatControllers[roomId] = controller;
    return controller;
  }

  /// Forces a `sent` receipt on a server-confirmed outgoing message that came
  /// back without one. The server omits the field for the synchronous POST
  /// response, so without this helper an outgoing bubble would render with no
  /// status icon until a `delivered`/`read` event arrives.
  ChatMessage _ensureSentReceipt(ChatMessage message) => message.receipt == null
      ? message.copyWith(receipt: ReceiptStatus.sent)
      : message;

  /// Disposes and removes the controller for a room. When [autoMarkAsRead]
  /// is true (default), flushes a `markAsRead` for the room before disposing
  /// so the chat list unread counter and last-read pointer stay in sync
  /// with what the user actually saw (mirrors WhatsApp's "close chat" flush).
  void removeChatController(String roomId) {
    if (autoMarkAsRead && _chatControllers.containsKey(roomId)) {
      unawaited(markAsRead(roomId));
    }
    if (_activeRoomId == roomId) _activeRoomId = null;
    _chatControllers.remove(roomId)?.dispose();
  }

  /// Id of the room the user is currently viewing on screen. `null` means
  /// the chat list (or no chat) is in foreground. Consumers wire it from
  /// their chat-room widget lifecycle: `setActiveRoom(roomId)` on enter,
  /// `setActiveRoom(null)` on leave.
  ///
  /// While set, [_onNewMessage] in the event router fires `markAsRead`
  /// immediately for incoming messages in that room — so the sender sees
  /// the second tick flip to blue in real time, exactly as WhatsApp does
  /// when both peers are in the same conversation.
  String? _activeRoomId;
  String? get activeRoomId => _activeRoomId;

  /// Marks [roomId] as the currently-foregrounded chat. Pass `null` when
  /// the user leaves it. Zeroes the room-list unread badge immediately —
  /// optimistically, on the client, synchronously with this call — instead
  /// of waiting for `markAsRead`'s network round-trip, so the badge clears
  /// the instant the user opens the room even on a slow/unstable
  /// connection, matching WhatsApp. Also triggers the real `markAsRead`
  /// request for [roomId] if [autoMarkAsRead] is true (cheap; idempotent
  /// when nothing changed) so the server's read cursor still advances.
  void setActiveRoom(String? roomId) {
    if (_activeRoomId == roomId) return;
    _activeRoomId = roomId;
    // A draft DM has no backend room yet (it materializes on the first sent
    // message), so mark-as-read would 403 with `not_member`. Skip it for
    // drafts; the room is marked read normally once it materializes.
    final isDraftRoom =
        roomId != null &&
        ((_chatControllers[roomId]?.isDraft ?? false) ||
            dm.isDraftRoutingKey(roomId));
    if (roomId != null && !isDraftRoom) {
      emitAnalyticsEvent(
        ChatAnalyticsEvent.roomOpened(
          roomId: roomId,
          isGroup: roomListController.getRoomById(roomId)?.isGroup ?? false,
        ),
      );
      // The roster frames that keep `memberCount` (and the title, the
      // avatar, the read-only flag) current are the only thing that
      // refreshes them, so a single frame lost to a dropped socket left
      // the header contradicting the room for as long as the row lived —
      // leaving and re-entering it changed nothing, because nothing
      // re-read the detail on the way in. Opening the room is the cheap,
      // self-healing moment to re-read it: once per entry, single-flighted
      // by the enricher.
      if (roomListController.getRoomById(roomId) != null) {
        _enrichRoomFromDetail(roomId);
      }
    }
    if (roomId != null && autoMarkAsRead && !isDraftRoom) {
      final targetRoomId = roomId;
      scheduleMicrotask(() {
        if (!_disposed && _activeRoomId == targetRoomId) {
          _roomListMutator.updateRoomUnread(targetRoomId, 0);
        }
      });
      unawaited(markAsRead(roomId));
    }
  }

  /// Returns the [ChatController] for [roomId] only if it has already been
  /// created (does NOT create a new one). Useful for read-only lookups such as
  /// resolving member names from the room list.
  ChatController? findChatController(String roomId) => _chatControllers[roomId];

  /// Associates a contact user ID with its DM room ID for typing indicator routing.
  @internal
  void registerDmRoom(String contactUserId, String roomId) =>
      dm.registerRoom(contactUserId, roomId);

  /// Returns the room ID for a DM with the given contact, or null.
  @internal
  String? getDmRoomId(String contactUserId) => dm.getRoomId(contactUserId);

  /// Returns the existing DM room id with [otherUserId] if there is one, or
  /// `null` if no conversation has been started yet. Checks the contact→room
  /// cache first (`getDmRoomId`) and falls back to scanning the room list for
  /// rows with `otherUserId == otherUserId`.
  ///
  /// Use this before calling [openDirectMessageDraft] to decide whether to
  /// open the existing conversation (`getChatController(existingId)`) or
  /// start a fresh draft.
  @internal
  String? findExistingDmRoom(String otherUserId) =>
      dm.findExisting(otherUserId);

  /// Opens a draft DM with [otherUserId] WhatsApp-style — returns a
  /// [ChatController] in `isDraft` state without creating a room
  /// server-side. The other user is hydrated (from cache or
  /// `client.users.get`) so `controller.otherUsers` is populated and
  /// downstream consumers (e.g. AppBars resolving titles via
  /// `RoomTitleResolver`) can render immediately.
  ///
  /// The draft is cached under the key `draft:<otherUserId>` in
  /// `_chatControllers`. The first successful send through this controller
  /// materializes a real room (`rooms.create` with `members: [otherUserId]`,
  /// plus any [extraRoomCustom]) — see `_OptimisticHandler.sendMessage`.
  ///
  /// Callers that want to reuse an existing conversation should call
  /// [findExistingDmRoom] first.
  ///
  /// [extraRoomCustom] is merged into the `custom` map of the
  /// materialized room. Pass `{'type': 'dm'}` (or whatever marker your app
  /// uses) when the [IsDmRoomPredicate] needs an explicit hint to recognize
  /// the room as a DM.
  @internal
  Future<ChatController> openDirectMessageDraft(
    String otherUserId, {
    Map<String, dynamic>? extraRoomCustom,
  }) => dm.openDraft(otherUserId, extraRoomCustom: extraRoomCustom);

  /// Key under which a draft DM controller is cached in `_chatControllers`.
  /// Exposed publicly so the UI layer can pass it to [sendMessage] (and
  /// other room-id-keyed APIs) before the draft has been materialized into
  /// a real room. Format: `draft:<otherUserId>`.
  @internal
  String draftRoutingKey(String otherUserId) => dm.draftRoutingKey(otherUserId);

  // Note: draft DM custom payloads (the per-contact map previously
  // here as `_draftRoomCustomByOtherUser`) live in [_dmContacts]
  // under `draftCustomFor`/`setDraftCustom` — same lifecycle as the
  // DM mapping itself, so a single service owns both.

  /// Returns the real server-side `roomId` for the DM with [otherUserId],
  /// creating the room if it does not exist yet. Idempotent — three branches:
  ///
  /// 1. There is already a known room with this contact
  ///    ([findExistingDmRoom] returns non-null) → returns that id.
  /// 2. There is an open draft controller for this contact
  ///    (`_chatControllers['draft:<otherUserId>']`): create the room via
  ///    `client.rooms.create`, rebind the controller from the draft slot to
  ///    the real id (`setRoomId` + `clearDraft`), seed `_dmRoomByContact`,
  ///    and add the row to the room list. Returns the real id.
  /// 3. No room and no draft: same as (2) but no controller to rebind. The
  ///    consumer typically calls [getChatController] afterwards.
  ///
  /// Use this from flows that need the real `roomId` BEFORE sending — e.g.
  /// uploading an attachment whose progress is tied to a row in the list,
  /// or any operation routed via `roomId` (typing, voice send, etc.). The
  /// optimistic `sendMessage` materializes on its own; consumers that only
  /// send text don't need to call this directly.
  ///
  /// [extraRoomCustom] overrides any custom payload previously registered
  /// for [otherUserId] via [openDirectMessageDraft]. Useful for ad-hoc
  /// callers without a draft controller.
  ///
  /// Failures propagate the underlying `ChatResult.ChatFailureResult` so the consumer can
  /// surface a retry. A failure does NOT leave a stale draft entry — the
  /// controller stays in `isDraft = true` and can retry on the next send.
  @internal
  Future<ChatResult<String>> ensureDmRoomMaterialized(
    String otherUserId, {
    Map<String, dynamic>? extraRoomCustom,
  }) => dm.ensureMaterialized(otherUserId, extraRoomCustom: extraRoomCustom);

  /// Fetches rooms from the server and populates the [roomListController].
  /// Loads user rooms using cache-then-network:
  /// 1. Shows cached room list instantly (if available).
  /// 2. Fetches fresh room list from network and replaces — unless
  ///    realtime (WS) is already connected and the adapter has been
  ///    initialized at least once. In that case the cache is trusted
  ///    and the network round-trip is skipped: incoming events keep
  ///    the room list up-to-date in real time.
  ///
  /// Pass [forceNetwork] to bypass the realtime optimization — useful
  /// for pull-to-refresh interactions where the user explicitly asks
  /// for a fresh server snapshot.
  ///
  /// A successful response — from this call, [resync]'s automatic pass
  /// after a reconnect, or the background revalidation fired by the
  /// cache-trusted branch above — is always treated as the caller's
  /// authoritative complete room set, including when it's legitimately
  /// empty: the listing endpoint fails outright on a bad read instead of
  /// answering 200 with a partial/best-effort page, so there's no
  /// ambiguity left for the client to guard against. A failed response
  /// (network error, timeout, 5xx) never touches the list, here or in any
  /// caller.
  @internal
  Future<ChatResult<void>> loadRooms({
    String type = 'all',
    bool forceNetwork = false,
  }) => rooms.load(type: type, forceNetwork: forceNetwork);

  Future<ChatResult<void>> _doLoadRooms({
    String type = 'all',
    bool forceNetwork = false,
  }) => _enricher.loadAll(type: type, forceNetwork: forceNetwork);

  void _loadReactionsFromMessages(
    ChatController controller,
    List<ChatMessage> messages,
  ) {
    for (final msg in messages) {
      final reactions = msg.metadata?['_reactions'];
      if (reactions is Map) {
        final counts = <String, int>{};
        for (final entry in reactions.entries) {
          counts[entry.key as String] = entry.value as int;
        }
        if (counts.isNotEmpty) controller.setReactions(msg.id, counts);
      }
      final reactionUsers = msg.metadata?['_reactionUsers'];
      if (reactionUsers is Map) {
        final ownEmojis = <String>{};
        for (final entry in reactionUsers.entries) {
          final users = entry.value;
          if (users is List && users.contains(currentUser.id)) {
            ownEmojis.add(entry.key as String);
          }
        }
        if (ownEmojis.isNotEmpty) {
          controller.setUserReactions(msg.id, ownEmojis);
        }
      }
    }
  }

  /// Loads initial messages for a room using cache-then-network:
  /// 1. Shows cached messages instantly (if available).
  /// 2. Fetches fresh messages from network in background and merges.
  Future<ChatResult<List<ChatMessage>>> loadMessages(
    String roomId, {
    int limit = 50,
  }) => messages.load(roomId, limit: limit);

  /// Re-adds the cached pending rows that never confirmed and marks them
  /// failed, so a send the previous session lost is still retriable after a
  /// restart. Rows the room already holds are orphans from a lost
  /// `deletePendingMessage` and are dropped from the cache instead of being
  /// resurrected — see [_supersedesPendingRow] for how that is decided.
  /// Without that guard a single failed cache delete would leak a ghost
  /// bubble that re-appears on every reload.
  Future<void> _rehydratePendingMessages(
    String roomId,
    ChatController controller,
  ) async {
    final cache = _cache;
    if (cache == null) return;
    try {
      final pending =
          (await cache.getPendingMessages(roomId)).dataOrNull ??
          const <PendingChatMessage>[];
      for (final p in pending) {
        final superseded = controller.messages.any(
          (m) => _supersedesPendingRow(m, p.message),
        );
        if (superseded) {
          unawaited(
            cache
                .deletePendingMessage(roomId, p.message.id)
                .catchError(_swallowCacheThrow),
          );
          continue;
        }
        final exists = controller.messages.any((m) => m.id == p.message.id);
        if (!exists) controller.addMessage(p.message);
        // Anything that survived to the next load couldn't confirm in the
        // previous session: surface it as failed so the user can retry.
        controller.markFailed(p.message.id);
      }
    } catch (_) {
      // Best-effort: cache hydration must never block the chat.
    }
  }

  /// `true` when [loaded] — a row the controller already holds — *is* the
  /// message the cached [pending] row stands for, so the pending row is an
  /// orphan and not a send to resurrect.
  ///
  /// The idempotency key decides it whenever both rows carry one:
  /// [ChatMessage.clientMessageId] round-trips through the backend inside
  /// `metadata`, so the same key under a different id is proof the send
  /// landed — and two different keys are proof of two different sends,
  /// however identical their text (the user deliberately sending "ok"
  /// twice, which the heuristic below cannot tell apart). Media rows are
  /// what make this load-bearing: they are built with no `text` while the
  /// send puts `''` on the wire, so `null != ''` hid the match, and since
  /// the rows gained a `clientMessageId` the resurrected ghost resolved
  /// onto the delivered message and repainted it as failed.
  ///
  /// When either side has no key — rows cached before media rows carried
  /// one, or a backend that does not echo it back — the original
  /// sender/type/text/timestamp heuristic stands, being the only signal
  /// those rows have.
  bool _supersedesPendingRow(ChatMessage loaded, ChatMessage pending) {
    if (loaded.id == pending.id) return false;
    final pendingKey = pending.clientMessageId;
    final loadedKey = loaded.clientMessageId;
    if (pendingKey != null && loadedKey != null) return pendingKey == loadedKey;
    return loaded.from == pending.from &&
        loaded.messageType == pending.messageType &&
        loaded.text == pending.text &&
        loaded.timestamp.difference(pending.timestamp).inSeconds.abs() <= 60;
  }

  /// Loads older messages for pagination using cache-then-network.
  /// No-op if already loading or no more pages.
  Future<ChatResult<List<ChatMessage>>> loadMoreMessages(
    String roomId, {
    int limit = 50,
  }) => messages.loadMore(roomId, limit: limit);

  // Message IDs with pending reaction deletes — skip WS refresh for these.
  // Backed by `PendingReactionsRegistry` (services/) so the
  // suppression logic has its own tested home rather than being a
  // loose Set sprinkled across handlers.
  final PendingReactionsRegistry _pendingReactionsRegistry =
      PendingReactionsRegistry();

  /// Sends a message with optimistic UI update. Shows immediately, confirms on server response.
  ///
  /// [operationKind] lets callers like [sendThreadReply] surface a more
  /// specific [OperationKind] on the error stream instead of the default
  /// [OperationKind.sendMessage]; pass `null` to use the default.
  @internal
  Future<ChatResult<ChatMessage>> sendMessage(
    String roomId, {
    required String text,
    String? referencedMessageId,
    MessageType messageType = MessageType.regular,
    Map<String, dynamic>? metadata,
    String? attachmentUrl,
    OperationKind? operationKind,
  }) => messages.send(
    roomId,
    text: text,
    referencedMessageId: referencedMessageId,
    messageType: messageType,
    metadata: metadata,
    attachmentUrl: attachmentUrl,
    operationKind: operationKind,
  );

  /// Forwards [messageId] (originally posted in [sourceRoomId]) to every
  /// room in [targetRoomIds]. Returns the list of forwarded message
  /// results in the same order. Successes carry the new server-assigned
  /// `ChatMessage`; failures carry the underlying `ChatFailure`.
  ///
  /// **Optimistic UI**: for each target with an open controller, an
  /// optimistic `MessageType.forward` bubble is inserted *before* the
  /// network call and confirmed/failed once the server responds.
  /// This avoids the visible delay between tapping "Forward" and the
  /// bubble landing via WS roundtrip.
  ///
  /// Materializes draft DMs inline when a target is a draft routing
  /// key — same pattern as [sendMessage] / [sendVoiceMessage]. The
  /// backend persists `forwardedFrom` / `forwardedFromRoom` metadata so
  /// receivers render the WhatsApp-style "Forwarded" chevron via
  /// `ForwardedBubble`.
  Future<List<ChatResult<ChatMessage>>> forwardMessage({
    required String sourceRoomId,
    required String messageId,
    required List<String> targetRoomIds,
    Map<String, dynamic>? extraMetadata,
  }) => messages.forward(
    sourceRoomId: sourceRoomId,
    messageId: messageId,
    targetRoomIds: targetRoomIds,
    extraMetadata: extraMetadata,
  );

  /// Edits a message with optimistic update. Reverts on failure.
  @internal
  Future<ChatResult<void>> editMessage(
    String roomId,
    String messageId, {
    required String text,
    Map<String, dynamic>? metadata,
  }) => messages.edit(roomId, messageId, text: text, metadata: metadata);

  /// Deletes a message globally. The deleter's own chat flips the
  /// row to a "You deleted this message" tombstone (WhatsApp-style)
  /// instead of removing it outright — other clients render the
  /// same tombstone via the `message_deleted` WS event. Restores on
  /// failure.
  @internal
  Future<ChatResult<void>> deleteMessage(String roomId, String messageId) =>
      messages.delete(roomId, messageId);

  /// "Delete for me": locally hides the tombstone of [messageId] in
  /// [roomId] without touching the server. WhatsApp behaviour for
  /// the deleter who wants to also clear the placeholder from their
  /// own view, or for any client that wants to drop a message
  /// locally. Drops from the controller AND the local cache so it
  /// stays gone after a room re-open / cold start.
  @internal
  Future<ChatResult<void>> deleteMessageLocally(
    String roomId,
    String messageId,
  ) => messages.deleteLocally(roomId, messageId);

  /// Sends an emoji reaction with optimistic update.
  @internal
  Future<ChatResult<void>> sendReaction(
    String roomId, {
    required String messageId,
    required String emoji,
  }) => messages.sendReaction(roomId, messageId: messageId, emoji: emoji);

  /// Fetches aggregated reactions for a message from the server.
  Future<ChatResult<List<AggregatedReaction>>> getReactions(
    String roomId,
    String messageId,
  ) => messages.getReactions(roomId, messageId);

  /// Removes the current user's reaction from a message with optimistic update.
  @internal
  Future<ChatResult<void>> deleteReaction(
    String roomId, {
    required String messageId,
    required String emoji,
  }) => messages.deleteReaction(roomId, messageId: messageId, emoji: emoji);

  /// Sends a typing indicator to a room (throttled per
  /// `TypingTimerRegistry.throttle`, default 3s). When [isTyping] is
  /// `true`, the registry also schedules an auto-stop timer
  /// (`TypingTimerRegistry.stopDelay`, default 1s) so the server gets
  /// a `stopsTyping` even when the caller goes silent.
  @internal
  Future<ChatResult<void>> sendTyping(String roomId, {bool isTyping = true}) =>
      messages.sendTyping(roomId, isTyping: isTyping);

  /// Marks all messages in a room as read.
  ///
  /// When [lastReadMessageId] is omitted, falls back to the id of the last
  /// non-own message currently held by the room's [ChatController]. Passing
  /// the id allows the backend to fan out a `receipt_updated` event to the
  /// original sender so the second tick can flip to "read"; legacy callers
  /// that omit it still get the room-level `lastReadAt` persisted as before.
  @internal
  Future<ChatResult<void>> markAsRead(
    String roomId, {
    String? lastReadMessageId,
  }) => messages.markAsRead(roomId, lastReadMessageId: lastReadMessageId);

  /// Clears chat history for the current user (client-side only).
  @internal
  Future<ChatResult<void>> clearChat(String roomId) =>
      messages.clearChat(roomId);

  /// Sends a read/delivery receipt for a specific message.
  @internal
  Future<ChatResult<void>> sendReceipt(
    String roomId,
    String messageId, {
    ReceiptStatus status = ReceiptStatus.read,
  }) => messages.sendReceipt(roomId, messageId, status: status);

  /// Sends a direct message to a contact.
  @internal
  Future<ChatResult<ChatMessage>> sendDirectMessage(
    String contactUserId, {
    String? text,
    MessageType messageType = MessageType.regular,
    String? attachmentUrl,
    Map<String, dynamic>? metadata,
  }) => messages.sendDirect(
    contactUserId,
    text: text,
    messageType: messageType,
    attachmentUrl: attachmentUrl,
    metadata: metadata,
  );

  /// Uploads a file attachment.
  @internal
  Future<ChatResult<AttachmentUploadResult>> uploadAttachment(
    Uint8List data,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  }) => messages.uploadAttachment(
    data,
    mimeType,
    onProgress: onProgress,
    cancelToken: cancelToken,
  );

  /// High-level helper: uploads [pick] and dispatches the resulting
  /// attachment message in one shot. Picks the right [MessageType]
  /// (`audio` for `audio/*`, `attachment` otherwise — image/video also
  /// resolve to `attachment` and let the bubble layer pick the right
  /// renderer via the MIME type), materializes the DM draft inline when
  /// [roomIdOrDraftKey] points to a draft routing key, and
  /// surfaces upload progress via [voiceUploadProgressFor]-style hooks
  /// when [onProgress] is provided.
  ///
  /// When [policy] is supplied (and isn't [AttachmentPolicy.unrestricted]),
  /// the bytes + mime are validated server-side-of-the-app before any
  /// network call. Violations surface as a `ValidationFailure` so the
  /// consumer can render the right error string. The picker helpers
  /// in [AttachmentPickers] already enforce policies at pick time;
  /// passing it here is a belt-and-suspenders for paths that build the
  /// bytes themselves (web drop targets, share-extensions, …).
  ///
  /// Use this when the composer has a single full-in-memory pick result
  /// from [AttachmentPickers]. For voice messages keep using the
  /// dedicated [sendVoiceMessage] (it owns the waveform + duration).
  @internal
  Future<ChatResult<ChatMessage>> sendAttachment(
    String roomIdOrDraftKey, {
    required Uint8List bytes,
    required String mimeType,
    String? fileName,
    AttachmentPolicy policy = AttachmentPolicy.unrestricted,
    void Function(int sent, int total)? onProgress,
  }) => messages.sendAttachment(
    roomIdOrDraftKey,
    bytes: bytes,
    mimeType: mimeType,
    fileName: fileName,
    policy: policy,
    onProgress: onProgress,
  );

  /// Per-message upload progress notifiers (0..1) for voice messages
  /// that are being uploaded right now. Backed by [VoiceUploadRegistry]
  /// so the lifecycle (`register` → `complete` vs `drop`, then the
  /// session-teardown sweep) lives in its own tested service rather than
  /// scattered across this class.
  ///
  /// The teardown sweep drops the registry's references and destroys
  /// nothing: these notifiers leave the SDK through
  /// [voiceUploadProgressFor] / [attachmentUploadProgressFor], and a host
  /// that resolved one once and subscribed to it directly would get a
  /// use-after-dispose on its next rebuild. See [VoiceUploadRegistry] for
  /// the full argument.
  final VoiceUploadRegistry _voiceUploads = VoiceUploadRegistry();

  /// Cancel tokens for every blob currently on the wire — `sendAttachment`,
  /// its poster frame, and `sendVoice` — see [cancelAttachmentUpload], and
  /// [_resetConnectionState], which cancels the lot when a session ends.
  /// Kept apart from [_voiceUploads]: a progress notifier and a cancel token
  /// have unrelated lifecycles (see [AttachmentUploadCancelRegistry]'s doc).
  final AttachmentUploadCancelRegistry _attachmentUploadCancels =
      AttachmentUploadCancelRegistry();

  final FailedUploadRegistry _failedUploads = FailedUploadRegistry();

  /// Bytes held for media rows whose upload failed, so `messages.retrySend`
  /// on one of those bubbles re-uploads the same file instead of refusing.
  ///
  /// Exposed to tune the two caps ([FailedUploadRegistry.maxEntries],
  /// [FailedUploadRegistry.maxBytesPerEntry]) — a host on constrained
  /// devices can shrink them, one that ships large media can widen them.
  /// Retention is memory-only and ends with the session; the defaults hold
  /// up to 8 files of up to 12 MB each.
  FailedUploadRegistry get failedUploads => _failedUploads;

  /// The single source of optimistic-row ids for this adapter — text sends
  /// ([OptimisticHandler]), forwards and both upload paths draw from it, so
  /// no two sends can mint the same string whichever entry point they came
  /// through. See [TempIdMinter] for why one shared counter and not one per
  /// call site.
  final TempIdMinter _tempIds = TempIdMinter();

  /// Returns a listenable for the upload progress of a pending voice message.
  /// Returns `null` if there is no upload in flight for that id.
  ValueListenable<double>? voiceUploadProgressFor(String messageId) =>
      _voiceUploads.listenableFor(messageId);

  /// Returns a listenable for the upload progress of a pending
  /// `messages.sendAttachment` call (photo/video/file — anything that
  /// isn't a recorded voice clip). Same backing registry as
  /// [voiceUploadProgressFor]; a separate name keeps call sites readable.
  /// Returns `null` if there is no upload in flight for that id.
  ValueListenable<double>? attachmentUploadProgressFor(String messageId) =>
      _voiceUploads.listenableFor(messageId);

  /// Returns a listenable that reports whether the in-flight
  /// `messages.sendAttachment` upload for [messageId] can still be aborted
  /// — the signal behind the cancel X painted inside the progress ring.
  /// Returns `null` when there is no send in flight for that id.
  ///
  /// Deliberately a second signal rather than a reading of
  /// [attachmentUploadProgressFor]: the ring outlives cancellability. It
  /// stays up until the row reaches a real final state (bytes uploaded,
  /// poster frame uploaded, send acknowledged), because retiring it earlier
  /// leaves the bubble resolving an attachment URL the message does not
  /// carry yet. Cancelling stops being possible much earlier, the instant
  /// the bytes land. This flips to `false` there, in place, so a ring
  /// already on screen drops its X without waiting for an unrelated rebuild.
  ValueListenable<bool>? attachmentUploadCancellableFor(String messageId) =>
      _attachmentUploadCancels.cancellableFor(messageId);

  /// Cancels the in-flight `messages.sendAttachment` or `messages.sendVoice`
  /// upload for [messageId] (the temp id of the still-uploading provisional
  /// message) and leaves no trace of it: the provisional bubble is removed
  /// rather than left behind as failed — the user chose to abort, so there
  /// is nothing to retry. See `ChatMessagesController.sendAttachment` for
  /// the cleanup this triggers; `sendVoice` performs the same one.
  ///
  /// No-op if no upload is in flight for [messageId] — e.g. it already
  /// finished, already failed, or was already cancelled.
  void cancelAttachmentUpload(String messageId) {
    _attachmentUploadCancels.cancel(messageId);
  }

  /// Records and confirms a voice message: optimistic bubble first, then upload
  /// (with progress published to [voiceUploadProgressFor]), then send.
  ///
  /// The optimistic bubble is shown without a usable URL until upload completes
  /// — the UI hides the play button while [voiceUploadProgressFor] returns
  /// non-null. On success the bubble flips to the real URL; on failure it is
  /// marked as failed and the progress notifier is cleaned up.
  @internal
  Future<ChatResult<ChatMessage>> sendVoiceMessage(
    String roomIdOrDraftKey, {
    required Uint8List audioBytes,
    required String mimeType,
    required Duration duration,
    required List<int> waveform,
  }) => messages.sendVoice(
    roomIdOrDraftKey,
    audioBytes: audioBytes,
    mimeType: mimeType,
    duration: duration,
    waveform: waveform,
  );

  /// Generic optimistic toggle for a boolean room flag (muted / pinned /
  /// hidden). Flips the visible state immediately, calls [apiCall], and
  /// rolls back on failure. Emits an [OperationError] through
  /// [operationErrors] tagged with [kind] when the API call fails.
  ///
  /// Captured as a helper because the 6 toggle methods below — mute,
  /// unmute, pin, unpin, hide, unhide — share the exact same flow, just
  /// differing on which `RoomListItem` field flips and which `client.rooms`
  /// endpoint runs.
  Future<ChatResult<void>> _toggleRoomFlag(
    String roomId,
    RoomListItem Function(RoomListItem room, bool value) applyFlag,
    bool desiredValue,
    Future<ChatResult<void>> Function(String roomId) apiCall,
    OperationKind kind,
  ) async {
    final room = roomListController.getRoomById(roomId);
    if (room != null) {
      roomListController.updateRoom(applyFlag(room, desiredValue));
    }
    final result = await apiCall(roomId);
    if (result.isFailure && room != null) {
      roomListController.updateRoom(applyFlag(room, !desiredValue));
    }
    return _emitFailure(result, kind, roomId: roomId);
  }

  /// Mutes a room with optimistic update. Pass [until] for a timed mute.
  @internal
  Future<ChatResult<void>> muteRoom(String roomId, {DateTime? until}) =>
      rooms.mute(roomId, until: until);

  /// Unmutes a room with optimistic update.
  @internal
  Future<ChatResult<void>> unmuteRoom(String roomId) => rooms.unmute(roomId);

  /// Pins a room with optimistic update.
  @internal
  Future<ChatResult<void>> pinRoom(String roomId) => rooms.pin(roomId);

  /// Unpins a room with optimistic update.
  @internal
  Future<ChatResult<void>> unpinRoom(String roomId) => rooms.unpin(roomId);

  /// Hides a room with optimistic update (removes from visible list).
  @internal
  Future<ChatResult<void>> hideRoom(String roomId) => rooms.hide(roomId);

  /// Unhides a room with optimistic update.
  @internal
  Future<ChatResult<void>> unhideRoom(String roomId) => rooms.unhide(roomId);

  /// Blocks a contact. WhatsApp-parity: the DM room STAYS in the
  /// blocker's chat list with full history — the composer is replaced
  /// by a "tap to unblock" banner (see [ChatView.isBlocked]) so the
  /// blocker can reverse course. The previous implementation removed
  /// the room entirely and forced consumers to pop the chat page,
  /// which lost the conversation context and surprised users.
  ///
  /// Adds [userId] to [blockedUserIds] and fires
  /// [onBlockedUsersChanged] so the host UI can react (e.g. hide
  /// suggestions, swap the composer for the blocked banner).
  @internal
  Future<ChatResult<void>> blockContact(String userId, {String? roomId}) =>
      contacts.block(userId, roomId: roomId);

  /// Unblocks a contact in the chat system. Removes [userId] from
  /// [blockedUserIds] and fires [onBlockedUsersChanged]. Does NOT
  /// recreate the DM row — consumers that need the room back should
  /// call [loadRooms] or open a fresh draft via
  /// [openDirectMessageDraft].
  @internal
  Future<ChatResult<void>> unblockContact(String userId) =>
      contacts.unblock(userId);

  /// Adds [userIds] to [roomId] as group members. WhatsApp-style default:
  /// [mode] = `RoomUserMode.inviteAndJoin` — the invited users join
  /// immediately without requiring an accept step. Apps that need an
  /// invitation-then-accept flow pass [mode] = `RoomUserMode.invite`.
  ///
  /// On success the adapter does NOT mutate the local
  /// [roomListController] directly — the backend emits a
  /// `UserJoinedEvent` per added user that the event router already
  /// turns into `ChatController.setOtherUsers` updates and metadata
  /// refreshes. This keeps the local state consistent with anyone else
  /// observing the same room (multi-device, web client, etc.).
  @internal
  Future<ChatResult<void>> addMembers(
    String roomId,
    List<String> userIds, {
    RoomUserMode mode = RoomUserMode.inviteAndJoin,
  }) => rooms.addMembers(roomId, userIds, mode: mode);

  /// Updates room metadata (name, subject, avatar, custom). Wrapper
  /// around `client.rooms.updateConfig` that emits [operationErrors]
  /// with [OperationKind.updateRoomConfig] on failure. Backend gates
  /// this on owner/admin role; non-privileged callers get a 403.
  @internal
  Future<ChatResult<void>> updateRoomConfig(
    String roomId, {
    String? name,
    String? subject,
    String? avatarUrl,
    Map<String, dynamic>? custom,
  }) => rooms.updateConfig(
    roomId,
    name: name,
    subject: subject,
    avatarUrl: avatarUrl,
    custom: custom,
  );

  /// Creates a group room in a single hop, optionally uploading an
  /// avatar first. Returns the newly-created room id on success so the
  /// caller can navigate straight into it.
  @internal
  Future<ChatResult<String>> createGroupRoom({
    required String name,
    required List<String> memberIds,
    Uint8List? avatarBytes,
    String? avatarMimeType,
    String? subject,
    bool allowInvitations = false,
    RoomAudience audience = RoomAudience.contacts,
    Map<String, dynamic>? custom,
  }) => rooms.createGroup(
    name: name,
    memberIds: memberIds,
    avatarBytes: avatarBytes,
    avatarMimeType: avatarMimeType,
    subject: subject,
    allowInvitations: allowInvitations,
    audience: audience,
    custom: custom,
  );

  bool _currentUserAvatarProbed = false;

  /// Removes [userId] from [roomId] — used by admins to kick a member.
  /// The backend rejects the call (403) if the caller lacks the
  /// permission; the SDK surfaces the failure via [operationErrors] like
  /// any other adapter op. On success the backend emits `UserLeftEvent`
  /// to all participants, which `ChatEventRouter` already handles.
  @internal
  Future<ChatResult<void>> removeMember(String roomId, String userId) =>
      rooms.removeMember(roomId, userId);

  /// Updates [userId]'s [RoomRole] inside [roomId] — admins promote
  /// members or demote other admins. Backend rejects if the caller lacks
  /// the permission (the SDK surfaces the failure via [operationErrors]).
  /// On success the backend emits `UserRoleChangedEvent` and the event
  /// router refreshes member lists.
  @internal
  Future<ChatResult<void>> updateMemberRole(
    String roomId,
    String userId,
    RoomRole role,
  ) => rooms.updateMemberRole(roomId, userId, role);

  /// Leaves a room and removes it from the list.
  @internal
  Future<ChatResult<void>> leaveRoom(String roomId) => rooms.leave(roomId);

  /// Retries sending a failed message.
  @internal
  Future<ChatResult<ChatMessage>> retrySend(String roomId, String messageId) =>
      messages.retrySend(roomId, messageId);

  /// Loads thread replies for a parent message.
  Future<ChatResult<List<ChatMessage>>> loadThread(
    String roomId,
    String messageId, {
    int limit = 50,
  }) => messages.loadThread(roomId, messageId, limit: limit);

  /// Sends a reply within a thread.
  ///
  /// Emits `OperationKind.sendThreadReply` on failure (not the generic
  /// `sendMessage`), so a single consumer of `operationErrors` does not
  /// receive a duplicate event for the same underlying failure.
  @internal
  Future<ChatResult<ChatMessage>> sendThreadReply(
    String roomId,
    String parentMessageId, {
    required String text,
  }) => messages.sendThreadReply(roomId, parentMessageId, text: text);

  /// Searches messages within a room. Returns a paginated response so callers
  /// (e.g. `MessageSearchController`) can drive load-more via `hasMore`.
  Future<ChatResult<ChatPaginatedResponse<ChatMessage>>> searchMessages(
    String query,
    String roomId, {
    ChatPaginationParams? pagination,
  }) => messages.search(query, roomId, pagination: pagination);

  /// Loads read receipts for a room.
  Future<ChatResult<List<ReadReceipt>>> loadReceipts(String roomId) =>
      messages.loadReceipts(roomId);

  /// Accepts a room invitation.
  @internal
  Future<ChatResult<void>> acceptInvitation(String roomId) =>
      rooms.acceptInvitation(roomId);

  /// Rejects a room invitation and removes it from the list. Restores the
  /// row on failure so a network glitch does not silently lose the invite.
  @internal
  Future<ChatResult<void>> rejectInvitation(String roomId) =>
      rooms.rejectInvitation(roomId);

  /// Pins a message in a room with optimistic update. Restores on failure.
  @internal
  Future<ChatResult<void>> pinMessage(String roomId, String messageId) =>
      messages.pin(roomId, messageId);

  /// Unpins a message from a room with optimistic update. Restores on failure.
  @internal
  Future<ChatResult<void>> unpinMessage(String roomId, String messageId) =>
      messages.unpin(roomId, messageId);

  /// Loads all pinned messages for a room and updates the controller state.
  Future<ChatResult<List<MessagePin>>> loadPins(String roomId) =>
      messages.loadPins(roomId);

  // --- Event Handlers ---

  /// Routes a real-time event from the SDK to the right adapter helper.
  /// All cases live in [ChatEventRouter] so this facade only carries the
  /// one-line delegate.
  late final ChatEventRouter _eventRouter = ChatEventRouter(
    ChatEventRouterDeps(
      client: client,
      controllers: _chatControllers,
      roomList: roomListController,
      dmContacts: _dmContacts,
      userCacheService: _userCacheService,
      pendingReactions: _pendingReactionsRegistry,
      presence: _presence,
      cache: _cache,
      connectionStateNotifier: connectionStateNotifier,
      autoMarkAsRead: autoMarkAsRead,
      autoConfirmDelivery: autoConfirmDelivery,
      currentUser: () => _currentUser,
      setCurrentUser: (user) => _currentUser = user,
      activeRoomId: () => _activeRoomId,
      isDisposed: () => _disposed,
      findCachedUser: findCachedUser,
      cacheUsersFn: cacheUsers,
      ensureUserCachedFn: _ensureUserCached,
      markAsReadFn: markAsRead,
      confirmDeliveredFn: _deliveredCoord.confirm,
      refreshMessageFn: _refreshMessage,
      refreshReactionsFn: _refreshReactions,
      handleUserJoinedFn: (roomId, userId) {
        _roomRosters.add(roomId, userId);
        _memberEventHandler.handleUserJoined(roomId, userId);
      },
      handleUserLeftFn: (roomId, userId, {String? actorUserId}) {
        _roomRosters.remove(roomId, userId);
        _memberEventHandler.handleUserLeft(
          roomId,
          userId,
          actorUserId: actorUserId,
        );
      },
      handleUserRejoinedFn: (roomId, userId) {
        _roomRosters.add(roomId, userId);
        _memberEventHandler.handleUserRejoined(roomId, userId);
      },
      addSystemMessageFn: _memberEventHandler.addSystemMessage,
      addRoomFromDetailFn: _addRoomFromDetail,
      enrichRoomFromDetailFn: _enrichRoomFromDetail,
      notifyRoomMembersChangedFn: notifyRoomMembersChanged,
      updateRoomLastMessage: (roomId, message) =>
          _roomListMutator.updateRoomLastMessage(roomId, message),
      updateRoomListReceipt: (roomId, messageId, status) =>
          _roomListMutator.updateRoomListReceipt(roomId, messageId, status),
      updateRoomReactionPreview: (roomId, reaction, userId, messageId) =>
          _roomListMutator.updateRoomReactionPreview(
            roomId,
            reaction,
            userId,
            messageId,
          ),
      updateRoomUnread: (roomId, count) =>
          _roomListMutator.updateRoomUnread(roomId, count),
      removeChatController: removeChatController,
      analyticsEmit: emitAnalyticsEvent,
      onAdminMessage: () => onAdminMessage,
      onBroadcast: () => onBroadcast,
      onError: () => onError,
      onReconnected: () => onReconnected,
      onRoomRemoved: () => onRoomRemoved,
      triggerResync: () {
        if (enableReconnectResync) unawaited(resync());
      },
    ),
  );

  void _refreshReactions(String roomId, String messageId) {
    final controller = _chatControllers[roomId];
    if (controller == null) return;
    client.messages
        .getReactions(roomId, messageId, cachePolicy: CachePolicy.networkOnly)
        .then((result) {
          if (_disposed) return;
          final active = _chatControllers[roomId];
          if (active == null) return;
          if (result.isFailure) {
            active.clearReactions(messageId);
            return;
          }
          final aggregated = result.dataOrThrow;
          final map = <String, int>{};
          final ownEmojis = <String>{};
          for (final r in aggregated) {
            map[r.emoji] = r.count;
            if (r.users.contains(currentUser.id)) {
              ownEmojis.add(r.emoji);
            }
          }
          active.setReactions(messageId, map);
          active.setUserReactions(messageId, ownEmojis);
        })
        .catchError((Object e) {
          logger?.call(
            'warn',
            'Failed to refresh reactions for $messageId: $e',
          );
        });
  }

  /// Adds a room to the controller AFTER a successful detail fetch.
  ///
  /// Used when the adapter learns about a new room via realtime events
  /// (`NewMessageEvent`, `RoomCreatedEvent`) and the room is not yet in the
  /// controller. We deliberately do NOT add a placeholder `RoomListItem(id:)`
  /// because doing so would cause the UI to briefly render a "ghost" room
  /// (raw roomId as title, no avatar) until the detail enrichment succeeds.
  ///
  /// If the detail fetch fails, the room is not added. The next `loadRooms`
  /// call will pick it up if the server still knows about it.
  void _addRoomFromDetail(String roomId, {ChatMessage? lastMessage}) =>
      _enricher.addFromDetail(roomId, lastMessage: lastMessage);

  void _enrichRoomFromDetail(String roomId) => _enricher.refreshRoom(roomId);

  /// Re-fetches a message after a realtime event that carried no row.
  ///
  /// There is no server-side unit GET, so `client.messages.get` resolves
  /// against the id-indexed local cache first. That cache can still hold the
  /// row as it was BEFORE the event this refresh is reacting to, and applying
  /// such a row overwrites what the event just rendered.
  ///
  /// [expectDeleted] marks the `message_deleted` path: there a row that comes
  /// back alive is stale by definition, so it is dropped instead of resurrect-
  /// ing the text over the tombstone (and stamping "edited" on a message that
  /// was never edited). Only a row confirming the deletion is applied — that
  /// is the one carrying `adminDeleted`, which is why this refresh exists.
  void _refreshMessage(
    String roomId,
    String messageId, {
    bool expectDeleted = false,
  }) {
    final controller = _chatControllers[roomId];
    if (controller == null) return;
    client.messages
        .get(roomId, messageId)
        .then((result) {
          if (_disposed) return;
          final active = _chatControllers[roomId];
          if (active == null) return;
          final updated = result.dataOrNull;
          if (updated == null) return;
          if (expectDeleted) {
            if (!updated.isDeleted) return;
            active.updateMessage(updated);
            _cache?.updateMessage(roomId, updated);
            return;
          }
          // Edit path. The REST projection may omit `text_history`, dropping
          // the "edited" marker; force it on so the tag survives. But a row
          // identical to the one already on screen is the same stale cache
          // hit the delete path guards against — the edit has not landed
          // locally yet — and forcing the marker on it would tag the
          // PRE-edit text as edited.
          final current = active.messages
              .where((m) => m.id == messageId)
              .firstOrNull;
          if (current != null &&
              current.text == updated.text &&
              current.isDeleted == updated.isDeleted) {
            return;
          }
          final refreshed = updated.isDeleted
              ? updated
              : updated.copyWith(isEdited: true);
          active.updateMessage(refreshed);
          _cache?.updateMessage(roomId, refreshed);
        })
        .catchError((Object e) {
          logger?.call('warn', 'Failed to refresh message $messageId: $e');
        });
  }

  /// "Delete kicked chat" — WhatsApp's option to manually remove a
  /// chat the user was kicked from. Drops it from the room list,
  /// clears the local cache for the room (messages, detail,
  /// unreads), and unmarks the kicked flag. No network call — the
  /// server already considers the user removed.
  ///
  /// Surfaced via [ChatRoomOption.deleteKickedChat] in the room
  /// options menu when `room.isParticipating == false`. Safe to
  /// call on participating rooms too (does the same cleanup), but
  /// the UI only exposes it after a kick.
  @internal
  Future<void> deleteKickedChat(String roomId) => rooms.deleteKicked(roomId);

  /// Token-first, like [mapExceptionToFailure] does for the edit/delete
  /// windows: the stable `error` token wins over the legacy `detail`
  /// string match. Sending into a blocked room answers
  /// `403 {"detail":"blocked","error":"blocked"}`, but creating the 1:1
  /// room answers `403 {"detail":"Cannot create room with blocked user:
  /// ID","error":"blocked"}` — prose in `detail`, the token only in
  /// `error`. Matching on `detail` alone made every room-materialization
  /// path miss the block.
  bool _isBlockedError(ChatFailure? failure) {
    if (failure is! ForbiddenFailure) return false;
    if (failure.errorToken == ChatErrorTokens.blocked) return true;
    final body = failure.body;
    if (body is Map) {
      return body['detail'] == ChatErrorTokens.blocked;
    }
    return false;
  }

  /// A send rejected because an admin muted the user in this room. The
  /// backend returns `403 {"detail":"muted"}` (see `guard_not_muted/2`),
  /// the mute sibling of the `"blocked"` detail handled above.
  bool _isMutedError(ChatFailure? failure) {
    if (failure is! ForbiddenFailure) return false;
    final body = failure.body;
    if (body is Map) {
      return body['detail'] == 'muted';
    }
    return false;
  }
}

// Note: the `_PendingMarkAsRead` tracker now lives inside
// `services/mark_as_read_coordinator.dart` together with the
// coalescing logic that uses it.

/// Internal `ChangeNotifier` subclass that exposes `notifyListeners` via
/// the public method [emit]. The adapter needs to fire a coarse "user
/// cache changed" signal from outside the notifier itself; the base
/// `notifyListeners` is `@protected` so we wrap it.
class _BroadcastNotifier extends ChangeNotifier {
  void emit() => notifyListeners();
}
