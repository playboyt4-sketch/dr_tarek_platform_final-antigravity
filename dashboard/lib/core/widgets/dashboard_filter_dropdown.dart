import 'package:flutter/material.dart';

import '../responsive/responsive.dart';
import '../theme/app_typography.dart';

class DashboardFilterDropdown<T> extends StatelessWidget {
  const DashboardFilterDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width = 320,
  });

  final T value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;
  final double width;

  TextStyle _itemStyle(double fontSize) => TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontSize: fontSize,
        height: 1.2,
        color: AppColors.ink,
      );

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    return Container(
      width: rs(width),
      padding: EdgeInsets.symmetric(horizontal: rs(24)),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.inputStroke, width: 1.5),
        borderRadius: BorderRadius.circular(28),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: rs(36),
            color: AppColors.ink,
          ),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(20),
          style: _itemStyle(rs(24)),
          items: <DropdownMenuItem<T>>[
            for (final MapEntry<T, String> entry in items.entries)
              DropdownMenuItem<T>(
                value: entry.key,
                child: Text(entry.value, style: _itemStyle(rs(24))),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
