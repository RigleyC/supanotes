# Plan 022: Refactor NoteToolbar into pure editing helpers

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 4639d85..HEAD -- lib/features/notes/presentation/widgets/note_toolbar.dart test/features/notes/presentation/widgets/note_toolbar_test.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: 021
- **Category**: tech-debt
- **Planned at**: commit `4639d85`, 2026-06-15
- **Issue**: (none)

## Why this matters

`NoteToolbar` is 431 lines and mixes UI rendering with document editing logic (block conversion, list conversion, task conversion, indentation). This makes the toolbar hard to test in isolation and easy to break when adding new node types. Extracting the editing commands into a pure helper class separates concerns: the toolbar decides what is active/enabled, and the helper decides how to mutate the document. This also fixes the currently broken "ordered list active" indicator and makes indent/unindent respect multi-node selections.

## Current state

- `lib/features/notes/presentation/widgets/note_toolbar.dart` (431 lines)
  - `NoteToolbar` — renders buttons and contains private editing methods.
  - `_ToolbarButton`, `_LabeledToolbarButton`, `_ToolbarDivider` — private UI widgets.
  - Private editing methods: `_setBlockType`, `_convertToListItem`, `_convertToTask`, `_indentListItem`, `_unindentListItem`, `_insertDivider`.
- `test/features/notes/presentation/widgets/note_toolbar_test.dart` (619 lines) — tests button active states and conversions.

Current excerpt (ordered list always inactive, line 117–122):

```dart
_ToolbarButton(
  icon: Icons.format_list_numbered,
  tooltip: 'Lista numerada',
  isActive: false,
  onPressed: () => _convertToListItem(ListItemType.ordered),
),
```

Current excerpt (indent only on single active node, lines 313–320):

```dart
void _indentListItem() {
  final nodeId = _activeNodeId(composer.selection);
  if (nodeId == null) return;
  final node = editor.context.document.getNodeById(nodeId);
  if (node is ListItemNode) {
    editor.execute([IndentListItemRequest(nodeId: nodeId)]);
  }
}
```

Repo conventions:
- Pure helpers go in `lib/features/<feature>/domain/` or `lib/core/utils/`.
- Widgets stay thin; UI state stays in widgets.

## Commands you will need

| Purpose   | Command | Expected on success |
|-----------|---------|---------------------|
| Analyze   | `flutter analyze lib/features/notes` | no issues |
| Tests     | `flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart` | all pass |
| Tests     | `flutter test test/features/notes` | all pass |
| Tests     | `flutter test` | all pass |

## Suggested executor toolkit

- Review existing `super_editor` requests: `ChangeParagraphBlockTypeRequest`, `ConvertListItemToParagraphRequest`, `ConvertParagraphToListItemRequest`, `ConvertParagraphToTaskRequest`, `ConvertTaskToParagraphRequest`, `ChangeListItemTypeRequest`, `IndentListItemRequest`, `UnIndentListItemRequest`, `ReplaceNodeRequest`, `InsertNodeAtCaretRequest`.

## Scope

**In scope**:
- `lib/features/notes/presentation/widgets/note_toolbar.dart` — refactor
- `lib/features/notes/domain/note_editor_commands.dart` — create
- `test/features/notes/presentation/widgets/note_toolbar_test.dart` — update
- `test/features/notes/domain/note_editor_commands_test.dart` — create

**Out of scope**:
- Changing `NoteEditor` or screen shells.
- Changing serializer, task component, or divider component.
- Adding new formatting buttons (e.g., code, underline, link).

## Git workflow

- Branch: `feat/022-refactor-note-toolbar`
- Commit per step; messages like `refactor(notes): extract note editor commands`, `refactor(notes): simplify NoteToolbar`, `test(notes): add editor commands unit tests`.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Extract pure editing commands

Create `lib/features/notes/domain/note_editor_commands.dart`:

