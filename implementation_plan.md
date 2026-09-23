# Implementation plan — local-first note persistence

## Tasks independentes e navegação Tasks/Notas

Status: Tasks 1–10 implementadas; documentação normativa e runbook da Task 11
alinhados. A verificação integrada e o rollout seguro permanecem na Task 12.

Design:
`docs/superpowers/specs/2026-09-03-standalone-tasks-tabs-design.md`.

Plano detalhado:
`docs/superpowers/plans/2026-09-15-standalone-tasks-tabs.md`.

Escopo aprovado em conversa: duas abas principais com Tasks primeiro; tasks
independentes local-first sincronizadas entre dispositivos do proprietário;
inclusão opcional e local das tasks dos documentos de notas na mesma lista;
histórico de concluídas; colaboração entre pessoas fica para uma fase futura.

O design também exige verificação atual, backup e encerramento explícito da
retenção antes de remover as tabelas relacionais legadas. A migração reutiliza
o nome `tasks` para o contrato independente depois de mover a relação antiga
para quarentena; dados antigos, vazios ou não, nunca são convertidos
automaticamente. A remoção física continua condicionada ao gate de retenção.

O design revisado também cobre rollout compatível do feed (`scope=notes` por
default e `scope=all` opt-in), bootstrap versionado, confirmação idempotente,
conflitos por `scheduleGeneration`, quarentena SQLite, visibilidade de notas,
identidade de notificações e invalidação temporal da lista.

### Contrato atual de ownership

- `TaskNode` vive no snapshot REST/OT da nota (`notes.document`) e no snapshot
  efetivo local. Texto, agenda, recorrência, reminder e conclusão de uma task
  de nota entram pelo fluxo de operações do documento.
- `Task` é a task independente e vive na tabela PostgreSQL `tasks`. A tabela
  Drift `tasks` é sua cópia local-first e `pending_task_operations` é sua
  outbox. O repositório/API de tasks é o caminho de mutação dessa entidade.
- A tabela `tasks` independente não é projeção de `TaskNode`, e `TaskNode` não
  é projetado ou copiado para ela. Também não existe conversão automática no
  sentido inverso. A aba Tasks apenas combina adaptadores de leitura locais.
- `tasks_legacy_quarantine_v31`, `task_completions_legacy_quarantine_v31` e
  os nomes equivalentes da quarentena SQLite são evidência de migração, não
  fontes de runtime. Dados legados nunca são promovidos sem decisão explícita.

As migrações PostgreSQL exigem backup restaurável, export protegido e gate de
retenção antes de qualquer limpeza. A migração Drift 32→33 preserva restos
locais por quarentena e pode bloquear apenas tasks independentes quando há
linhas antigas. O feed mantém `scope=notes` como default para clientes antigos;
clientes novos usam `scope=all` somente depois do bootstrap versionado.

## Per-note preference synchronization

Status: planned; implementation approved.

Design: `docs/superpowers/specs/2026-08-14-per-note-preferences-sync-design.md`.
Execution plan: `docs/superpowers/plans/2026-08-14-per-note-preferences-sync.md`.

Scope: synchronize favorite, archived, hide-completed, and image collapse as
per-user per-note state; retain the local dirty row for offline delivery; remove
the shared-note collapse-images contract and all obsolete code.

## Windows debug launch: invalid canonical Delta snapshot

Status: complete.

- [x] Add a regression test for the backend writing mutation operations into a document snapshot.
- [x] Normalize the REST/OT document at the backend boundary so snapshots contain insert operations only.
- [x] Keep local editor hydration able to repair the existing cached mutation operation without weakening the public snapshot contract.
- [x] Reproduce the Windows launch and run focused, analyzer, backend, and full checks.

Status: complete for ticket 01.

Review-fix pass: complete.

Scope: ticket 01, atomic local persistence during remote note hydration.

- [x] Confirm the current write order and data-loss failure mode.
- [x] Expose a pure document projection result.
- [x] Persist document, catalog row, content projection, and task projection atomically.
- [x] Update catalog hydration to use the aggregate transaction.
- [x] Add first-hydration and rollback tests.
- [x] Run focused tests, full suite, code review, and commit the ticket.

Review fixes:

