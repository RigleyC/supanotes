# Plan 058: Concluir a arquitetura Yjs-first (correções + visão de dois níveis de CRDT)

> **Executor instructions**: Follow this plan phase by phase. Run every
> verification command and confirm the expected result before moving to the
> next phase. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 2be0c77..HEAD -- backend/internal/sync backend/internal/agent backend/internal/notes backend/internal/tasks backend/db/queries lib/core/sync lib/features/notes/domain lib/features/notes/data lib/features/notes/presentation/controllers lib/features/notes/presentation/widgets`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: L (phased — P0/P1 are S–M, P2–P6 are M–L)
- **Risk**: MED (P0/P1 LOW, P4/P5 MED — touch the editor-sync core)
- **Depends on**: none (supersedes elements of 058-indexed prior plans for sync)
- **Category**: tech-debt + direction + bug
- **Planned at**: commit `2be0c77`, 2026-07-13

## Why this matters

A migração para YDoc está ~70% pronta: o YDoc é a fonte de verdade no editor e no sync WS, mas a camada de projeção (backend) está incompleta (não ordena nós, não apaga tasks órfãs, não reindexa embeddings, não deriva `task_completions`), o agente não propaga edições em tempo real, o completar task pelo dashboard bypassa o YDoc (e é revertido pela projeção), e notas editadas offline nunca sobem. Além disso, a visão de arquitetura enviada pelo usuário vai além da ADR 0005: tasks devem ser CRDTs independentes (Y.Map por task), o agente deve operar via operações granulares (não reconstruindo o doc inteiro), e há espaço para presence e notificações event-driven. Este plano fecha as lacunas de correção e leva a implementação à visão completa.

## Current state

Fatos que o executor precisa, emlined — não "como discutido":

- **ADR**: `docs/adr/0005-yjs-first-sync-architecture.md` — YDoc é fonte de verdade; `notes.content`/`tasks`/`task_completions`/embeddings são projeções read-only; recorrência roda no cliente; agente escreve só via Yjs.
- **CONTEXT.md**: `Note` = YDoc; `Task` = nó com metadata (não entidade independente); `Projection` = derivada read-only.
- `backend/internal/sync/projection.go:124-178` — `deriveMarkdownFromDoc` itera `nodesMap.Keys()` (ordem de inserção), **ignora `position`** → conteúdo/título fora de ordem.
- `backend/internal/sync/projection.go:78-96` — `ProjectNoteContentFromYDoc` só upserta tasks; **não apaga** tasks órfãs; **não escreve `task_completions`**.
- `backend/internal/sync/room.go:124` — `RoomManager.BroadcastIfActive` existe mas **tem zero chamadores**; mutações do agente (`agent/service.go:20` → `YDocService.ApplyNodeMutation`) aplicam+bufferam+projetam mas não broadcastam.
- `backend/internal/tasks/service.go:170-235` — `CompleteTask` escreve direto em `tasks`+`task_completions` (bypass do YDoc); a próxima projeção reverte `completed` para `false`.
- `backend/db/queries/notes.sql:130-131` — `UpdateNoteContent` atualiza content/excerpt mas **não marca `embedding_status='pending'`**; nada dispara o worker de embeddings.
- `backend/internal/agent/tools/notes_tools.go:250-277` — `AppendToNoteTool` cria doc novo com `GenerateKeyBetween("", "")` **sem ler a posição máxima existente** → nós novos ordenam antes dos existentes.
- `lib/core/sync/sync_service.dart:238-309` — `push()` envia notes/contexts/tags/links/prefs mas **não envia `local_yjs_states`**; WS só conecta para a nota ativa. Notas editadas offline e não reabertas nunca sincronizam.
- `lib/core/sync/yjs_sync_manager.dart:48-132` — `_reconstructFromContent` reconstrói YDoc de `notes.content` (markdown) quando não há `local_yjs_states`; diverge do estado do servidor e pode sobrescrever/merge incorreto.
- `backend/internal/sync/service.go:182` — `UpsertNote` com `Content: ""` + comentário stale "trigger from note_nodes" (trigger não existe desde a migration 000033).
- `backend/db/queries/sync.sql:46-58` — `UpsertTask` ainda referencia coluna `node_id` (órfã após drop de `note_nodes`).
- `lib/features/notes/domain/yjs_doc_editor_bridge.dart` e `backend/internal/agent/tools/notes_tools.go` — task é `{completed, indent, ...}` inline no `data` do nó do YDoc; **não** é um `Y.Map` CRDT independente.
- **Modelo atual**: `YDoc → YMap("nodes")` onde cada entry é um JSON string com `{id, type, position, data:{text,completed,dueDate,recurrence}}` + `YText("content/<id>")`. Não há `YMap("tasks")`.

### Convenções a honrar

- Go: handlers finos, lógica em services, logs estruturados (`log/slog`), SQL via sqlc (`make sqlc` regenera `backend/internal/db/sqlcgen/`).
- Flutter: Riverpod 3.x manual (sem codegen), `AsyncValue.when`, `super_editor`, snake_case em arquivos. Ver `AGENTS.md` e `RIVERPOD.md`.
- Sync wire: WebSocket Yjs sync protocol para notas; REST só CRUD entities (contexts, tags, links, prefs).
- Commit: Conventional Commits (`type(scope): desc`).

## Commands you will need

| Purpose          | Command                                            | Expected on success |
|------------------|----------------------------------------------------|---------------------|
| Build backend    | `cd backend && go build ./...`                     | exit 0              |
| Lint backend     | `cd backend && go vet ./...`                       | exit 0              |
| Test backend     | `cd backend && go test ./internal/sync/... ./internal/agent/... ./internal/notes/... ./internal/tasks/...` | all pass |
| Regenerate sqlc  | `cd backend && sqlc generate`                      | exit 0, no diff in git except sqlcgen/ |
| Migrate DB       | `cd backend && go run ./cmd/migrate up`            | applied             |
| Analyze Flutter  | `flutter analyze`                                  | exit 0, no errors   |
| Test Flutter     | `flutter test`                                     | all pass            |
| Build runner     | `dart run build_runner build --delete-conflicting-outputs` | exit 0        |

## Scope

**In scope** (arquivos que o plano modifica; detalhado por fase em "Steps"):
- Backend: `internal/sync/{projection.go,ydoc_service.go,room.go,service.go,handler.go}`, `internal/agent/{service.go,tools/notes_tools.go,operations/...}`, `internal/notes/service.go`, `internal/tasks/service.go`, `db/queries/{notes.sql,sync.sql,tasks.sql}`, `db/migrations/000034_*.sql`, `internal/embeddings/...`.
- Flutter: `lib/core/sync/{sync_service.dart,sync_mapper.dart,yjs_sync_manager.dart,yjs_websocket_client.dart}`, `lib/features/notes/domain/{yjs_doc_editor_bridge.dart,yjs_node_codec.dart,note_sync_coordinator.dart,note_node.dart,task_*}`, `lib/features/tasks/data/local/tasks_local_repository.dart`, `lib/features/notes/presentation/...`.

**Out of scope**:
- Redis/Presence externo (P6 usa memória; Redis é pós-plano).
- Reescrita do editor (super_editor permanece; só muda a ponte YDoc↔nó).
- TS/TS-like stack (continueg em Dart+Go).
- Migração de dados de produção (script de verificação `note_yjs_states` vs `note_nodes` é pré-existente e fora deste plano — assumir que já rodou).

## Git workflow

- Branch: `feat/yjs-architecture-completion` (ou `fix/` para P0).
- Commit por fase/passio lógico, Conventional Commits: `fix(sync): order projection nodes by position`, `feat(agent): broadcast mutations to WS rooms`, etc.
- Não push/PR senão instruído.

## Steps (fases)

As fases P0–P2 são corretivas e têm alta confiança. P3–P6 alinham à visão e podem ser executadas incrementalmente; cada uma deixa o sistema funcional ao fim.

---

### Phase 0 — Correções de projeção e sync (correctness, blocking)

Objetivo: a projeção backend refletir fielmente o YDoc, e edições chegarem a todos os clientes.

#### Step 0.1 — Ordenar nós por `position` na projeção

`backend/internal/sync/projection.go`: em `deriveMarkdownFromDoc` e `deriveTasksFromDoc`, coletar `(position, key)` antes de iterar e ordenar por `position` (string fractional indexing — mesma comparação usada em `lib/core/utils/fractional_indexing.dart` e `pkg/utils`). Não há helper Go; adicionar `sortByPosition` local comparando strings lexicograficamente (o `fractional_indexing_dart` gera strings Monroe-orderable).

Alvo:
```go
type nodeMeta struct { Position string; Key string; Data json.RawMessage; Type string }
metas := /* decodificar */ 
sort.Slice(metas, func(i,j int) bool { return metas[i].Position < metas[j].Position })
// iterar metas em ordem
```

**Verify**: novo teste `backend/internal/sync/projection_test.go` — constrói um `crdt.Doc` com 3 nós em posições não-inserção (c, a, b); asserta `deriveMarkdownFromDoc` retorna linhas em ordem a,b,c. `cd backend && go test ./internal/sync/ -run TestProjectionOrdersByPosition` → PASS.

#### Step 0.2 — Apagar tasks órfãs na projeção

`projection.go::ProjectNoteContentFromYDoc`: antes do loop de upsert, consultar `SELECT id FROM tasks WHERE note_id = $1` e computar o conjunto de IDs presentes no YDoc (`deriveTasksFromDoc`); deletar os ausentes via `q.DeleteTasks` (nova query ou `DELETE FROM tasks WHERE note_id = $1 AND id <> ALL($2::uuid[])`). Tratar o caso de task removida do documento preservando `task_completions` (não cascatear).

**Verify**: teste insere task via YDoc, projeta, remove nó do YDoc, reprojeta → `SELECT count(*) FROM tasks WHERE note_id=$1` == 0; `task_completions` preservadas.

#### Step 0.3 — Reindexar embeddings ao projetar

`db/queries/notes.sql::UpdateNoteContent`: adicionar `embedding_status = 'pending'` ao UPDATE (ou criar query `UpdateNoteContentAndMarkPending`). Regenerar sqlc. Confirmar que o worker existente em `internal/embeddings` consome `embedding_status='pending'`.

**Verify**: `grep -n "embedding_status" backend/db/queries/notes.sql` mostra a mudanote; teste de projeção → `SELECT embedding_status FROM notes WHERE id=$1` == `pending`.

#### Step 0.4 — Broadcast agente → clientes WS

`backend/internal/sync/ydoc_service.go::ApplyNodeMutationLocked` (ou um wrapper em `service.go::service.Push` para o path do agente): após aplicar+buffer+projetar, chamar `s.roomMgr.BroadcastIfActive(noteID, update)` com o `payload` (update crudo) — note que `BroadcastIfActive` já reenquadra com `ygsync.EncodeUpdate`. Para path REST Push de Yjs state (P2), idem após aplicar o update.

Adicionar dependência de `RoomManager` em `YDocService` (ou passar via construtor/Setter para evitar ciclo).

**Verify**: teste `backend/internal/sync/room_integration_test.go` — agente aplica update numa note com 1 cliente WS conectado; asserta cliente recebeu framed update. `go test ./internal/sync/ -run TestAgentBroadcasts` → PASS.

#### Step 0.5 — `append_to_note` posiciona no fim

`backend/internal/agent/tools/notes_tools.go::AppendToNoteTool.Execute`: antes de construir doc novo, chamar `LoadYDocState` (ou `YDocService.DocFor`) para obter a posição máxima existente; usar `GenerateKeyBetween(maxPos, "")`. Se preferir não carregar o doc: query em `note_yjs_states`+`note_yjs_updates` p/ `DocFor`.

Alvo:
```go
existing, _ := t.yjsSvc.DocFor(ctx, formatID(nid)) // pode propagar erro
// ler max position de existing.GetMap("nodes")
```

**Verify**: teste cria note com 2 nós, chama append → projeta → `notes.content` termina com conteúdo original + appended.

#### Step 0.6 — Limpeza pós-migração

- `backend/internal/sync/service.go:182`: trocar `Content: ""` por `Content: n.Content` (ou manter vazio só se realmente derivado) e remover comentário stale.
- `backend/db/queries/sync.sql`: remover `node_id` de `UpsertTask` (e params Go). Migration `000034_drop_tasks_node_id.up.sql`: `ALTER TABLE tasks DROP COLUMN IF EXISTS node_id;` + down.
- Deletar ou marcar `// Deprecated: remove after note_nodes dropped` em `backend/restore_notes.go`, `backend/reindex_notes.go`, `backend/cmd/remigrate/` (referenciam `note_nodes`; quebrarão se rodados — adicionar `_ "unsafe"` guard ou deletar os arquivos).
- Atualizar `CONTEXT.md` removendo referência a `note_nodes` para título.

