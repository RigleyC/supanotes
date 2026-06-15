# Plan 018: Replace custom Markdown serializer with super_editor

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 4639d85..HEAD -- lib/features/notes/data/markdown_serializer.dart lib/features/notes/presentation/controllers/note_editor_controller.dart lib/features/notes/data/notes_repository.dart test/features/notes/data/markdown_serializer_test.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `4639d85`, 2026-06-15
- **Issue**: (none)

## Why this matters

`lib/features/notes/data/markdown_serializer.dart` reimplements a full Markdown parser/serializer (437 lines) that already exists inside the pinned `super_editor` dependency. The custom implementation supports only a subset of Markdown, has edge-case bugs (trims every line, no link/code/image/table support, fragile italic detection), and requires ongoing maintenance every time the editor gains a new node type. Switching to `super_editor`'s built-in `deserializeMarkdownToDocument` / `serializeDocumentToMarkdown` removes ~400 lines of fragile code, immediately adds support for links, inline code, images, tables, and nested lists, and lets the project benefit from upstream fixes. The only behavior that must be preserved is the round-trip of stable task IDs and divider SVG indices through Markdown storage.

## Current state

- `lib/features/notes/data/markdown_serializer.dart` — hand-rolled parser/serializer. Exports `parseMarkdownToDocument(String)` and `serializeDocumentToMarkdown(MutableDocument)`.
- `lib/features/notes/presentation/controllers/note_editor_controller.dart:29` — imports `markdown_serializer.dart` and calls both functions.
- `test/features/notes/data/markdown_serializer_test.dart` — 298 lines of tests for the custom serializer.
- `super_editor` (pinned git ref `a26abb380be1a1d0e747fd5d1043190fdb93de14`) already exports:
  - `deserializeMarkdownToDocument(String markdown, {MarkdownSyntax syntax = MarkdownSyntax.superEditor, ...})`
  - `serializeDocumentToMarkdown(Document doc, {MarkdownSyntax syntax = MarkdownSyntax.superEditor, List<DocumentNodeMarkdownSerializer> customNodeSerializers = const []})`
  - `DocumentNodeMarkdownSerializer`, `NodeTypedDocumentNodeMarkdownSerializer<T>`
  - `ElementToNodeConverter` for custom block parsing during deserialization.

Repo conventions observed:
- File naming: `snake_case.dart`.
- Riverpod providers declared manually (no codegen).
- Error handling: propagate via `AsyncValue.error`, do not swallow errors.

## Commands you will need

| Purpose   | Command | Expected on success |
|-----------|---------|---------------------|
| Analyze   | `flutter analyze lib/features/notes` | no issues |
| Tests     | `flutter test test/features/notes/data/markdown_serializer_test.dart` | all pass after rewrite |
| Tests     | `flutter test test/features/notes` | all pass |
| Tests     | `flutter test` | all pass |

## Suggested executor toolkit

- Read `super_editor` source at the pinned ref:
  - `super_editor/lib/src/infrastructure/serialization/markdown/document_to_markdown_serializer.dart`
  - `super_editor/lib/src/infrastructure/serialization/markdown/markdown_to_document_parsing.dart`
  - `super_editor/lib/src/infrastructure/serialization/markdown/super_editor_syntax.dart`
- Use the existing `custom_task_component_test.dart` and `note_toolbar_test.dart` as regression guards for task/divider behavior.

## Scope

**In scope**:
- `lib/features/notes/data/markdown_serializer.dart` — rewrite or delete
- `test/features/notes/data/markdown_serializer_test.dart` — rewrite
- `lib/features/notes/presentation/controllers/note_editor_controller.dart` — update imports/calls
- `lib/features/notes/presentation/widgets/custom_divider_component.dart` — adjust metadata read
- `lib/features/notes/presentation/widgets/custom_task_component.dart` — adjust if it reads task ID from text

**Out of scope**:
- Any change to `NoteToolbar`, `NoteEditorScreen`, `InboxScreen` logic beyond import updates.
- Adding new Markdown features (links, images, tables) beyond what comes for free with `super_editor`.
- Backend serialization for sync payloads; that uses the same Markdown string, so no changes needed.