```dart
import 'package:super_editor/super_editor.dart';

/// Pure document-editing helpers used by [NoteToolbar].
class NoteEditorCommands {
  const NoteEditorCommands();

  /// Returns the selected nodes, or the node at the caret if the selection is collapsed.
  static List<DocumentNode> selectedNodes(Document document, DocumentSelection? selection) {
    if (selection == null) return [];
    if (selection.isCollapsed) {
      final node = document.getNodeById(selection.extent.nodeId);
      return node != null ? [node] : [];
    }
    return document.getNodesInside(selection.start, selection.end).toList();
  }

  /// Toggles [attribution] across the current selection.
  static void toggleInlineAttribution(Editor editor, DocumentComposer composer, Attribution attribution) {
    final selection = composer.selection;
    if (selection == null) return;
    final range = selection.isCollapsed
        ? DocumentRange(start: selection.extent, end: selection.extent)
        : selection;
    editor.execute([
      ToggleTextAttributionsRequest(documentRange: range, attributions: {attribution}),
    ]);
  }

  /// Changes the block type of all selected paragraph/list/task nodes.
  static void setBlockType(Editor editor, DocumentComposer composer, Attribution? blockType) {
    final requests = <EditRequest>[];
    for (final node in selectedNodes(editor.context.document, composer.selection)) {
      if (node is ParagraphNode) {
        requests.add(ChangeParagraphBlockTypeRequest(nodeId: node.id, blockType: blockType));
      } else if (node is ListItemNode) {
        requests.add(ConvertListItemToParagraphRequest(
          nodeId: node.id,
          paragraphMetadata: {'blockType': blockType},
        ));
      } else if (node is TaskNode) {
        requests.add(ReplaceNodeRequest(
          existingNodeId: node.id,
          newNode: ParagraphNode(
            id: node.id,
            text: node.text,
            metadata: blockType != null ? {'blockType': blockType} : <String, dynamic>{},
          ),
        ));
      }
    }
    if (requests.isNotEmpty) editor.execute(requests);
  }

  /// Converts selected nodes to the given list item type, or toggles off if already that type.
  static void convertToListItem(Editor editor, DocumentComposer composer, ListItemType type) {
    final requests = <EditRequest>[];
    for (final node in selectedNodes(editor.context.document, composer.selection)) {
      if (node is ListItemNode) {
        if (node.type != type) {
          requests.add(ChangeListItemTypeRequest(nodeId: node.id, newType: type));
        }
      } else if (node is TaskNode) {
        requests.add(ReplaceNodeRequest(
          existingNodeId: node.id,
          newNode: ListItemNode(id: node.id, itemType: type, text: node.text, indent: node.indent),
        ));
      } else if (node is ParagraphNode) {
        requests.add(ConvertParagraphToListItemRequest(nodeId: node.id, type: type));
      }
    }
    if (requests.isNotEmpty) editor.execute(requests);
  }

  /// Converts selected nodes to/from tasks.
  static void convertToTask(Editor editor, DocumentComposer composer) {
    final requests = <EditRequest>[];
    for (final node in selectedNodes(editor.context.document, composer.selection)) {
      if (node is ParagraphNode) {
        requests.add(ConvertParagraphToTaskRequest(nodeId: node.id));
      } else if (node is ListItemNode) {
        requests.add(ConvertListItemToParagraphRequest(nodeId: node.id));
        requests.add(ConvertParagraphToTaskRequest(nodeId: node.id));
      } else if (node is TaskNode) {
        requests.add(ConvertTaskToParagraphRequest(nodeId: node.id));
      }
    }
    if (requests.isNotEmpty) editor.execute(requests);
  }

  /// Indents all selected list items.
  static void indentListItems(Editor editor, DocumentComposer composer) {
    for (final node in selectedNodes(editor.context.document, composer.selection)) {
      if (node is ListItemNode) {
        editor.execute([IndentListItemRequest(nodeId: node.id)]);
      }
    }
  }

  /// Unindents all selected list items.
  static void unindentListItems(Editor editor, DocumentComposer composer) {
    for (final node in selectedNodes(editor.context.document, composer.selection)) {
      if (node is ListItemNode) {
        editor.execute([UnIndentListItemRequest(nodeId: node.id)]);
      }
    }
  }

  /// Inserts a horizontal rule at the caret.
  static void insertDivider(Editor editor, {required int dividerCount}) {
    final index = math.Random().nextInt(dividerCount) + 1;
    editor.execute([
      InsertNodeAtCaretRequest(
        node: HorizontalRuleNode(
          id: Editor.createNodeId(),
          metadata: {'dividerIndex': index},
        ),
      ),
    ]);
  }
}
```

**Verify**: `flutter analyze lib/features/notes/domain/note_editor_commands.dart` → no issues.

### Step 2: Rewrite `NoteToolbar` to use the helper

Replace the private editing methods in `NoteToolbar` with calls to `NoteEditorCommands`:

```dart
void _toggleInline(Attribution attribution) =>
    NoteEditorCommands.toggleInlineAttribution(editor, composer, attribution);

void _setBlockType(Attribution? blockType) =>
    NoteEditorCommands.setBlockType(editor, composer, blockType);

void _convertToListItem(ListItemType type) =>
    NoteEditorCommands.convertToListItem(editor, composer, type);

void _convertToTask() => NoteEditorCommands.convertToTask(editor, composer);

void _indentListItem() => NoteEditorCommands.indentListItems(editor, composer);

void _unindentListItem() => NoteEditorCommands.unindentListItems(editor, composer);

void _insertDivider() => NoteEditorCommands.insertDivider(editor, dividerCount: _dividerCount);
```