**Verify**: `grep -rn "note_nodes" backend/internal backend/db` → 0 matches (exceto migrations históricas 024–032 e `backup.sql`); `go build ./...` → exit 0.

---

### Phase 1 — YDoc como única fonte de verdade para task state

Objetivo: completar task pelo dashboard/CLI passa pelo YDoc; `task_completions` derivado da projeção.

#### Step 1.1 — Operações de task via YDoc no backend

Criar `backend/internal/agent/operations/task_ops.go` (ou `internal/tasks/yjs_mutation.go`) com:
- `CompleteTaskYjs(ctx, ydocSvc, noteID, nodeID)`: `WithDoc` → set `data.completed=true`, `data.lastCompletedAt=now` (e recorrência: reset + `dueDate=next`); retorna update.
- `ReopenTaskYjs`, `UpdateTaskPriorityYjs` (se existir prioridade), `SetDueDateYjs`.

`tasks/service.go::CompleteTask` deixa de escrever em SQL diretamente; delega para `CompleteTaskYjs` e dispara projeção. `task_completions` deixa de ser escrita por aqui.

**Verify**: teste `backend/internal/tasks/service_test.go` — complete task → le YDoc → `data.completed==true` && `data.lastCompletedAt` set; `SELECT FROM tasks` espelha YDoc após projeção.

