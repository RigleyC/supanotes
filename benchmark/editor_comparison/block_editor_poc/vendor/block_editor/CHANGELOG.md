# Changelog

All notable changes to the `block_editor` package are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
This package adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.0.4-dev.1] — 2026-04-02

Re-release of Phase 4 content with updated package README and fully working example app. No API changes from `0.0.3-dev.1`.

### Changed

- Package `README.md` rewritten with full public API documentation, usage examples, and roadmap
- Example app completed — demonstrates all built-in block types, formatting toolbar, slash command menu, block action menu, keyboard shortcuts, drag and drop, and read-only viewer mode

---

## [0.0.3-dev.1] — 2026-04-01

Phase 4 — Toolbar & Commands. 540 tests passing. API is unstable — breaking changes are expected before `1.0.0`.

### Added

**Keyboard Shortcuts**
- `KeyboardShortcutHandler` — centralised keyboard shortcut dispatcher, fully testable without the Flutter binding
- `ModifierKeys` — value object carrying `cmd`, `shift`, `alt` booleans; production callers use `ModifierKeys.fromHardware()`, test callers construct directly
- `KeyboardShortcutHandler.handle(KeyEvent, ModifierKeys)` — dispatches a key event and returns whether it was consumed

**Formatting Toolbar**
- `FormattingToolbar` — context-sensitive floating toolbar appearing over any expanded text selection; never shown in `readOnly` mode
- Eight buttons: Bold, Italic, Underline, Strikethrough, Inline Code, Link, Text Color, Background Color
- Each button reflects active / inactive / mixed state across the selection with toggle semantics
- Display mode controlled by `BlockEditorWidget.toolbarBreakpoint` — floats above selection anchor above threshold, pins to editor bottom below it
- Color buttons delegate to `onColorPickerRequested` callback when provided, otherwise open built-in 12-swatch palette popover

**Slash Command Menu**
- `SlashCommandMenu` — data-driven block insertion menu triggered by `/` at the start of an empty block or after a space; never shown in `readOnly` mode
- Groups entries by `BlockPlugin.slashCommandGroup()` — built-in order: Text, Headings, Lists, Media, Embeds, Advanced; external groups follow alphabetically
- Real-time filtering as the user types; arrow key navigation; Enter or Tab confirms; Escape or Backspace-to-empty dismisses; mouse click selects
- On confirmation: empty triggering block is transformed to selected type; block with content gets a new block inserted below; `/` and filter text removed

**Block Action Menu**
- `BlockActionMenu` — five-action floating menu anchored to each block's drag handle; never shown in `readOnly` mode
- Actions: Delete Block, Duplicate Block, Turn Into (submenu), Move Up, Move Down
- Move Up disabled for first block; Move Down disabled for last block; all actions dispatch through `BlockController`

**`BlockEditorWidget` — new parameters**
- `toolbarBreakpoint` (`double`, default `768.0`) — width threshold in logical pixels controlling toolbar display mode
- `onColorPickerRequested` (`Future<Color?> Function(Color? currentColor)?`) — optional custom color picker callback; built-in 12-swatch palette used when null

**`BlockRegistry`**
- `plugins` getter — returns all registered `BlockPlugin` instances; used by `SlashCommandMenu` and `BlockActionMenu`

**`BlockController`**
- `duplicate(String blockId)` — inserts a copy of the identified block immediately below it with a fresh UUID, preserving type, attributes, children, and delta

**`EditorEditingOperations` — new methods**
- `applyStrikethrough()` — toggles strikethrough on expanded selection or stores as pending attribute on collapsed selection
- `applyInlineCode()` — toggles inline code on expanded selection or stores as pending attribute on collapsed selection
- `applyAttributes(InlineAttributes)` — applies arbitrary `InlineAttributes` to the expanded selection; used by toolbar for color application
- `extendSelectionToLineStart()`, `extendSelectionToLineEnd()` — extend selection focus to start or end of current block
- `extendSelectionToDocumentStart()`, `extendSelectionToDocumentEnd()` — extend selection focus to first or last offset in document
- `extendSelectionWordLeft()`, `extendSelectionWordRight()` — extend selection focus one word boundary, crossing block boundaries
- `applyBold()`, `applyItalic()`, `applyUnderline()` — now also store pending attributes on collapsed selection, applied to next inserted character

