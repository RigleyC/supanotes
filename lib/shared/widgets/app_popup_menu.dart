import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<T?> showAdaptivePopupMenu<T>({
  required BuildContext context,
  required List<AdaptivePopupMenuItem<T>> items,
}) async {
  if (Theme.of(context).platform == TargetPlatform.iOS) {
    final selected = await showCupertinoModalPopup<int>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          for (var i = 0; i < items.length; i++)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(i),
              child: Text(items[i].label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          isDefaultAction: true,
          child: const Text('Cancelar'),
        ),
      ),
    );
    if (selected != null && selected < items.length) {
      return items[selected].value;
    }
    return null;
  }

  final renderBox = context.findRenderObject() as RenderBox?;
  final offset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
  final size = renderBox?.size ?? Size.zero;

  return showMenu<T>(
    context: context,
    position: RelativeRect.fromLTRB(
      offset.dx + size.width,
      offset.dy + 56,
      offset.dx + size.width,
      offset.dy,
    ),
    items: [
      for (final item in items)
        PopupMenuItem<T>(
          value: item.value,
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(item.icon as IconData?),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(item.label)),
            ],
          ),
        ),
    ],
  );
}
