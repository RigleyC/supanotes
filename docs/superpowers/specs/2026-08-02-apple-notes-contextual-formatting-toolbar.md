# Apple Notes-inspired contextual formatting toolbar

## Problem Statement

A toolbar atual permite formatar a nota por meio de um popover pequeno. Esse comportamento não corresponde ao fluxo observado no Apple Notes: ao tocar em `Aa`, a toolbar compacta é substituída por um painel de formatação persistente, ancorado acima do teclado. O usuário consegue aplicar várias formatações sem reabrir o menu, enquanto a nota permanece visível e o cursor continua ativo.

## Solution

Transformar a toolbar em uma superfície contextual com dois estados: compacto e formatação.

No estado compacto, a toolbar exibe as intenções principais da edição. Ao tocar em `Aa`, ela se transforma em um painel expandido de formatação, com título, botão de fechamento e controles agrupados. O teclado permanece aberto, o editor não é recriado e o painel permanece aberto após cada comando.

O painel deve refletir continuamente a seleção atual: estilo de bloco, negrito, itálico, tachado e tipo de lista. O usuário pode fechar o painel com `X`, toque fora, `Escape` ou retorno do sistema.

## User Stories

1. As a note editor user, I want to tap `Aa` to open a dedicated formatting panel, so that I can find text formatting controls in one predictable place.
2. As a note editor user, I want the compact toolbar to be replaced by the formatting panel, so that two competing toolbars are not shown at the same time.
3. As a note editor user, I want the formatting panel to remain above the keyboard, so that I can see the text I am formatting.
4. As a note editor user, I want the keyboard to remain open when formatting starts, so that I can continue typing immediately.
5. As a note editor user, I want a visible `Format` title, so that I understand the purpose of the expanded panel.
6. As a note editor user, I want a close button, so that I can return to the compact toolbar explicitly.
7. As a note editor user, I want the panel to close when I tap outside it, so that temporary formatting mode does not remain open accidentally.
8. As a keyboard user, I want `Escape` to close formatting mode, so that I can return to the compact toolbar without touching the screen.
9. As a note editor user, I want to choose Body, Title, Heading, Subheading, or the supported block styles, so that I can structure the note quickly.
10. As a note editor user, I want the current block style to be highlighted, so that I know which style applies at the cursor.
11. As a note editor user, I want to apply bold to the current selection, so that I can emphasize text without leaving formatting mode.
12. As a note editor user, I want to apply italic to the current selection, so that I can change emphasis without reopening the panel.
13. As a note editor user, I want to apply strikethrough to the current selection, so that I can mark text as removed or completed.
14. As a note editor user, I want active inline styles to remain highlighted, so that formatting state is visible.
15. As a note editor user, I want to change the selection while the panel is open, so that I can format multiple parts of a note in one session.
16. As a note editor user, I want the panel to remain open after applying a command, so that repeated formatting is fast.
17. As a note editor user, I want formatting commands to target the selection that was active before tapping the toolbar, so that opening the panel does not move the formatting target.
18. As a note editor user, I want unsupported actions to be hidden or clearly disabled, so that the interface never promises a command the document model cannot execute.
19. As a note editor user, I want list and checklist state to remain consistent with the document, so that the compact and formatting modes do not disagree.
20. As a desktop user, I want the same two-mode interaction model, so that the editor does not have unrelated behavior on desktop.
21. As a user with reduced-motion enabled, I want the mode change to be immediate or minimal, so that the interface remains comfortable.
22. As a user with high-contrast settings, I want the panel to remain readable without relying on blur or transparency, so that all controls remain usable.
23. As a screen-reader user, I want the mode, close action, active styles, and disabled actions to be announced, so that the formatting panel is understandable without visual inspection.
24. As a maintainer, I want the toolbar state to remain local UI state, so that formatting mode does not leak into providers or persisted note data.
25. As a maintainer, I want all document mutations to use the existing editor command path, so that formatting remains synchronized through the canonical REST/OT document flow.

## Implementation Decisions

