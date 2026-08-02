# Note Formatting Toolbar Mode

## Problem Statement

A toolbar da nota mistura ações permanentes, como anexos e listas, com ações de formatação que só fazem sentido quando o usuário está editando texto. Quando todas essas ações ficam visíveis na mesma linha, a toolbar ocupa espaço e a relação entre a ação `Aa` e as opções de formatação não fica clara.

## Solution

Adicionar um modo dedicado de formatação, inspirado no Apple Notes. A toolbar compacta será substituída por uma toolbar de formatação quando o usuário tocar em `Aa`.

O modo de formatação exibirá um botão `X`, uma linha de estilos de bloco e uma linha de formatação inline. O modo permanecerá aberto enquanto o usuário selecionar outros trechos e aplicar várias formatações. Tocar em `X`, tocar fora ou pressionar `Escape` retornará à toolbar compacta.

## User Stories

1. As a note editor user, I want to open a dedicated formatting toolbar from `Aa`, so that formatting actions are grouped in one clear place.
2. As a note editor user, I want the compact toolbar to be replaced while formatting mode is open, so that the interface does not show two competing toolbars.
3. As a note editor user, I want to see H1, H2, H3 and quote in a dedicated block-format row, so that block styles are easy to scan.
4. As a note editor user, I want to see bold, italic and strikethrough in a dedicated inline-format row, so that text styles are grouped separately from block styles.
5. As a note editor user, I want the formatting toolbar to remain open after applying a style, so that I can continue formatting without reopening it.
6. As a note editor user, I want the formatting toolbar to reflect the current selection, so that active block and inline styles remain clear when I move through the document.
7. As a note editor user, I want to select another text range while the formatting toolbar is open, so that I can format multiple places in one editing session.
8. As a note editor user, I want applying a formatting action to preserve the current editor selection, so that the command targets the intended text.
9. As a note editor user, I want to close formatting mode with `X`, so that I can return to the normal editing actions.
10. As a keyboard user, I want `Escape` to close formatting mode, so that I can return to the compact toolbar without reaching for the close button.
11. As a note editor user, I want tapping outside the formatting toolbar to close it, so that the editor does not remain in a special mode accidentally.
12. As a note editor user, I want the transition between compact and formatting modes to be fluid, so that the toolbar feels like one component changing state.
13. As a desktop user, I want the same compact and formatting modes as on mobile, so that formatting behavior is consistent across platforms.
14. As a user with reduced motion enabled, I want the mode transition to become immediate or minimal, so that the interface respects my accessibility preference.
15. As a note editor user, I want disabled actions to remain disabled and visually clear in formatting mode, so that unavailable commands cannot be triggered accidentally.
16. As a maintainer, I want the editor and document command flow to remain unchanged, so that this is a presentation and interaction change only.

## Implementation Decisions

- Model the toolbar as two presentation modes: compact and formatting.
- Keep the mode state local to the toolbar; it is UI state and does not belong in a provider or document model.
- Render exactly one toolbar mode at a time. Entering formatting mode replaces the compact toolbar content instead of placing a second floating overlay above it.
- Use the existing toolbar glass surface and existing `motor` spring tokens for the transition. `AnimatedSize` may own the structural height change, while `motor` handles internal icon, opacity, scale and color transitions.
- In compact mode, `Aa` opens formatting mode. Existing list, attachment, image and other compact actions remain available there.
- In formatting mode, `X` closes the mode. The formatting content has two rows: block styles (H1, H2, H3, quote) and inline styles (bold, italic, strikethrough).
- Keep the list-format popover as a separate compact-mode action unless a later spec explicitly moves list actions into formatting mode.
- Keep the `NoteToolbar` editor and composer listeners active in both modes. The toolbar remains the same editor integration point and does not recreate the editor.
- Derive active states from the current composer selection and selected document nodes on every rebuild. Do not duplicate document state inside the formatting toolbar.
- While formatting mode is open, applying a command must not close the mode. The command must use the latest valid editor selection; if tapping a toolbar action changes focus, restore or reapply the captured selection before dispatching the command.
- If the selection changes while formatting mode is open, update active states without closing the mode. A rapid sequence of selection changes must settle on the latest toolbar state.
- Preserve existing command callbacks and REST/OT document mutation flow. No direct document or projected-task writes are introduced.
- Preserve button semantics, labels, hit targets, disabled states, keyboard dismissal and editor focus behavior.
- Respect `MediaQuery.disableAnimations` by switching the mode transition and microinteractions to immediate state changes or a minimal transition.
- Support narrow mobile widths and desktop widths without overflow. Rows may use bounded horizontal scrolling or adaptive layout while preserving the two-row grouping.
- Outside dismissal must not interrupt an in-flight formatting command. It only changes the toolbar mode after the command callback has been dispatched.

## Testing Decisions

- Test through the existing `NoteToolbar` widget harness at the highest practical seam. Tests must assert visible behavior and interaction outcomes, not private animation controllers, exact spring values or animation frame counts.
- Extend the toolbar widget tests to verify:
  - compact mode exposes `Aa` and existing compact actions;
  - tapping `Aa` replaces the compact actions with `X` and the two formatting rows;
  - H1, H2, H3 and quote apply the expected block command;
  - bold, italic and strikethrough apply to the current selection;
  - the formatting toolbar stays visible after each command;
  - changing the selection while the mode is open updates active states;
  - `X`, outside tap and `Escape` return to compact mode;
  - focus and selection are preserved after applying a command;
  - rapid selection changes expose only the latest active state;
  - reduced motion reaches the same final visible states without waiting for spring settling;
  - desktop constraints render both modes without overflow.
- Run the focused toolbar widget tests first, then related editor presentation tests, then `flutter analyze`.
- Reuse the existing editor conversion and toolbar tests as prior art. Do not add a new integration seam unless the existing toolbar harness cannot observe focus or selection behavior.

## Out of Scope

- Adding a new animation, overlay or icon-morph package.
- Changing the editor document model, REST/OT operations, synchronization or authentication.
- Moving list actions into the formatting mode in this iteration.
- Adding underline, text color, highlight, alignment or other new formatting commands.
- Redesigning the glass material, toolbar placement or editor layout beyond the mode transition.
- Implementing arbitrary SVG path morphing.
- Persisting toolbar mode across navigation, app restart or devices.

## Further Notes

The main success criterion is that the toolbar behaves as one continuous component with two deliberate states: compact for general editing actions and formatting-focused for an uninterrupted formatting session.

The implementation should avoid destroying and recreating the editor integration when switching modes. The mode transition changes only the toolbar presentation, which keeps selection tracking and command dispatch centralized.
