import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ui/design/app_colors.dart';
import '../../../ui/design/app_spacing.dart';

/// Debounced search bar for filtering the server locations list.
class LocationSearchBar extends StatefulWidget {
  const LocationSearchBar({
    super.key,
    required this.onChanged,
    this.debounceDuration = const Duration(milliseconds: 300),
  });

  final ValueChanged<String> onChanged;
  final Duration debounceDuration;

  @override
  State<LocationSearchBar> createState() => _LocationSearchBarState();
}

class _LocationSearchBarState extends State<LocationSearchBar> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(widget.debounceDuration, () {
      widget.onChanged(value.trim());
    });
  }

  void _onClear() {
    _controller.clear();
    _debounce?.cancel();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: _onTextChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search locations',
        hintStyle: TextStyle(color: AppColors.inkSoft),
        prefixIcon: const Icon(Icons.search, color: AppColors.inkMuted),
        suffixIcon: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            if (_controller.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.clear, size: 20),
              color: AppColors.inkMuted,
              onPressed: _onClear,
            );
          },
        ),
        filled: true,
        fillColor: AppColors.surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space4,
          vertical: AppSpacing.space3,
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
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}