- [x] Reject stale or missing local rows before publishing remote hydration.
- [x] Remove the insert/update mode flag and centralize metadata updates in the DAO.
- [x] Separate pure document projection from database persistence.
- [x] Test the real editor session opening from local storage.
- [x] Run the final full suite, review, and commit the fixes.

## Editor text and task completion snack

Status: complete.

- [x] Use white text for the editor document styles.
- [x] Keep only the completion title and undo action in the task snack.
- [x] Add focused coverage for hiding the next-occurrence message.
- [x] Run focused tests and analyzer; the full suite timed out in the environment.

## Task metadata sheet bottom spacing

Status: complete.

- [x] Identify the duplicated bottom spacing in the modal content.
- [x] Reduce the explicit bottom gap while preserving safe-area spacing.
- [x] Run the focused task metadata sheet test and analyzer.

## Note draft lifecycle and initial focus

Status: complete.

- [x] Represent a newly opened local note as a draft until its canonical document has meaningful content.
- [x] Keep drafts out of catalog lists while preserving the stable note ID for the editor session and REST/OT outbox.
- [x] Commit drafts from canonical document projection and discard untouched drafts as a complete local aggregate.
- [x] Mark a note as having a remote copy after successful REST/OT sync.
- [x] Derive initial focus from draft state and remove the router-level new-note focus flag.
- [x] Add focused lifecycle, catalog, editor, and sync tests.
- [x] Run analyzer, focused tests, and diff checks.

## Draft lifecycle quality corrections

Status: complete.

- [x] Project the final editor flush before allowing draft cleanup.
- [x] Make untouched-draft validation and aggregate deletion atomic.
- [x] Use one database lifecycle store instead of optional repository fallbacks.
- [x] Keep attachment drafts visible and distinguish editor autofocus from
  aggregate lifecycle state.
- [x] Make `hasRemoteCopy` explicit in every `NoteModel` construction.
- [x] Add regression coverage for immediate close and attachment visibility.

## Editor empty viewport focus

Status: complete.

- [x] Reproduce taps below the document but above the mobile toolbar.
- [x] Add regression coverage for caret placement, focus, keyboard reopening,
  and a document with only hidden tasks.
- [x] Handle trailing hidden tasks through the Super Editor content-tap
  delegate API.
- [x] Run focused tests, analyzer, full suite, and two-axis code review.

## iOS task text selection

Status: complete.

- [x] Reproduce the long-press conflict between task actions and iOS text selection.
- [x] Restrict task action long press to the checkbox.
- [x] Preserve secondary-click task actions on desktop.
- [x] Add iOS selection regression coverage across task blocks.
- [x] Run focused tests, analyzer, full suite, code review, and commit.

## Remove desktop version features

Status: complete (see `walkthrough.md`).

Decisions confirmed with the user:
- Keep the `windows/` platform folder — the app stays buildable on Windows; only the desktop *features* are removed.
- Remove desktop tests and update living docs; historical specs (`docs/superpowers/specs/`, `plans/003-*.md`, `.scratch/`) stay.
- Dependencies: list below is pending user review.

### Scope of the desktop version (analysis)

The desktop feature was introduced in `18627c70` (2026-07-24) and refined through `b688b08e` (2026-08-06). It covers:

1. **Split-view shell (`AdaptiveNotesShell`)** — resizable/collapsible sidebar + content surface, wire-through `ShellRoute` in the router.
2. **Desktop notes sidebar** — `NotesSidebar` (navigation), `DesktopSidebarSurface`, `DesktopContentSurface`, `ResizeDragHandle`.
3. **Desktop editor chrome** — `DesktopNoteChrome`, `DesktopEditorViewport` (+ `DesktopEditorLayoutScope`), writer typography (`note_desktop_stylesheet.dart`), translucent surfaces and layout tokens.
4. **Desktop formatting popover** — `DesktopSelectionFormattingOverlay` (follows selection, `follow_the_leader`).
5. **Native context menus** — `note_context_menu.dart` via `super_context_menu`, wired into note tiles/cards/rows/sidebar.
6. **Desktop markdown shortcuts** — `MarkdownTaskShortcutPlugin`/`MarkdownInlineUpstreamSyntaxPlugin` gated `isDesktop`.
7. **Branch adaptations inside shared screens** — `notes_list_screen`, `note_editor_screen`, `note_editor`, `note_stylesheet`/`note_mobile_stylesheet`, `share_link_reader_screen`, `note_icon_interaction_policy`.
8. **Orphan desktop dep** — `local_notifier` (declared + registered in Windows, never used in Dart).

