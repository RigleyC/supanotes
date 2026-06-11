# Pull Down Draggable Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the notes pull-down interaction using `DraggableScrollableSheet`, with the notes list/grid as the sheet content and the daily brief as the revealed background.

**Architecture:** The sheet owns the drag/scroll coordination through Flutter's built-in `DraggableScrollableSheet` and its provided `ScrollController`. `PullDownBriefPanel` becomes a small wrapper around a dark background plus a white draggable sheet surface. The only canonical visual state is the sheet progress derived from `DraggableScrollableController.size`; appbar color, rounded corners, and background effects derive from that progress.

**Tech Stack:** Flutter `DraggableScrollableSheet`, `DraggableScrollableController`, `CustomScrollView`, widget tests with `WidgetTester`.

---

## Design Decisions

- Use `DraggableScrollableSheet` because the notes list is intended to be the draggable content.
- Do not copy the repo example's boolean `isExpanded` threshold model. It uses separate thresholds (`>= .8` and `< .85`) and turns progress into coarse state. SupaNotes should derive visuals from continuous progress.
- Do not keep the current `Listener`/`VelocityTracker` implementation. `DraggableScrollableSheet` coordinates dragging and inner scrolling if the child uses the provided `ScrollController`.
- Keep state local to `NotesListScreen`; do not introduce Riverpod for transient visual progress.
- Preserve current list/grid content, `headerSlivers`, note actions, offline indicator, and FAB.

---

## Files

- Modify: `lib/features/notes/presentation/widgets/pull_down_brief_panel.dart`
  - Replace custom pointer/spring implementation with `DraggableScrollableSheet`.
  - Provide the sheet's `ScrollController` to the child through a builder.
  - Expose continuous progress via `onProgressChanged`.
- Modify: `lib/features/notes/presentation/widgets/notes_list_view.dart`
  - Add optional `ScrollController? controller`.
  - Pass it to `CustomScrollView`.
- Modify: `lib/features/notes/presentation/widgets/notes_grid_view.dart`
  - Add optional `ScrollController? controller`.
  - Pass it to `CustomScrollView`.
- Modify: `lib/features/notes/presentation/notes_list_screen.dart`
  - Use the new `PullDownBriefPanel` builder API.
  - Keep appbar colors derived from `_panelProgress`.
- Modify: `test/features/notes/presentation/widgets/pull_down_brief_panel_test.dart`
  - Replace old transform/offset assumptions with sheet-size behavior.
  - Verify the sheet starts closed, can drag open, reports progress, and keeps rounded corners stable.

---

## Task 1: Add Controller Support To Notes Scroll Views

**Files:**
- Modify: `lib/features/notes/presentation/widgets/notes_list_view.dart`
- Modify: `lib/features/notes/presentation/widgets/notes_grid_view.dart`

- [ ] **Step 1: Update `NotesListView` constructor and field**

Add the optional controller parameter.

```dart
const NotesListView({
  super.key,
  required this.notes,
  required this.headerSlivers,
  required this.onTap,
  required this.onDelete,
  required this.onToggleFavorite,
  this.controller,
});

final ScrollController? controller;
```

- [ ] **Step 2: Pass controller to `NotesListView`'s `CustomScrollView`**

```dart
return CustomScrollView(
  controller: controller,
  physics: const ClampingScrollPhysics(),
  slivers: [
    ...headerSlivers,
    // existing slivers stay unchanged
  ],
);
```

- [ ] **Step 3: Update `NotesGridView` constructor and field**

Add the same optional parameter.

```dart
const NotesGridView({
  super.key,
  required this.notes,
  required this.headerSlivers,
  required this.onTap,
  required this.onDelete,
  required this.onToggleFavorite,
  this.controller,
});

final ScrollController? controller;
```

- [ ] **Step 4: Pass controller to `NotesGridView`'s `CustomScrollView`**

```dart
return CustomScrollView(
  controller: controller,
  physics: const ClampingScrollPhysics(),
  slivers: [
    ...headerSlivers,
    // existing slivers stay unchanged
  ],
);
```

- [ ] **Step 5: Run analyzer for the two widgets**

Run:

```powershell
dart analyze lib/features/notes/presentation/widgets/notes_list_view.dart lib/features/notes/presentation/widgets/notes_grid_view.dart
```

Expected: `No issues found!`

---

## Task 2: Replace PullDownBriefPanel With Draggable Sheet

**Files:**
- Modify: `lib/features/notes/presentation/widgets/pull_down_brief_panel.dart`

- [ ] **Step 1: Replace the public API with builder-based child**

Use this API so the sheet can pass its `ScrollController` to list/grid.

```dart
class PullDownBriefPanel extends StatefulWidget {
  const PullDownBriefPanel({
    super.key,
    required this.background,
    required this.builder,
    this.onProgressChanged,
  });

  final Widget background;
  final Widget Function(BuildContext context, ScrollController controller) builder;
  final ValueChanged<double>? onProgressChanged;

  static const double _closedSize = 0.78;
  static const double _openSize = 1.0;
  static const double _cornerRadius = 30;

  @override
  State<PullDownBriefPanel> createState() => _PullDownBriefPanelState();
}
```

