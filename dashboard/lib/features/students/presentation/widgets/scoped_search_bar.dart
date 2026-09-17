import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';

/// Search scopes for [ScopedSearchBar]: Name / Type / Plan / Status.
enum SearchScope {
  name('Name', 'Search by Name...'),
  type('Type', 'Search by Type (Center / Guest)...'),
  plan('Plan', 'Search by Plan (FREE / PRO / MAX)...'),
  status('Status', 'Search by Status (Active / Inactive)...');

  final String label;
  final String placeholder;
  const SearchScope(this.label, this.placeholder);
}

/// Smart scoped search bar (`Scoped Search Bar`, 8 variants):
/// 420 x 44, radius 16, white, 1 px #E5E7EB border.
///
/// Left scope selector (18 px arrow #374151 + active scope label),
/// 20 px vertical divider, borderless text field with a scope-driven
/// placeholder, and an animated 160 px dropdown card (8 px offset,
/// Y:8 / blur:20 shadow, #F3F4F6 active highlight).
class ScopedSearchBar extends StatefulWidget {
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<SearchScope>? onScopeChanged;
  final SearchScope initialScope;
  final String? initialQuery;

  const ScopedSearchBar({
    super.key,
    this.onSearchChanged,
    this.onScopeChanged,
    this.initialScope = SearchScope.name,
    this.initialQuery,
  });

  @override
  State<ScopedSearchBar> createState() => _ScopedSearchBarState();
}

class _ScopedSearchBarState extends State<ScopedSearchBar> {
  late SearchScope _currentScope = widget.initialScope;
  bool _isOpen = false;
  late final TextEditingController _textController =
      TextEditingController(text: widget.initialQuery);
  final OverlayPortalController _overlayController =
      OverlayPortalController();
  final LayerLink _layerLink = LayerLink();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _selectScope(SearchScope scope) {
    setState(() {
      _currentScope = scope;
      _isOpen = false;
      _overlayController.hide();
    });
    widget.onScopeChanged?.call(scope);
  }

  void _toggleDropdown() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _overlayController.show();
      } else {
        _overlayController.hide();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (BuildContext context) {
          return CompositedTransformFollower(
            link: _layerLink,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 6),
            child: Align(
              alignment: Alignment.topLeft,
              child: _buildDropdownMenu(),
            ),
          );
        },
        child: Container(
          width: 420,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: <Widget>[
              // Scope Selector Button
              InkWell(
                key: const ValueKey<String>('scope-selector'),
                onTap: _toggleDropdown,
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      _isOpen
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: const Color(0xFF374151),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _currentScope.label,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Vertical Divider
              Container(
                width: 1,
                height: 20,
                color: const Color(0xFFE5E7EB),
              ),
              const SizedBox(width: 12),
              // Search Input Text Field
              Expanded(
                child: TextField(
                  controller: _textController,
                  onChanged: widget.onSearchChanged,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    color: Color(0xFF111827),
                  ),
                  decoration: InputDecoration(
                    hintText: _currentScope.placeholder,
                    hintStyle: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 14,
                      color: Color(0xFF9CA3AF),
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownMenu() {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      builder: (BuildContext context, double value, Widget? child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 4 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: SearchScope.values.map((SearchScope scope) {
            final bool isSelected = scope == _currentScope;
            return InkWell(
              key: ValueKey<String>('scope-option-${scope.name}'),
              onTap: () => _selectScope(scope),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFF3F4F6)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.centerLeft,
                child: Text(
                  scope.label,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? const Color(0xFF111827)
                        : const Color(0xFF374151),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