NOT desktop (keep as-is, clarified):
- Slash command menu **is** a desktop feature (created by `9fea523e feat(desktop): add slash command menu`; full history is `fix(desktop): ...`). It leaks into mobile today (`note_editor.dart:396` without a gate), but mobile intent is the toolbar → **remove it**.
- `super_clipboard`/rich keyboard actions are cross-platform (kept).
- `adaptive_platform_ui` (kept).
- `window_manager` window bootstrap (kept because `windows/` stays).
- Device-token FCM dead code in `auth_repository` (documented fallback `'desktop'`, never called).
- `follow_the_leader` cannot be removed from the project: it is a transitive dependency of `super_editor` itself (`super_editor/pubspec.yaml:36`, used in core `document_layout.dart`). After removing the slash menu + desktop popover, drop the *direct* entry from `pubspec.yaml` (super_editor keeps it resolved).

### Removal steps

1. **Delete desktop-only files** (18):
   - `lib/features/notes/catalog/presentation/adaptive_notes_shell.dart`
   - `lib/features/notes/catalog/presentation/widgets/{desktop_sidebar_surface,desktop_content_surface,resize_drag_handle,notes_sidebar,note_context_menu}.dart`
   - `lib/features/notes/catalog/application/desktop_layout_preferences.dart`
   - `lib/features/notes/editor/presentation/note_desktop_stylesheet.dart`
   - `lib/features/notes/editor/presentation/widgets/{desktop_editor_viewport,desktop_note_chrome,desktop_selection_formatting_overlay,slash_command_overlay}.dart`
   - `lib/features/notes/editor/document/{markdown_task_shortcut_plugin,markdown_task_shortcut_reaction,slash_command_options}.dart`
   - `lib/shared/theme/desktop_layout_tokens.dart`, `lib/shared/widgets/desktop_translucent_surface.dart`
   - Trim `lib/core/utils/platform_utils.dart`: keep `isDesktopPlatform()` (used by `main.dart` window bootstrap); drop `kDesktopBreakpoint` + `isDesktopLayout`.

2. **Revert router** (`lib/core/router/app_router.dart`): drop `ShellRoute`/`AdaptiveNotesShell`; `home` and `note/:id` become plain top-level `GoRoute`s.

3. **Remove desktop branches from shared screens**:
   - `notes_list_screen.dart`: delete `isDesktopLayout` placeholder scaffold.
   - `note_editor_screen.dart`: single mobile AppBar path (remove transparent bg, `!isDesktop` predicate, `DesktopNoteChrome`, `DesktopEditorViewport`).
   - `note_editor.dart`: mobile-only stylesheet (`mobileNoteStylesheet`), remove `_cachedIsDesktop`, `DesktopEditorLayoutScope` resolution, `DesktopSelectionFormattingOverlay`, markdown plugin gate, dual `ValueKey`, `NoteSuggestionOverlay` gating, and the slash menu wiring (`_slashCommandController`, `SlashCommandOverlay`).
   - `note_editor_config.dart`: drop `slashCommandController` param from `editorKeyboardActions`.
   - `rich_keyboard_actions.dart`: drop `SlashCommandController` import and `slashMenuKeyboardHandler` prefix.
   - `share_link_reader_screen.dart`: always `mobileNoteStylesheet` (remove 700px breakpoint + desktop stylesheet import).
   - `note_card.dart`/`notes_list_view.dart`: remove `NoteContextMenuWidget` wrappers.
   - `note_icon_interaction_policy.dart`: keep mobile long-press logic only; drop desktop context-menu predicates.
   - `note_stylesheet.dart` refactor is kept (shared `buildNoteStylesheet` + mobile profile). Note: write build steps in `task.md`.

4. **Dependencies** (resolved with user):
   - Remove direct deps: `super_context_menu` (native context menu removed), `follow_the_leader` (no app code uses it anymore; stays transitively via `super_editor`).
   - Keep: `window_manager`, `super_clipboard`, `device_info_plus` override, `local_notifier` (user preference; orphan desktop dep — notifications go through `flutter_local_notifications`).
   - `flutter pub get` after removing deps; no Windows registry patch needed (`local_notifier` stays).