#### Step 1.2 — Projeção deriva `task_completions` de `lastCompletedAt`

`projection.go`: comparar `lastCompletedAt` anterior (lido de `tasks` antes do upsert) com o novo; se transicionou de nil → tempo, inserir em `task_completions(id, task_id, completed_at, user_id)` (id UUID v5 do nodeID+timestamp). Reabrir → não deletar (histórico imutável).

**Verify**: teste completa, reabre, completa de novo → 2 rows em `task_completions` com `completed_at` distintos.

#### Step 1.3 — Recorrência no cliente (Flutter)

`lib/features/tasks/...` ao completar task recorrente: passa `dueDate` + `completed=false` para o YDoc no mesmo update (lógica `calculateNextDueDate` já existe em `backend/internal/tasks/service.go:305` — portar para `lib/core/utils/`). Remover recorrência do `tasks.Service.CompleteTask` Go (fica só no cliente).

**Verify**: teste Flutter completa task `daily` → nó no YDoc tem `completed=false`, `dueDate=amanhã`; projeção → `tasks` row `status=open`, `due_date=amanhã`.

#### Step 1.4 — Remover escritas diretas de tasks do REST Push

`sync/service.go::Push`: remover loop `payload.TaskCompletions` e campo de `SyncPayload`; `sync_mapper.dart` já não envia tasks/completions. `SyncPayload` perde `TaskCompletions`.