The exact `_closedSize` should be tuned once visually checked. Start at `0.78` because it reveals roughly the top brief area on a phone-sized viewport while keeping the notes list mostly visible. If the current `180px` reveal needs to be preserved precisely, calculate it from viewport height in Task 2 Step 4.

- [ ] **Step 2: Add controller lifecycle**

```dart
class _PullDownBriefPanelState extends State<PullDownBriefPanel> {
  late final DraggableScrollableController _controller;

  @override
  void initState() {
    super.initState();
    _controller = DraggableScrollableController()
      ..addListener(_notifyProgress);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_notifyProgress)
      ..dispose();
    super.dispose();
  }
}
```

- [ ] **Step 3: Derive progress continuously from sheet size**

```dart
void _notifyProgress() {
  final progress = ((_controller.size - PullDownBriefPanel._closedSize) /
          (PullDownBriefPanel._openSize - PullDownBriefPanel._closedSize))
      .clamp(0.0, 1.0);
  widget.onProgressChanged?.call(progress);
}
```

- [ ] **Step 4: Build the draggable sheet**

If preserving exact 180px reveal is more important than a fixed fraction, compute `closedSize` from constraints:

```dart
@override
Widget build(BuildContext context) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final closedSize =
          ((constraints.maxHeight - 180) / constraints.maxHeight).clamp(0.0, 1.0);

      return Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          const Positioned.fill(child: ColoredBox(color: Colors.black)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 180,
            child: widget.background,
          ),
          DraggableScrollableSheet(
            controller: _controller,
            snap: true,
            snapSizes: [closedSize, PullDownBriefPanel._openSize],
            initialChildSize: closedSize,
            minChildSize: closedSize,
            maxChildSize: PullDownBriefPanel._openSize,
            builder: (context, scrollController) {
              return Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(PullDownBriefPanel._cornerRadius),
                ),
                clipBehavior: Clip.hardEdge,
                child: widget.builder(context, scrollController),
              );
            },
          ),
        ],
      );
    },
  );
}
```

Important correction versus the example repo: do not keep separate `isExpanded` boolean state. If a boolean is needed later, derive it from progress.

- [ ] **Step 5: Run old focused tests and observe failures**

Run:

```powershell
flutter test test/features/notes/presentation/widgets/pull_down_brief_panel_test.dart
```

Expected: old tests fail because they assert transform offset and `Material` under `Transform`. This is correct; Task 3 replaces them with sheet-contract tests.

---

## Task 3: Rewrite Pull-Down Tests For Draggable Sheet

**Files:**
- Modify: `test/features/notes/presentation/widgets/pull_down_brief_panel_test.dart`

- [ ] **Step 1: Replace fixture with builder API**

