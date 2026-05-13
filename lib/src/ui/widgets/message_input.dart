import 'dart:async';

import 'package:flutter/material.dart';
import 'package:noma_chat/noma_chat.dart';

/// Composer for the chat: text field, attach/voice buttons, reply preview
/// and editing affordances. Reads/edits state through the bound
/// [ChatController] and reports user actions via the `on…` callbacks.
class MessageInput extends StatefulWidget {
  const MessageInput({
    super.key,
    required this.controller,
    required this.onSendMessage,
    this.onSendMessageRich,
    this.onEditMessage,
    this.theme = ChatTheme.defaults,
    this.onTypingChanged,
    this.onPickCamera,
    this.onPickGallery,
    this.onPickFile,
    this.onAttachTap,
    this.onVoiceMessageReady,
    this.onPermissionDenied,
    this.maxRecordingDuration = const Duration(minutes: 15),
    this.maxLines = 5,
    this.showAttachButton = true,
    this.showVoiceButton = true,
    this.enableLinkPreview = true,
    this.linkPreviewFetcher,
  });

  final ChatController controller;
  final ValueChanged<String> onSendMessage;

  /// Optional rich-send callback. When provided, it is invoked instead of
  /// [onSendMessage] and receives any auxiliary metadata the composer has
  /// gathered (e.g. link previews). Falls back to [onSendMessage] when null.
  final void Function(String text, Map<String, dynamic>? metadata)?
      onSendMessageRich;
  final void Function(ChatMessage message, String newText)? onEditMessage;
  final ChatTheme theme;
  final ValueChanged<bool>? onTypingChanged;
  final VoidCallback? onPickCamera;
  final VoidCallback? onPickGallery;
  final VoidCallback? onPickFile;

  /// When provided, the attach button invokes this directly instead of
  /// showing the built-in [AttachmentPickerSheet]. Use it when the consumer
  /// wants to render its own attachment sheet/menu without going through
  /// the legacy camera/gallery/file picker.
  final VoidCallback? onAttachTap;
  final void Function(VoiceMessageData data)? onVoiceMessageReady;
  final VoidCallback? onPermissionDenied;
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

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput>
    with WidgetsBindingObserver {
  final _textController = TextEditingController();
  bool _hasText = false;
  bool _isEditing = false;
  VoiceRecordingController? _voiceController;
  double _dragOffsetX = 0;
  double _dragOffsetY = 0;

  static const _lockThreshold = -100.0;
  // Cancel threshold is computed dynamically from screen width: roughly a
  // third of the available width has to be travelled to the left so a quick
  // accidental drag doesn't tear the recording down.
  static const _cancelThresholdRatio = 1 / 3;

  LinkPreviewFetcher? _linkFetcher;
  Timer? _linkDebounce;
  String? _previewedUrl;
  LinkPreviewMetadata? _currentPreview;
  bool _previewLoading = false;
  final Set<String> _dismissedUrls = {};
  int _linkRequestSeq = 0;

  static const _linkDebounceDuration = Duration(milliseconds: 500);

  bool get _isRecordingNew =>
      _voiceController != null &&
      _voiceController!.state != VoiceRecordingState.idle;

  bool get _isActiveRecording =>
      _voiceController?.state == VoiceRecordingState.recording;

  bool get _isLockedOrPreListen =>
      _voiceController?.state == VoiceRecordingState.locked ||
      _voiceController?.state == VoiceRecordingState.preListen;

  final LayerLink _voiceButtonLink = LayerLink();
  OverlayEntry? _lockHintEntry;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addObserver(this);
    if (widget.enableLinkPreview) {
      _linkFetcher = widget.linkPreviewFetcher ?? LinkPreviewFetcher();
    }
    _onControllerChanged();
  }

