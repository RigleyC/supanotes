# Implementation Plan: Apple Notes-style Autosave

## Context

O `CONTEXT.md` define:
> **"save" versus "sync"**: A **save** is a local persistence operation (Drift). A **sync** is a network push/pull operation. The user should never perceive either; the UI reflects the local database immediately. The network is an implementation detail.

> **"flush"**: A **flush** is an immediate, synchronous-or-near-synchronous **save** that bypasses the debounce. Used when the user leaves the editing surface so that no in-flight edits are lost.

## Goal

Fazer o autosave do SupaNotes funcionar igual ao Apple Notes: transparente, imediato, e sem preocupação para o usuário.

## Decisions (resolved)

1. **Save local + sync background**: O usuário nunca vê "salvando" ou "sincronizando". A UI reflete o banco local imediatamente.
2. **Erro de save local**: retry silencioso com backoff. Nunca mostrar UI de erro para falha de save local.
3. **Flush no pop**: `PopScope` salva imediatamente antes de sair. O `await` espera o save local completar (delay imperceptível, <100ms).
4. **Debounce 500ms**: Reduzido de 2000ms para 500ms. O save local acontece mais rápido, parecendo instantâneo.
5. **Remover `SaveIndicator`**: O `editorStatusProvider`, `EditorStatus`, `SaveIndicator`, e `editor_status_notifier.dart` foram removidos. Não há mais indicador visual de save.

## Changes

### Frontend

#### `lib/core/constants/app_constants.dart`
- **Change**: `autoSaveDebounceMs` de `2000` para `500`

#### `lib/features/notes/presentation/note_editor_screen.dart`
- **Add**: `PopScope` com `canPop: false` + `onPopInvokedWithResult` que faz `await _flushBeforePop()`
- **Add**: `Future<void> _flushBeforePop()` que:
  1. Cancela debounce
  2. Chama `_flushContentSave` e `_flushTitleSave` com `await`
  3. Depois faz `context.pop()`
- **Remove**: Todas referências a `editorStatusProvider` (já feito)
- **Remove**: `SaveIndicator` da AppBar (já feito)

#### `lib/features/notes/presentation/inbox_screen.dart`
- **Remove**: Todas referências a `editorStatusProvider` (já feito)
- **Remove**: `SaveIndicator` da AppBar (já feito)
- **Keep**: `PopScope` + `_saveAndPop()` já existe — o `flush` já funciona. Não precisa mudar.

#### `lib/features/notes/presentation/controllers/editor_status_notifier.dart`
- **Remove**: Arquivo deletado (já feito)

#### `lib/features/notes/presentation/widgets/save_indicator.dart`
- **Remove**: Arquivo deletado (já feito)

#### `lib/features/notes/domain/editor_status.dart`
- **Remove**: Arquivo deletado (já feito)

### Backend

Nenhuma mudança no backend. O sync continua funcionando com o `SyncService` existente (push/pull a cada 30s ou quando detecta conexão).

## Verification

- [ ] Digitar no editor → esperar 500ms → verificar se `isDirty = true` no banco
- [ ] Digitar no editor → apertar back antes de 500ms → verificar se o pop deu flush e o dado foi salvo
- [ ] Verificar se `SaveIndicator` não aparece em nenhuma tela
- [ ] Verificar se o sync continua funcionando (push/pull)
- [ ] Verificar se não há referências a `editorStatusProvider` no código

## Notes

- O `TODO: log internal error` nos `catch` blocks é intencional. O log será adicionado futuramente (não é prioridade agora).
- O `sync` pra rede é **não-blocking** — o `SyncService` roda em background. O usuário nunca espera o sync.
- O `InboxScreen` já tinha `PopScope` + `_saveAndPop()`. Não precisou mudar.
