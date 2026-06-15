# Plan 020: Clean up CustomDividerComponent metadata persistence

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 4639d85..HEAD -- lib/features/notes/presentation/widgets/custom_divider_component.dart lib/features/notes/data/markdown_serializer.dart test/features/notes/data/markdown_serializer_test.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: 018
- **Category**: tech-debt
- **Planned at**: commit `4639d85`, 2026-06-15
- **Issue**: (none)

## Why this matters

`CustomDividerComponent` renders decorative SVG dividers. The current code stores the chosen SVG index inside the node ID as `div_12_uuid`, mixing visual state with document identity. After plan 018 introduces custom divider serialization, the divider index should live in the node's metadata (`HorizontalRuleNode.metadata['dividerIndex']`) and the ID should be just an ID. This makes the component simpler, the serialization cleaner, and removes the random-ID collision risk.

## Current state

- `lib/features/notes/presentation/widgets/custom_divider_component.dart` (132 lines)
  - `CustomDividerComponentBuilder` creates view model and component.
  - `CustomDividerComponentViewModel` extends `SingleColumnLayoutComponentViewModel` with selection mixin.
  - `CustomDividerComponent.build` parses `nodeId` to extract SVG index (lines 95–107).
- `lib/features/notes/data/markdown_serializer.dart` — will contain `_DividerNodeSerializer` after plan 018.

Current excerpt (lines 95–109):

```dart
int index = 1;
if (nodeId.startsWith('div_')) {
  final parts = nodeId.split('_');
  if (parts.length >= 2) {
    index = int.tryParse(parts[1]) ?? 1;
  }
} else {
  index = (nodeId.hashCode.abs() % _dividerCount) + 1;
}
```

## Commands you will need

| Purpose   | Command | Expected on success |
|-----------|---------|---------------------|
| Analyze   | `flutter analyze lib/features/notes` | no issues |
| Tests     | `flutter test test/features/notes/data/markdown_serializer_test.dart` | all pass |
| Tests     | `flutter test test/features/notes` | all pass |
| Tests     | `flutter test` | all pass |

## Suggested executor toolkit

- Review the `_DividerNodeSerializer` written in plan 018.
- Review the default `HorizontalRuleComponent` in `super_editor/src/default_editor/horizontal_rule.dart`.

## Scope

**In scope**:
- `lib/features/notes/presentation/widgets/custom_divider_component.dart` — rewrite
- `lib/features/notes/data/markdown_serializer.dart` — ensure `_DividerNodeSerializer` writes/reads `dividerIndex` metadata

**Out of scope**:
- Changing the SVG asset set or asset naming.
- Changing how dividers are inserted from the toolbar.
- Removing the custom divider visual.

## Git workflow

- Branch: `feat/020-clean-divider-metadata`
- Commit per step; messages like `refactor(notes): store divider index in node metadata`, `refactor(notes): simplify custom divider component`.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Ensure serialization preserves divider index in metadata

Confirm that plan 018's `_DividerNodeSerializer` produces:

```markdown
--- <!-- divider:UUID|index:N -->
```

and that the deserializer stores:

```dart
HorizontalRuleNode(
  id: id,
  metadata: {'dividerIndex': index},
)
```

If plan 018 is already merged, this should already be true. If not, coordinate or implement it in the same branch.

**Verify**: `flutter test test/features/notes/data/markdown_serializer_test.dart` → divider round-trip test passes and asserts `(node as HorizontalRuleNode).getMetadataValue('dividerIndex') == N`.

### Step 2: Simplify `CustomDividerComponent`

Change the component to read the index from node metadata. The builder already has access to the `DocumentNode`, so pass the metadata value (or the whole node) through the view model.

Update `CustomDividerComponentViewModel` to include `dividerIndex`:

```dart
class CustomDividerComponentViewModel extends SingleColumnLayoutComponentViewModel with SelectionAwareViewModelMixin {
  CustomDividerComponentViewModel({
    required super.nodeId,
    super.createdAt,
    super.maxWidth,
    super.padding = EdgeInsets.zero,
    super.opacity = 1.0,
    DocumentNodeSelection? selection,
    Color selectionColor = Colors.transparent,
    this.caret,
    required this.caretColor,
    this.dividerIndex = 1,
  }) {
    super.selection = selection;
    super.selectionColor = selectionColor;
  }

  UpstreamDownstreamNodePosition? caret;
  Color caretColor;
  int dividerIndex;

  @override
  CustomDividerComponentViewModel copy() {
    return CustomDividerComponentViewModel(
      nodeId: nodeId,
      createdAt: createdAt,
      maxWidth: maxWidth,
      padding: padding,
      opacity: opacity,
      selection: selection,
      selectionColor: selectionColor,
      caret: caret,
      caretColor: caretColor,
      dividerIndex: dividerIndex,
    );
  }
}
```

Update `CustomDividerComponentBuilder.createViewModel`:

