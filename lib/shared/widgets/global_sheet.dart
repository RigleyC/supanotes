import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:supanotes/core/utils/app_haptics.dart';

export 'global_sheet_header.dart';
export 'global_sheet_page.dart';

/// Opens a Family-based bottom sheet with a page-aware, fixed-header layout.
///
/// Owns only the Family modal configuration; feature widgets keep their own
/// state, navigation targets, scrolling, and persistence rules. The caller
/// remains the authority for the final action after awaiting this future.
Future<T?> showGlobalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  VoidCallback? onDismissed,
}) {
  AppHaptics.controlTap();
  var dismissalNotified = false;
  var listenerScheduled = false;
  Animation<double>? routeAnimation;
  AnimationStatusListener? dismissalListener;

  void notifyDismissed() {
    if (dismissalNotified) return;
    dismissalNotified = true;
    if (routeAnimation != null && dismissalListener != null) {
      routeAnimation!.removeStatusListener(dismissalListener!);
    }
    onDismissed?.call();
  }

  return FamilyModalSheet.show<T>(
    context: context,
    contentBackgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    builder: (sheetContext) {
      if (onDismissed != null && !listenerScheduled) {
        listenerScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (dismissalNotified) return;
          if (!sheetContext.mounted) {
            notifyDismissed();
            return;
          }
          routeAnimation = ModalRoute.of(sheetContext)?.animation;
          if (routeAnimation == null) {
            notifyDismissed();
            return;
          }
          dismissalListener = (status) {
            if (status == AnimationStatus.dismissed) notifyDismissed();
          };
          routeAnimation!.addStatusListener(dismissalListener!);
          if (routeAnimation!.status == AnimationStatus.dismissed) {
            notifyDismissed();
          }
        });
      }
      return builder(sheetContext);
    },
  );
}

/// Dismisses a global sheet, including any pages pushed inside it.
void dismissGlobalSheet(BuildContext context) {
  final sheet = FamilyModalSheet.of(context);
  while (sheet.canPopPage()) {
    sheet.popPage();
  }
  sheet.popPage();
}