## Git workflow

- Branch: `feat/018-replace-markdown-serializer`
- Commit per step; use Conventional Commits: `refactor(notes): ...`, `test(notes): ...`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Verify the built-in serializer already covers the existing test matrix

Create a temporary scratch file (do not commit it) and assert that `deserializeMarkdownToDocument` and `serializeDocumentToMarkdown` round-trip the existing test cases.

Cases to verify:
- Empty input yields a document with one empty `ParagraphNode`.
- Plain paragraph.
- `# H1`, `## H2`, `### H3`.
- `> quote`.
- `- item` unordered list.
- `1. item` ordered list.
- `- [ ] task` and `- [x] task`.
- `**bold**`, `*italic*`, `~strikethrough~`.
- Multiple paragraphs separated by blank lines.
- Horizontal rule `---`.

**Verify**: `flutter test test/features/notes/data/markdown_serializer_test.dart` → currently passes (baseline). You may temporarily add a `test/scratch_serializer_test.dart` and delete it after this step.

### Step 2: Implement custom serializers for task and divider identity

Task IDs and divider SVG indices must survive `Document → Markdown → Document`. Encode them as HTML comments in Markdown, exactly as the current code does, but use `super_editor`'s extension points instead of a hand-rolled loop.

Create or update `lib/features/notes/data/markdown_serializer.dart` to contain only:

```dart
import 'package:super_editor/super_editor.dart';

/// Parses [markdown] into a [MutableDocument] using the super_editor parser,
/// while preserving custom SupaNotes metadata (task IDs, divider indices).
MutableDocument parseMarkdownToDocument(String markdown) {
  return deserializeMarkdownToDocument(
    markdown,
    customElementToNodeConverters: [
      _TaskElementConverter(),
      _DividerElementConverter(),
    ],
  );
}

/// Serializes [doc] to Markdown using the super_editor serializer,
/// while preserving custom SupaNotes metadata (task IDs, divider indices).
String serializeDocumentToMarkdown(MutableDocument doc) {
  return serializeDocumentToMarkdown(
    doc,
    customNodeSerializers: [
      _TaskNodeSerializer(),
      _DividerNodeSerializer(),
    ],
  );
}
```

Wait — `serializeDocumentToMarkdown` is the name of the function being defined. The `super_editor` function with the same name is exported. In the current code the file hides it (`hide serializeDocumentToMarkdown`). After this change, stop hiding it and call it explicitly, or rename the wrapper to `serializeNoteToMarkdown` / `parseNoteToMarkdown` to avoid the collision. **Recommended**: rename the public API to `parseNoteToMarkdown` and `serializeNoteToMarkdown` and update the single caller in `note_editor_controller.dart`. This removes the confusing `hide` import.

Implement `_TaskNodeSerializer`:

```dart
class _TaskNodeSerializer extends NodeTypedDocumentNodeMarkdownSerializer<TaskNode> {
  @override
  String doSerialization(Document document, TaskNode node, {NodeSelection? selection}) {
    final textToConvert = selection is TextNodeSelection && !selection.isCollapsed
        ? node.text.copyText(selection.start, selection.end)
        : node.text;
    return '- [${node.isComplete ? 'x' : ' '}] ${textToConvert.toMarkdown()} <!-- task:${node.id} -->';
  }
}
```

Implement `_DividerNodeSerializer`:

```dart
class _DividerNodeSerializer extends NodeTypedDocumentNodeMarkdownSerializer<HorizontalRuleNode> {
  @override
  String doSerialization(Document document, HorizontalRuleNode node, {NodeSelection? selection}) {
    final index = node.getMetadataValue('dividerIndex') ?? 1;
    return '--- <!-- divider:${node.id}|index:$index -->';
  }
}
```

Implement `_TaskElementConverter`:

