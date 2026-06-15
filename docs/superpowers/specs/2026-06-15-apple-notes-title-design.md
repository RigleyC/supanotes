# Design Spec: Apple Notes Style Note Title

Define note titles in SupaNotes similar to Apple Notes: the first line/block of the document is styled as H1 (Header 1) and locked as such. The note title shown in the list is extracted from this first H1 block.

## Requirements

1. **Automatic H1 on first line**: 
   - A new empty note must start with its first block styled as H1 (`header1` block type in `super_editor`).
   - Pressing `Enter` on the first line (the H1 block) will create a new paragraph below it styled as normal body text (standard paragraph).
2. **First line locked as H1**:
   - The first block of the document cannot have its block type changed (e.g. to a list item, task/checklist, or H2/H3).
   - If the first block is deleted or changed, the editor will immediately coerce it back to a `header1` paragraph.
3. **Disabled Toolbar**:
   - The formatting toolbar (`NoteToolbar`) will be completely disabled (all buttons inactive) whenever the selection/caret is on the first line.
4. **Title Extraction**:
   - The note's title is extracted from the first block's text.
   - The note's excerpt is extracted from the rest of the text, excluding the title line (this is already supported by the repository's excerpt logic).

## Proposed Changes

### [MODIFY] [note_editor_controller.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/controllers/note_editor_controller.dart)

- Coerce the first node of the document to be a `ParagraphNode` with `blockType` equal to `header1Attribution`.
- Add an `_ensureFirstNodeIsHeader1()` helper called during `init()` and on every document change (`_onDocumentChanged`).
- If the first node is not a `ParagraphNode` or doesn't have `blockType: header1Attribution`, we change it.

### [MODIFY] [note_editor.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/note_editor.dart)

- Clean up old static title-prepending logic in `initState` which is no longer needed since coercion handles H1 conversion and loading.
- Ensure that if content is parsed, the first node is coerced to H1.

### [MODIFY] [note_toolbar.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/note_toolbar.dart)

- Check if the current selection includes the first node of the document.
- Disable the entire toolbar when the cursor is on the first line.

---

## Verification Plan

### Automated Tests
- We will verify that existing unit/widget tests continue to pass and run them locally.

### Manual Verification
- Create a new note: verify it starts with a large H1-styled header.
- Type a title and press `Enter`: verify the next block is normal size body text.
- Try to change the block type of the title line (using toolbar or keyboard/markdown shortcuts): verify it remains H1 and the toolbar is disabled when cursor is on the first line.
- Select all and delete: verify the editor resets to a single empty H1 line.
- Exit note and check list: verify the note's title is the text of the first line, and the description (excerpt) starts from the second line text.
