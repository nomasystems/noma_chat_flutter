# Migration guide

## 0.33.x → 0.34.0

Nothing is removed. Two defaults change what they do at runtime (each with
an opt-out), one field is added to `ChatViewBuilders`, and — the change with
the widest reach — an unresolved display name stops falling back to the raw
id anywhere in the UI layer.

### No id is ever painted as a name

`ChatUiAdapter.displayNameFor(userId)` used to fall back to `userId` itself
when nobody had a name for that person. It now falls back to an **empty
string**. This is the one true breaking change in this release, in the
sense that it changes what a lot of surfaces render, even though no
signature moves: `MentionOverlay`, `UserProfileView`, `UserInfoPage`,
`GroupMembersView`, `MemberPickerSheet`, `BlockedUsersView`,
`MessageInfoSheet`, the reaction-detail sheet, `TypingStatusText`, the
default `userFetcher` of `NomaChatView`, and a room's default title for a
1:1 whose other member has no resolved name (`RoomTitleContext` /
`RoomListItem.displayName`) all used to show a raw UUID as a last resort and
now show nothing there instead.

If your app read `displayNameFor` (or one of the widgets above) expecting a
usable string in every case, add your own placeholder for the empty case —
the SDK deliberately no longer decides what that placeholder says:

```dart
final label = chat.adapter.displayNameFor(userId);
Text(label.isEmpty ? 'Unknown' : label);
```

Two related, narrower spots keep the old "use the id" behaviour on purpose,
because the id there is not decoration but a sentinel the SDK itself relies
on to know a name has not arrived yet:

- Membership banners ("X joined", "X left") still compose with the id
  internally while a name lookup is in flight, and repaint themselves once
  it resolves — but `metadata['userLabel']` / `metadata['actorLabel']` on
  the persisted system message are now blank, not the id, once the lookup
  gives up. `metadata['userId']` still carries the id itself, unchanged.
- `MessageInput`'s @mention autocomplete no longer inserts `@<uuid>` into
  the message text when the mentioned person has no resolvable name; it
  closes the overlay and leaves the composer text as the user typed it.

### A DM's default title is no longer the other member's id

Before a name resolves, a 1:1 room without its own `name` used to show the
other member's raw id as its title (`RoomTile`, the chat app bar). It now
shows nothing there and falls through to whatever `RoomListItem.name`
carries, and finally to an empty string — never a UUID. Order of
resolution for a 1:1's title: `RoomTitleResolver` (if you supply one) →
name from `userDirectoryResolver` → chat's own cached profile name → empty.
A host that wants a placeholder while a name is still resolving supplies one
through `RoomTitleResolver` or the empty-string case of whatever renders the
title, exactly as for the point above.

### `ChatViewBuilders` gains `readOnlyNoticeBuilder`

