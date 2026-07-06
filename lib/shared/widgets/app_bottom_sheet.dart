import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  double maxHeightFactor = 0.85,
}) {
  final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: isIOS ? CupertinoColors.systemBackground : null,
    shape: isIOS
        ? const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          )
        : null,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: AppSpacing.lg + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * maxHeightFactor,
          ),
          child: builder(ctx),
        ),
      );
    },
  );
}