**Verify**: `grep -n "TaskCompletions" backend/internal/sync` → 0; `go build ./...` → exit 0.

---

### Phase 2 — Offline YDoc sync via REST (fechar o gap)

Objetivo: notas editadas offline (não ativas no WS) atinjam o servidor.

#### Step 2.1 — Flutter envia `local_yjs_states` no push

`lib/core/sync/sync_service.dart::push`: enviar entradas de `local_yjs_states` marcadas dirty (introduzir `isDirty` em `LocalYjsStates` Drift table — ou usar `updatedAt` > `lastSyncedAt`). `sync_mapper.dart`: `localYjsStateToJson` (base64 state). Payload: `note_yjs_states: [...]`.

#### Step 2.2 — Backend aplica estados Yjs no Push

`sync/service.go::Push`: para cada `note_yjs_states` no payload, aplicar via `YDocService.ApplyNodeMutation` (merge do state remoto no doc cache) e `FlushUpdates`. Tratar conflito de room ativa: se room existe para a note, NÃO mutar via REST (o WS é canônico) — enfileirar para compaction.

#### Step 2.3 — Remover `_reconstructFromContent` fallback

`lib/core/sync/yjs_sync_manager.dart:48-132`: deletar `_reconstructFromContent`; `loadDoc` retorna doc vazio quando não há `local_yjs_states` (servidor entrega via WS/REST). Adicionar migração Drift que garanta `local_yjs_states` populado para notes existentes (via pull).

**Verify**: teste Flutter — note sem `local_yjs_states`, `loadDoc` → doc vazio; após pull, `local_yjs_states` existe; `loadDoc` → doc populado.

---

### Phase 3 — Árvore de blocos com IDs imutáveis e ordenação robusta

Objetivo: mover/ordenar blocos sem depender de offsets; `position` gerenciado consistentemente.

#### Step 3.1 — Documentar invariante de block-id

`docs/adr/0006-block-tree-invariants.md` (novo ADR): block-id imutável em `nodes` YMap key; `position` fractional indexing (não YArray) decicão ADR 0005; mover = regravar `position` no YMap entry; AI/comentários referenciam block-id.

#### Step 3.2 — Helper central de posição