```dart
class _TaskElementConverter implements ElementToNodeConverter {
  static final _taskIdPattern = RegExp(r'<!--\s*task:(.*?)\s*-->');

  @override
  DocumentNode? handleElement(md.Element element) {
    if (element.attributes['class'] != 'task-list-item') return null;

    final input = element.children?.firstWhereOrNull(
      (c) => c is md.Element && c.tag == 'input',
    ) as md.Element?;
    final isComplete = input?.attributes['checked'] == 'true';

    final rawText = element.textContent;
    final idMatch = _taskIdPattern.firstMatch(rawText);
    final id = idMatch?.group(1)?.trim() ?? Editor.createNodeId();
    final text = rawText.replaceFirst(_taskIdPattern, '').trim();

    return TaskNode(
      id: id,
      text: parseInlineMarkdown(text),
      isComplete: isComplete,
    );
  }
}
```

Wait: `super_editor`'s default deserialization already creates `TaskNode`s from `class="task-list-item"` via `UnorderedListWithCheckboxSyntax`. A custom `ElementToNodeConverter` runs **first** in the visitor and can intercept the element. If you return a node, the visitor stops processing that element. So the converter above should work.

Implement `_DividerElementConverter`:

```dart
class _DividerElementConverter implements ElementToNodeConverter {
  static final _dividerPattern = RegExp(r'<!--\s*divider:(.*?)\s*-->');
  static final _indexPattern = RegExp(r'\|index:(\d+)');

  @override
  DocumentNode? handleElement(md.Element element) {
    if (element.tag != 'hr') return null;

    final previous = // need access to previous markdown line; not available here
    ...
  }
}
```

STOP: `ElementToNodeConverter` only receives the `md.Element`. The `<hr>` element produced by the Markdown parser does **not** contain the trailing HTML comment. The comment is parsed as a separate text node after the `<hr>`. Therefore an `ElementToNodeConverter` alone cannot capture the comment.

Instead, use a **custom block syntax** that matches `--- <!-- divider:... -->` as a single block and produces an `md.Element` containing the id/index as attributes. Example:

```dart
class _DividerWithMetadataSyntax extends md.BlockSyntax {
  static final _pattern = RegExp(r'^---\s+<!--\s*divider:(.*?)\s*-->$');

  @override
  RegExp get pattern => _pattern;

  @override
  bool canEndBlock(md.BlockParser parser) => true;

  @override
  md.Node? parse(md.BlockParser parser) {
    final match = _pattern.firstMatch(parser.current.content);
    parser.advance();

    final raw = match!.group(1)!;
    final id = raw.split('|').first;
    final indexMatch = RegExp(r'index:(\d+)').firstMatch(raw);
    final index = indexMatch != null ? int.parse(indexMatch.group(1)!) : 1;

    return md.Element('hr-divider', [])
      ..attributes['id'] = id
      ..attributes['index'] = '$index';
  }
}
```

Then an `ElementToNodeConverter` for `hr-divider` creates `HorizontalRuleNode(id: id, metadata: {'dividerIndex': index})`.

Also keep the standard `md.HorizontalRuleSyntax` so plain `---` still works; it will create a `HorizontalRuleNode` with a generated id and default divider index.

**Update `parseNoteToMarkdown`**:

```dart
MutableDocument parseNoteToMarkdown(String markdown) {
  return deserializeMarkdownToDocument(
    markdown,
    customBlockSyntax: [
      _DividerWithMetadataSyntax(),
    ],
    customElementToNodeConverters: [
      _TaskElementConverter(),
      _DividerElementConverter(),
    ],
  );
}
```

**Verify**: `flutter analyze lib/features/notes` → no issues.

### Step 3: Update callers and remove the `hide` import

In `lib/features/notes/presentation/controllers/note_editor_controller.dart`:

- Change the import `package:super_editor/super_editor.dart hide serializeDocumentToMarkdown;` to `package:super_editor/super_editor.dart;`.
- Replace `parseMarkdownToDocument(content)` with `parseNoteToMarkdown(content)`.
- Replace `serializeDocumentToMarkdown(doc)` with `serializeNoteToMarkdown(doc)`.

**Verify**: `flutter analyze lib/features/notes` → no issues.

### Step 4: Update divider component to read metadata instead of parsing the node ID

In `lib/features/notes/presentation/widgets/custom_divider_component.dart`:

Replace the `nodeId` parsing block (lines 95–107) with:

