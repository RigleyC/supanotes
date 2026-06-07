/// Search input field with an integrated debounce timer.
///
/// Wraps a [TextField] styled to match the rest of the app and emits
/// debounced [onQueryChanged] callbacks so the parent screen does not
/// hit the backend on every keystroke.
///
/// The widget is **uncontrolled from the outside**: it owns its own
/// [TextEditingController] (and the [FocusNode] when the parent does
/// not pass one in) so the parent only has to listen for the debounced
/// query. Pass an [autofocus] of `true` to pop the keyboard on mount —
/// this is the default on the search screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:supanotes/core/constants/app_constants.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

class SearchInputBar extends StatefulWidget {
  const SearchInputBar({
    super.key,
    required this.onQueryChanged,
    this.initialQuery = '',
    this.autofocus = true,
    this.debounce = const Duration(milliseconds: AppConstants.searchDebounceMs),
    this.hintText = 'Buscar notas',
  });

  /// Called with the trimmed query after [debounce] has elapsed
  /// without further keystrokes.
  ///
  /// The empty string is a valid value — the screen uses it to clear
  /// the result list when the user empties the field.
  final ValueChanged<String> onQueryChanged;

  final String initialQuery;
  final bool autofocus;
  final Duration debounce;
  final String hintText;

  @override
  State<SearchInputBar> createState() => _SearchInputBarState();
}

class _SearchInputBarState extends State<SearchInputBar> {
  late final TextEditingController _controller;
  Timer? _debounceTimer;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _hasText = widget.initialQuery.isNotEmpty;
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final raw = _controller.text;
    final hasText = raw.isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.debounce, () {
      widget.onQueryChanged(raw.trim());
    });
  }

  void _clear() {
    _debounceTimer?.cancel();
    _controller.clear();
    // Immediate emit so the parent drops results without waiting for
    // the debounce window to close.
    widget.onQueryChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.hintText,
        prefixIcon: Icon(Icons.search, color: scheme.onSurfaceVariant),
        suffixIcon: _hasText
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Limpar',
                onPressed: _clear,
              )
            : null,
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
    );
  }
}
