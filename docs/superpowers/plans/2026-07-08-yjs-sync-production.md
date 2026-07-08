# Yjs Sync — Produção (Plano C)

> **For agentic workers:** Disparar agents em paralelo para tasks independentes. Tasks A-B-C-D-E podem rodar em paralelo.

**Goal:** Tornar a feature de sync Yjs pronta para produção, resolvendo todos os blockers da auditoria.

**Arquitetura:** Aditivo nos paths existentes. Nenhuma mudança no protocolo WS. Foco em: (1) tombstoning de deleções na projeção, (2) completar o path local→remoto (NodeSyncManager → Yjs Doc → WS), (3) habilitar broadcast de push REST para clientes WS, (4) limpeza de dead code.

---

## Tasks

### Task A: Deletion tombstoning na projeção (client + server)

**Files:**
- Modify: `lib/core/sync/yjs_sync_manager.dart` — `_projectToNodes` deve soft-delete nós que sumiram do YMap
- Modify: `backend/internal/sync/projection.go` — `projectDocToDB` deve soft-delete nodes/tasks ausentes do YMap

**Mudanças:**
- Client: antes do batch insert, fetch IDs existentes em `note_nodes` pra note, compute diff vs YMap keys, soft-delete os que sumiram
- Server: mesmo pattern dentro da tx com advisory lock, query `GetNodesByNoteId` / `GetTasksByNoteId`, diff vs YMap keys, `UPDATE note_nodes SET deleted_at=NOW() WHERE note_id=$1 AND id NOT IN (...)`

- [ ] Step 1: Implementar client side
- [ ] Step 2: Implementar server side
- [ ] Step 3: Testar

### Task B: Task completed_at na projeção (server)

**Files:**
- Modify: `backend/internal/sync/projection.go` — adicionar `SetCompletedAt` no `UpsertTaskParams` + SQL
- Modify (if needed): `backend/internal/db/queries/sync.sql` — adicionar `completed_at` no `ON CONFLICT DO UPDATE`
- Regenerate sqlc

**Mudanças:**
- `taskJSON` já tem `CompletedAt` (`projection.go:39`)
- `UpsertTask` SQL precisa incluir `completed_at` no UPDATE
- Gerar sqlc

- [ ] Step 1: Adicionar `completed_at` no SQL upsert
- [ ] Step 2: Regenerar sqlc
- [ ] Step 3: Testar

### Task C: BroadcastIfActive no REST push

**Files:**
- Modify: `backend/internal/sync/service.go` — chamar `BroadcastIfActive` após `ApplyNodeMutation`

**Mudanças:**
- No loop de `nodesByNote` em `Push`, após `ApplyNodeMutation`, chamar `BroadcastIfActive(noteIDStr, update)` para notificar clientes WS conectados

- [ ] Step 1: Adicionar chamada
- [ ] Step 2: Verificar se YDocService expõe acesso ao pool para BroadcastIfActive

### Task D: Fix connectNote race + lifecycle

**Files:**
- Modify: `lib/features/notes/presentation/controllers/note_editor_provider.dart`

**Mudanças:**
- `connectNote` precisa ser awaited com `.catchError`
- Guard contra execução após dispose
- Usar um token de cancelamento (AtomicBool) para ignorar callback se provider já foi disposed

- [ ] Step 1: Adicionar `_disposed` flag no provider
- [ ] Step 2: Envolver connectNote em try/catch com guard
- [ ] Step 3: Testar

### Task E: Local→Remote Yjs bridge

**Files:**
- Modify: `lib/features/notes/domain/node_sync_manager.dart` — adicionar `onFlush` callback
- Modify: `lib/features/notes/domain/yjs_doc_editor_bridge.dart` — adicionar `sendUpdate`
- Modify: `lib/features/notes/domain/yjs_node_codec.dart` — adicionar helper para aplicar op individual ao Doc
- Modify: `lib/features/notes/presentation/controllers/note_editor_controller.dart` — aceitar `sendUpdate`
- Modify: `lib/features/notes/presentation/controllers/note_editor_provider.dart` — passar `sendUpdate`

**Mudanças:**
- `NodeSyncManager._drainQueue` após commit chama `onFlush(ops)` se definido
- Bridge implementa `onFlush` aplicando cada op ao Yjs Doc via transact
- Yjs Doc `observeUpdates` (ou após transact) coleta o update e chama `sendUpdate`

- [ ] Step 1: Adicionar callback em NodeSyncManager
- [ ] Step 2: Implementar bridge onFlush
- [ ] Step 3: Wire no controller/provider
- [ ] Step 4: Testar

### Task F: Clean up dead code

**Files:**
- Modify: `lib/core/sync/yjs_sync_manager.dart` — remover `saveState`, `nodeExists`, `unloadDoc`, `_nodeExistence`
- Modify: `lib/features/notes/presentation/controllers/note_editor_controller.dart` — remover `emptyNoteExit` dead code
- Modify: `backend/internal/sync/service.go` — remover `sanitizeTaskStatus`, `isEmptyIncomingRegularNote`
- Modify: `backend/internal/sync/ws_handler.go` — remover `var _ = pgx.ErrNoRows` e import
- Delete: `backend/internal/sync/ot/` (empty dir)
- Modify: `backend/internal/sync/room.go` — remover `BroadcastIfActive` se não usada OU mantê-la se Task C a usa

### Task G: Remover isDirty de note_nodes e tasks

**Files:**
- Modify: `lib/core/database/tables/note_nodes.dart` — remover coluna isDirty
- Modify: `lib/core/database/tables/tasks.dart` — remover coluna isDirty
- Modify: `lib/core/sync/sync_service.dart` — remover filtro isDirty de push para note_nodes/tasks
- Modify: `lib/features/notes/domain/node_sync_manager.dart` — remover `locallyDirtyNodeIds` para note_nodes/tasks
- Drift: regenerar
