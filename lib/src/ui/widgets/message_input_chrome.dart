part of 'message_input.dart';

/// The pieces [MessageInput] paints around the text field: the mention
/// overlay, the reply and link-preview banners, the recording area, the
/// input row itself and the send, attach, camera and voice buttons that
/// sit in it.
extension _MessageInputChrome on _MessageInputState {
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
      voiceButtonSlot: _MessageInputState._voiceButtonSlot,
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
                contextMenuBuilder: buildTextSelectionMenu,
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
            _MessageInputState._voiceButtonSlot,
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
          padding: _MessageInputState._voiceButtonInset,
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