- Model the toolbar as two local presentation states: compact and formatting.
- Render one state at a time. Formatting mode replaces the compact toolbar content.
- Keep the formatting mode local to the toolbar. Do not add provider state, database fields, sync fields, or persisted preferences.
- Keep the existing editor, composer, selection listener, document listener, focus node, and command callbacks active in both states.
- Keep the keyboard open when entering formatting mode. Do not use a modal route or a modal bottom sheet for this interaction.
- Anchor the expanded panel to the same bottom editor area that currently hosts the toolbar, above the current keyboard inset.
- Use the existing glass surface and motion conventions. Animate the structural expansion and internal content, but respect reduced-motion settings.
- The expanded panel contains:
  - a header with a formatting title and close action;
  - a horizontally scrollable block-style group;
  - an inline-style group;
  - supported list and indentation controls where applicable.
- Use the current document model capabilities for the first implementation: block styles already supported by the editor, bold, italic, strikethrough, list types, checklist, and indentation.
- Do not add underline, text color, highlight, alignment, tables, drawing, audio, scanning, or other new document capabilities in this slice unless an existing command and serialization path already support them.
- Derive active states from the current composer selection and document nodes on every rebuild. Do not duplicate document state inside the toolbar.
- Capture the current valid selection when formatting mode opens. If a button temporarily takes focus, restore the captured selection before dispatching the command.
- Applying a formatting command must not close formatting mode.
- When the selection changes while formatting mode is open, update active states to the latest selection. Obsolete selection snapshots must not override newer selection state.
- Close formatting mode with the close button, outside tap, Escape, or system back handling. Closing restores editor focus when appropriate.
- Outside dismissal must not cancel or reorder a command that was already dispatched.
- Preserve button semantics, hit targets, disabled behavior, and Portuguese accessibility labels used by the app.
- Keep list formatting as a separate compact-mode action unless product scope later moves list controls into the expanded formatting panel. If list controls are shown in the panel, they must reuse the existing list command semantics.
- Keep all mutations flowing through the existing editor command layer and operation capture. Do not write projected task data directly.
- Keep the change limited to presentation and interaction. Do not change the canonical document schema, REST/OT protocol, sync lifecycle, or attachment repository.

## Testing Decisions

- Use the existing rendered `NoteToolbar` widget seam as the primary test seam.
- Test observable behavior, not private animation controllers, exact spring physics, frame counts, or private widget names.
- Verify that compact mode exposes the formatting trigger and existing compact actions.
- Verify that tapping the formatting trigger replaces compact content with the expanded panel.
- Verify that the keyboard/focus contract is preserved when entering formatting mode.
- Verify that the expanded panel exposes its title and close action.
- Verify that selecting each supported block style updates the document and keeps the panel open.
- Verify that bold, italic, and strikethrough target the captured selection and keep the panel open.
- Verify that changing the editor selection while the panel is open updates active states.
- Verify that a selection change cannot be overwritten by an older captured selection.
- Verify that close button, outside tap, Escape, and system back return to compact mode.
- Verify that the editor focus is restored after closing.
- Verify disabled inline commands when there is no non-collapsed text selection.
- Verify list and checklist active states against the current document.
- Verify narrow mobile constraints do not overflow and allow horizontal access to controls.
- Verify desktop constraints render both modes without overflow.
- Verify reduced-motion settings reach the same final states without waiting for animation settling.
- Verify high-contrast mode uses an opaque readable surface.
- Verify semantics expose labels, enabled state, active state, and close action.
- Run the focused toolbar widget tests first, then related editor presentation tests, then Flutter analysis.
- Reuse existing toolbar and editor widget test fixtures as prior art. Do not introduce a second editor integration seam.

## Out of Scope

- Implementing every Apple Notes feature.
- Adding underline, text color, highlight, alignment, tables, drawing, handwriting, audio recording, transcription, document scanning, or Apple Intelligence.
- Changing the document schema or block serialization.
- Changing REST/OT operations, synchronization, rebasing, projection, or authentication.
- Replacing the editor or composer.
- Persisting toolbar mode across navigation, restart, or devices.
- Redesigning the entire editor screen or navigation bar.
- Replacing the existing glass design system.
- Adding a new animation framework.
- Moving list actions permanently into formatting mode without a separate product decision.
- Creating direct writes to the projected tasks table.

## Further Notes

The supplied Apple Notes screenshots show a persistent formatting surface rather than a transient popover. The key behavior to reproduce is the interaction model: one toolbar changes state, the keyboard stays available, the panel remains open through multiple commands, and the current selection continues to drive active states.

The implementation should be delivered as a small vertical slice. Visual fidelity should be validated on a narrow mobile viewport first, then on desktop and high-contrast/reduced-motion configurations.