```dart
@override
SingleColumnLayoutComponentViewModel? createViewModel(Document document, DocumentNode node) {
  if (node is! HorizontalRuleNode) return null;

  return CustomDividerComponentViewModel(
    nodeId: node.id,
    createdAt: node.metadata[NodeMetadata.createdAt],
    selectionColor: const Color(0x00000000),
    caretColor: const Color(0x00000000),
    dividerIndex: node.getMetadataValue('dividerIndex') ?? 1,
  );
}
```

Update `CustomDividerComponent.build`:

```dart
@override
Widget build(BuildContext context) {
  final index = (widget.dividerIndex < 1 || widget.dividerIndex > _dividerCount)
      ? 1
      : widget.dividerIndex;
  final padIndex = index.toString().padLeft(2, '0');
  final assetPath = 'assets/dividers/divider_$padIndex.svg';

  return IgnorePointer(
    child: SelectableBox(
      selection: widget.selection,
      selectionColor: widget.selectionColor,
      child: Opacity(
        opacity: widget.opacity,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: SizedBox(
            height: 24,
            width: double.infinity,
            child: SvgPicture.asset(assetPath, fit: BoxFit.fitWidth),
          ),
        ),
      ),
    ),
  );
}
```

Delete all `nodeId.startsWith('div_')` parsing logic.

**Verify**: `flutter analyze lib/features/notes/presentation/widgets/custom_divider_component.dart` → no issues.

### Step 3: Update divider insertion to store a deterministic index

In `lib/features/notes/presentation/widgets/note_toolbar.dart`, the `_insertDivider` method currently generates:

```dart
final index = math.Random().nextInt(35) + 1;
final id = 'div_${index}_${Editor.createNodeId()}';
editor.execute([
  InsertNodeAtCaretRequest(node: HorizontalRuleNode(id: id)),
]);
```

Change it to:

```dart
final index = math.Random().nextInt(_dividerCount) + 1;
editor.execute([
  InsertNodeAtCaretRequest(
    node: HorizontalRuleNode(
      id: Editor.createNodeId(),
      metadata: {'dividerIndex': index},
    ),
  ),
]);
```

Add `_dividerCount = 35` as a constant in `note_toolbar.dart` or import it from `custom_divider_component.dart`.

**Verify**: `flutter analyze lib/features/notes/presentation/widgets/note_toolbar.dart` → no issues.

### Step 4: Add/rewrite tests

Update `markdown_serializer_test.dart` (from plan 018) to assert:

```dart
expect((node as HorizontalRuleNode).getMetadataValue('dividerIndex'), 12);
```

Add a widget test in `test/features/notes/presentation/widgets/custom_divider_component_test.dart` (create if absent):

- A divider with `dividerIndex: 7` renders the asset `assets/dividers/divider_07.svg`.
- A divider without metadata defaults to index 1.

**Verify**: `flutter test test/features/notes/data/markdown_serializer_test.dart` → all pass.
**Verify**: `flutter test test/features/notes/presentation/widgets/custom_divider_component_test.dart` → all pass.

### Step 5: Run regression suite

**Verify**:
- `flutter test test/features/notes` → all pass.
- `flutter test` → all pass.
- `flutter analyze` → no issues.

## Test plan

- Update `markdown_serializer_test.dart` divider round-trip test to assert `dividerIndex` metadata.
- Create `test/features/notes/presentation/widgets/custom_divider_component_test.dart` with two tests: explicit index and default index.
- Keep `note_toolbar_test.dart` green as regression guard for divider insertion.

## Done criteria

- [ ] `CustomDividerComponent` no longer parses `nodeId` to extract the SVG index.
- [ ] `HorizontalRuleNode` stores `dividerIndex` in metadata.
- [ ] Divider insertion in `note_toolbar.dart` writes metadata instead of encoding index in ID.
- [ ] `flutter analyze lib/features/notes` exits 0.
- [ ] `flutter test test/features/notes/data/markdown_serializer_test.dart` exits 0.
- [ ] `flutter test test/features/notes/presentation/widgets/custom_divider_component_test.dart` exits 0.
- [ ] `flutter test test/features/notes` exits 0.
- [ ] `flutter test` exits 0.
- [ ] `plans/README.md` status row for plan 020 updated to DONE.

## STOP conditions

Stop and report if:
- Plan 018 has not landed and you cannot implement the metadata-based serializer in the same branch cleanly.
- Tests rely on the old `div_INDEX_UUID` format and cannot be updated simply.
- The asset path generation breaks for indices 1–9 (padding).

## Maintenance notes

- If the number of divider SVGs changes, update `_dividerCount` in both `custom_divider_component.dart` and `note_toolbar.dart` (or extract a shared constant).
- Reviewers should confirm that existing notes with old `div_INDEX_UUID` IDs still render correctly. Plan 018's deserializer should handle both old and new formats; if it doesn't, add a fallback to parse the old ID format in `CustomDividerComponentBuilder` temporarily.