A new named field. Code that builds `ChatViewBuilders` with named arguments
(the only supported way — it is `const`) compiles unchanged. See
[Developer Guide — ReadOnlyNoticeBuilder](./doc/DEVELOPER_GUIDE.md#readonlynoticebuilder--why-a-room-is-read-only)
for what it is for.

### A room can now be closed by the backend's write policy, not just by its type

`RoomDetail.isReadOnly` / `RoomListItem.isReadOnly` gain a third cause,
combined with `||` alongside the two that already existed (a non-owner in an
announcement channel, a moderation mute): `RoomConfig.writePolicy ==
RoomWritePolicy.ownerOnly && userRole != owner`. No backend sends this field
yet, so the practical effect today is nil — but a room whose backend starts
setting `config.writePolicy: "owner_only"` will close its composer for every
member but the owner from the moment this version is running, with no
further app change needed. See
[Developer Guide — ReadOnlyNoticeBuilder](./doc/DEVELOPER_GUIDE.md#readonlynoticebuilder--why-a-room-is-read-only).

### The room list's text filter matches strictly more rooms than before

`RoomListController`'s search used to compare the query against the room's
raw `name` and its last message only — never the *resolved* title. A 1:1
room without its own name (the common case: its title comes from
`RoomTitleResolver` or the other member's profile) was invisible to the
search box even when the title on screen matched the query. The filter now
matches `displayName` (falls back to `name`) and, when a
`participantNameResolver` is wired, the room's participants too. A room
that used to match still matches; some that did not now do. See
[Developer Guide — ParticipantNameResolver](./doc/DEVELOPER_GUIDE.md#participantnameresolver--recordroomroster--searching-the-room-list-by-member).

### The first send after a new DM room is created now retries automatically

`sendRetryPolicy` defaults to `SendRetryPolicy.firstSendOnly()`: a send that
raced its own room's creation and came back "room not found" is retried
automatically, up to three times, reusing the original optimistic id so a
send that actually landed is never duplicated. A host that relied on that
failure surfacing immediately to the user restores the 0.33 behaviour with:

```dart
NomaChat.create(..., sendRetryPolicy: const SendRetryPolicy.none())
```

### Outgoing images are shrunk by default on every picker path

`AttachmentPickers.pickImageFromCamera` / `pickImageFromGallery` /
`pickVideoFromGallery` / `pickMultipleMedia` / `pickFile` now default their
new `shrinker:` parameter to `DefaultAttachmentShrinker` instead of sending
untouched bytes: an oversized `image/*` pick is resized and re-encoded as
JPEG before it reaches your send call. A non-image is never touched. Opt
out per call with `shrinker: const NoAttachmentShrinker()`, or per policy
with `AttachmentPolicy(shrinkEnabled: false)`. `ChatUiAdapter
(attachmentShrinker: ...)` — the engine used by `NomaChatView`'s own capture
path — keeps its own separate default of `NoAttachmentShrinker`, unchanged.
See [Developer Guide — attachmentShrinker](./doc/DEVELOPER_GUIDE.md#attachmentshrinker--outgoing-image-reduction).

`AttachmentPolicy.deniedExtensions` is now also checked on the image/video
picker paths, not only on `pickFile` as before — a policy relying on that
list to block a specific extension now blocks it everywhere, not only on
generic file picks.

## 0.31.x → 0.32.0

Breaking at compile time in exactly one place: pushing the in-app camera
screen yourself.

### `CameraCapturePage.show()` returns a `CameraCaptureSubmission`, not a `CameraCaptureResult`

The screen now has a caption field on its review step, so what it hands
back is the confirmed capture *plus* that caption:

```dart
// Before (0.31.x and earlier)
final CameraCaptureResult? shot = await CameraCapturePage.show(context: context);

// After (0.32.0+)
final CameraCaptureSubmission? submission = await CameraCapturePage.show(context: context);
if (submission == null) return;
final CameraCaptureResult shot = submission.capture;
final String? caption = submission.caption;
```

`CameraCaptureReview.onSend` changes from a `VoidCallback` to a
`ValueChanged<String?>` (the typed caption, or `null`) for the same reason —
relevant only to a host that mounts `CameraCaptureReview` directly rather
than through `CameraCapturePage.show()`.

Nothing else moves: `NomaChatView`'s own camera row already handles this
internally, so a host that never calls `CameraCapturePage.show()` or
`CameraCaptureReview` by hand is unaffected.

## 0.28.x → 0.29.0

No compile-time break. Two fixes change what an existing call site
*answers* without changing what it compiles to — read this before
upgrading if you act on either result.

### Deleting a room can now fail, and says so

`ChatRoomsController.delete` used to drop the row from the list and report
success regardless of whether the durable "deleted" marker was actually
written. It now returns a failure — and leaves the row on screen — when
that write fails, since a row dropped without its marker used to reappear
on the next list rebuild with its old preview intact, which is worse than a
delete that visibly did nothing. Key any "deleted" confirmation UI off this
result rather than assuming the call always succeeds.

### `markRoomDeleted` / `clearRoomDeleted` / `getDeletedRoomIds` no longer swallow failures

These three used to collapse a datasource failure into success (for the
first two) or into an empty set (for the third). They now propagate the
underlying `ChatResult` as-is. A direct caller that treated them as
infallible will start seeing failures it was previously blind to.

## 0.27.x → 0.28.0

Two changes break a build; the rest change what an existing screen does
without touching what it compiles to.

### `onSendMessageRequest` / `onEditMessage` / `onSendReply` answer *was this taken?*, not *did it arrive?*

On `ChatViewCallbacks`, on `MessageInput` (same-named constructor
parameters), and on `ThreadView.onSendReply`, the callback type changes from
`void Function(...)` to `FutureOr<bool> Function(...)`. A callback that
dispatches unconditionally and does not care about the hand-back path
migrates by ending with `return true`:

```dart
// Before
onSendMessageRequest: (text) { myQueue.enqueue(text); },

// After
onSendMessageRequest: (text) { myQueue.enqueue(text); return true; },
```

- `true` — something now owns the message (an optimistic bubble, a queue);
  the composer clears exactly as before. A send that reached the wire and
  failed there is still `true`: it has its own failed bubble with its own
  retry.
- `false` — the request was refused outright with nowhere else for the
  wording to live (a closed contact gate, a read-only room, a moderation
  veto). The composer hands the text back — where the user left it, under
  the reply it was answering, with edit mode reopened on the message being
  edited — unless the user has already started typing something else in
  the meantime, in which case the hand-back is silently dropped.

### `RoomListItem` and `UnreadRoom` gain a field in the middle of their constructors

Both models add `lastMessageIsSystem` (`bool`, default `false`). The named
constructors and `copyWith` are unaffected — every call site that names its
arguments compiles unchanged. What breaks:

- Freezed's generated **positional** callbacks — `when`, `maybeWhen`,
  `whenOrNull` — take one more positional argument in the field's position.
  Any call site already using one of those on `RoomListItem` or `UnreadRoom`
  needs the new parameter added.
- A host implementing `ChatRoomsApi` itself (rather than using the SDK's)
  must add the matching `bool? lastMessageIsSystem` parameter that
  `updateCachedRoomPreview` gains.

### Two behaviour changes ride along silently — a call site that still compiles does not mean it still does the same thing

- **`ChatViewBehaviors.withRoomState` stops overwriting a host's own
  `readOnly` / `readOnlyLabel`.** They are now combined with `||`/host-wins
  rules instead of the room state replacing them outright: the composer
  stays closed when *either* the room or the host says so. An app that
  closed the composer for a reason only it knew (a contact gate, a
  per-app permission) was being silently re-opened by any room the SDK
  itself considered writable — that no longer happens.
- **`RoomTile.lastMessagePreviewBuilder` no longer gets a `"Name: "` sender
  prefix put in front of it.** A non-null return value is now taken as a
  finished sentence and painted as-is. A host whose builder already names
  the actor was getting a duplicated prefix ("Alice: Alice joined"); one
  that relied on the SDK to prepend the name now has to do it itself.

## 0.26.x → 0.27.0

Nothing breaks at compile time: no API was removed or narrowed. Four
defaults changed what they do at runtime, and each has an opt-out.

### An empty room now draws a card

A room with no messages used to be an icon and a line of text. It now
shows `DefaultEmptyRoomState` — the same explanation plus, in a 1:1 that
can be written to, a one-tap 👋 that sends the first message.

- Keep the labels you already set: `ChatViewBehaviors.emptyTitle` /
  `emptySubtitle` / `emptyIcon` still win over the SDK's.
- Take the whole card over: `ChatViewBuilders.emptyRoomBuilder`. Return
  `null` for rooms you have nothing to say about and the SDK card is drawn
  for those.
- Suppress the greeting without suppressing the card: build
  `EmptyRoomState(suggestions: const [])` from the builder.

```dart
builders: ChatViewBuilders(
  emptyRoomBuilder: (context, room) => EmptyRoomState(
    title: myTitleFor(room.roomId),
    header: MyPlanCard(room.roomId),
    actions: [MySharePlanButton(room.roomId)],
  ),
),
```

### The unread divider lands somewhere else

It anchors on the reader's own read cursor instead of counting back from
the end of the loaded page, so it no longer appears above the date
separator or above the reader's own messages, and it is not drawn until
the first page has settled. A host that fed `ChatViewBehaviors.unreadCount`
keeps working — that count is now the fallback used when no cursor is
available, not the primary source.

### A group's grey ✓✓ has a narrower divisor

Delivery is now judged against the members who have ever acknowledged
something in the room, not the whole roster. Restore the old behaviour per
controller:

```dart
ChatController(groupReceiptPolicy: GroupReceiptPolicy.allMembers)
```

Blue is unchanged: it still requires every member of the room.

### The open context menu tints its row

Opt out with `MessageList.highlightRowWhileContextMenuOpen: false`, or
drive `activeRowMessageId` yourself to decide which row is tinted and when.

## 0.25.x → 0.26.0

### Breaking: `MessageAction` gained `discardFailed`

**What fails.** Only an *exhaustive* `switch` over `MessageAction` with no
default arm — the same shape that breaks on a new `MessageType` or
`ChatFailure` variant:

```
The type 'MessageAction' is not exhaustively matched by the switch cases
since it doesn't match 'MessageAction.discardFailed'.
```

**The fix.** Handle it, or add the wildcard arm that keeps the switch
forward compatible:

```dart
    switch (action) {
      // …
      case MessageAction.discardFailed:
        adapter.messages.discardFailed(roomId, message.id);
      default:
        break;
    }
```

`discardFailed` is offered only on an outgoing row whose send failed, and
only when the menu is told the row is failed
(`MessageContextMenu(isFailed: …)` — `ChatView` passes it for you). It drops
the bubble, its cached pending copy and any bytes retained for it; nothing
goes to the server, because the message never got there.

**If you pass your own `enabledActions`**, adding `discardFailed` to the set
is optional. A set that has `delete` and not `discardFailed` keeps its own
`delete` on failed rows — ungated by the delete window, which has nothing
to say about a message the server never saw — so the user always has a way
out of the red bubble, and `NomaChatView`'s built-in delete callback
discards such a row rather than asking the server to delete something it
never received. Adopt `discardFailed` for the explicit version of it; keep
your own set if you route `delete` yourself, but route it to
`ChatUiAdapter.messages.discardFailed` when the row is failed.

### Breaking: `ChatClient` gained `cancelOfflineSend`

**What fails.** Only a class that `implements ChatClient` — a hand-rolled
client or a test double that is not `MockChatClient`:

```
Missing concrete implementation of 'ChatClient.cancelOfflineSend'.
```

**The fix.** Drop whatever your offline queue holds for that optimistic
row, and return how many operations went. A client with no queue returns
`0`:

```dart
  @override
  int cancelOfflineSend(String tempId) => 0;
```

**Why it exists.** A send that failed on connectivity leaves a copy of
itself in the offline queue, which drains on every reconnect. Discarding
the failed bubble therefore sent the message anyway, and retrying it sent
it twice; `discardFailed` and `retrySend` now call this first. If your
client owns a queue, a `0` here reintroduces both.

### Three defaults changed behaviour

None of these break a build. All three are opt-out.

**Deleting a message now asks first.** `MessageAction.delete` — the delete
that reaches everyone and cannot be undone — goes through a confirmation
dialog before anything is sent. `MessageAction.deleteForMe` and
`MessageAction.discardFailed` are not gated: neither leaves the device.
Turn it off with `ChatViewBehaviors(confirmDeleteForEveryone: false)` if you
run a confirmation of your own.

This lives in `NomaChatView`'s built-in `onDeleteMessage`. A host that
supplies its own `ChatViewCallbacks.onDeleteMessage`, or that replaces the
long-press menu wholesale through `ChatViewCallbacks.onMessageLongPress`,
owns the confirmation itself — the SDK never sees the tap.

**Blocked senders are pruned inside groups.** A blocked person's messages
used to stay fully readable in a group room. They are now replaced by a
one-line placeholder (`BlockedContentPolicy.placeholder`, the new default).
`ChatViewBehaviors.blockedContentPolicy` takes `hide` (drop the rows
outright) or `show` (the old behaviour — for a host whose backend already
filters blocked content server-side). `NomaChatView` fills the id set from
`ChatUiAdapter.blockedUserIds`; pass `ChatViewBehaviors.blockedSenderIds`
to filter on a different set.

1:1 chats are untouched, whatever the policy says: the history stays whole
and readable, quotes included, and the only thing a block changes there is
the blocked-contact banner over the composer — which `NomaChatView` already
raised on its own, resolving the peer from the room's `otherUserId` against
`ChatUiAdapter.blockedUserIds`, with no host wiring. No room notice either:
nothing is being pruned to explain.

The prune covers the whole room, not just the bubble: the quoted strip a
reply paints of a blocked message, the reactions a blocked user left on
anyone's message, and — through `RoomListView` / `RoomTile` — the room
list preview of a group whose last message is theirs. A group that is
pruning also carries a one-line notice at the top of the history
(`ChatUiLocalizations.blockedInRoomNotice`), so the reader can tell why
part of the conversation is missing.

`blockedSenderIds` holds **chat** user ids — the same space as
`ChatMessage.from`, `RoomListItem.otherUserId` and
`ChatUiAdapter.contacts.block`. A host that keys blocking on its own user
ids must map them before handing the set over; an id that matches nobody
prunes nothing and looks exactly like the feature being off.

**A failed media send stops claiming it was sent.** The chat-list row is
stamped with the message the moment you hit send; when the upload or the
send then failed, nothing used to undo it, so the list read "You: 📷 Photo"
with a sent tick for a photo that never left the device. The preview now
falls back to the room's newest real message, or clears when the failed
send was the only one. Text sends are unchanged.

### New, additive

- **`ChatUiAdapter.messages.discardFailed(roomId, messageId)`** — the way
  out of a failed send the user has decided not to make. It empties the
  offline queue of that row too, so nothing delivers it later.
- **`ChatUiAdapter.failedUploads`** — a `FailedUploadRegistry` holding the
  bytes of failed uploads so `messages.retrySend` can re-upload them
  instead of refusing with `attachment_never_uploaded`. Memory-only, ends
  with the session, and bounded by two tunable caps (`maxEntries`, default
  8; `maxBytesPerEntry`, default 12 MB). Past the cap nothing is retained
  and the retry refuses exactly as it did before.
- **`ChatController.setEditingMessage(message, {draftText})`** and
  **`ChatController.editingDraftText`** — seed the composer with something
  other than the message's own text. `NomaChatView` uses it to hand back
  what the user had typed when an edit is refused with the 403
  `edit_window_expired` that used to be silent
  (`ChatViewBehaviors.restoreComposerOnEditFailure`, `true` by default);
  the reason arrives alongside it as a snackbar on the operation-error
  stream. Any other refusal leaves the composer shut, because nothing
  would be telling the user why it reopened.
- **`showChatNotice(context, message, {snackBarBuilder})`** and
  **`ChatNoticeScope`** — see below.
- **`ChatViewBuilders.blockedMessageBuilder`** — replace the built-in
  blocked-sender placeholder.
- **`MessageList.blockedSenderIds` / `.blockedContentPolicy` /
  `.blockedMessageBuilder`** — the same knobs, for a host driving
  `MessageList` directly. It prunes in groups only, decided by its own
  `isGroup` (host flag first, `otherUsers.length > 1` as the fallback).
- **`RoomListView.blockedSenderIds` / `.blockedContentPolicy`** and
  **`RoomTile.blockedSenderIds` / `.blockedContentPolicy`** — the preview
  side of the same prune. `RoomListView` defaults the set to the
  `adapter`'s when one is wired, so a list and the rooms it opens agree
  without the host repeating himself; pass `const {}` to opt out.
- **`ChatViewCallbacks.onDiscardFailedMessage`** — wired by `NomaChatView`.

### A `user_joined` / `user_left` frame — and opening a room — refresh the room detail

`RoomListItem.memberCount` only ever came from a room-detail fetch, and a
join refreshed the roster without going back for it — so a header counting
participants kept the number it was opened with, contradicting the "…
joined" card printed right underneath, and kept it across a
leave-and-reopen because the cached detail was stale too. Both frames now
invalidate the cached detail and re-read it, the way `user_role_changed`
already did.

`ChatUiAdapter.setActiveRoom(roomId)` re-reads it as well, for a room the
list already knows: frames alone are only as reliable as the socket, and
one lost to a reconnect used to leave the count wrong for the lifetime of
the row. Nothing to change on your side. Expect one `GET /rooms/{id}` per
room entry and per membership change — reads are single-flighted per room,
and a burst of frames collapses into one read plus one trailing re-read
rather than one read per frame.

### Non-text bubbles read differently under a screen reader

Only `Semantics` labels changed; nothing visual moved. A caption now
follows its type label instead of replacing it ("You: Photo, en la playa,
Sent"), and a forward announces itself ("You: Forwarded, …"). If you
assert on bubble semantics in widget tests, those two strings are the ones
that changed. `mediaSemanticLabel(message, l10n)` is the exported helper
that builds the body, should you want the same wording elsewhere; it
returns `null` for a message that is nothing but its own text.

### SDK notices go through one door now

Every short message the SDK raises by itself used to call
`ScaffoldMessenger.of(context).showSnackBar`. That throws whenever any
`Scaffold` under the messenger is halfway through its own teardown — a
`Scaffold` unregisters in `dispose`, never in `deactivate` — and the notice
died with the throw. They all go through `showChatNotice` now, which
publishes after the frame while the tree is still settling.

Nothing to change on your side: with no `ChatNoticeScope` mounted, the
notices behave exactly as before, only reliably. To present them your own
way — a top banner, your design system's toast — mount the scope above your
`MaterialApp`, so the routes the SDK pushes inherit it:

```dart
ChatNoticeScope(
  presenter: (context, message) {
    myBanners.show(message);
    return true; // false leaves this one to the SDK
  },
  child: MaterialApp(/* … */),
);
```

`OperationFeedbackListener` routes through it too, so a host that already
customized `snackBarBuilder` there keeps that shape; the scope wins over it
when both are wired.

### The Nordic + Eastern-EU locales cover the new confirmations

`sv`, `no`, `da`, `pl` and `cs` carry a core set and fall back to English
outside it. All six strings added in this release —
`deleteMessageConfirmTitle`, `deleteMessageConfirmBody`, `discardMessage`,
`editWindowExpired`, `blockedMessageHidden`, `blockedInRoomNotice` — are
inside that set, translated in all twelve bundled locales. If you were
overriding them per-locale to work around an English fallback, drop the
override.

## 0.19.x → 0.20.0

### Breaking: `ChatMembersApi.list` gained `cachePolicy`

**What fails.** Only a class that `implements ChatMembersApi` and declares
`list` explicitly — in practice a hand-written test fake:

```
'_FakeMembersApi.list' isn't a valid override of 'ChatMembersApi.list'.
```

Production code that *calls* `members.list` is unaffected, and so are fakes
that fall back to `noSuchMethod`. `MembersApi` and `MockMembersApi` already
have it.

**The fix.** One parameter, forwarded like the ones next to it:

```dart
  @override
  Future<ChatResult<ChatPaginatedResponse<RoomUser>>> list(
    String roomId, {
    ChatPaginationParams? pagination,
    List<RoomMemberExpand> expand = const [],
    CachePolicy? cachePolicy,          // add this
  }) => _delegate.list(
    roomId,
    pagination: pagination,
    expand: expand,
    cachePolicy: cachePolicy,          // and forward it
  );
```

### The roster cache only covers one shape

`cachePolicy` is honoured **only** when `pagination` is `null` and `expand`
is empty. Any other shape bypasses the cache in both directions, whatever
you pass. This is not an oversight: one record per room cannot answer "page
3" of a large group, and handing a bare cached roster to a caller that asked
for `expand: [users]` would blank every name and avatar it was about to
render. A paginated/expanded screen (such as the built-in
`GroupMembersView`) behaves exactly as it did in 0.19.x.

### Naming no `cachePolicy` is not the same as naming the default

`members.list` without a `cachePolicy` keeps 0.19.x semantics down to the
letter: it goes to the network, and a failed fetch is a `ChatFailureResult`
— you never get the roster from disk behind your back. It does **not** fall
back to `CacheConfig.defaultReadPolicy` (`networkFirst`), which would have
turned every existing `fold(showError, render)` into "render a stale roster,
never show an error" without a line of your code changing.

The response is still written through to the cache either way, so the
disk-only readers find it there: the SDK's own hydration pass, and any
`CachePolicy.cacheOnly` call of your own. The offline fallback is one
argument away when you want it:

```dart
// 0.19.x behaviour, unchanged: the network answers, or the call fails.
await chat.client.members.list(roomId);

// Opt in: network first, the roster on disk when the network is down.
await chat.client.members.list(
  roomId,
  cachePolicy: CachePolicy.networkFirst,
);
```

### `cacheOnly` on a cache-less client is a miss, not a fetch

If you build the SDK without a cache and pass `CachePolicy.cacheOnly`, the
call no longer falls through to the network. `users.get`,
`rooms.getUserRooms`, `rooms.get`, `members.list`, `contacts.list`,
`messages.list` and `messages.getReactions` now answer
`NetworkFailure('No cached data available')` — the same miss they report
for an empty store. That policy's contract is that it emits nothing, and
the SDK's own disk-only passes lean on it.

Nothing to change unless you were using `cacheOnly` as "read it, cache or
no cache". Name the policy you actually want there: `networkFirst` for
disk-when-offline, or no policy at all for the pre-cache semantics
(network answer, or a failure).

### `connect()` now touches the disk before the socket

`ChatUiAdapter.connect()` hydrates the room list from the local store before
opening the connection, unless you already called `rooms.hydrate()`. Nothing
to change — but if you time your connection, expect the local read in that
measurement. A store that throws is logged through `adapter.logger` and
skipped; it never fails the connect.

If you want rows on screen even earlier (before you connect at all), call it
yourself:

```dart
await adapter.rooms.hydrate();   // paints from disk, emits nothing
// ... your own gating, then:
await adapter.connect();         // sees the hydration already done, skips it
```

### Behaviour: cold-start DM rows are named again

The disk pass now resolves DM identities from the cached roster instead of
leaving them anonymous until the network answered. It still emits nothing.
As a consequence, duplicate DM rooms for one contact collapse on the cache
pass again (0.19.0 let both rows show until the network pass) — the loser is
only *persisted* as removed by an authoritative pass, exactly as before.

## 0.13.x → 0.14.0

Only one item can break your build, and it only affects test code. The rest
of this section is behaviour you should know about before shipping the bump.

### Breaking: `ChatClient` gained `pendingOperationCount` / `flushPendingOperations()`

**What fails.** Any class that `implements ChatClient` and declares every
member explicitly stops compiling:

```
Missing concrete implementations of 'ChatClient.pendingOperationCount'
and 'ChatClient.flushPendingOperations'.
```

In practice this is a hand-written test fake — a wrapper that delegates to a
real client so a test can intercept one or two calls. Production code that
*uses* `ChatClient` is unaffected, and so are fakes that fall back to
`noSuchMethod`. `NomaChatClient` and `MockChatClient` already implement both.

**The fix.** Two members per fake, delegating exactly like the members
around them:

```dart
class _FakeChatClient implements ChatClient {
  _FakeChatClient(this._delegate);
  final ChatClient _delegate;

  // ... your existing overrides ...

  @override
  void cancelPendingRequests([String reason = 'cancelled']) =>
      _delegate.cancelPendingRequests(reason);

  // Add these two:
  @override
  int get pendingOperationCount => _delegate.pendingOperationCount;

  @override
  Future<void> flushPendingOperations() => _delegate.flushPendingOperations();
}
```

If your fake has no delegate to forward to, the no-op pair is fine — it is
what `MockChatClient` does:

```dart
@override
int get pendingOperationCount => 0;

@override
Future<void> flushPendingOperations() async {}
```

**What you gain.** The same two members on the real client: read
`pendingOperationCount` to drive a "N pending" badge without shadow-counting
sends yourself, and call `flushPendingOperations()` behind a manual "retry
sending" button. Normal operation needs neither — the queue drains on every
connection on its own.

### Non-breaking, but delete your workaround: sub-controllers are mockable

`ChatRoomsController`, `ChatMessagesController`, `ChatDmController`,
`ChatContactsController` and `ChatProfileController` moved from `final class`
to `interface class`. Nothing that compiled before stops compiling; the point
is what is now allowed.

Until `0.13.x`, `final` meant you could not implement these from another
package, so mocking `ChatUiAdapter` in a host test suite pushed you onto the
`@internal` pass-throughs on the adapter itself — plus an analyzer ignore to
keep the build quiet:

```dart
// ignore_for_file: invalid_use_of_internal_member

await adapter.loadRooms();
await adapter.openDirectMessageDraft(otherUserId);
final key = adapter.draftRoutingKey(otherUserId);
await adapter.leaveRoom(roomId);
```

Now the public sub-controller path works, and the mocks compile:

```dart
// No ignore needed.
await adapter.rooms.load();
await adapter.dm.openDraft(otherUserId);
final key = adapter.dm.draftRoutingKey(otherUserId);
await adapter.rooms.leave(roomId);
```

```dart
class MockChatRoomsController extends Mock implements ChatRoomsController {}
class MockChatDmController extends Mock implements ChatDmController {}

class MockChatUiAdapter extends Mock implements ChatUiAdapter {
  @override
  final ChatRoomsController rooms = MockChatRoomsController();
  @override
  final ChatDmController dm = MockChatDmController();
}
```

Migrate the call sites and drop `invalid_use_of_internal_member` from the
files that only needed it for chat.

### Behavioural: the offline queue drains on the *first* connection

Queued operations used to wait for a re*connect*: the drain was gated on
having connected at least once already, so anything enqueued during a cold
start stayed in the queue until the connection dropped and came back. It now
drains on every `connected` event, the first one included.

Nothing to change — but if your app assumed a queued send would linger (for
instance, a screen that let the user cancel it before it went out), that
window is now much shorter. Missed-unread catch-up is unchanged: it still
runs only after a genuine disconnect→reconnect cycle.

To drain on demand at any other moment, call `flushPendingOperations()`.

### Behavioural: WS close `4002` invalidates the token and stops looping

`4002` (`auth_failed`) is now treated like `4003`/`4004`: the cached token is
invalidated, so the next attempt fetches a fresh one instead of re-offering
the credential the server just refused. And after **3** consecutive
token-rejecting closes (`4002`/`4003`/`4004`) with no successful
authentication in between, the transport gives up: it stops reconnecting and
emits a terminal `ChatAuthException` on the event stream. A successful auth,
or an explicit `connect()`, resets the counter.

If you wrote something like this to work around the old loop, delete it — it
now fights the SDK for control of the socket:

```dart
// Remove: the SDK handles 4002 itself as of 0.14.0.
chat.connectionStateNotifier.addListener(() async {
  if (chat.connectionState == ChatConnectionState.error) {
    await auth.refreshIfNeeded();
    await chat.disconnect();
    await chat.connect();
  }
});
```

What you should keep is a terminal-failure path: when the SDK reports the
session terminated, send the user through your real re-authentication flow
rather than retrying the socket.

### New: client-side duplicate guard on room and member operations

`rooms.create`, `rooms.updateConfig`, `members.invite` (hence
`members.joinWithToken`) and `members.remove` now deduplicate concurrent
identical calls and send a deterministic `Idempotency-Key` header. No API
change, nothing to migrate.

**Do not over-trust it.** The backend does not read `Idempotency-Key` yet.
This stops a double-tap or a local retry of a request that never left the
device; it does **not** deduplicate a retry whose original request already
reached and was applied by the server. If you were planning to drop your own
"disable the button while the request is in flight" guard because the SDK is
now idempotent, don't — it isn't, not end to end.

### New: reuse the SDK's backoff and circuit breaker

If your app calls the same backend outside the bundled HTTP client, the
resilience primitives are now exported instead of being internal:

```dart
import 'package:noma_chat/noma_chat_advanced.dart';

final delayMs = computeBackoffMs(attempt: 0); // 0-based: 0 = first retry

final breakers = CircuitBreakerRegistry();
final breaker = breakers.forPath('/v1/messages/$messageId');
if (!breaker.allowRequest()) return;
try {
  await doRequest();
  breaker.recordSuccess();
} catch (_) {
  breaker.recordFailure();
  rethrow;
}
```

`CircuitBreakerRegistry` groups by the first meaningful path segment, so a
`503` storm on `/messages` does not open the circuit for `/rooms`. Use a bare
`CircuitBreaker` when one shared circuit is what you want.

### Fixed: relative signed attachment URLs

Attachments whose signed download URL came back relative to the API base
failed to download. The URL is now resolved against the configured base URL
first. No action required.

### Cleanup: `CachePolicy` is no longer `@experimental`

Remove any `// ignore: experimental_member_use` you added around a
`CachePolicy` value.

## 0.12.x → 0.13.0

### Breaking: `ChatConnectionState` gained `authenticating`

A new state is emitted between the socket opening and the server
confirming `auth_ok` (previously indistinguishable from `connecting`).
Any exhaustive `switch` over `ChatConnectionState` in your code needs a
new case — the SDK's own `ConnectionBanner` and internal transport
selection already handle it, mapping it the same way as `connecting`:

```dart
switch (state) {
  case ChatConnectionState.connecting:
  case ChatConnectionState.authenticating:
    showConnectingSpinner();
  case ChatConnectionState.connected:
    hideSpinner();
  // ...
}
```

`isWorking` now includes `authenticating`; `isConnected` / `isOffline` do
not.

### Behavioural: `disconnect()` no longer clears the room list

`ChatUiAdapter.disconnect()` is now cache-first by default
(`clearRooms: false`): the room list, the currently foregrounded room's
`ChatController`, and the DM contact↔room binding all survive a
`disconnect()` — the list never flashes empty across a
background/reconnect cycle, and a subsequent `resync()` can backfill the
open conversation. If you relied on the old eager-wipe behavior (e.g. a
screen that expects the list to be empty right after backgrounding),
pass `disconnect(clearRooms: true)` explicitly. `signOut()` / `dispose()`
are unaffected — they always do the full wipe internally.

### Behavioural: the SDK now manages app lifecycle by default

`ChatUiAdapter` (and `NomaChat.create` / `.fromConfig` / `.fromClient`)
default `manageAppLifecycle` to `true`: the adapter registers its own
`WidgetsBindingObserver` and reconnects on resume / optionally
disconnects after a grace period on pause, per `lifecyclePolicy`
(`ChatLifecyclePolicy.standard()` by default — keeps the socket alive in
background; pass `.pushOptimized()` to disconnect after a grace period
instead, e.g. when the backend suppresses push while a connection is
active).

**If your app has its own `AppLifecycleService`/reconnect logic for
chat, remove it in the same change that bumps to `0.13.0`** — running
both means two lifecycle managers racing to `connect()`/`disconnect()`
the same adapter. To opt out entirely (keep your own lifecycle handling
unchanged), pass `manageAppLifecycle: false`:

```dart
final chat = await NomaChat.create(
  // ...
  manageAppLifecycle: false, // opt out; you drive connect()/disconnect() yourself
);
```

Registration is best-effort: it silently no-ops when no Flutter binding
is available (e.g. an adapter built in a plain `test()`, not
`testWidgets()`), so it never crashes a host or an existing test suite.

### New: deep-link-safe room open — `adapter.rooms.open(roomId)`

Opening a room the local list/cache hasn't synced yet (a push
notification or a shared link to a brand-new room) used to mean either a
blind `getChatController(roomId)` (renders an empty/ghost room) or
hand-rolled fetch-then-add logic. `rooms.open` does both, with typed
failures instead of collapsing everything to "this chat doesn't exist":

```dart
final result = await adapter.rooms.open(roomId);
switch (result) {
  case ChatSuccess(:final data):
    openRoom(data); // ready ChatController
  case ChatFailureResult(failure: NotFoundFailure()):
    showChatGoneMessage();
  case ChatFailureResult(failure: AuthFailure() || ForbiddenFailure()):
    promptReauth();
  case ChatFailureResult(failure: NetworkFailure() || TimeoutFailure()):
    showRetry(); // transient — NOT "gone"
  case ChatFailureResult(:final failure):
    showError(failure);
}
```

Pass `fetchIfMissing: false` to restrict the lookup to what's already in
the room list (skips the network round-trip, returns `NotFoundFailure`
instead).

### New: non-destructive room list merge — `RoomListController.mergeRooms`

Mostly internal (used by the adapter's own cache-first `loadRooms`), but
public for hosts that maintain their own `RoomListController` outside the
adapter: `mergeRooms(incoming, {required authoritative})` upserts rows in
place. A non-authoritative merge never drops a row it can't vouch for; an
authoritative merge reconciles fully (drops rows missing from `incoming`)
without ever exposing an empty list in between, unlike `setRooms`
(clear-then-refill).

### Fixed: duplicate-DM room list flicker

If you saw a DM's room-list row alternate between two different
`roomId`s across refreshes (usually visible right after a fresh
conversation, before the backend's own duplicate cleanup catches up),
that was a client-side tie-break bug, now fixed — no action needed.

## 0.11.x → 0.12.0

### Behavioural: the id returned by `send()` can be provisional

Backends running `ack_mode = async` (an opt-in deployment mode; the backend default is `sync`) answer
`POST /rooms/{id}/messages` and `POST /contacts/{id}/messages` with `201`
and an echo built **before** persistence — its `id` does not correspond to
the stored message. The SDK now surfaces this instead of pretending the id
is final:

- `ChatMessage.isProvisional` (new flag) is `true` on such echoes, and
  `ChatMessage.clientMessageId` is always populated on them.
- The authoritative message arrives via `NewMessageEvent` carrying the same
  `clientMessageId`; the SDK's controller and cache reconcile by that key
  automatically (no duplicates, nothing stranded under the provisional id).

**Do not use the id returned by `send()` / `sendDirectMessage()` for
immediate follow-ups** (react / edit / delete / pin). When
`isProvisional == true`, wait for the matching `NewMessageEvent` and use its
`id`:

```dart
final res = await chat.client.messages.send(roomId, text: 'hi');
final sent = res.dataOrNull;
if (sent != null && sent.isProvisional) {
  // Correlate later: event.message.clientMessageId == sent.clientMessageId
}
```

No action is needed if you only render through the bundled `ChatUiAdapter`
/ `NomaChatView` — the bubble stays in the *sending* state until the event
confirms it, then swaps to the authoritative message.

### Non-breaking additions

- `contacts.sendDirectMessage()` gained an optional `clientMessageId`
  parameter (auto-generated when omitted) and now always sends the key, so
  DM retries are idempotent. Custom `ChatContactsApi` implementers must add
  the parameter to their override.
- DM typing (`contacts.sendTyping()`) is now always sent over REST; the
  broken contact-addressed WS `typing` frame was removed (the backend only
  accepts room-scoped frames).
- WS close code `4006` (`transport_disabled`) now suspends WS for the
  session and `RealtimeMode.auto` fails over to SSE/polling immediately.

## 0.9.x → 0.10.0

### Breaking: message pagination is now bidirectional opaque cursors

`ChatCursorPaginationParams.before` and `.after` (the ISO-8601 timestamp
fields) were **removed entirely** — they no longer exist, are no longer emitted
as `before` / `after` query params, and the timestamp/id boundary dedup that
backed them in the polling realtime engine is gone.

`messages.list` (and `getDirectMessages` / `getConversationMessages`) now page
with the opaque, seq-based cursors the backend returns on every page:

- `ChatPaginatedResponse.prevCursor` — anchored on the **oldest** message of
  the page. Pass it back as `cursor` with `direction: ChatCursorDirection.older`
  to load **older history**.
- `ChatPaginatedResponse.nextCursor` — anchored on the **newest** message.
  Pass it back with `direction: ChatCursorDirection.newer` (the backend
  default) to **catch up** on newer messages.

`hasMore` reports whether more pages exist *in the requested direction*. The
cursors are seq-based, so paging never skips or replays messages that share an
exact millisecond.

**Before:**

```dart
// Load older history by oldest-timestamp
final res = await chat.client.messages.list(
  roomId,
  pagination: ChatCursorPaginationParams(before: oldest.timestamp.toIso8601String()),
);
```

**After:**

```dart
final first = await chat.client.messages.list(roomId);
final older = await chat.client.messages.list(
  roomId,
  pagination: ChatCursorPaginationParams(
    cursor: first.dataOrThrow.prevCursor,
    direction: ChatCursorDirection.older,
    limit: 30,
  ),
);
```

If you implement `ChatMessagesApi` yourself, parse the response `prev` field
into `ChatPaginatedResponse.prevCursor` (alongside `next` →`nextCursor`).

### Breaking: `members.invite` now returns `InviteResult`

`members.invite` used to return `ChatResult<void>` — a `ChatSuccess` meant the
HTTP call worked, but said nothing about whether each user was actually added.
It now returns `ChatResult<InviteResult>` so you can inspect the per-user
outcome (the backend answers `207 Multi-Status` when some users succeed and
others fail — banned, already a member, etc.).

The `userRole` parameter was **removed** (the backend never accepted a
per-invite role; assign roles afterwards with `updateRole`). A new optional
`token` parameter was added for joining a public room by invitation token.

**Before:**

```dart
final result = await chat.client.members.invite(
  roomId,
  userIds: ['user-123', 'user-456'],
  userRole: MemberRole.member, // removed
);

switch (result) {
  case ChatSuccess():
    showOk(); // assumed everyone was added — not necessarily true!
  case ChatFailureResult(:final failure):
    showError(failure);
}
```

**After:**

```dart
final result = await chat.client.members.invite(
  roomId,
  userIds: ['user-123', 'user-456'],
  // token: publicRoomToken, // optional: public-room join by token
);

switch (result) {
  case ChatSuccess(:final data) when data.hasFailures:
    for (final f in data.failed) {
      showError('${f.userId}: ${f.detail ?? 'failed'} (${f.code})');
    }
  case ChatSuccess(:final data):
    showOk('${data.succeeded.length} invited'); // data.allSucceeded == true
  case ChatFailureResult(:final failure):
    // Every user failed (non-2xx) or a transport error.
    showError(failure);
}
```

`InviteResult` exposes `results` (a `List<InviteUserResult>` with
`userId` / `success` / `code?` / `detail?` each), plus the derived
`succeeded`, `failed`, `hasFailures` and `allSucceeded`. To roughly preserve
the old "did the call work" check, branch on `data.allSucceeded`.

### Deprecated: header-only attachment download — use signed URLs

Attachment download moves to a **signed-URL** primary path. The backend now
authorizes attachment access by room membership (fail-closed) and exposes
`GET /attachments/{attachmentId}/signed-url?roomId=...`, which returns a
short-lived, self-authorizing URL (HMAC signature + expiry + user baked in).
That URL drops straight into `Image.network` / `CachedNetworkImage` / a native
viewer.

The legacy header-only flow (`GET /attachments/{attachmentId}` authorized by
the `x-attachment-metadata` header alone) is **deprecated**. It now also
requires a membership-checked `roomId`; without one the backend returns
`403` with the `not_a_room_member` token (exposed as
`ChatErrorTokens.notARoomMember`).

In the SDK:

- New `attachments.signedUrl(attachmentId, roomId: ...)` →
  `ChatResult<AttachmentSignedUrl>` (the `.url` is absolute and ephemeral).
- `attachments.download` gained an optional `roomId`. **Pass it** — when
  present the SDK takes the signed-URL path automatically. Calling
  `download(id, metadata: ...)` *without* `roomId` is the deprecated path and
  will now 403.

**Before:**

```dart
final res = await chat.client.attachments.download(
  attachmentId,
  metadata: storedMetadata,
);
```

**After:**

```dart
// Display / cache: resolve a signed URL.
final res = await chat.client.attachments.signedUrl(
  attachmentId,
  roomId: roomId,
);
final url = res.dataOrNull?.url; // -> Image.network(url) / CachedNetworkImage

// Raw bytes: pass roomId so download takes the signed-URL path.
final bytes = await chat.client.attachments.download(
  attachmentId,
  roomId: roomId,
);
```

**For custom `ChatAttachmentsApi` implementers:** the interface gained
`signedUrl(...)` (a new method you must implement) and `download` gained the
optional `roomId` parameter. The bundled `MockChatClient` already implements
both.

### Behaviour change: `ChatConfig.ssePath` default is now `/eventsource`

The default SSE path changed from `/events` to `/eventsource`. The old default
never worked against CHT/NRTE, so this is a fix, not a regression. **If you
override `ssePath` explicitly, you are unaffected.** If you relied on the old
default and pointed a custom backend at `/events`, set it back:

```dart
config: ChatConfig(ssePath: '/events'),
```

### New: `ChatConfig.actAsUserId` (managed-user delegation)

Set `actAsUserId` to act on behalf of a managed user — every REST request then
injects `X-From-User-Id: <actAsUserId>`. The backend enforces the
parent→managed relationship (`403` if not allowed). REST only; it does not
change the real-time identity.

```dart
config: ChatConfig(actAsUserId: managedUserId),
```

### New: `rooms.create(..., forceGroup: true)`

`rooms.create` gained an optional `forceGroup` flag. By default a contacts room
with a single other member collapses to a DM-style room; pass `forceGroup:
true` to keep it a named group. Existing calls are unchanged (`forceGroup`
defaults to `false`).

```dart
await chat.client.rooms.create(
  name: 'Team Alpha',
  audience: RoomAudience.contacts,
  members: [otherUserId],
  forceGroup: true,
);
```

### Note: `presence.update(statusText:)` is not persisted

`presence.update` accepts a `statusText:` argument, but the backend currently
**ignores** it — a custom status string will not round-trip to other users.
The parameter is reserved for future backend support; do not rely on it yet.

### Recommended: render rooms with `NomaChatView`

A new `NomaChatView` widget is the recommended drop-in for a chat-room screen.
It wraps `ChatRoomAppBar` + `ChatView` and auto-wires the seven room behaviors
(history + pin load, unread divider, group member hydration, blocked /
room-removed reactions, role-aware context menu, report dialog, reaction-user
fetcher) that hosts previously had to reimplement.

This is **additive** — `ChatView` is unchanged and remains available for fully
custom screens. Migrating is optional, but typically deletes a lot of
boilerplate:

```dart
// Before: ChatView composed by hand (controller, app bar, callbacks, unread
// snapshot, member hydration, report dialog… all wired manually).

// After:
NomaChatView(
  roomId: roomId,
  adapter: chat.adapter,
  onRoomLeft: () => Navigator.of(context).maybePop(),
)
```

See the [Developer Guide — NomaChatView](./doc/DEVELOPER_GUIDE.md#nomachatview)
for the full list of override slots.

### Internal: dropped `json_annotation` / `json_serializable` deps

These code-gen dependencies were removed from the package — the SDK no longer
uses them. **No consumer impact:** they were never part of the public API. If
you depended on them transitively through `noma_chat`, add them to your own
`pubspec.yaml`.

### New: `members.list(expand:)` — embed names + avatars, kill the roster N+1

`members.list` gains an optional `expand` param. Pass
`expand: const [RoomMemberExpand.users]` and the SDK sends `?expand=users`,
making the backend embed each member's `displayName` + `avatarUrl` in the row.
`RoomUser` gains nullable `displayName` / `avatarUrl`, populated only on an
expanded response. Rendering a group roster no longer needs a
`GET /users/{id}` per member — one `list` call carries it all.

```dart
final res = await chat.client.members.list(
  roomId,
  expand: const [RoomMemberExpand.users],
);
// res.dataOrNull.items each carry m.displayName / m.avatarUrl (or null).
```

Backward-compatible: omit `expand` and the fields stay `null`, exactly as
before. The bundled `GroupMembersView` already opts in and seeds the adapter
user cache from the embedded fields, so the group screen renders names +
avatars with no extra fetches. See the
[Developer Guide — listing members](./doc/DEVELOPER_GUIDE.md#listing-members--list-and-the-users-expansion).

> **Custom `ChatMembersApi` implementers:** `list` gained an
> `List<RoomMemberExpand> expand = const []` parameter. It is optional with a
> default, so existing implementations keep compiling; add the param to your
> override to forward the expansion (and honour it server-side).

### New: unified room preferences — `rooms.patchPreferences()`

Room preferences (mute / pin / hide) now funnel through one endpoint:
`rooms.patchPreferences(roomId, {muted?, muteUntil?, pinned?, hidden?})` sends
a partial `PATCH /rooms/{roomId}/preferences` and returns the merged
server-side state as a new `RoomPreferences` model (`muted`, `pinned`,
`hidden`, `muteUntil?`). Pass only the fields you want to change; a non-null
`muteUntil` is sent as an ISO-8601 string for WhatsApp-style timed mutes.

```dart
final res = await chat.client.rooms.patchPreferences(
  roomId,
  pinned: true,
  hidden: false,
);
// res.dataOrNull -> RoomPreferences(muted, pinned, hidden, muteUntil?)
```

**Breaking — the six data-API toggles are removed.** `chat.client.rooms.mute`
/ `unmute` / `pin` / `unpin` / `hide` / `unhide` no longer exist. Call
`patchPreferences` directly:

```dart
// Before:
await chat.client.rooms.mute(roomId);
await chat.client.rooms.mute(roomId, until: someInstant);
await chat.client.rooms.unmute(roomId);
await chat.client.rooms.pin(roomId);
await chat.client.rooms.hide(roomId);

// After:
await chat.client.rooms.patchPreferences(roomId, muted: true);
await chat.client.rooms.patchPreferences(roomId, muteUntil: someInstant);
await chat.client.rooms.patchPreferences(roomId, muted: false);
await chat.client.rooms.patchPreferences(roomId, pinned: true);
await chat.client.rooms.patchPreferences(roomId, hidden: true);
```

The single-flag convenience wrappers **with optimistic UI updates** remain on
the UI adapter — `adapter.rooms.mute/unmute/pin/unpin/hide/unhide` are
unchanged and now drive `patchPreferences` internally — so consumers using the
adapter API need no changes.

> **Custom `ChatRoomsApi` implementers:** the interface no longer declares the
> six toggles. Implement only
> `Future<ChatResult<RoomPreferences>> patchPreferences(String roomId, {bool? muted, DateTime? muteUntil, bool? pinned, bool? hidden})`
> against `PATCH /rooms/{id}/preferences`.

### Breaking: managed-users list — only `users.getManagedByParent()`

Listing the users a parent manages is served by a single canonical method.
`users.getManagedByParent(parentId, {pagination})` calls
`GET /users/{parentId}/managed-users` (operationId `getManagedUsersByParent`)
and returns the paginated `{users, hasMore}` response.

```dart
// Before (removed):
final res = await chat.client.users.getManaged(parentId);

// After:
final res = await chat.client.users.getManagedByParent(parentId);
// res.dataOrNull -> ChatPaginatedResponse<ChatUser>
```

**`users.getManaged(userId)` is removed.** It previously targeted the legacy
`GET /managed-users/{userId}` route; replace every call with
`getManagedByParent`, which takes the same arguments and returns the same shape.
`deleteManaged` / `searchManaged` / `createManaged` are unchanged.

> **Custom `ChatUsersApi` implementers:** the interface no longer declares
> `getManaged`. Implement only
> `Future<ChatResult<ChatPaginatedResponse<ChatUser>>> getManagedByParent(String parentId, {ChatPaginationParams? pagination})`,
> pointed at `GET /users/{parentId}/managed-users`.

### Breaking: contact / last-unread sender ids read the canonical field only

The SDK now reads **only** the canonical sender/identity field; the legacy XMPP
aliases are no longer accepted. `ChatContact` parses `userId` only (the `jid`
and `id` fallbacks are gone), and `UnreadRoom`'s last-message preview parses
`from` only (the `fromJid` fallback is gone). This is a no-op against a current
backend, which already emits the canonical fields. A server that emits *only*
the dropped `jid` / `fromJid` aliases will now surface an empty sender id — such
servers are no longer supported.

### Note: SDK spec mirror corresponds to the `user` audience bundle

The SDK ships a mirror copy of the backend OpenAPI spec at
[`doc/chat-api-openapi.yml`](./doc/chat-api-openapi.yml) for reference and codegen. The
backend source spec now annotates every operation with an `x-audience` tag
(`user` / `admin` / `internal`) and a Redocly config that generates three
audience-scoped bundles. The SDK only needs the **`user`** surface: the mirror
corresponds to that `user` audience bundle and can be regenerated from the
backend source where Redocly is available (e.g.
`npx @redocly/cli bundle user@v1 --config redocly.yaml`). Admin- and
internal-only operations are intentionally absent from the SDK surface.

### New: global message search — `messages.search()` `roomId` is now optional

`messages.search` used to require a `roomId` and only ever searched one room.
The argument is now optional (`String? roomId`): omit it to search **globally**
across every room the caller belongs to (the backend scopes results to the
authenticated user's rooms), or keep passing `roomId:` to scope to a single
room.

```dart
// Global: search across all of the caller's rooms
final all = await chat.client.messages.search('invoice');

// Single room (unchanged)
final inRoom = await chat.client.messages.search('invoice', roomId: roomId);
```

No call-site changes are required: existing single-room callers already pass
`roomId:` by name, and that keeps working. The `roomId` query param is sent to
`GET /messages/search` only when non-null.

> **Custom `ChatMessagesApi` implementers:** the `search` signature changed
> from `search(String query, {required String roomId, ...})` to
> `search(String query, {String? roomId, ...})`. Make `roomId` nullable in your
> override and forward it only when non-null (the bundled `RestMessagesApi`
> omits the `roomId` query param when it is `null`).

### New: canonical reactions endpoint — `messages.addReaction()`

Reactions now have a dedicated sub-resource endpoint instead of riding on the
message-send path. `messages.addReaction(roomId, messageId, emoji: '👍')` POSTs
`/rooms/{roomId}/messages/{messageId}/reactions` (HTTP `201`), and
`messages.deleteReaction` gains an optional `emoji`:

```dart
// React (the only supported way)
await chat.client.messages.addReaction(roomId, messageId, emoji: '👍');

// Un-react: omit `emoji` to clear the caller's reaction wholesale...
await chat.client.messages.deleteReaction(roomId, messageId);
// ...or pass it to remove a specific one (DELETE …/reactions?emoji=👍)
await chat.client.messages.deleteReaction(roomId, messageId, emoji: '👍');
```

Modelling a reaction as a sub-resource keeps it out of the message timeline and
the offline send queue. The built-in optimistic UI (`ChatView` / `NomaChatView`)
already reacts and un-reacts through these calls — **no UI consumer changes are
required**.

**Breaking — reactions no longer ride on the send path.** The SDK no longer
sends reactions via `send(messageType: MessageType.reaction)`; `addReaction`
(and `deleteReaction`) is the only supported reaction API. The general
`messages.send` still accepts `messageType` / `reaction` for any other purpose,
but if your code constructed reaction messages by hand, switch to
`addReaction`.

> **Custom `ChatMessagesApi` implementers:** two interface members changed.
> `addReaction(String roomId, String messageId, {required String emoji})` is
> **new** — add an override (POST the `{emoji}` body to the reactions
> sub-resource). `deleteReaction` gained an optional `String? emoji` parameter —
> forward it as the `?emoji=` query param when non-null. The bundled
> `RestMessagesApi` / `CachedMessagesApi` show the reference shape.

### New: group invite links — `members.joinWithToken` + `ChatInviteLink`

Public / invitable rooms can now be joined via a shareable link. Build one
from a room's `publicToken` with `ChatInviteLink(...).toUri(base)`, and
self-join from an incoming deep link with
`members.joinWithToken(roomId, token: …)` (a wrapper over `invite` with
`inviteAndJoin` for the current user). Both `toUri` and
`ChatInviteLink.tryParse` accept custom query-parameter names. Surface it in
the room menu with the new `ChatRoomOption.inviteViaLink` preset (copies the
link to the clipboard by default). Additive — see the
[Developer Guide — invite links](./doc/DEVELOPER_GUIDE.md#invite-links--joinwithtoken--chatinvitelink).

> **Custom `ChatMembersApi` implementers:** `joinWithToken` is a new interface
> method. If you implement `ChatMembersApi` directly (rather than using the
> bundled client / `MockChatClient`), add it — delegating to your `invite`.

### New: export a chat — `adapter.messages.exportChat`

`adapter.messages.exportChat(roomId)` returns a `ChatExport` whose `text` is
the room's full history as a WhatsApp-style transcript. No new dependency —
writing the file and sharing it is left to your app. Surface it with
`ChatRoomOption.exportChat`.

### New: "Message info" sheet — `MessageInfoSheet` + `MessageAction.info`

`MessageInfoSheet` lists who read / was delivered a message. `NomaChatView`
wires it automatically: `MessageAction.info` is now in the default
context-menu set and shows only on the user's own messages.

> **Exhaustive `switch` on `MessageAction`:** the enum gained an `info` value.
> A non-default `switch` over `MessageAction` will need a new branch (or a
> `default`). The bundled menu handles it; only custom menus are affected.

### Behaviour: WebSocket close 4005 suspends both transports

A terminal auth close (`4005 too_many_auth_attempts`) now stops the WebSocket
**and** prevents the SSE failover from reconnecting with the rejected token.
The SDK emits a terminal `ChatAuthException` (`exception.terminal == true`) and
stays in `error` until you obtain a fresh token and call `connect()` again.
Listen for it to drive a re-authentication prompt.

### New: idempotent sends — `clientMessageId`

`messages.send` accepts an optional `clientMessageId` (≤128 chars). When set,
the backend makes the send idempotent over `(roomId, sender, clientMessageId)`:
a POST retry that replays the same key returns the already-persisted message
(the same `201` as a fresh send, no duplicate). The key round-trips inside the
response `metadata.clientMessageId`, which the SDK reads back and surfaces on
`ChatMessage.clientMessageId`. **You usually don't pass it yourself**:
`NomaChatView` / the adapter generate one per optimistic message and the offline
queue reuses it on every retry, so a send that actually landed before a network
failure surfaced is never duplicated. Pass your own only for custom send flows on
unreliable networks.

### Behaviour: `RateLimitFailure.retryAfter` now populated on CHT

CHT's `429` sends `X-RateLimit-Reset` (seconds until the window resets) and no
`Retry-After`. The SDK now reads `X-RateLimit-Reset` as a fallback, so
`RateLimitFailure.retryAfter` (and the retry interceptor's back-off) reflect the
real reset window instead of being `null`. No code change required.

### New: starred messages — `MessageAction.star` + `StarredMessagesView`

Per-user message bookmarks (WhatsApp-style). `messages.starMessage` /
`unstarMessage` and `messages.listStarred` (paginated, across all rooms) are new
on `ChatMessagesApi`; the adapter exposes `adapter.messages.star/unstar/
loadStarred`. `MessageAction.star` is in the default context menu (wired in
`NomaChatView`), and `StarredMessagesView` (or `.fromAdapter(adapter)`) renders
the list. **Exhaustive switches on `MessageAction` must add a `star` case.**

### New: mute with a duration — `rooms.mute(roomId, until:)`

The UI-adapter `adapter.rooms.mute` takes an optional `until` (a `DateTime`);
omit it for a permanent mute. (On the data API this maps to
`patchPreferences(roomId, muteUntil: …)`.) `ChatRoomOption.muteRoom` is now
duration-aware — its
`onToggle` callback was replaced by `onMute(DateTime? until)` + `onUnmute()`,
and the SDK presents a `MuteDurationSheet` (8h / 1 week / always) on tap:

```dart
ChatRoomOption.muteRoom(
  l10n: l10n,
  muted: room.muted,
  onMute: (until) => adapter.rooms.mute(roomId, until: until),
  onUnmute: () => adapter.rooms.unmute(roomId),
);
```

`RoomDetail`, `UnreadRoom` and `RoomListItem` gained a `muteUntil` field.

### New: "@" mention badge + Archived section

`UnreadRoom` / `RoomListItem` gained `unreadMentions`; `RoomTile` shows an "@"
badge when it is `> 0`. `RoomListView` now renders a collapsible **Archived**
section for hidden rooms (backed by the existing `hidden` pref);
`RoomListController` exposes `archivedRooms` / `hasArchivedRooms`, and
`ChatRoomOption.archiveChat` / `unarchiveChat` map to `rooms.hide` / `unhide`.

### New: edit/delete windows + typed 403 failures

`ChatViewBehaviors` gained `editWindow` (default 15 min) and `deleteWindow`
(default 2 days): `NomaChatView` hides the edit / delete context-menu actions on
your own messages once the window closes (pass `null` to disable). A late
attempt the backend rejects now surfaces as the typed `EditWindowExpiredFailure`
/ `DeleteWindowExpiredFailure` (instead of a generic `ForbiddenFailure`).

### New: stable error tokens on `ChatFailure` — `errorToken`

Every `ChatFailure` now exposes a `String? errorToken`: a stable, snake_case
symbolic code from the server's vocabulary (e.g. `room_not_found`,
`edit_window_expired`, `blocked`, `rate_limited`, `cannot_delete_other_user`).
Branch and localize on the token instead of the English `message`, which was
never contractual. The token is `null` on older servers or when no token
applies — never the empty string.

This is **purely additive** — no existing API changed. The SDK already routed
edit/delete-window 403s to typed failures by string-matching the `detail`
field; it now prefers the stable token when present and keeps the string match
as a fallback for older servers, so nothing breaks either way.

**Before** (branching on English prose — fragile):

```dart
result.fold(
  (failure) {
    if (failure.message.contains('window')) showEditTooLate();
    else showGenericError();
  },
  (data) => render(data),
);
```

**After** (branching on the stable key):

```dart
result.fold(
  (failure) {
    final label = switch (failure.errorToken) {
      ChatErrorTokens.editWindowExpired => l10n.editTooLate,
      ChatErrorTokens.blocked => l10n.youAreBlocked,
      ChatErrorTokens.rateLimited => l10n.slowDown,
      ChatErrorTokens.cannotDeleteOtherUser => l10n.cannotDeleteOther,
      _ => l10n.genericError, // unknown / older server / no token
    };
    showSnackBar(label);
  },
  (data) => render(data),
);
```

The well-known tokens live on `ChatErrorTokens` (a constants holder), but the
field is a `String?` (not an enum) on purpose: a new server token arrives
verbatim and never breaks the SDK. The same token rides on
`OperationError.failure.errorToken`, so a global `operationErrors` listener can
localize centrally.

### New: GDPR self-deletion — `users.deleteCurrentUser()`

The backend tightened account deletion to **own-account-only**. There is now a
dedicated `DELETE /users/me`, exposed as `client.users.deleteCurrentUser()`:

```dart
final res = await client.users.deleteCurrentUser();
res.fold(
  (failure) => showError(failure),
  (_) async {
    await chat.dispose();
    goToOnboarding();
  },
);
```

Prefer it for self-service erasure — it resolves the principal from the auth
token and so can never target the wrong account.

`users.delete(userId)` still exists, but **`userId` must be the caller's own
id**. Passing any other id returns a 403 that surfaces as a `ForbiddenFailure`
carrying `errorToken == ChatErrorTokens.cannotDeleteOtherUser`. Migrate
self-service flows from `delete(myId)` to `deleteCurrentUser()`.

### Confirmed: `message_delivered` / `message_acked` WS events supported

No migration needed — calling this out for completeness: the SDK parses and
dispatches the backend's `message_acked` and `message_delivered` events
(`MessageAckedEvent` / `MessageDeliveredEvent`) plus `receipt_updated`
(`ReceiptUpdatedEvent`). See the event catalogue in the developer guide.

## 0.5.x → 0.6.x

### Breaking: type renames

Several types were prefixed with `Chat` to avoid collisions with types from
other packages (`result_dart`, `dartz`, pagination helpers, etc.).

| Before (0.5.x)              | After (0.6.x)                 |
| --------------------------- | ----------------------------- |
| `Result<T>`                 | `ChatResult<T>`               |
| `Success<T>`                | `ChatSuccess<T>`              |
| `Failure`                   | `ChatFailureResult`           |
| `PaginationParams`          | `ChatPaginationParams`        |
| `CursorPaginationParams`    | `ChatCursorPaginationParams`  |
| `PaginatedResponse<T>`      | `ChatPaginatedResponse<T>`    |
| `SortOrder`                 | `ChatSortOrder`               |

`ChatFailure` (the sealed base class for all domain-specific failures) keeps
its name — only the `Failure` result-wrapper type that was distinct from it
was renamed to `ChatFailureResult`.

**Before:**

```dart
import 'package:noma_chat/noma_chat.dart';

Future<void> loadRooms() async {
  final Result<PaginatedResponse<ChatRoom>> result =
      await chat.client.rooms.list(
    params: PaginationParams(limit: 20, sortOrder: SortOrder.desc),
  );

  switch (result) {
    case Success(:final value):
      // use value.items
    case Failure(:final failure):
      // handle failure
  }
}
```

**After:**

```dart
import 'package:noma_chat/noma_chat.dart';

Future<void> loadRooms() async {
  final ChatResult<ChatPaginatedResponse<ChatRoom>> result =
      await chat.client.rooms.list(
    params: ChatPaginationParams(limit: 20, sortOrder: ChatSortOrder.desc),
  );

  switch (result) {
    case ChatSuccess(:final value):
      // use value.items
    case ChatFailureResult(:final failure):
      // handle failure
  }
}
```

**Cursor pagination:**

```dart
// Before
final params = CursorPaginationParams(cursor: lastCursor, limit: 50);
// After
final params = ChatCursorPaginationParams(cursor: lastCursor, limit: 50);
```

### Breaking: mock classes moved to a testing barrel

`MockChatClient` and its eight `Mock*Api` siblings were removed from the
primary `package:noma_chat/noma_chat.dart` barrel. Import the dedicated
testing barrel in test files:

```dart
// Before
import 'package:noma_chat/noma_chat.dart'; // exposed MockChatClient

// After
import 'package:noma_chat/noma_chat_testing.dart'; // all Mock*Api siblings
```

The primary barrel is unchanged for production imports.

### Behaviour change: RetryInterceptor

Non-idempotent verbs (POST, PATCH, DELETE) are no longer retried on transient
connection errors by default. If you have a POST endpoint that is safe to
replay (e.g. because it is idempotent on your backend), opt in per request:

```dart
await chat.client.messages.sendCustom(
  roomId: roomId,
  payload: myPayload,
  extra: {'idempotent': true}, // opt-in replay for this call
);
```

### New: `ChatConfig.developerLogger` / `debugOnlyLogger`

Two ready-made logger callbacks are now available as static helpers on
`ChatConfig` — no need to wire `dart:developer` manually:

```dart
// Before
import 'dart:developer' as dev;
final chat = await NomaChat.create(
  // …
  logger: (level, msg) => dev.log(msg, name: 'noma_chat'),
);

// After
final chat = await NomaChat.create(
  // …
  logger: ChatConfig.debugOnlyLogger, // silent in release, developer.log in debug
);
```

### New: `MetricCallback` (observability)

Wire a metric sink to capture SDK-emitted telemetry events:

```dart
final chat = await NomaChat.create(
  // …
  metricCallback: (name, data) => myAnalytics.record(name, data),
);
```

See [TELEMETRY.md](./TELEMETRY.md) for the full event catalog.