Mover/portar `GenerateKeyBetween` para backend Go (`pkg/utils/fractional.go` se não existir). `yjs_doc_editor_bridge.dart::_calcPosition` já usa; padronizar.

**Verify**: teste Go `fractional_test.go` cobrindo entre, início, fim, reset de dedup.

---

### Phase 4 — Dois níveis de CRDT (task como Y.Map)

Objetivo: alinhar à visão do usuário: task como `Y.Map` independente, nó do doc referencia `taskId`.

> ⚠️ Esta fase migra o schema do YDoc. Requer estratégia de compat (ler doc legado e migrar on-load — Â la `_reconstructFromContent` mas YDoc→YDoc).

#### Step 4.1 — Novo schema YDoc

```
YDoc
├── YMap "nodes" → {id, parentId, position, type, data:{taskId?}}  // data NÃO contém completed/dueDate
└── YMap "tasks" → { taskId -> Y.Map { title, completed, dueDate, recurrence, priority, assignee, lastCompletedAt } }
```

`YMap("tasks")` com `setAttr(taskId, YMap(...))` — ou, se `dart_crdt` suporta YMap aninhado, usar nativo. Senão, JSON CRDT-friendly (cada field como attr da YMap da task).

#### Step 4.2 — Bridge/Codec adaptado

`yjs_node_codec.dart::noteNodesFromDoc`: nó `type=task` → `data.taskId` (não `completed`). Novo `taskEntriesFromDoc(doc)` lendo `YMap("tasks")`. `yjs_doc_editor_bridge.dart::_serializeNode` para task só escreve `taskId`; `completed`/`dueDate` vão para `YMap("tasks")` via helper `setTaskField`.

#### Step 4.3 — TaskWidget observa YMap da task

`lib/features/notes/presentation/...` task node widget: observa `doc.getMap("tasks").getAttr(taskId)` (ou stream) e rebuild em mudança — mudar `completed` não toca o nó do documento.

#### Step 4.4 — Projeção lê dois níveis

`projection.go::deriveTasksFromDoc`: itera `YMap("tasks")` (não `nodes`); título de `YText("content/<nodeId>")` vinculado via map `taskId→nodeId` (ou armazenar `nodeId` no YMap da task). `deriveMarkdownFromDoc`: nó task.renderiza checkbox conforme `tasks[taskId].completed`.

#### Step 4.5 — Migração de doc legado

On-load (Flutter `YjsSyncManager.loadDoc` e backend `YDocService.DocFor`): detectar `YMap("tasks")` ausente e migrar entradas antigas (nós com `data.completed`) → criar YMap da task; remover `completed` do `data` do nó. Rodar dentro de `transact`.

**Verify**: teste converte doc legado → novo schema; `noteNodesFromDoc` não vê `completed` no data; `taskEntriesFromDoc` tem 1 entry com `completed`. Reabrir/convergência CRDT entre 2 clientes editando campos diferentes da mesma task.

---

### Phase 5 — Agente como executor de operações

Objetivo: IA usa operações declarativas, aplicadas ao YDoc pelo mesmo caminho que um usuário.

#### Step 5.1 — Vocabulário de operações

`backend/internal/agent/operations/operations.go`: `MoveBlock(nodeID, afterNodeID)`, `CreateTask(nodeID, title)`, `UpdateTaskField(taskID, field, value)`, `CompleteTask(taskID)`, `InsertParagraph(nodeID, text, afterNodeID)`, `DeleteBlock(nodeID)`. Cada operação = função `Apply(doc) → []byte update`.

#### Step 5.2 — Executor

`backend/internal/agent/executor.go`: `Execute(ctx, noteID, ops []Op)`: `YDocService.WithDoc` → aplica cada op dentro de `doc.Transact` → `crdt.EncodeStateAsUpdateV1` → `ApplyNodeMutation` (que já projeta+broadcasta P0.4).

#### Step 5.3 — Ferramentas do agente emitem ops

`notes_tools.go`: `AddNoteTool`/`AppendToNoteTool` refatorados para emitir `[InsertParagraph, CreateTask, ...]` ao invés de construir doc do zero. Nova `CompleteTaskTool`, `MoveBlockTool`, `UpdateTaskFieldTool`.

**Verify**: teste `append_to_note` produz 1 op `InsertParagraph` por linha; `CompleteTaskTool` → `data.completed==true` && WS broadcasta.

---

### Phase 6 — Presence (em memória) e notificações event-driven

> Estes são P3 na prioridade; descrever mas podem ficar para plano separado.

