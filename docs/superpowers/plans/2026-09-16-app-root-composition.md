# App root composition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Separar o bootstrap do processo da composição da aplicação sem alterar o comportamento dos runtimes ou das rotas.

**Architecture:** `main.dart` inicializa o Flutter, plataforma, timezone, locale, preferências e o `ProviderContainer`, depois chama `runApp`. `SupaNotesApp` e sua orquestração Riverpod permanecem juntas em `lib/app/supa_notes_app.dart`, onde também ficam `MaterialApp.router`, temas, overlays e listeners globais.

**Tech Stack:** Flutter, Riverpod manual, GoRouter e `adaptive_platform_ui`.

**Spec:** `docs/superpowers/specs/2026-09-03-standalone-tasks-tabs-design.md`

## Global Constraints

- Não alterar contratos de share, sync, notificações ou app links nesta refatoração.
- Preservar a ordem atual de ativação e o ciclo de vida dos providers.
- Manter `SnackOverlay` no builder do `MaterialApp.router`, apenas movendo-o para o arquivo de composição.
- Preservar mudanças não relacionadas já presentes no worktree.
- Validar somente comportamento e compilação; não adicionar testes visuais.

---

### Task 1: Extrair a composição da aplicação

**Files:**
- Create: `lib/app/supa_notes_app.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- `SupaNotesApp` continua público e sem parâmetros, mantendo o mesmo ponto de entrada usado por `runApp`.
- O `ProviderContainer` continua criado uma única vez em `main.dart` e injetado via `UncontrolledProviderScope`.

- [x] Mover `SupaNotesApp` e `_SupaNotesAppState` integralmente para o novo arquivo.
- [x] Mover os imports usados apenas pela composição para `supa_notes_app.dart`.
- [x] Reduzir `main.dart` aos imports e responsabilidades de bootstrap.
- [x] Confirmar que router, listeners, temas, overlays e ordem de lifecycle permanecem byte-a-byte equivalentes.

### Task 2: Validar a extração

**Files:**
- Test: `test/features/tasks/presentation/tasks_screen_test.dart`
- Test: `test/shared/widgets/app_snackbar_test.dart`

- [x] Rodar `dart format` nos dois arquivos Dart alterados/criados.
- [x] Rodar os testes comportamentais focados de Tasks e SnackOverlay.
- [x] Rodar `dart analyze lib/app/supa_notes_app.dart lib/main.dart`.
- [x] Rodar `git diff --check` e confirmar que nenhum arquivo não relacionado foi staged.

---