Keep the UI widgets (`_ToolbarButton`, `_LabeledToolbarButton`, `_ToolbarDivider`) in the same file; they are small and private.

**Verify**: `flutter analyze lib/features/notes/presentation/widgets/note_toolbar.dart` → no issues.

### Step 3: Fix ordered list active state

Update the ordered list button:

```dart
_ToolbarButton(
  icon: Icons.format_list_numbered,
  tooltip: 'Lista numerada',
  isActive: blockType == listItemAttribution && _selectedListType == ListItemType.ordered,
  onPressed: () => _convertToListItem(ListItemType.ordered),
)
```

Add a helper:

```dart
ListItemType? _selectedListType(DocumentSelection? selection) {
  if (selection == null) return null;
  for (final node in selectedNodes(editor.context.document, selection)) {
    if (node is ListItemNode) return node.type;
  }
  return null;
}
```

Update `isListItem` and the bullet list button to use `_selectedListType`:

```dart
final selectedListType = _selectedListType(selection);
final isListItem = selectedListType != null;

_ToolbarButton(
  icon: Icons.format_list_bulleted,
  tooltip: 'Lista',
  isActive: selectedListType == ListItemType.unordered,
  onPressed: () => _convertToListItem(ListItemType.unordered),
),
_ToolbarButton(
  icon: Icons.format_list_numbered,
  tooltip: 'Lista numerada',
  isActive: selectedListType == ListItemType.ordered,
  onPressed: () => _convertToListItem(ListItemType.ordered),
),
```

**Verify**: `flutter analyze lib/features/notes/presentation/widgets/note_toolbar.dart` → no issues.

### Step 4: Add unit tests for `NoteEditorCommands`

Create `test/features/notes/domain/note_editor_commands_test.dart`:

- `setBlockType` converts paragraph to H1/H2/H3/blockquote.
- `setBlockType` converts list item to paragraph with block type.
- `setBlockType` converts task to paragraph with block type.
- `convertToListItem` converts paragraph/task to unordered/ordered list.
- `convertToTask` converts paragraph/list to task and back.
- `indentListItems` indents multiple selected list items.
- `unindentListItems` unindents multiple selected list items.

Use `MutableDocument`, `MutableDocumentComposer`, and `createDefaultDocumentEditor` as in `note_toolbar_test.dart`.

**Verify**: `flutter test test/features/notes/domain/note_editor_commands_test.dart` → all pass.

### Step 5: Update widget tests

Update `test/features/notes/presentation/widgets/note_toolbar_test.dart`:

- Keep all existing conversion tests; they should still pass because the public behavior is unchanged.
- Add tests for ordered list active state.
- Add tests for multi-node indent/unindent (new behavior).

**Verify**: `flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart` → all pass.

### Step 6: Run regression suite

**Verify**:
- `flutter test test/features/notes/domain/note_editor_commands_test.dart` → all pass.
- `flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart` → all pass.
- `flutter test test/features/notes` → all pass.
- `flutter test` → all pass.
- `flutter analyze` → no issues.

## Test plan

- Create `test/features/notes/domain/note_editor_commands_test.dart` with unit tests for all command methods.
- Update `note_toolbar_test.dart` with active-state and multi-selection tests.
- Keep `custom_task_component_test.dart` and `note_editor_screen_test.dart` green as regression guards.

## Done criteria

- [ ] `lib/features/notes/domain/note_editor_commands.dart` exists and contains all editing helpers.
- [ ] `NoteToolbar` no longer contains private editing command methods.
- [ ] Ordered list button reflects active state correctly.
- [ ] Indent/unindent respect multi-node selection.
- [ ] `flutter analyze lib/features/notes` exits 0.
- [ ] `flutter test test/features/notes/domain/note_editor_commands_test.dart` exits 0.
- [ ] `flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart` exits 0.
- [ ] `flutter test test/features/notes` exits 0.
- [ ] `flutter test` exits 0.
- [ ] `plans/README.md` status row for plan 022 updated to DONE.

## STOP conditions

Stop and report if:
- Any existing `note_toolbar_test` fails because the helper changed the order or count of `EditRequest`s.
- The ordered list active state cannot be determined reliably from the current selection.
- Multi-node indent/unindent produces invalid document structure or crashes.

## Maintenance notes

- New toolbar commands should be added to `NoteEditorCommands` and unit-tested before being wired to a button.
- Reviewers should verify that the toolbar buttons visually match the previous active states and that the ordered list button now highlights correctly.