#### Step 6.1 — Protocolo de presence

WS mensagens JSON: `{"type":"presence","user_id":..,"cursor":{nodeId,offset},"selection":...}`. `Room` mantém `map[userID]presence` em memória; broadcast em N ms. Redis fica fora (ADR futura).

#### Step 6.2 — Event bus + NotificationService

`backend/internal/notifications/`: event bus interno (`chan`/observer). `TaskCompletedEvent` emitido pela projeção; `NotificationService` despacha para push/email/telegram existentes. `tasks.Service` para de notificar direto.

---

## Test plan

- **Backend (por fase)**: P0 — `projection_test.go` (ordem, órfã, embedding), `room_integration_test.go` (broadcast agente). P1 — `tasks/service_test.go` (complete via YDoc, recorrência cliente), `projection_task_completions_test.go`. P2 — `service_test.go` (push aplica Yjs state), `yjs_sync_manager_test.dart` (sem fallback). P3 — `fractional_test.go`. P4 — `task_ymap_test.go` (migração + concorrência). P5 — `executor_test.go`, `operations_test.go`.
- Padrão estrutural: `backend/internal/sync/compactor_integration_test.go` (Go, setup real pool/mock) e `backend/internal/agent/service_test.go` (fake `yDocIngest`).
- **Flutter**: `test/crdt_validation/crdt_convergence_test.dart` como padrão para convergência; novo `yjs_doc_editor_bridge_test.dart` para P3/P4.
- Verificação final: `cd backend && go test ./... && go vet ./...` + `flutter analyze && flutter test` → todos passam.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `cd backend && go build ./...` exit 0
- [ ] `cd backend && go vet ./...` exit 0
- [ ] `cd backend && go test ./internal/sync/... ./internal/agent/... ./internal/notes/... ./internal/tasks/...` all pass
- [ ] `flutter analyze` exit 0
- [ ] `flutter test` all pass (incl. novos testes de P0/P1/P4)
- [ ] `grep -rn "note_nodes" backend/internal backend/db/queries` → 0 matches (migrations históricas 024–033 e `backup.sql`除外)
- [ ] `BroadcastIfActive` tem ≥1 chamador (`grep -n "BroadcastIfActive" backend`)
- [ ] `deriveMarkdownFromDoc` ordena por `position` (teste dedicado passa)
- [ ] Projeção deleta tasks órfãs (teste dedicado passa)
- [ ] `UpdateNoteContent` marca `embedding_status='pending'`
- [ ] `tasks.Service.CompleteTask` não escreve em `tasks` diretamente (escreve YDoc)
- [ ] Projeção deriva `task_completions` de `lastCompletedAt`
- [ ] `SyncService.push` envia `note_yjs_states`
- [ ] `_reconstructFromContent` removido
- [ ] `plans/README.md` status row atualizado

## STOP conditions

Stop and report back (do not improvise) if:

- O código em "Current state" não corresponde aos excertos (drift desde `2be0c77`).
- Um passo falha verificação 2x após correção razoável.
- O fix parece exigir tocar arquivo fora do escopo.
- `dart_crdt` não suporta `YMap` aninhado necessário para P4 (reporte e adapte para JSON attr antes de avançar).
- Descobrir que `note_yjs_states` de notas existentes em produção está incompleto/inconsistente (a ADR 0005 exige verificação prévia — não execute P0.6/drop sem isso).
- `sqlc generate` introduz diff inesperado fora de `internal/db/sqlcgen/`.

## Maintenance notes

- **P0/P1** devem landar antes de P4 (migração de schema de task): a projeção que apaga órfãs e deriva `task_completions` é pré-requisito do schema de dois níveis.
- P2 (offline REST) pode ser adiado se o app for sempre online para notas ativas; mas "offline-first" é um princípio do produto (AGENTS.md/ADR) — recomenda-se não pular.
- P4 (YMap por task) muda o wire YDoc: depois de deploy, clientes antigos e novos coexistem só com a migração on-load (4.5); nunca remover a migração antes de todos os clientes atualizados.
- P5 (ops do agente) substitui o construção-de-doc do `add_note`/`append_to_note` — revisar uso em `internal/agent/context.go` e `routines`.
- Revisão PR: escrutinar P0.4 (race entre broadcast WS e flush Buffers) e P4.5 (idempotência da migração de doc).
- Follow-up explícito fora do plano: presence em Redis (P6.1), full-text search reindexação incremental, snapshots ADR (compactor já existe — documentar em ADR 0007).