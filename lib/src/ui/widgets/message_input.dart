import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/message.dart';
import '../../models/user.dart';
import '../controller/chat_controller.dart';
import '../models/link_preview_metadata.dart';
import '../models/send_message_request.dart';
import '../models/voice_message_data.dart';
import '../services/attachment_bytes_loader.dart';
import '../services/link_preview_fetcher.dart';
import '../theme/chat_theme.dart';
import '../utils/url_detector.dart';
import '_voice_recorder_gesture.dart';
import 'attachment_picker_sheet.dart';
import 'bubbles/link_preview_bubble.dart';
import 'mention_overlay.dart';
import 'reply_preview.dart';
import 'voice_recorder_button.dart';
import 'voice_recorder_overlay.dart';

import '_recording_indicators.dart';

/// Composer for the chat: text field, attach/voice buttons, reply preview
/// and editing affordances. Reads/edits state through the bound
/// [ChatController] and reports user actions via the `on…` callbacks.
class MessageInput extends StatefulWidget {
  const MessageInput({
    super.key,
    required this.controller,
    this.onSendMessageRequest,
    this.onEditMessage,
    this.theme = ChatTheme.defaults,
    this.onTypingChanged,
    this.onPickCamera,
    this.onPickGallery,
    this.onPickFile,
    this.onShareLocation,
    this.attachmentExtraOptions = const [],
    this.onAttachTap,
    this.onVoiceMessageReady,
    this.onPermissionDenied,
    this.canStartRecording,
    this.onRecordingRejected,
    this.maxRecordingDuration = const Duration(minutes: 15),
    this.maxLines = 5,
    this.showAttachButton = true,
    this.showVoiceButton = true,
    this.enableLinkPreview = true,
    this.linkPreviewFetcher,
    this.enableMentions = false,
    this.mentionUsers = const [],
    this.attachmentMediaLoader,
    this.displayNameResolver,
    @visibleForTesting this.voiceRecordingControllerFactory,
  });

  final ChatController controller;

  /// Canonical send callback. Receives a [SendMessageRequest] carrying the
  /// trimmed text plus everything the composer gathered for this send
  /// (link-preview metadata, the message being replied to, etc.). Forward
  /// it to `ChatUiAdapter.sendMessage` and the optimistic bubble will be
  /// rendered with quoted reply, link preview, etc. — no extra wiring.
  ///
  /// Single send slot — the legacy `onSendMessage` / `onSendMessageRich`
  /// callbacks were removed. Consumers that only need plain text can read
  /// `request.text` and ignore the rest.
  ///
  /// Return `true` when the request was taken and the composer may clear.
  /// Return `false` when the send was refused and nothing else holds the
  /// wording — the composer puts the text back where the user left it,
  /// still typed, instead of losing it. A send that left the device and
  /// failed on the wire is `true`: the bubble it raised carries the text
  /// and its own retry.
  final FutureOr<bool> Function(SendMessageRequest request)?
  onSendMessageRequest;

  /// Confirms an edit of the message the composer is editing.
  ///
  /// Same verdict as [onSendMessageRequest]: `true` when the edit was taken
  /// and the composer may close, `false` when it was refused and the new
  /// wording exists nowhere else — the composer reopens on that message
  /// with the text still typed. Nothing else holds it: a refused edit rolls
  /// the bubble back to the original wording.
  final FutureOr<bool> Function(ChatMessage message, String newText)?
  onEditMessage;
  final ChatTheme theme;
  final ValueChanged<bool>? onTypingChanged;
  final VoidCallback? onPickCamera;
  final VoidCallback? onPickGallery;
  final VoidCallback? onPickFile;

  /// Wires the "Location" row in the built-in attachment sheet. Apps that
  /// hook a maps picker here (or fire a one-off geolocation pull) get the
  /// row for free — when null the row simply isn't rendered.
  final VoidCallback? onShareLocation;

  /// Extra rows appended to the built-in attachment sheet, after the
  /// SDK's Camera/Gallery/File/Location options. Useful for
  /// app-specific actions (contact card, poll, plan attachment, …).
  final List<AttachmentSheetOption> attachmentExtraOptions;

  /// When provided, the attach button invokes this directly instead of
  /// showing the built-in [AttachmentPickerSheet]. Use it when the consumer
  /// wants to render its own attachment sheet/menu without going through
  /// the legacy camera/gallery/file picker.
  final VoidCallback? onAttachTap;
  final void Function(VoiceMessageData data)? onVoiceMessageReady;
  final VoidCallback? onPermissionDenied;

  /// Asked before the mic button arms anything, so a room the user cannot
  /// post to never reaches the recorder — nor the system microphone
  /// permission it would ask for. Returning false vetoes the touch and
  /// calls [onRecordingRejected]. Synchronous: see
  /// [VoiceRecorderGesture.canStartRecording].
  final bool Function()? canStartRecording;