5. **Remove desktop tests** (delete files + strip desktop cases):
   - Delete: `desktop_layout_tokens_test.dart`, `markdown_shortcuts_test.dart`, `note_desktop_stylesheet_test.dart`, `desktop_note_layout_test.dart`, `desktop_caret_test.dart`, `notes_sidebar_test.dart`, `slash_command_overlay_test.dart`.
   - Strip desktop/slash cases: `note_editor_screen_test.dart`, `note_creation_navigation_test.dart`, `note_icon_interaction_policy_test.dart`, `rich_clipboard_test.dart` (slash references); fix imports in `note_toolbar_test.dart`; desktop mentions in `task_metadata_sheet_test.dart`, `list_marker_alignment_test.dart`.

6. **Update living docs** to remove desktop references: `AGENTS.md` ("mobile + desktop"), `CONTEXT.md`, `docs/architecture/notes-file-reference.md`, `docs/e2e-test-scenario-matrix.md`, `implementation_plan.md`, `walkthrough.md`. Historical specs stay.

7. **Verification**: `flutter analyze` clean; run mobile-focused test suite (`notes`, `catalog`, `editor`, `tasks`); confirm no remaining imports of removed symbols via grep; update `task.md`.

Status: **complete** (desktop features removed). See `walkthrough.md`.

## Note sharing hardening

Status: complete.

- [x] Fix public Share Link authentication fallback and guest route shell.
- [x] Make authenticated attachment delivery stable across all note routes.
- [x] Make the share sheet bounded and scrollable; restore widget coverage.
- [x] Align Go and Dart canonical snapshot validation.
- [x] Prevent direct-share account enumeration.
- [x] Fix App Link reopen behavior and canonical mobile host wiring.
- [x] Avoid unnecessary native endpoint rendering work.
- [x] Add focused regression tests and run the full verification suite.

## Historical: Task document-native migration

Status: implementation, local verification, production backfill, and backend
deployment are complete. Physical cleanup remains a separately approved
operation after retention.

The approved design is in
`docs/superpowers/specs/2026-08-12-task-document-native-design.md`.
The migration plan is in
`plans/005-task-document-native-migration.md`.
The section below records the note-only migration that preceded the
independent-task resource. It remains applicable to `TaskNode` blocks, but is
not the ownership model for the current independent `Task`. The older
incremental relational projection design is historical evidence and must not
be executed independently or reintroduced as a bridge between the two task
sources.

### Decisions

- At the time of this note-only migration, `TaskNode` in the canonical note
  document was the only task model. It remains the only model for note blocks;
  the current independent task is the separate `Task` entity documented at the
  top of this plan.
- REST/OT owns task content and metadata. SQLite stores the local effective
  document for offline reads and notifications.
- `dueDate` is the recurrence anchor. A completion is stored as
  `completions[scheduledAt] = completedAt`.
- Consecutive early completions are allowed. A series can move from 12 to 19
  and then 26 even when both completions happen on day 10.
- Monthly recurrence preserves the original anchor day across short months.
- `scheduledAt` is a wall-clock calendar identity without an offset;
  `completedAt` is the actual UTC instant.
- Early and late completion preserve the scheduled occurrence key. The next
  occurrence is calculated from the original schedule.
- Notifications use a future-target resolver when the visible recurring
  occurrence is overdue.
- An overdue occurrence remains historical. The next reached occurrence is
  the active one. Reopening removes only the exact scheduled occurrence.
- Changing schedule metadata clears the completion history for that task.
- The metadata sheet receives `TaskMetadataDraft`; it does not receive a
  relational `TaskModel`.
- Notification scheduling uses the effective local document. Shared-link
  visitors do not run a local notification scheduler.

### Execution order

1. [x] Define the document-native task and recurring-occurrence contract.
2. [x] Remove `TaskModel` from the editor, task metadata sheet, and editor
   callbacks.
3. [x] Persist the effective local note document after local operations and
   remote rebase/hydration.
4. [x] Historical note-only step: move notification reads to `TaskNode` and
   remove the former relational task providers and projection writers.
5. [x] Historical note-only step: remove the former relational task REST/MCP
   runtime paths and unused backend task services and queries. The current
   independent-task API is a separate resource under `internal/tasks`.
6. [x] Add and execute the production backup, export, isolated restore,
   read-only preflight, canonical backfill, and retention runbook. No
   production data is deleted by this change.
