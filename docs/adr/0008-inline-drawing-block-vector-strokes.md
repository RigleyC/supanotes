# 0008. Inline Drawing Block with Vector Strokes & Local Undo Stack

* Status: Accepted
* Date: 2026-07-26

## Context

Users requested the ability to draw and sketch inside notes, similar to Apple Notes. SupaNotes stores note contents as a versioned JSON document snapshot (`notes.document` JSONB) rendered via `super_editor` in a Flutter `CustomScrollView`. 

Integrating freehand drawing presents technical challenges:
1. Touch/mouse gesture conflicts between document scrolling and stroke capturing.
2. Data format choices (raster images vs vector strokes).
3. Undo/redo granular control without cluttering the global document operation history.

## Decision

We will implement **Drawing Block** (`type: "drawing"`) as an inline structural node in `super_editor` with the following architectural decisions:

1. **Vector Stroke Data Model**: Strokes (`x, y`, pressure, width, color, tool type) are stored directly in vector format within the block data in `notes.document`.
2. **Inline Component with Explicit Edit Toggle**: The block is rendered inline in the document stream. Touch/mouse scrolling passes through the block in read-only view. The user taps an explicit "Edit Drawing" toggle to capture gestures for drawing.
3. **Local Undo/Redo Stack**: Stroke undo/redo operates locally within the active drawing tool session. Upon deactivating drawing mode, the final block state is committed to `super_editor` as a single document change.
4. **Insertion**: Accessible via Slash Menu (`/desenho`, `/draw`, `/rabisco`) and an editor toolbar button.

## Consequences

### Positive
* 100% vector fidelity across platforms (iOS, Android, Windows, macOS) and screen densities.
* Zero gesture conflicts with page scrolling (`CustomScrollView`).
* Clean REST/OT document snapshot compatibility without breaking existing block projections.

### Negative / Trade-offs
* Large drawings with thousands of stroke points increase JSON snapshot size.
* Requires custom `ComponentBuilder` in `super_editor` to render `CustomPainter` vector paths efficiently.