  void _onControllerChanged() {
    final editing = widget.controller.editingMessage;
    if (editing != null && !_isEditing) {
      _isEditing = true;
      _textController.text = editing.text ?? '';
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
  }

  void _onTextChanged() {
    final hasText = _textController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
    widget.onTypingChanged?.call(hasText);
    _maybeScheduleLinkPreview();
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

  Future<void> _fetchPreview(String url) async {
    final fetcher = _linkFetcher;
    if (fetcher == null) return;
    if (!mounted || !_textController.text.contains(url)) return;

    final seq = ++_linkRequestSeq;
    setState(() {
      _previewedUrl = url;
      _previewLoading = true;
      _currentPreview = null;
    });

    LinkPreviewMetadata? preview;
    try {
      preview = await fetcher.fetch(url);
    } catch (_) {
      preview = null;
    }

    if (!mounted || seq != _linkRequestSeq) return;
    final stillTyped = _textController.text.contains(url);
    setState(() {
      _previewLoading = false;
      _currentPreview = stillTyped ? preview : null;
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
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final editing = widget.controller.editingMessage;
    if (editing != null) {
      if (widget.onEditMessage != null) {
        widget.onEditMessage!(editing, text);
      } else {
        _dispatchSend(text, null);
      }
      widget.controller.setEditingMessage(null);
    } else {
      Map<String, dynamic>? metadata;
      final preview = _currentPreview;
      if (preview != null && text.contains(preview.url)) {
        metadata = preview.toMessageMetadata();
      }
      _dispatchSend(text, metadata);
      widget.controller.setReplyTo(null);
    }
    _resetLinkPreviewState();
    _textController.clear();
  }

  void _dispatchSend(String text, Map<String, dynamic>? metadata) {
    final rich = widget.onSendMessageRich;
    if (rich != null) {
      rich(text, metadata);
    } else {
      widget.onSendMessage(text);
    }
  }

  void _resetLinkPreviewState() {
    _linkDebounce?.cancel();
    _previewedUrl = null;
    _currentPreview = null;
    _previewLoading = false;
    _dismissedUrls.clear();
  }

  void _showAttachmentPicker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => AttachmentPickerSheet(
        onPickCamera: widget.onPickCamera,
        onPickGallery: widget.onPickGallery,
        onPickFile: widget.onPickFile,
        cameraLabel: widget.theme.l10n.camera,
        galleryLabel: widget.theme.l10n.gallery,
        fileLabel: widget.theme.l10n.file,
        theme: widget.theme,
      ),
    );
  }

  Future<void> _onLongPressStart() async {
    _voiceController ??= VoiceRecordingController(
      maxDuration: widget.maxRecordingDuration,
    );

    final result = await _voiceController!.startRecording();
    if (!mounted) return;
    switch (result) {
      case StartRecordingResult.started:
        _voiceController!.addListener(_onVoiceStateChanged);
        setState(() {});
      case StartRecordingResult.permissionDenied:
        widget.onPermissionDenied?.call();
      case StartRecordingResult.permissionJustGranted:
      case StartRecordingResult.alreadyRunning:
        break;
    }
  }

  void _onLongPressEnd() {
    if (_voiceController == null) return;

    final state = _voiceController!.state;
    if (state == VoiceRecordingState.recording) {
      _sendVoiceMessage();
    }
    _dragOffsetX = 0;
    _dragOffsetY = 0;
  }

  void _onDragUpdate(Offset delta) {
    if (_voiceController?.state != VoiceRecordingState.recording) return;

    _dragOffsetX += delta.dx;
    _dragOffsetY += delta.dy;

    final screenWidth = MediaQuery.maybeSizeOf(context)?.width ?? 360;
    final cancelThreshold = -screenWidth * _cancelThresholdRatio;

    if (_dragOffsetX < cancelThreshold) {
      _dragOffsetX = 0;
      _dragOffsetY = 0;
      _voiceController!.cancelRecording();
    } else if (_dragOffsetY < _lockThreshold) {
      _dragOffsetX = 0;
      _dragOffsetY = 0;
      _voiceController!.lockRecording();
    }
  }

  Future<void> _sendVoiceMessage() async {
    if (_voiceController == null) return;

    final state = _voiceController!.state;
    VoiceMessageData? data;

    if (state == VoiceRecordingState.recording) {
      data = await _voiceController!.stopRecording();
    } else if (state == VoiceRecordingState.locked ||
        state == VoiceRecordingState.preListen) {
      data = await _voiceController!.confirmSend();
    }

    if (data != null) {
      widget.onVoiceMessageReady?.call(data);
    }
    _cleanupVoiceController();
  }

  void _onVoiceStateChanged() {
    if (!mounted) return;
    if (_voiceController?.state == VoiceRecordingState.idle) {
      _cleanupVoiceController();
    }
    _syncLockHintOverlay();
    setState(() {});
  }

  void _syncLockHintOverlay() {
    final shouldShow = _isActiveRecording;
    if (shouldShow && _lockHintEntry == null) {
      _showLockHintOverlay();
    } else if (!shouldShow && _lockHintEntry != null) {
      _removeLockHintOverlay();
    }
  }

  void _showLockHintOverlay() {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _lockHintEntry = OverlayEntry(builder: (overlayContext) {
      return Positioned(
        left: 0,
        top: 0,
        child: CompositedTransformFollower(
          link: _voiceButtonLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
          offset: const Offset(0, -12),
          child: Material(
            color: Colors.transparent,
            child: widget.theme.lockHintBuilder?.call(overlayContext) ??
                _LockHintPill(theme: widget.theme),
          ),
        ),
      );
    });
    overlay.insert(_lockHintEntry!);
  }

  void _removeLockHintOverlay() {
    _lockHintEntry?.remove();
    _lockHintEntry = null;
  }

  void _cleanupVoiceController() {
    _voiceController?.removeListener(_onVoiceStateChanged);
    _removeLockHintOverlay();
    if (mounted) setState(() {});
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        _voiceController?.state == VoiceRecordingState.recording) {
      _voiceController!.cancelRecording();
      _cleanupVoiceController();
    }
  }

  @override
  void dispose() {
    _saveDraft();
    _linkDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerChanged);
    _textController.dispose();
    _voiceController?.removeListener(_onVoiceStateChanged);
    _voiceController?.dispose();
    _removeLockHintOverlay();
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
    if (_isLockedOrPreListen) {
      child = _buildRecordingArea();
      key = 'locked';
    } else if (_isActiveRecording) {
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
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: child,
        ),
        child: KeyedSubtree(
          key: ValueKey(key),
          child: child,
        ),
      ),
    );

    Widget inputArea = content;

    // Wrap in a long-press detector that persists across recording state changes.
    // This ensures slide-to-cancel and slide-to-lock gestures continue working
    // even after the UI switches from mic button to recording overlay.
    if (widget.showVoiceButton && widget.onVoiceMessageReady != null) {
      inputArea = GestureDetector(
        onLongPressStart: !_isRecordingNew ? (_) => _onLongPressStart() : null,
        onLongPressMoveUpdate: (details) {
          _onDragUpdate(Offset(
            details.localOffsetFromOrigin.dx,
            details.localOffsetFromOrigin.dy,
          ));
        },
        onLongPressEnd: (_) => _onLongPressEnd(),
        behavior: _isRecordingNew
            ? HitTestBehavior.opaque
            : HitTestBehavior.deferToChild,
        child: inputArea,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: widget.theme.inputBackgroundColor ?? Colors.white,
        boxShadow: widget.theme.inputContainerShadow,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPreviewBanner(),
            _buildLinkPreviewBanner(),
            inputArea,
          ],
        ),
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
            backgroundColor: widget.theme.linkPreviewBackgroundColor ??
                Colors.grey.shade100,
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
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismissPreview,
            child: const SizedBox(
              width: 36,
              height: 36,
              child: Center(child: Icon(Icons.close, size: 18)),
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
              color: widget.theme.editingBackgroundColor ?? Colors.blue.shade50,
              border: Border(
                left: BorderSide(
                  color: widget.theme.editingBorderColor ?? Colors.blue,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.edit,
                    size: 16,
                    color: widget.theme.editingBorderColor ?? Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.theme.l10n.editing,
                        style: widget.theme.editingLabelStyle ??
                            TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                      ),
                      Text(
                        editing.text ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: widget.theme.editingPreviewStyle ??
                            const TextStyle(
                                fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.controller.setEditingMessage(null),
                  child: const SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(child: Icon(Icons.close, size: 18)),
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
            theme: widget.theme,
            onDismiss: () => widget.controller.setReplyTo(null),
          ),
        );
      },
    );
  }

  Widget _buildRecordingArea() {
    return VoiceRecorderOverlay(
      controller: _voiceController!,
      theme: widget.theme,
      onSend: _sendVoiceMessage,
    );
  }

  Widget _buildActiveRecordingRow() {
    final controller = _voiceController!;
    final custom = widget.theme.recordingComposerBuilder
        ?.call(context, controller, _sendVoiceMessage);
    if (custom != null) return custom;
    return _ActiveRecordingRow(
      controller: controller,
      theme: widget.theme,
      voiceButton: _buildVoiceButton(),
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
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: TextField(
                controller: _textController,
                maxLines: widget.maxLines,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                textAlignVertical: TextAlignVertical.center,
                style: widget.theme.inputTextStyle,
                decoration: InputDecoration(
                  hintText: widget.theme.l10n.writeMessage,
                  hintStyle: widget.theme.inputHintStyle,
                  border: _composerBorder(),
                  enabledBorder: _composerBorder(),
                  focusedBorder: _composerBorder(),
                  disabledBorder: _composerBorder(),
                  filled: true,
                  fillColor:
                      widget.theme.inputFillColor ?? Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 11),
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
            _buildVoiceButton(),
          ],
        ],
      ),
    );
  }

  OutlineInputBorder _composerBorder() {
    final borderColor = widget.theme.inputBorderColor;
    return OutlineInputBorder(
      borderRadius: widget.theme.inputBorderRadius ?? BorderRadius.circular(24),
      borderSide: borderColor != null
          ? BorderSide(
              color: borderColor,
              width: widget.theme.inputBorderWidth ?? 1,
            )
          : BorderSide.none,
    );
  }

  Widget _buildSendButton() {
    return Semantics(
      label: widget.theme.l10n.send,
      button: true,
      enabled: _hasText,
      child: GestureDetector(
        onTap: _hasText ? _send : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: widget.theme.sendIconBuilder?.call(context, _hasText) ??
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
            ? (widget.theme.sendButtonColor ?? Colors.blue)
            : (widget.theme.sendButtonDisabledColor ?? Colors.grey.shade300),
        shape: BoxShape.circle,
      ),
      child: Icon(
        widget.theme.sendButtonIcon ?? Icons.send,
        color: widget.theme.sendButtonIconColor ?? Colors.white,
        size: 20,
      ),
    );
  }

  Widget _buildAttachButton() {
    return Semantics(
      label: widget.theme.l10n.gallery,
      button: true,
      child: GestureDetector(
        onTap: widget.onAttachTap ?? _showAttachmentPicker,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: widget.theme.attachIconBuilder?.call(context) ??
              Icon(
                widget.theme.attachButtonIcon ?? Icons.attach_file,
                color: widget.theme.attachButtonColor,
              ),
        ),
      ),
    );
  }

  Widget _buildCameraButton() {
    return Semantics(
      label: widget.theme.l10n.camera,
      button: true,
      child: GestureDetector(
        onTap: widget.onPickCamera,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: widget.theme.voiceButtonColor ?? Colors.grey.shade200,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: widget.theme.cameraIconBuilder?.call(context) ??
                Icon(
                  widget.theme.cameraButtonIcon ?? Icons.camera_alt_outlined,
                  size: 20,
                  color: widget.theme.cameraButtonColor ??
                      widget.theme.voiceButtonIdleIconColor ??
                      Colors.grey.shade700,
                ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceButton() => CompositedTransformTarget(
        link: _voiceButtonLink,
        child: VoiceRecorderButton(theme: widget.theme),
      );
}

class _ActiveRecordingRow extends StatelessWidget {
  const _ActiveRecordingRow({
    required this.controller,
    required this.theme,
    required this.voiceButton,
  });

  final VoiceRecordingController controller;
  final ChatTheme theme;
  final Widget voiceButton;

  @override
  Widget build(BuildContext context) {
    final activeColor = theme.voiceRecorderActiveColor ?? Colors.red;
    final hintColor =
        theme.voiceRecorderHintStyle?.color ?? Colors.grey.shade700;
    final hintStyle = theme.voiceRecorderHintStyle ??
        TextStyle(color: hintColor, fontSize: 16);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        height: 40,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _RecordingPulsingMic(color: activeColor),
            const SizedBox(width: 8),
            Expanded(
              child: _SlideToCancelHint(
                color: hintColor,
                style: hintStyle,
                text: theme.l10n.slideToCancel,
              ),
            ),
            const SizedBox(width: 8),
            voiceButton,
          ],
        ),
      ),
    );
  }
}