7. [x] Review scheduler boundary changes, schema versioning, generated SQL,
   and test coverage for regressions.
8. [x] Run the complete Flutter and Go verification suites.
9. [x] Run the thermo-nuclear maintainability review and resolve every finding.

### Data safety gates

- [x] Take a restorable PostgreSQL backup before production rollout.
- [x] Historical release gate: export the then-legacy `tasks` and
      `task_completions` relations before any physical cleanup.
- [x] Run a read-only comparison between relational rows and task blocks in
      `notes.document`.
- [x] Classify rows as corresponding, orphaned, or conflicting. Production
      had zero relational task rows; document-only blocks were classified as
      canonical data, not as missing legacy rows.
- [x] Keep the legacy export under controlled retention until the canonical
      document path is confirmed in production.
- [x] No automatic `DROP TABLE` migration was added. Physical cleanup of
      legacy/quarantined relations is a separate, approved operation after the
      retention period; it must not remove the current independent `Task`
      table.

## Haptic feedback defaults

Status: plan written; awaiting implementation approval.

The detailed plan is in
`docs/superpowers/plans/2026-08-13-haptic-feedback.md`.

Scope includes the shared control defaults, the `GlobalSheetHeader`, all
controls inside the task metadata sheet, all controls inside the emoji/icon
picker sheets, and normalization of the existing editor haptic calls. The
plan keeps native picker feedback and feature-owned scrolling unchanged.

## Code quality and reliability corrections (2026-09-16)

Status: complete after delegated Luna high implementation and independent Sol
low validation.

Design:
`docs/superpowers/specs/2026-09-16-code-quality-reliability-corrections-design.md`.

Execution plan:
`docs/superpowers/plans/2026-09-16-code-quality-reliability-corrections.md`.

This work applies the layered audit to concrete code: security/configuration,
attachments, MCP/sharing, Go domain boundaries, Flutter auth/editor/tasks and
the sync/database coordinator. The agents preserved the existing dirty
worktree and the invariant that `TaskNode` and independent `Task` never become
one persisted model. No visual-only tests were added. Focused Go/Flutter
verification and the independent Sol review are complete.

## Navigation, task creation and auth follow-up (2026-09-16)

The follow-up scope covers the reported iOS navigation shell, completed-task
back affordance, standalone-task creation modal, empty notes layout, focus
dismiss control, note/task navigation stalls, and the Dio access/refresh-token
contract. Implementation was delegated in disjoint Luna high scopes: shell and
routing, task form/modal, notes/editor interaction, and auth transport. The
`AdaptiveScaffold` is intentionally retained because it is the host required
by `AdaptiveBottomNavigationBar`; route gating controls when that bar is shown.
The implementation reuses shared components, keeps `AsyncValue.when` as the
state boundary, and adds no visual-only tests. Focused Flutter tests/analyzer,
auth interceptor coverage, `git diff --check`, and Sol low review are complete.

## Task occurrence completion and archived history (2026-09-23)

Status: implementation complete; focused verification is recorded in
`task.md` and `walkthrough.md`.

- Keep the latest started recurring occurrence visibly completed until the
  next scheduled boundary. Completed takes precedence over overdue.
- Keep non-recurring tasks completed until explicitly reopened.
- Show the current completed occurrence in the Tasks list and preserve the
  separate historical screen. Reopen uses the displayed occurrence identity.
- Keep note task operations in the REST/OT document path and independent task
  operations in the TaskRepository/outbox path.
- Keep the note checkbox checked after animation, refresh at the next
  occurrence boundary without a document operation, and respect hide-completed.
- Archive schedule history separately in `completionHistory`. Records retain
  the original civil `scheduledAt`, original `hasTime`, and UTC `completedAt`;
  `scheduledAt` is nullable for tasks completed before they had a date.
- Independent task history lives in Drift and Postgres. Note task history lives
  in TaskNode metadata. The server archives transactionally on schedule edits;
  migrations start with an empty archive and infer no lost history.
- Keep reminder resolution on the next eligible occurrence after completion.
- Exclude blocked outbox operations from local rebase.
- Enforce the note-task schedule/history invariant in the REST/OT document
  service. The client sends schedule, archive, and active-state clear in one
  metadata operation; the server rejects changes that would lose completions.
