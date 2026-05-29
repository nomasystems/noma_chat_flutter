import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/chat_theme.dart';

/// Debounced text field used to filter the room list by name.
class RoomSearchBar extends StatefulWidget {
  const RoomSearchBar({
    super.key,
    this.onChanged,
    this.hintText = 'Search',
    this.debounceDuration = const Duration(milliseconds: 300),
    this.theme = ChatTheme.defaults,
  });

  final ValueChanged<String>? onChanged;
  final String hintText;
  final Duration debounceDuration;
  final ChatTheme theme;

  @override
  State<RoomSearchBar> createState() => _RoomSearchBarState();
}

class _RoomSearchBarState extends State<RoomSearchBar> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(widget.debounceDuration, () {
      widget.onChanged?.call(_controller.text);
    });
  }

  void _clear() {
    _controller.clear();
    _debounce?.cancel();
    widget.onChanged?.call('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _controller,
        style: widget.theme.roomList.searchTextStyle,
        // Outlined style matching the host app's other TextFields (login
        // / onboarding form). Earlier "pill" treatment (filled, no
        // border) didn't fit the rest of the surface and the contrast
        // between the inside and outside of the field was muddy.
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (_, value, __) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: widget.theme.l10n.clearText,
                onPressed: _clear,
              );
            },
          ),
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          isDense: true,
        ),
      ),
    );
  }
}
