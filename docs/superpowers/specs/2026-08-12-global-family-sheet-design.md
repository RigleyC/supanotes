# Global Family Sheet Design

## Status

Approved for documentation. Implementation is not started.

## Context

SupaNotes uses two bottom-sheet patterns:

- `FamilyModalSheet`, which supports a stack of pages. `TaskMetadataSheet` uses
  this pattern. Its internal pages use a header with a close icon that calls
  `popPage()`.
- `showAppBottomSheet`, which uses Flutter's default modal bottom sheet for
  simpler content.

The Family pattern already has the required close semantics. The missing part
is a shared page layout and a shared entry point so features do not duplicate
header, spacing, color, height, and navigation behavior.

## Goals

- Standardize feature sheets on the Family sheet visual language.
- Provide a reusable page header with a title and a close icon aligned to the
  top right.
- Support different titles for the root page and internal pages.
- Keep the header fixed while only the content that owns a scroll view scrolls.
- Preserve the existing `TaskMetadataSheet` save-after-close behavior.
- Let callers complete feature actions after `await showGlobalSheet(...)`.

## Non-goals

- Do not add a global state manager for sheets.
- Do not move feature persistence or business rules into the shared sheet.
- Do not replace `FamilyModalSheet` or modify the external package.
- Do not migrate every existing `showAppBottomSheet` in the first change.
- Do not add compatibility wrappers for obsolete sheet paths.

## Proposed API

Add a shared presentation component, for example in
`lib/shared/widgets/global_sheet.dart`:

```dart
Future<T?> showGlobalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
})
```

`showGlobalSheet` delegates to `FamilyModalSheet.show<T>` and owns the shared
modal configuration: dismissible behavior, drag behavior, content background,
safe-area behavior, and the standard height constraint.

Each visible page uses a shared wrapper:

```dart
GlobalSheetPage(
  title: 'Editar horário e frequência',
  child: TaskMetadataSheetBody(taskId: taskId),
)
```

The wrapper owns the fixed header and renders the supplied feature widget
below it. A feature page remains responsible for its own content layout and
scroll controller.

## Header and navigation behavior

The shared header displays the page title and a close icon. The close action
calls `FamilyModalSheet.of(context).popPage()`.

This uses the existing Family behavior:

- On an internal page, `popPage()` returns to the previous page.
- On the root page, `popPage()` dismisses the entire sheet.
- Dismissal resolves the `Future` returned by `showGlobalSheet`.

The shared component must not own an `onClose` business callback. The caller
performs the final action after the await:

```dart
await showGlobalSheet(...);
await saveFinalState();
```

Therefore, closing by the header icon, outside tap, drag gesture, or system
back has the same root-page completion behavior. Returning from an internal
page does not resolve the root sheet future and does not save prematurely.

## Layout and scrolling

The page wrapper uses a column-like layout:

1. Fixed top and horizontal padding.
2. Shared header.
3. Feature content.

If the feature content contains a `CustomScrollView`, `ListView`, or another
scrollable widget, it receives the remaining space and scrolls below the fixed
header. The wrapper must not put the header and the content in the same outer
scroll view.

The initial standard height is a maximum of 50% of the viewport. The shared
entry point has no height override in the first implementation. A feature that
needs a larger sheet must be reviewed as a separate design decision.

## Migration order

1. Migrate `TaskMetadataSheet` root and internal pages. This is the reference
   flow because it already saves state after the root sheet closes.
2. Migrate the note icon picker. Remove its duplicated header and use the
   shared fixed-header layout for the emoji and catalog pages.
3. Evaluate `showAppBottomSheet` consumers one feature at a time. Keep the
   existing helper until each consumer is intentionally migrated.

## Testing

Add focused widget tests for the shared component and migrated flows:

- Root-page `X` closes the sheet and allows the caller's post-await action.
- Internal-page `X` returns to the previous page without closing the root.
- Different pages render different titles.
- The header remains visible while a long content list scrolls.
- `TaskMetadataSheet` still saves the final provider state only after root
  dismissal.
- Note icon picker search and color controls remain fixed while the icon grid
  scrolls.

Run the focused Flutter tests and analyzer checks. Run the full Flutter suite
after migration, reporting any timeout separately from completed checks.

## Risks and decisions

The shared component is intentionally a thin presentation boundary. A feature
must not assume that a close icon means “save immediately”; it means either
“go back” or “dismiss the root sheet”. The feature's post-await code remains
the authority for persistence.

`showAppBottomSheet` is not removed in this design because its consumers may
need a different height or interaction model. Removal should happen only when
all consumers have been migrated and verified.