  /// Called instead of starting a recording when [canStartRecording]
  /// vetoes the touch. Without it a prompt is floated over the mic button.
  final VoidCallback? onRecordingRejected;

  final Duration maxRecordingDuration;

  final int maxLines;
  final bool showAttachButton;
  final bool showVoiceButton;

  /// Whether to fetch and show Open Graph previews for URLs typed in the
  /// composer. When true, the preview is shown above the input while typing
  /// and is embedded into the outgoing message metadata when sent.
  final bool enableLinkPreview;

  /// Optional fetcher override. When null and [enableLinkPreview] is true, a
  /// default [LinkPreviewFetcher] is created internally.
  final LinkPreviewFetcher? linkPreviewFetcher;

  /// When `true` and the user types `@<query>`, the composer floats a
  /// [MentionOverlay] above the input filtering [mentionUsers] by
  /// `displayName`. Tapping a user inserts `@<Name> ` into the text.
  ///
  /// Mentions land in the message body as plain text (no inline
  /// metadata token yet — that needs a server-side update to round-trip
  /// reliably). The renderer doesn't highlight them today either; the
  /// purpose right now is making the @-typing UX feel like WhatsApp /
  /// Slack.
  final bool enableMentions;

  /// Source list for the mention overlay. Typically
  /// `controller.otherUsers` for the active room. Empty when
  /// [enableMentions] is `false`.
  final List<ChatUser> mentionUsers;

  /// Fetches the pinned reply's referenced-image bytes through the
  /// authenticated client and renders the thumbnail from memory instead of
  /// handing `Image.network` a signed URL that 401s without a Bearer
  /// token. Typically wired to `ChatUiAdapter.defaultAttachmentMediaLoader`.
  /// `null` (default) keeps the plain-URL thumbnail unchanged.
  final AttachmentMediaLoader? attachmentMediaLoader;

  /// Resolves a user id to the name shown on the composer's reply strip —
  /// the "who am I answering" line above the quote. Same contract and
  /// same wiring as [MessageList.displayNameResolver]
  /// (`ChatViewBuilders.displayNameResolver`): return `null` for an id you
  /// cannot name and the strip keeps its unnamed form rather than printing
  /// a raw id. When omitted, names come from `controller.otherUsers`.
  ///
  /// The local user is never asked of it: quoting yourself is labelled with
  /// the localised "You" from [ChatTheme.l10nOf], as WhatsApp does.
  final String? Function(String userId)? displayNameResolver;

  /// Replaces the [VoiceRecordingController] the composer builds for each
  /// capture. Test-only seam: it is what lets a widget test hold the
  /// arming window open across frames instead of racing the platform
  /// recorder.
  @visibleForTesting
  final VoiceRecordingControllerFactory? voiceRecordingControllerFactory;

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _isEditing = false;
  bool _wasReplyingOrEditing = false;
  late final MessageInputVoiceController _voice;

  LinkPreviewFetcher? _linkFetcher;
  Timer? _linkDebounce;
  String? _previewedUrl;
  LinkPreviewMetadata? _currentPreview;
  bool _previewLoading = false;
  final Set<String> _dismissedUrls = {};
  int _linkRequestSeq = 0;

  // Mention overlay state. `_mentionQuery` is the substring typed after
  // the most recent `@` and up to the caret; `_mentionStartIndex` is the
  // absolute index of that `@` in the text. Both are null when the
  // overlay is hidden.
  String? _mentionQuery;
  int? _mentionStartIndex;

  static const _linkDebounceDuration = Duration(milliseconds: 500);

