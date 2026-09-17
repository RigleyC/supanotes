import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

/// A platform-native popup menu with one API for every platform.
class AppPopupMenu<T> extends StatelessWidget {
  const AppPopupMenu({
    required this.items,
    required this.onSelected,
    required this.icon,
    this.appleSymbol = 'ellipsis',
    this.iconColor,
    this.size = 44,
    super.key,
  });

  final List<AppPopupMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final IconData icon;
  final String appleSymbol;
  final Color? iconColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isApple =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    if (isApple) {
      return CNPopupMenuButton.icon(
        buttonIcon: CNSymbol(appleSymbol, size: 18, color: iconColor),
        buttonStyle: CNButtonStyle.plain,
        size: size,
        items: [
          for (final item in items) ...[
            if (item.dividerBefore) const CNPopupMenuDivider(),
            CNPopupMenuItem(
              label: item.label,
              icon: item.appleSymbol == null
                  ? null
                  : CNSymbol(item.appleSymbol!, size: 18),
              isDestructive: item.isDestructive,
            ),
          ],
        ],
        onSelected: (index) {
          var selectableIndex = 0;
          for (final item in items) {
            if (item.dividerBefore) selectableIndex++;
            if (index == selectableIndex) {
              onSelected(item.value);
              return;
            }
            selectableIndex++;
          }
        },
      );
    }

    return PopupMenuButton<T>(
      icon: Icon(icon, color: iconColor, size: 18),
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final item in items) ...[
          if (item.dividerBefore) const PopupMenuDivider(),
          PopupMenuItem<T>(
            value: item.value,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: AppSpacing.sm,
              children: [
                if (item.materialIcon != null)
                  Icon(item.materialIcon, size: AppSpacing.iconSm),
                Flexible(child: Text(item.label)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// An item displayed by [AppPopupMenu].
class AppPopupMenuItem<T> {
  const AppPopupMenuItem({
    required this.label,
    required this.value,
    this.appleSymbol,
    this.materialIcon,
    this.dividerBefore = false,
    this.isDestructive = false,
  });

  final String label;
  final T value;
  final String? appleSymbol;
  final IconData? materialIcon;
  final bool dividerBefore;
  final bool isDestructive;
}