### Changed

- `TextDelta.applyAttributes` — toggle semantics added for boolean attributes (bold, italic, underline, strikethrough, inlineCode); if every op in the target range already has the attribute set it is removed, otherwise set on all ops; color and link attributes unaffected

### Fixed

- Background color (`InlineAttributes.backgroundColor`) was stored correctly but never rendered; `RichTextRenderer` now reads and applies it alongside inline code background, with inline code taking priority
- `InlineAttributes.copyWith` silently ignored null values causing toggle-off to never work; `TextDelta.applyAttributes` now constructs `InlineAttributes(...)` directly so null correctly clears a field

### Breaking Changes

- `EditorEditingOperations` is no longer `const`-constructible — it holds mutable pending attribute state; all construction sites use `EditorEditingOperations(controller)` without `const` so no call site changes are required for existing consumers

---

## [0.0.2-dev.1] — 2026-03-20

First published pre-release. Covers Phase 1 (Document Model), Phase 2 (Rendering Engine), and Phase 3 (Block Plugin System). API is unstable — breaking changes are expected in future pre-release versions before `1.0.0`.

### Added

**Document Model (Phase 1)**
- `BlockNode` — typed content node with `id`, `type`, `attributes`, and `children`
- `BlockDocument` — root container with ordered `BlockNode` list, JSON serialisation and deserialisation
- `TextDelta` — inline rich text model as a list of `DeltaOp` objects
- `DeltaOp` sealed class with `TextOp` subtype carrying `InlineAttributes`
- `InlineAttributes` — bold, italic, underline, strikethrough, inline code, link, text color, background color
- `BlockController` — document state manager with insert, delete, update, move, and transform operations
- `BlockTypes` — typed constants for all built-in block type identifiers
- `EditorSelection` — sealed class replacing `BlockSelection` for cursor and range selection
- Undo/redo stack with snapshot-based history
- `selectionStream` on `BlockController` alongside the document change stream

**Rendering Engine (Phase 2)**
- `BlockRenderer` — stateless widget mapping `BlockNode` to its Flutter widget via `BlockRegistry`
- `BlockEditorWidget` — root editor widget with external `BlockController` ownership, keyboard events, focus, and scroll
- `RichTextRenderer` — converts `TextDelta` into a `TextSpan` tree
- Block widgets for Paragraph, H1, H2, H3, BulletList, NumberedList, Todo, Quote, and Divider
- Cursor rendering with public animation API
- Single-block and cross-block selection highlight
- Character-level editing operations in pure Dart
- Drag and drop block reordering with ghost preview and drop indicator
- `readOnly` flag on `BlockEditorWidget`
- `BlockEvent` sealed class as the universal block interaction contract
- `CustomBlockEvent` wrapper subtype for external package event extensibility

**Block Plugin System (Phase 3)**
- `BlockPlugin` abstract interface — `blockType`, `build()`, `serialize()`, `deserialize()`, optional `toolbarButton()`, `slashCommandItem()`, `slashCommandGroup()`
- `BlockRegistry` with public `register(BlockPlugin)` method — built-in blocks pre-registered internally
- Per-block stream system via `BlockController.streamForBlock(String blockId)`
- `EditorEditingOperations` extended to operate on `TextDelta.ops` preserving inline formatting
- IME and mobile soft keyboard input via `TextInputConnection`
- Built-in media block plugins: Image, Video, YouTube embed, File attachment, Code, Callout, Link
- Inline embed `DeltaOp` subtypes for variables and tags

---

## [0.0.1] — 2026-01-01

Initial mono-repo scaffold. No functional code. Repository structure, CI pipeline, Melos workspace configuration, and pubspec files only.