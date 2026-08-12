import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/material.dart';

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
}) {
  return FamilyModalSheet.show<T>(
    context: context,
    isDismissible: true,
    enableDrag: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.5,
    ),
    contentBackgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    builder: builder,
  );
}