```dart
const contentKey = Key('notes-content');

class _TestApp extends StatelessWidget {
  const _TestApp({this.onProgressChanged});

  final ValueChanged<double>? onProgressChanged;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: PullDownBriefPanel(
            background: const ColoredBox(color: Colors.black),
            onProgressChanged: onProgressChanged,
            builder: (context, controller) {
              return CustomScrollView(
                key: contentKey,
                controller: controller,
                physics: const ClampingScrollPhysics(),
                slivers: [
                  SliverList.builder(
                    itemCount: 40,
                    itemBuilder: (context, index) {
                      return SizedBox(
                        height: 56,
                        child: Text('Note $index'),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Test initial sheet is closed and rounded**

```dart
testWidgets('starts as a rounded sheet over the brief background', (tester) async {
  await tester.pumpWidget(const _TestApp());

  final material = tester.widget<Material>(find.byType(Material).last);

  expect(
    material.borderRadius,
    const BorderRadius.vertical(top: Radius.circular(30)),
  );
});
```

- [ ] **Step 3: Test drag reports progress**

```dart
testWidgets('reports progress while dragging sheet open', (tester) async {
  final progressValues = <double>[];
  await tester.pumpWidget(_TestApp(onProgressChanged: progressValues.add));

  await tester.drag(find.byKey(contentKey), const Offset(0, -180));
  await tester.pumpAndSettle();

  expect(progressValues, isNotEmpty);
  expect(progressValues.last, greaterThan(0));
});
```

- [ ] **Step 4: Test normal inner scroll does not alter sheet once open**

```dart
testWidgets('uses sheet controller for inner scrolling after expansion', (tester) async {
  final progressValues = <double>[];
  await tester.pumpWidget(_TestApp(onProgressChanged: progressValues.add));

  await tester.drag(find.byKey(contentKey), const Offset(0, -300));
  await tester.pumpAndSettle();
  final progressAfterOpen = progressValues.last;

  await tester.drag(find.byKey(contentKey), const Offset(0, -240));
  await tester.pumpAndSettle();

  expect(progressValues.last, closeTo(progressAfterOpen, 0.01));
});
```

- [ ] **Step 5: Run focused tests**

Run:

```powershell
flutter test test/features/notes/presentation/widgets/pull_down_brief_panel_test.dart
```

Expected: all pull-down tests pass.

---

## Task 4: Wire Notes Screen To The Sheet Builder

**Files:**
- Modify: `lib/features/notes/presentation/notes_list_screen.dart`

- [ ] **Step 1: Replace `child:` usage with `builder:`**

```dart
PullDownBriefPanel(
  background: const DailyBriefPanel(),
  onProgressChanged: (progress) => _panelProgress.value = progress,
  builder: (context, scrollController) {
    return Cue.onChange(
      value: _viewMode,
      motion: .smooth(),
      acts: [.fadeIn()],
      child: _viewMode == _NotesViewMode.grid
          ? NotesGridView(
              key: const ValueKey('grid'),
              controller: scrollController,
              notes: visibleNotes,
              headerSlivers: headerSlivers,
              onTap: _openNote,
              onDelete: _deleteNote,
              onToggleFavorite: _toggleFavorite,
            )
          : NotesListView(
              key: const ValueKey('list'),
              controller: scrollController,
              notes: visibleNotes,
              headerSlivers: headerSlivers,
              onTap: _openNote,
              onDelete: _deleteNote,
              onToggleFavorite: _toggleFavorite,
            ),
    );
  },
)
```

- [ ] **Step 2: Keep appbar progress interpolation**

Retain the current local `ValueNotifier<double> _panelProgress` and color interpolation:

```dart
final easedProgress = Curves.easeOut.transform(progress.clamp(0, 1));
final appBarColor = Color.lerp(
  Colors.transparent,
  Colors.black,
  easedProgress,
)!;
final iconColor = Color.lerp(
  Colors.black,
  Colors.white,
  easedProgress,
)!;
```

- [ ] **Step 3: Run analyzer for touched files**

Run:

```powershell
dart analyze lib/features/notes/presentation/notes_list_screen.dart lib/features/notes/presentation/widgets/pull_down_brief_panel.dart lib/features/notes/presentation/widgets/notes_list_view.dart lib/features/notes/presentation/widgets/notes_grid_view.dart test/features/notes/presentation/widgets/pull_down_brief_panel_test.dart
```

Expected: `No issues found!`

---

## Task 5: UX Verification And Tuning

**Files:**
- Modify only if visual tuning is required:
  - `lib/features/notes/presentation/widgets/pull_down_brief_panel.dart`

- [ ] **Step 1: Run the app**

Run:

```powershell
flutter run -d windows
```

Expected: SupaNotes launches.

- [ ] **Step 2: Verify closed state**

Check:
- Daily brief area is mostly hidden behind the notes sheet.
- Notes list/grid is the draggable sheet surface.
- Top corners are rounded consistently.
- Appbar icons match the visible background.

- [ ] **Step 3: Verify dragging behavior**

Check:
- Dragging the notes sheet down reveals the daily brief.
- Dragging up expands the sheet back.
- The sheet snaps between closed and open.
- No flickering corners while scrolling notes.
- The list continues to scroll normally after the sheet reaches max size.

- [ ] **Step 4: Tune closed reveal height if needed**

If `180` feels wrong on device, adjust only this value in `PullDownBriefPanel`:

```dart
static const double _briefRevealHeight = 180;
```

Use the value in the `closedSize` calculation:

```dart
final closedSize =
    ((constraints.maxHeight - PullDownBriefPanel._briefRevealHeight) /
            constraints.maxHeight)
        .clamp(0.0, 1.0);
```

- [ ] **Step 5: Run final focused verification**

Run:

```powershell
flutter test test/features/notes/presentation/widgets/pull_down_brief_panel_test.dart
dart analyze lib/features/notes/presentation/notes_list_screen.dart lib/features/notes/presentation/widgets/pull_down_brief_panel.dart lib/features/notes/presentation/widgets/notes_list_view.dart lib/features/notes/presentation/widgets/notes_grid_view.dart test/features/notes/presentation/widgets/pull_down_brief_panel_test.dart
```

Expected:
- Pull-down tests pass.
- Analyzer reports no issues for touched files.

---

## Self-Review

- Spec coverage: uses `DraggableScrollableSheet`, makes list/grid the sheet content, preserves daily brief background, appbar color sync, rounded sheet, and snap behavior.
- Repo example corrections: removes boolean `isExpanded` as source of truth, avoids threshold mismatch, avoids raw pointer handling, and derives visual progress continuously from controller size.
- Placeholder scan: no TBD/TODO/fill-later items.
- Type consistency: `PullDownBriefPanel.builder` consistently receives `ScrollController`; list/grid both accept `ScrollController? controller`.
- Scope: only notes pull-down widget, notes screen integration, list/grid controller plumbing, and focused widget tests.