  final LayerLink _voiceButtonLink = LayerLink();
  final GlobalKey _voiceButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    widget.controller.addListener(_onControllerChanged);
    _voice = MessageInputVoiceController(
      maxRecordingDuration: widget.maxRecordingDuration,
      recordingControllerFactory: widget.voiceRecordingControllerFactory,
    )..addListener(_onVoiceChanged);
    if (widget.enableLinkPreview) {
      _linkFetcher = widget.linkPreviewFetcher ?? LinkPreviewFetcher();
    }
    _onControllerChanged();
  }

  void _onVoiceChanged() {
    if (mounted) setState(() {});
  }

  void _onControllerChanged() {
    final editing = widget.controller.editingMessage;
    if (editing != null && !_isEditing) {
      _isEditing = true;
      // `editingDraftText` is what the user had typed when an edit was
      // refused; the message's own text is the wording the server still
      // holds. Prefer the former so re-entering edit mode after a refusal
      // hands back the attempt rather than undoing it.
      _textController.text =
          widget.controller.editingDraftText ?? editing.text ?? '';
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: _textController.text.length),
      );
    } else if (editing == null && _isEditing) {
      _isEditing = false;
      _textController.clear();
    } else if (editing == null && !_isEditing) {
      final draft = widget.controller.draft;
      if (draft != null && draft.isNotEmpty && _textController.text.isEmpty) {
        _textController.text = draft;
        _textController.selection = TextSelection.fromPosition(
          TextPosition(offset: draft.length),
        );
      }
    }
    _maybeAutofocus(editing != null || widget.controller.replyingTo != null);
  }

  /// Requests keyboard focus the moment either "replying to" or "editing"
  /// transitions from off to on — swiping/selecting reply or long-pressing
  /// edit should put the caret straight in the composer, matching every
  /// other chat app, instead of leaving the user to tap the field manually.
  /// Deferred to a post-frame callback: `_onControllerChanged` can fire
  /// mid-build (the controller notifies synchronously), and requesting
  /// focus then throws.
  void _maybeAutofocus(bool replyingOrEditing) {
    if (replyingOrEditing && !_wasReplyingOrEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
    _wasReplyingOrEditing = replyingOrEditing;
  }

  void _onTextChanged() {
    final hasText = _textController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
    widget.onTypingChanged?.call(hasText);
    _maybeScheduleLinkPreview();
    _detectMentionQuery();
  }

  void _detectMentionQuery() {
    if (!widget.enableMentions) return;
    final text = _textController.text;
    final selection = _textController.selection;
    if (!selection.isValid || selection.start != selection.end) {
      _setMention(null, null);
      return;
    }
    final caret = selection.start;
    // Walk back from the caret looking for an `@`. If we hit whitespace
    // first, there's no active mention. The `@` is valid only when it
    // starts a fresh token (preceded by whitespace or string start).
    int? atIndex;
    for (var i = caret - 1; i >= 0; i--) {
      final ch = text[i];
      if (ch == '@') {
        atIndex = i;
        break;
      }
      if (ch == ' ' || ch == '\n') break;
    }
    if (atIndex == null) {
      _setMention(null, null);
      return;
    }
    if (atIndex > 0) {
      final before = text[atIndex - 1];
      if (before != ' ' && before != '\n') {
        _setMention(null, null);
        return;
      }
    }
    final query = text.substring(atIndex + 1, caret);
    _setMention(query, atIndex);
  }

  void _setMention(String? query, int? startIndex) {
    if (_mentionQuery == query && _mentionStartIndex == startIndex) return;
    setState(() {
      _mentionQuery = query;
      _mentionStartIndex = startIndex;
    });
  }

  void _selectMention(ChatUser user) {
    final startIndex = _mentionStartIndex;
    if (startIndex == null) return;
    final text = _textController.text;
    final selection = _textController.selection;
    if (!selection.isValid) return;
    final caret = selection.start;
    final name = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : user.id;
    final replacement = '@$name ';
    final newText = text.replaceRange(startIndex, caret, replacement);
    final newCaret = startIndex + replacement.length;
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCaret),
    );
    _setMention(null, null);
  }

  void _maybeScheduleLinkPreview() {
    if (_linkFetcher == null || _isEditing) return;
    final text = _textController.text;
    final urls = UrlDetector.extractUrls(text);
    final url = urls.isNotEmpty ? urls.first : null;

    if (url == null) {
      _linkDebounce?.cancel();
      if (_currentPreview != null || _previewLoading) {
        setState(() {
          _currentPreview = null;
          _previewLoading = false;
          _previewedUrl = null;
        });
      }
      return;
    }

    if (_dismissedUrls.contains(url)) return;
    if (url == _previewedUrl) return;

    _linkDebounce?.cancel();
    _linkDebounce = Timer(_linkDebounceDuration, () => _fetchPreview(url));
  }

  /// `UrlDetector` normalizes matches by prepending `https://`, so a bare
  /// host typed without a scheme (e.g. `example.com`) is NOT a substring of
  /// the normalized url (`https://example.com`). Compare scheme-insensitively
  /// so the live preview isn't discarded for schemeless input.
  bool _textContainsUrl(String text, String url) {
    if (text.contains(url)) return true;
    final stripped = url.replaceFirst(RegExp(r'^https?://'), '');
    return stripped.isNotEmpty && text.contains(stripped);
  }

  Future<void> _fetchPreview(String url) async {
    final fetcher = _linkFetcher;
    if (fetcher == null) return;
    if (!mounted || !_textContainsUrl(_textController.text, url)) return;

    final seq = ++_linkRequestSeq;
    setState(() {
      _previewedUrl = url;
      _previewLoading = true;
      _currentPreview = null;
    });

    // Decouple the visible spinner from the actual fetch so a slow page
    // doesn't strand the UI in a permanently-loading state, but ALSO
    // doesn't drop the preview on the floor when the fetch eventually
    // succeeds. Previous version awaited a hard `.timeout(8s, ()=>null)`
    // wrapper: when the underlying request took >8s the composer
    // gave up and showed nothing — even though the fetch kept running
    // and eventually completed (cached) so the next send had a preview
    // but the visible banner never did. Now we listen for the real
    // completion and update state regardless of timing.
    final fetchFuture = fetcher.fetch(url);
    final spinnerTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted || seq != _linkRequestSeq) return;
      if (_currentPreview != null) return;
      // Hide the bar but keep waiting for the late preview to land.
      setState(() => _previewLoading = false);
    });

    // `.then` (instead of `await`) on the in-flight future: the await
    // continuation was getting silently dropped on iOS Simulator —
    // logs confirmed `_doFetch` resolved but the awaiting frame never
    // resumed, so the banner stayed hidden until the user hit Send and
    // a fresh fetch landed in the cache. Using a `.then` callback
    // bypasses whatever zone/microtask quirk swallowed the await.
    fetchFuture
        .then((preview) {
          spinnerTimer.cancel();
          if (!mounted || seq != _linkRequestSeq) return;
          final stillTyped = _textContainsUrl(_textController.text, url);
          setState(() {
            _previewLoading = false;
            _currentPreview = stillTyped ? preview : null;
          });
        })
        .catchError((Object _) {
          spinnerTimer.cancel();
          if (!mounted || seq != _linkRequestSeq) return;
          setState(() {
            _previewLoading = false;
            _currentPreview = null;
          });
        });
  }

  void _dismissPreview() {
    final url = _previewedUrl;
    if (url != null) _dismissedUrls.add(url);
    setState(() {
      _previewedUrl = null;
      _currentPreview = null;
      _previewLoading = false;
    });
  }

  void _send() {
    unawaited(_sendAsync());
  }

  Future<void> _sendAsync() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final editing = widget.controller.editingMessage;
    final Future<bool> outcome;
    ChatMessage? replyTo;
    if (editing != null) {
      if (widget.onEditMessage != null) {
        outcome = _dispatchEdit(editing, text);
      } else {
        outcome = _dispatchSend(
          SendMessageRequest(text: text, editing: editing),
        );
      }
      widget.controller.setEditingMessage(null);
    } else {
      Map<String, dynamic>? metadata;
      final preview = _currentPreview;
      if (preview != null && _textContainsUrl(text, preview.url)) {
        metadata = preview.toMessageMetadata();
      } else if (widget.enableLinkPreview && _linkFetcher != null) {
        // The user typed an URL and hit Send before the debounced
        // fetcher resolved — first-send-of-a-fresh-URL race. Block
        // briefly to give the fetch a chance: the second send for the
        // same URL would have hit the in-memory cache and rendered
        // the preview, leaving the first message preview-less and
        // confusing. Cap at 2.5s so a flaky page doesn't freeze the
        // composer; if it doesn't resolve in time we send without
        // metadata (same fallback as before).
        final urls = UrlDetector.extractUrls(text);
        if (urls.isNotEmpty) {
          final url = urls.first;
          if (!_dismissedUrls.contains(url)) {
            LinkPreviewMetadata? fetched;
            try {
              fetched = await _linkFetcher!
                  .fetch(url)
                  // Re-typed to the nullable form before the deadline, and
                  // that hop is load-bearing: `Future<T>.timeout` checks
                  // `onTimeout` against the *runtime* `T`, so a host-injected
                  // fetcher narrowing its override to
                  // `Future<LinkPreviewMetadata>` — a legal covariant
                  // override, and this fetcher is public and injectable —
                  // makes `() => null` a TypeError raised at the call
                  // boundary, before `timeout` subscribes to anything. The
                  // `catch` below would swallow it and every send would ship
                  // preview-less, silently.
                  .then<LinkPreviewMetadata?>((preview) => preview)
                  .timeout(
                    const Duration(milliseconds: 2500),
                    onTimeout: () => null,
                  );
            } catch (_) {
              fetched = null;
            }
            if (!mounted) return;
            if (fetched != null && _textContainsUrl(text, fetched.url)) {
              metadata = fetched.toMessageMetadata();
            }
          }
        }
      }
      // C.1 — when mentions are enabled, scan the trimmed text for
      // `@<DisplayName>` tokens that match a known mentionable user
      // and stash the matched userIds in `metadata.mentions`. This
      // makes the data available server-side for analytics, push
      // notifications targeted at mentioned users, etc. The render
      // path doesn't depend on this list — `parseMarkdown` highlights
      // every `@\w+` token regardless — but the persistence layer
      // does.
      if (widget.enableMentions && widget.mentionUsers.isNotEmpty) {
        final ids = _extractMentionUserIds(text);
        if (ids.isNotEmpty) {
          metadata = {...?metadata, 'mentions': ids};
        }
      }
      replyTo = widget.controller.replyingTo;
      outcome = _dispatchSend(
        SendMessageRequest(text: text, metadata: metadata, replyTo: replyTo),
      );
      widget.controller.setReplyTo(null);
    }
    _resetLinkPreviewState();
    _textController.clear();
    if (editing == null) widget.controller.setDraft(null, notify: false);
    if (await outcome) return;
    _restoreRefusedComposer(text: text, editing: editing, replyTo: replyTo);
  }

  /// Puts a refused send back the way the user left it: the wording in the
  /// field, the message being replied to under it, edit mode reopened on
  /// the message that was being edited. Only reached when the host says
  /// the request was turned down and nothing else holds the text.
  ///
  /// The composer is cleared optimistically when Send is pressed — a
  /// refusal that resolves a second later must not overwrite whatever the
  /// user started typing meanwhile, nor a reply or edit they opened in the
  /// gap, so each of those aborts the hand-back.
  void _restoreRefusedComposer({
    required String text,
    ChatMessage? editing,
    ChatMessage? replyTo,
  }) {
    if (!mounted) return;
    if (_textController.text.trim().isNotEmpty) return;
    final controller = widget.controller;
    if (controller.editingMessage != null || controller.replyingTo != null) {
      return;
    }
    if (editing != null) {
      controller.setEditingMessage(editing, draftText: text);
      return;
    }
    controller.setDraft(text, notify: false);
    _textController.text = text;
    _textController.selection = TextSelection.fromPosition(
      TextPosition(offset: text.length),
    );
    if (replyTo != null) controller.setReplyTo(replyTo);
  }

  /// Name for the author of the message being replied to, as shown on the
  /// composer's reply strip.
  ///
  /// Answering yourself is labelled with the localised "You" — the strip
  /// exists to say WHO you are answering, and leaving it blank for your own
  /// messages (which is what the list's own sender resolver does, on
  /// purpose, so a bubble is not labelled with its reader's name) left the
  /// composer never naming anyone at all. An id nobody can name returns
  /// null and the strip stays unnamed rather than printing a raw id.
  String? _quotedSenderName(BuildContext context, String userId) {
    if (userId == widget.controller.currentUser.id) {
      return widget.theme.l10nOf(context).you;
    }
    final resolved = widget.displayNameResolver?.call(userId)?.trim();
    if (resolved != null && resolved.isNotEmpty && resolved != userId) {
      return resolved;
    }
    final name = widget.controller.otherUsers
        .where((u) => u.id == userId)
        .firstOrNull
        ?.displayName
        ?.trim();
    return (name == null || name.isEmpty) ? null : name;
  }

  /// Returns the userIds of every `mentionUsers` entry whose display
  /// name appears as a `@<token>` boundary in [text]. Case-insensitive,
  /// word-boundary aware, dedup'd. Empty list when nothing matches.
  List<String> _extractMentionUserIds(String text) {
    final lower = text.toLowerCase();
    final found = <String>{};
    for (final user in widget.mentionUsers) {
      final name = user.displayName?.trim();
      if (name == null || name.isEmpty) continue;
      final needle = '@${name.toLowerCase()}';
      var idx = 0;
      while ((idx = lower.indexOf(needle, idx)) >= 0) {
        final after = idx + needle.length;
        final atBoundary =
            after == lower.length || !_isWordChar(lower.codeUnitAt(after));
        if (atBoundary) {
          found.add(user.id);
          break;
        }
        idx = after;
      }
    }
    return found.toList(growable: false);
  }

  static bool _isWordChar(int codeUnit) {
    return (codeUnit >= 0x30 && codeUnit <= 0x39) || // 0-9
        (codeUnit >= 0x41 && codeUnit <= 0x5A) || // A-Z
        (codeUnit >= 0x61 && codeUnit <= 0x7A) || // a-z
        codeUnit == 0x5F; // _
  }

  Future<bool> _dispatchSend(SendMessageRequest request) async {
    final send = widget.onSendMessageRequest;
    if (send == null) return true;
    return send(request);
  }

  Future<bool> _dispatchEdit(ChatMessage message, String text) async {
    final edit = widget.onEditMessage;
    if (edit == null) return true;
    return edit(message, text);
  }

  void _resetLinkPreviewState() {
    _linkDebounce?.cancel();
    _previewedUrl = null;
    _currentPreview = null;
    _previewLoading = false;
    _dismissedUrls.clear();
  }

  void _showAttachmentPicker() {
    // Through the shared presenter: this one used to pass no shape at all,
    // so it rounded at Material's own radius while its siblings rounded at
    // theirs. See [ChatSheetPresentation].
    widget.theme.showSheet<void>(
      context,
      builder: (_) => AttachmentPickerSheet(
        onPickCamera: widget.onPickCamera,
        onPickGallery: widget.onPickGallery,
        onPickFile: widget.onPickFile,
        onShareLocation: widget.onShareLocation,
        extraOptions: widget.attachmentExtraOptions,
        cameraLabel: widget.theme.l10nOf(context).camera,
        galleryLabel: widget.theme.l10nOf(context).gallery,
        fileLabel: widget.theme.l10nOf(context).file,
        locationLabel: widget.theme.l10nOf(context).location,
        title: widget.theme.l10nOf(context).attach,
        theme: widget.theme,
      ),
    );
  }

  Future<void> _sendVoiceMessage() async {
    final data = await _voice.confirmSend();
    if (data != null) {
      widget.onVoiceMessageReady?.call(data);
    }
  }

  @override
  void didUpdateWidget(covariant MessageInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _saveDraft();
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _onControllerChanged();
    }
  }

  @override
  void dispose() {
    _saveDraft();
    _linkDebounce?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    _textController.dispose();
    _focusNode.dispose();
    _voice.removeListener(_onVoiceChanged);
    _voice.dispose();
    super.dispose();
  }

  void _saveDraft() {
    // Called from dispose(); the widget tree is being torn down so we must
    // not propagate notifyListeners() — that would trigger setState() on
    // other ListenableBuilders while the tree is locked.
    final text = _textController.text.trim();
    if (text.isNotEmpty && !_isEditing) {
      widget.controller.setDraft(text, notify: false);
    } else if (text.isEmpty) {
      widget.controller.setDraft(null, notify: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget child;
    final String key;
    if (_voice.isLockedOrPreListen) {
      child = _buildRecordingArea();
      key = 'locked';
    } else if (_voice.isRecording || _voice.isPreparing) {
      child = _buildActiveRecordingRow();
      key = 'recording';
    } else {
      child = _buildInputRow();
      key = 'input';
    }
    final Widget content = AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.bottomCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: KeyedSubtree(key: ValueKey(key), child: child),
      ),
    );

    Widget inputArea = _withPersistentVoiceButton(content);

    // Wrap in a pointer listener that persists across recording state
    // changes so slide-to-cancel and slide-to-lock gestures keep working
    // even after the UI switches from mic button to recording overlay.
    if (widget.showVoiceButton && widget.onVoiceMessageReady != null) {
      inputArea = VoiceRecorderGesture(
        controller: _voice,
        layerLink: _voiceButtonLink,
        theme: widget.theme,
        onPermissionDenied: widget.onPermissionDenied,
        onVoiceMessageReady: widget.onVoiceMessageReady,
        canStartRecording: widget.canStartRecording,
        onRecordingRejected: widget.onRecordingRejected,
        voiceButtonKey: _voiceButtonKey,
        child: inputArea,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: widget.theme.input.backgroundColor ?? Colors.white,
        boxShadow: widget.theme.input.containerShadow,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMentionOverlay(),
            _buildPreviewBanner(),
            _buildLinkPreviewBanner(),
            inputArea,
          ],
        ),
      ),
    );
  }

  Widget _buildMentionOverlay() {
    if (!widget.enableMentions) return const SizedBox.shrink();
    final query = _mentionQuery;
    if (query == null) return const SizedBox.shrink();
    if (widget.mentionUsers.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: MentionOverlay(
        query: query,
        users: widget.mentionUsers,
        onSelect: _selectMention,
        theme: widget.theme,
      ),
    );
  }

  Widget _buildLinkPreviewBanner() {
    if (!widget.enableLinkPreview) return const SizedBox.shrink();
    final preview = _currentPreview;
    if (preview == null && !_previewLoading) return const SizedBox.shrink();
    if (preview == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: SizedBox(
          height: 2,
          child: LinearProgressIndicator(
            backgroundColor:
                widget.theme.linkPreviewBackgroundColor ?? Colors.grey.shade100,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LinkPreviewBubble(
              url: preview.url,
              title: preview.title,
              description: preview.description,
              imageUrl: preview.imageUrl,
              theme: widget.theme,
            ),
          ),
          Semantics(
            key: const ValueKey('chat_link_preview_close_button'),
            identifier: 'chat_link_preview_close_button',
            label: widget.theme.l10nOf(context).close,
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismissPreview,
              child: const SizedBox(
                width: 36,
                height: 36,
                child: Center(child: Icon(Icons.close, size: 18)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewBanner() {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final editing = widget.controller.editingMessage;
        if (editing != null) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color:
                  widget.theme.input.editingBackgroundColor ??
                  Colors.blue.shade50,
              border: Border(
                left: BorderSide(
                  color: widget.theme.input.editingBorderColor ?? Colors.blue,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.edit,
                  size: 16,
                  color: widget.theme.input.editingBorderColor ?? Colors.blue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.theme.l10nOf(context).editing,
                        style:
                            widget.theme.input.editingLabelStyle ??
                            const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                      ),
                      Text(
                        editing.text ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            widget.theme.input.editingPreviewStyle ??
                            const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                      ),
                    ],
                  ),
                ),
                Semantics(
                  key: const ValueKey('chat_edit_cancel_button'),
                  identifier: 'chat_edit_cancel_button',
                  label: widget.theme.l10nOf(context).close,
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.controller.setEditingMessage(null),
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(child: Icon(Icons.close, size: 18)),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final replyingTo = widget.controller.replyingTo;
        if (replyingTo == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ReplyPreview(
            message: replyingTo,
            senderName: _quotedSenderName(context, replyingTo.from),
            theme: widget.theme,
            onDismiss: () => widget.controller.setReplyTo(null),
            mediaLoader: widget.attachmentMediaLoader,
            roomId: widget.controller.roomId,
          ),
        );
      },
    );
  }

  Widget _buildRecordingArea() {
    // The overlay needs the live drag offsets so it can slide the
    // "← Slide to cancel" hint horizontally with the finger and the
    // "Slide up to lock" pill vertically — WhatsApp-style follow-the-
    // finger feedback. The thresholds themselves are also forwarded
    // so the overlay can fade the hints as progress nears the trip
    // point. Resets to 0 the moment the long-press ends.
    final screenWidth = MediaQuery.maybeSizeOf(context)?.width ?? 360;
    return VoiceRecorderOverlay(
      controller: _voice.recording!,
      theme: widget.theme,
      onSend: _sendVoiceMessage,
      dragOffsetX: _voice.dragOffsetX,
      dragOffsetY: _voice.dragOffsetY,
      cancelThreshold: _voice.thresholds.cancelThresholdFor(screenWidth),
      lockThreshold: _voice.thresholds.lockThreshold,
    );
  }

  /// Whether the host's `recordingComposerBuilder` is what paints the
  /// composer right now.
  ///
  /// It is documented as the layout "while voice recording is active", so
  /// it is only called once capture really is live. During the arming
  /// window the SDK's own [ActiveRecordingRow] stands in: a host builder
  /// is entitled to assume `controller.state == recording`, and handing it
  /// an idle controller with a zero duration and an empty waveform would
  /// blank or flicker its composer on every touch.
  bool get _usesCustomRecordingComposer =>
      _voice.isRecording && widget.theme.input.recordingComposerBuilder != null;

  Widget _buildActiveRecordingRow() {
    final controller = _voice.recording!;
    if (_usesCustomRecordingComposer) {
      return widget.theme.input.recordingComposerBuilder!(
        context,
        controller,
        _sendVoiceMessage,
      );
    }
    return ActiveRecordingRow(
      controller: controller,
      theme: widget.theme,
      voiceButtonSlot: _voiceButtonSlot,
    );
  }

  Widget _buildInputRow() {
    final showSend = _hasText || !widget.showVoiceButton;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.showAttachButton) ...[
            _buildAttachButton(),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Semantics(
              identifier: 'chat_message_input',
              child: TextField(
                key: const ValueKey('chat_message_input'),
                controller: _textController,
                focusNode: _focusNode,
                maxLines: widget.maxLines,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                textAlignVertical: TextAlignVertical.center,
                style: widget.theme.input.textStyle,
                decoration: InputDecoration(
                  hintText: widget.theme.l10nOf(context).writeMessage,
                  hintStyle: widget.theme.input.hintStyle,
                  hintMaxLines: 1,
                  border: _composerBorder(),
                  enabledBorder: _composerBorder(),
                  focusedBorder: _composerBorder(),
                  disabledBorder: _composerBorder(),
                  filled: true,
                  fillColor:
                      widget.theme.input.fillColor ?? Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          if (showSend)
            _buildSendButton()
          else ...[
            if (widget.onPickCamera != null) ...[
              _buildCameraButton(),
              const SizedBox(width: 12),
            ],
            _voiceButtonSlot,
          ],
        ],
      ),
    );
  }

  OutlineInputBorder _composerBorder() {
    final borderColor = widget.theme.input.borderColor;
    return OutlineInputBorder(
      borderRadius:
          widget.theme.input.borderRadius ?? BorderRadius.circular(24),
      borderSide: borderColor != null
          ? BorderSide(
              color: borderColor,
              width: widget.theme.input.borderWidth ?? 1,
            )
          : BorderSide.none,
    );
  }

  Widget _buildSendButton() {
    return Semantics(
      key: const ValueKey('chat_send_button'),
      identifier: 'chat_send_button',
      label: widget.theme.l10nOf(context).send,
      button: true,
      enabled: _hasText,
      child: GestureDetector(
        onTap: _hasText ? _send : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child:
              widget.theme.input.sendIconBuilder?.call(context, _hasText) ??
              _defaultSendCircle(),
        ),
      ),
    );
  }

  Widget _defaultSendCircle() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _hasText
            ? (widget.theme.input.sendButtonColor ?? Colors.blue)
            : (widget.theme.input.sendButtonDisabledColor ??
                  Colors.grey.shade300),
        shape: BoxShape.circle,
      ),
      child: Icon(
        widget.theme.input.sendButtonIcon ?? Icons.send,
        color: widget.theme.input.sendButtonIconColor ?? Colors.white,
        size: 20,
      ),
    );
  }

  Widget _buildAttachButton() {
    return Semantics(
      key: const ValueKey('chat_attach_button'),
      identifier: 'chat_attach_button',
      label: widget.theme.l10nOf(context).attach,
      button: true,
      child: GestureDetector(
        onTap: widget.onAttachTap ?? _showAttachmentPicker,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child:
              widget.theme.input.attachIconBuilder?.call(context) ??
              Icon(
                widget.theme.input.attachButtonIcon ?? Icons.attach_file,
                color: widget.theme.input.attachButtonColor,
              ),
        ),
      ),
    );
  }

  Widget _buildCameraButton() {
    return Semantics(
      key: const ValueKey('chat_camera_button'),
      identifier: 'chat_camera_button',
      label: widget.theme.l10nOf(context).camera,
      button: true,
      child: GestureDetector(
        onTap: widget.onPickCamera,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color:
                  widget.theme.input.voiceButtonColor ?? Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: Center(
              child:
                  widget.theme.input.cameraIconBuilder?.call(context) ??
                  Icon(
                    widget.theme.input.cameraButtonIcon ??
                        Icons.camera_alt_outlined,
                    size: 20,
                    color:
                        widget.theme.input.cameraButtonColor ??
                        widget.theme.input.voiceButtonIdleIconColor ??
                        Colors.grey.shade700,
                  ),
            ),
          ),
        ),
      ),
    );
  }

  /// Reserves the footprint of the mic button inside a composer row. The
  /// button itself is painted over the rows — see
  /// [_withPersistentVoiceButton].
  static const Widget _voiceButtonSlot = SizedBox(width: 40, height: 40);

  /// Trailing inset of the persistent mic button. Matches the horizontal
  /// padding of the composer rows, so the floating button lands exactly on
  /// the slot each row reserves for it. Directional, like the rows
  /// themselves: the slot is the last child of a `Row`, so it swaps sides
  /// under an RTL [Directionality] and the button has to follow.
  static const EdgeInsetsDirectional _voiceButtonInset =
      EdgeInsetsDirectional.only(end: 16);

  /// Whether the persistent mic button paints anything for the row that is
  /// on screen. It stays mounted either way (see
  /// [_withPersistentVoiceButton]); this only decides whether it takes up
  /// any space.
  bool get _voiceButtonVisible {
    if (!widget.showVoiceButton) return false;
    if (_voice.isLockedOrPreListen) return false;
    if (_voice.isRecording || _voice.isPreparing) {
      return !_usesCustomRecordingComposer;
    }
    return !_hasText;
  }

  /// Paints the one and only mic button over the swapping composer rows.
  ///
  /// It lives OUTSIDE the `AnimatedSwitcher` on purpose. The switcher keeps
  /// the outgoing row mounted for the whole 200 ms cross-fade, so a mic
  /// button built inside the rows exists twice whenever the composer swaps
  /// back and forth inside that window — which is precisely what a short
  /// touch does now that the recording row goes up on touch down. Two live
  /// copies means two widgets holding [_voiceButtonKey] (Flutter throws
  /// "Multiple widgets used the same GlobalKey") and two leaders on
  /// [_voiceButtonLink] (the `_debugPreviousLeaders` assertion, which is
  /// what the previous split between an idle button and a recording one
  /// was dodging). The key is held unconditionally so there is exactly one
  /// holder at every instant, whatever the composer is showing.
  ///
  /// The leader on [_voiceButtonLink], on the other hand, only exists while
  /// there is a button to lead: a leader over an empty rectangle would
  /// anchor the "slide up to lock" pill to a zero-sized point at the very
  /// edge of the screen, and `showWhenUnlinked: false` — the follower's own
  /// safety net — would have nothing left to catch. That is what a host
  /// painting its own recording composer would get.
  Widget _withPersistentVoiceButton(Widget content) {
    return Stack(
      alignment: AlignmentDirectional.centerEnd,
      children: [
        content,
        Padding(
          padding: _voiceButtonInset,
          child: KeyedSubtree(
            key: _voiceButtonKey,
            child: _voiceButtonVisible
                ? CompositedTransformTarget(
                    link: _voiceButtonLink,
                    child: VoiceRecorderButton(theme: widget.theme),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