class _RecordingPulsingMic extends StatefulWidget {
  const _RecordingPulsingMic({required this.color});
  final Color color;

  @override
  State<_RecordingPulsingMic> createState() => _RecordingPulsingMicState();
}

class _RecordingPulsingMicState extends State<_RecordingPulsingMic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) => Opacity(
        opacity: 0.45 + 0.55 * _controller.value,
        child: Icon(Icons.mic, color: widget.color, size: 26),
      ),
    );
  }
}

class _SlideToCancelHint extends StatefulWidget {
  const _SlideToCancelHint({
    required this.color,
    required this.style,
    required this.text,
  });

  final Color color;
  final TextStyle style;
  final String text;

  @override
  State<_SlideToCancelHint> createState() => _SlideToCancelHintState();
}

class _SlideToCancelHintState extends State<_SlideToCancelHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Opacity(
          opacity: 0.35 + 0.65 * t,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(Icons.chevron_left, color: widget.color, size: 24),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.text,
                  style: widget.style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LockHintPill extends StatefulWidget {
  const _LockHintPill({required this.theme});
  final ChatTheme theme;

  @override
  State<_LockHintPill> createState() => _LockHintPillState();
}

class _LockHintPillState extends State<_LockHintPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.theme.voiceRecorderLockIconColor ??
        Colors.grey.shade700;
    final pillColor = widget.theme.inputBackgroundColor ?? Colors.white;
    return IgnorePointer(
      child: Container(
        width: 40,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: pillColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 20, color: iconColor),
            const SizedBox(height: 8),
            SizedBox(
              height: 22,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (_, _) {
                  final t = _controller.value;
                  final fade = t < 0.5
                      ? (t * 2)
                      : 1 - ((t - 0.5) * 2);
                  final dy = -8 * t;
                  return Transform.translate(
                    offset: Offset(0, dy),
                    child: Opacity(
                      opacity: fade.clamp(0.0, 1.0),
                      child: Icon(
                        Icons.keyboard_arrow_up,
                        size: 22,
                        color: iconColor,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
