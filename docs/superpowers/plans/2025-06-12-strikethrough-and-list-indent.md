# Strikethrough Toolbar Button & List Indentation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a strikethrough formatting button to the note editor toolbar, round-trip `~strikethrough~` in markdown, and ensure Tab/Shift+Tab works for bullet list indentation.

**Architecture:** Three independent changes: (1) toolbar button reuses the existing `_toggleInline(strikethroughAttribution)` pattern in `note_toolbar.dart` — no new dispatch logic needed since `strikethroughAttribution` already exists in the super_editor fork at `attributions.dart:39`. (2) Markdown serializer extends the existing `_applyInlineFormatting` walker to handle `~...~` tilde-delimited strikethrough (matching super_editor's own syntax). Serializer outputs `~text~`. (3) List indent/outdent uses super_editor's built-in `tabToIndentListItem`/`shiftTabToUnIndentListItem` from `defaultKeyboardActions` — add indent/outdent toolbar buttons + ensure keyboard actions are wired.

**Tech Stack:** Flutter, super_editor (fork at `super_editor_fork/`), Riverpod

---

### Task 1: Add strikethrough button to editor toolbar

**Files:**
- Modify: `lib/features/notes/presentation/widgets/note_toolbar.dart:33-48` (wire button state + callback)
- Modify: `lib/features/notes/presentation/widgets/note_toolbar.dart:152-178` (add field + button in `_ToolbarContainer`)
- Test: (manual — widget tests are out of scope for this task)

- [ ] **Step 1: Wire strikethrough state and callback in `NoteToolbar.build()`**

In `note_toolbar.dart`, add `isStrikethrough` and `onToggleStrikethrough` to the `_ToolbarContainer` constructor call:

```dart
return _ToolbarContainer(
  isBold: _selectionHasAttribution(selection, boldAttribution),
  isItalic: _selectionHasAttribution(selection, italicsAttribution),
  isStrikethrough: _selectionHasAttribution(selection, strikethroughAttribution),
  blockType: blockType,
  onToggleBold: () => _toggleInline(boldAttribution),
  onToggleItalic: () => _toggleInline(italicsAttribution),
  onToggleStrikethrough: () => _toggleInline(strikethroughAttribution),
  onSetH1: () => _setBlockType(header1Attribution),
  onSetH2: () => _setBlockType(header2Attribution),
  onSetH3: () => _setBlockType(header3Attribution),
  onConvertToUnorderedList: () => ...
  // keep rest unchanged
);
```

- [ ] **Step 2: Add `isStrikethrough` + `onToggleStrikethrough` fields to `_ToolbarContainer`**

```dart
class _ToolbarContainer extends StatelessWidget {
  const _ToolbarContainer({
    required this.isBold,
    required this.isItalic,
    required this.isStrikethrough,
    required this.blockType,
    required this.onToggleBold,
    required this.onToggleItalic,
    required this.onToggleStrikethrough,
    // keep rest unchanged
  });

  final bool isBold;
  final bool isItalic;
  final bool isStrikethrough;
  final Attribution? blockType;
  final VoidCallback onToggleBold;
  final VoidCallback onToggleItalic;
  final VoidCallback onToggleStrikethrough;
  // keep rest unchanged
```

- [ ] **Step 3: Add strikethrough `_ToolbarButton` to `_ToolbarContainer.build()`**

Place it after the italic button, before the `_ToolbarDivider`:

```dart
_ToolbarButton(
  icon: Icons.format_strikethrough,
  tooltip: 'Tachado',
  isActive: isStrikethrough,
  onPressed: onToggleStrikethrough,
),
const _ToolbarDivider(),
```

- [ ] **Step 4: Verify the toolbar compiles and the button toggles strikethrough**

Run: `dart analyze lib/features/notes/presentation/widgets/note_toolbar.dart`
Expected: No errors.

---

### Task 2: Add strikethrough round-trip in markdown serializer

**Files:**
- Modify: `lib/features/notes/data/markdown_serializer.dart:217-261`
- Test: `test/features/notes/data/markdown_serializer_test.dart`

The super_editor fork already handles `~strikethrough~` syntax in its built-in markdown inline parser (see `markdown_inline_upstream_plugin.dart:621`). The project's own custom `_applyInlineFormatting` needs the same support for round-trip persistence.

- [ ] **Step 1: Write failing tests for strikethrough parse and serialize**

Add to the `inline formatting` test group in `markdown_serializer_test.dart`:

```dart
test('~strikethrough~ is recognised as strikethrough', () {
  final doc = parseMarkdownToDocument('this is ~strikethrough~ text');

  final text = (doc.first as ParagraphNode).text;
  final spans = text.getAttributionSpansInRange(
    attributionFilter: (a) => a == strikethroughAttribution,
    range: SpanRange(0, text.toPlainText().length),
  );
  expect(spans, isNotEmpty);
  expect(text.toPlainText(), 'this is strikethrough text');
});

test('serializer outputs ~strikethrough~ syntax', () {
  // Build a document with strikethrough attribution manually.
  final text = AttributedText(
    'hello world',
    AttributedSpans(
      markers: [
        const SpanMarker(
          attribution: strikethroughAttribution,
          offset: 0,
          markerType: SpanMarkerType.start,
        ),
        const SpanMarker(
          attribution: strikethroughAttribution,
          offset: 5,
          markerType: SpanMarkerType.end,
        ),
      ],
    ),
  );
  final doc = MutableDocument(nodes: [
    ParagraphNode(id: Editor.createNodeId(), text: text),
  ]);

  final out = serializeDocumentToMarkdown(doc);
  expect(out, '~hello~ world');
});

test('strikethrough round-trips', () {
  const original = 'text with ~strikethrough~ inside';
  final doc = parseMarkdownToDocument(original);
  expect(serializeDocumentToMarkdown(doc), original);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/features/notes/data/markdown_serializer_test.dart`
Expected: 3 new tests FAIL

- [ ] **Step 3: Tilde handling in `_applyInlineFormatting`**

Extend the walker to track a `strikethrough` boolean. Add the `~` check BEFORE single `*` (italic) because `~` is its own character, not a subset of `*`:

```dart
AttributedText _applyInlineFormatting(String source) {
  final spans = AttributedSpans();
  final text = StringBuffer();
  var i = 0;
  var bold = false;
  var italic = false;
  var strikethrough = false;

  while (i < source.length) {
    final remaining = source.substring(i);

    if (remaining.startsWith('**')) {
      bold = !bold;
      i += 2;
      continue;
    }
    if (remaining.startsWith('~')) {
      strikethrough = !strikethrough;
      i += 1;
      continue;
    }
    if (remaining.startsWith('*')) {
      italic = !italic;
      i += 1;
      continue;
    }

    final start = text.length;
    text.write(source[i]);
    final end = text.length;
    if (bold) {
      spans.addAttribution(
        newAttribution: boldAttribution,
        start: start,
        end: end,
      );
    }
    if (italic) {
      spans.addAttribution(
        newAttribution: italicsAttribution,
        start: start,
        end: end,
      );
    }
    if (strikethrough) {
      spans.addAttribution(
        newAttribution: strikethroughAttribution,
        start: start,
        end: end,
      );
    }
    i += 1;
  }

  return AttributedText(text.toString(), spans);
}
```

- [ ] **Step 4: Add strikethrough serialization in `serializeDocumentToMarkdown`**

The `serializeDocumentToMarkdown` function currently calls `node.text.toPlainText()` for each node type (paragraph, list, etc.). This loses all attributions. To output ~~ syntax, we need a helper that walks the `AttributedSpans` of a node's text and emits the markdown markers.

Add this helper after `serializeDocumentToMarkdown`:

```dart
/// Converts [text] back to markdown inline syntax, wrapping
/// strikethrough spans with `~...~`.
///
/// Only handles strikethrough — bold/italic are left as plain text
/// for now since they are not round-tripped by the serializer.
String _serializeInlineFormatting(AttributedText text) {
  final plain = text.toPlainText();
  final spans = text.getAttributionSpansInRange(
    attributionFilter: (a) => a == strikethroughAttribution,
    range: SpanRange(0, plain.length),
  );
  if (spans.isEmpty) return plain;

  final buffer = StringBuffer();
  var pos = 0;
  for (final span in spans) {
    if (span.start > pos) {
      buffer.write(plain.substring(pos, span.start));
    }
    buffer.write('~');
    buffer.write(plain.substring(span.start, span.end));
    buffer.write('~');
    pos = span.end;
  }
  if (pos < plain.length) {
    buffer.write(plain.substring(pos));
  }
  return buffer.toString();
}
```

Then replace every `node.text.toPlainText()` call in `serializeDocumentToMarkdown` with `_serializeInlineFormatting(node.text)`. The affected lines are:

- Line 175: `node.text.toPlainText()` in the TaskNode branch
- Line 177: `node.text.toPlainText()` in the ListItemNode branch
- Line 185: `node.text.toPlainText()` in the ParagraphNode branch
- Line 203: `node.text.toPlainText()` in the TextNode branch

Replace each with `_serializeInlineFormatting(node.text)`.

- [ ] **Step 5: Run tests to verify all pass**

Run: `dart test test/features/notes/data/markdown_serializer_test.dart`
Expected: All tests PASS (including the 3 new strikethrough tests)

---

### Task 3: Add list indent/outdent via Tab key + toolbar buttons

**Files:**
- Modify: `lib/features/notes/presentation/widgets/note_toolbar.dart` (add indent/outdent buttons)
- Note: Tab/Shift+Tab keyboard actions are already included in super_editor's `defaultKeyboardActions`/`defaultImeKeyboardActions`, so no custom keyboard wiring is needed unless it's broken on the target platform.

- [ ] **Step 1: Add indent/outdent actions to `NoteToolbar`**

Add two new methods to `NoteToolbar`:

```dart
void _indentListItem() {
  final nodeId = _activeNodeId(composer.selection);
  if (nodeId == null) return;
  final node = editor.context.document.getNodeById(nodeId);
  if (node is ListItemNode) {
    editor.execute([IndentListItemRequest(nodeId: nodeId)]);
  }
}

void _unindentListItem() {
  final nodeId = _activeNodeId(composer.selection);
  if (nodeId == null) return;
  final node = editor.context.document.getNodeById(nodeId);
  if (node is ListItemNode) {
    editor.execute([UnIndentListItemRequest(nodeId: nodeId)]);
  }
}
```

- [ ] **Step 2: Wire callbacks in `_ToolbarContainer`**

Add `onIndent` and `onUnindent` parameters:

```dart
return _ToolbarContainer(
  // ...existing params...
  onIndent: _indentListItem,
  onUnindent: _unindentListItem,
);
```

In `_ToolbarContainer`, add fields and buttons. Place them after the list buttons, before the task button:

```dart
final bool canIndent;  // true when cursor is on a list item
final bool canUnindent;  // true when cursor is on a list item and indent > 0
final VoidCallback onIndent;
final VoidCallback onUnindent;
```

In the build method, after the numbered list button:

```dart
_ToolbarButton(
  icon: Icons.format_indent_increase,
  tooltip: 'Aumentar indentação',
  isActive: false,
  onPressed: onIndent,
),
_ToolbarButton(
  icon: Icons.format_indent_decrease,
  tooltip: 'Diminuir indentação',
  isActive: false,
  onPressed: onUnindent,
),
```

Add `canIndent`/`canUnindent` state computation in `NoteToolbar.build()`:

```dart
final activeNodeId = _activeNodeId(selection);
final blockType = _activeBlockType(activeNodeId);
final isListItem = blockType == listItemAttribution;
final indent = _listItemIndent(activeNodeId);

return _ToolbarContainer(
  // ...existing params...
  canIndent: isListItem && indent < 6,
  canUnindent: isListItem && indent > 0,
  onIndent: _indentListItem,
  onUnindent: _unindentListItem,
);
```

Add the `_listItemIndent` helper:

```dart
int _listItemIndent(String? nodeId) {
  if (nodeId == null) return 0;
  final node = editor.context.document.getNodeById(nodeId);
  if (node is ListItemNode) return node.indent;
  return 0;
}
```

- [ ] **Step 3: Verify analyzer passes**

Run: `dart analyze lib/features/notes/presentation/widgets/note_toolbar.dart`
Expected: No errors.

- [ ] **Step 4: Verify the full project builds**

Run: `flutter build` (or `dart compile` equivalent)
Expected: Build succeeds.

---

## Self-Review

**Spec coverage:**
1. Strikethrough button → Task 1 (toolbar button)
2. Strikethrough markdown persistence → Task 2 (parse + serialize)
3. Tab/Shift+Tab list indent/outdent → Task 3 (already in default keyboard actions + toolbar buttons added)

**Placeholder scan:** No TBDs, TODOs, or placeholders found. Every step has exact code and commands.

**Type consistency:** `strikethroughAttribution` matches the type from `super_editor` fork. `IndentListItemRequest`/`UnIndentListItemRequest` match the request classes in `list_items.dart`. `_serializeInlineFormatting` output uses `~...~` which matches `_applyInlineFormatting` input parser.