```dart
int index = node.getMetadataValue('dividerIndex') ?? 1;
if (index < 1 || index > _dividerCount) {
  index = ((node.id.hashCode.abs() % _dividerCount) + 1);
}
```

If the builder receives only `nodeId`, pass the full node metadata through the view model or change the builder to read from the `DocumentNode` directly.

**Verify**: `flutter analyze lib/features/notes` → no issues.

### Step 5: Rewrite tests for the new serializer

Replace `test/features/notes/data/markdown_serializer_test.dart` with tests that exercise the public wrapper functions `parseNoteToMarkdown` / `serializeNoteToMarkdown`.

Required test cases (adapt from the existing file):
- Empty input → single empty paragraph.
- Plain paragraph round-trips.
- H1/H2/H3 parse with correct `blockType` and round-trip.
- Blockquote round-trips.
- Unordered and ordered list items parse as `ListItemNode`.
- Open and completed tasks parse as `TaskNode` with correct `isComplete`.
- Task ID comment is preserved through parse → serialize.
- Divider with metadata comment preserves id and `dividerIndex`.
- Plain `---` creates `HorizontalRuleNode`.
- Inline bold, italic, strikethrough round-trip.
- Math expression `2*3=6` does not become italic (should pass automatically with `super_editor`).
- Escaped asterisk `a \* b` becomes literal `a * b`.
- Multiple paragraphs separated by blank lines round-trip.

Add at least one new test proving the gain:
- A Markdown link `[text](url)` survives parse and serialize.

**Verify**: `flutter test test/features/notes/data/markdown_serializer_test.dart` → all pass.

### Step 6: Delete the old serializer body and keep only the wrapper

After tests pass, remove any leftover helper functions from `markdown_serializer.dart` so the file contains only the public API, the custom serializers, converters, and block syntax.

**Verify**: `flutter analyze lib/features/notes` → no issues.

### Step 7: Run full regression suite

**Verify**:
- `flutter test test/features/notes` → all pass.
- `flutter test` → all pass.
- `flutter analyze` → no issues.

## Test plan

- Rewrite `test/features/notes/data/markdown_serializer_test.dart` with the cases listed in Step 5.
- Add one new test proving Markdown link round-trip.
- Keep `custom_task_component_test.dart` and `note_toolbar_test.dart` green as regression guards.
- If any existing test in `note_editor_screen_test.dart` fails because of title/content formatting differences, fix the expectation — do not revert to the old serializer.

## Done criteria

- [ ] `lib/features/notes/data/markdown_serializer.dart` is reduced to the public wrapper + custom task/divider serializers/converters.
- [ ] `note_editor_controller.dart` calls `parseNoteToMarkdown` / `serializeNoteToMarkdown`.
- [ ] `flutter analyze lib/features/notes` exits 0.
- [ ] `flutter test test/features/notes/data/markdown_serializer_test.dart` exits 0 with all rewritten tests passing.
- [ ] `flutter test test/features/notes` exits 0.
- [ ] `flutter test` exits 0.
- [ ] `plans/README.md` status row for plan 018 updated to DONE.

## STOP conditions

Stop and report if:
- The `super_editor` pinned ref does not export `deserializeMarkdownToDocument`, `serializeDocumentToMarkdown`, `DocumentNodeMarkdownSerializer`, `NodeTypedDocumentNodeMarkdownSerializer`, `ElementToNodeConverter`, or `MarkdownSyntax`.
- A custom block syntax for `--- <!-- divider:... -->` cannot intercept the line before the default `HorizontalRuleSyntax` consumes it.
- The built-in serializer produces output that breaks task/divider ID round-trip even after custom serializers/converters are added.
- Any test outside `markdown_serializer_test.dart` fails in a way that requires changing screen logic — that is out of scope for this plan.

## Maintenance notes

- After this plan, new Markdown features come mostly for free from `super_editor`. If the project ever upgrades `super_editor`, re-run the serializer tests first.
- The HTML comment format `<!-- task:ID -->` and `<!-- divider:ID|index:N -->` is now the canonical on-disk format; do not change it without a migration.
- Reviewers should verify that the custom task/divider serializers run **before** the default ones (they are prepended to the list) and that the custom block syntax is registered.
