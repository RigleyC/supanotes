# Progressive Content Fade Design

## Goal

Fade note content to transparent as it moves through the top 48 pixels of the notes list or note editor. Keep the transparent AppBar and its controls fully opaque above the content.

## Design

Add a shared `ProgressiveFade` widget that wraps only the content viewport. It uses `ShaderMask` with `BlendMode.dstIn`. Its default fade height is 48 pixels. Opacity rises through 20%, 40%, 60%, 80%, and 90% within that region, then reaches 100% at 56 pixels, aligned with the toolbar end. Calculate all stops from `bounds.height`, not the screen height, and clamp them to `0.0..1.0`.

Keep `extendBodyBehindAppBar: true` so content can move behind the transparent AppBar. Remove the AppBar background gradients because they paint over content instead of changing content opacity. Do not wrap the AppBar in the mask.

## Validation

A widget test verifies the destination-in mask, the 48-pixel default, and the bounds-based curve. Focused tests and static analysis cover the changed files.
