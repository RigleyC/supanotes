# Plano de Implementação: Sincronização, Migração e Tradução de Nodes para o Agente

**Objetivo:** Remover por completo o Markdown (.md) como formato de persistência e sincronização de dados. O Flutter e o Go backend sincronizarão `note_nodes` nativos diretamente. O Go backend atuará como "tradutor on-demand" para o Agente de IA, gerando Markdown dinamicamente quando o Agente ler uma nota, e parseando o Markdown gerado pelo Agente de volta para a estrutura de Nós ao criar ou anexar conteúdo.

---

### Task 1: Migração de Banco (Backend) — soft-delete para Nodes

**Arquivos:**
- Create: `backend/db/migrations/000025_add_deleted_at_to_note_nodes.up.sql`
- Create: `backend/db/migrations/000025_add_deleted_at_to_note_nodes.down.sql`

- [ ] **Step 1: Criar arquivos de migração**
Adicionar coluna `deleted_at TIMESTAMPTZ` na tabela `note_nodes` no PostgreSQL para permitir soft-deletes no motor de sincronização.

- [ ] **Step 2: Rodar migração local**
Rodar: `migrate -path backend/db/migrations -database "postgres://postgres:postgres@localhost:5432/supanotes?sslmode=disable" up`

---

### Task 2: Consultas SQL de Sincronização (Backend)

**Arquivos:**
- Modify: `backend/db/queries/sync.sql`

- [ ] **Step 1: Escrever queries de sync**
Adicionar no arquivo `sync.sql`:
```sql
-- name: GetSyncNoteNodes :many
SELECT nn.*
FROM note_nodes nn
JOIN notes n ON n.id = nn.note_id
LEFT JOIN note_shares ns ON ns.note_id = n.id AND ns.user_id = sqlc.arg('user_id')::uuid
WHERE (n.user_id = sqlc.arg('user_id')::uuid OR ns.user_id = sqlc.arg('user_id')::uuid)
  AND nn.updated_at > sqlc.arg('last_synced_at')
ORDER BY nn.updated_at ASC
LIMIT sqlc.arg('limit');

-- name: UpsertNoteNode :one
INSERT INTO note_nodes (id, note_id, parent_id, position, type, data, created_at, updated_at, deleted_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, NOW(), $8)
ON CONFLICT (id) DO UPDATE
SET note_id = EXCLUDED.note_id,
    parent_id = EXCLUDED.parent_id,
    position = EXCLUDED.position,
    type = EXCLUDED.type,
    data = EXCLUDED.data,
    updated_at = NOW(),
    deleted_at = EXCLUDED.deleted_at
RETURNING *;
```

- [ ] **Step 2: Regenerar SQLC**
Rodar `cd backend && sqlc generate`.

---

### Task 3: API de Sincronização de Nodes (Backend)

**Arquivos:**
- Modify: `backend/internal/sync/service.go`

- [ ] **Step 1: Atualizar struct `SyncPayload`**
Adicionar `NoteNodes []sqlcgen.NoteNode `json:"note_nodes"`` no payload de sync.

- [ ] **Step 2: Atualizar métodos de Push e Pull**
No `Push()`, fazer o loop por `payload.NoteNodes` e salvar usando `UpsertNoteNode`. No `Pull()`, consultar os nós atualizados usando `GetSyncNoteNodes`.

---

### Task 4: Script de Migração (Backend)

**Arquivos:**
- Modify: `backend/cmd/migrate_nodes/main.go`

- [ ] **Step 1: Atualizar script de migração**
Ajustar o script existente para ler todas as notas em markdown (`content`), parseá-las linha a linha criando `note_nodes` correspondentes, e após migrar com sucesso, **limpar o campo `content`** (ou marcá-lo como vazio) para garantir que não utilizaremos mais Markdown legado.

---

### Task 5: Drift Database Schema (Flutter)

**Arquivos:**
- Modify: `lib/core/database/tables/note_nodes.dart`
- Modify: `lib/core/database/database.dart`

- [ ] **Step 1: Adicionar `deletedAt` e `isDirty` no Drift**
Adicionar `DateTimeColumn get deletedAt => dateTime().nullable()();` e `BoolColumn get isDirty => boolean().withDefault(const Constant(true))();` na tabela `NoteNodes`.

- [ ] **Step 2: Rodar build_runner**
Rodar `dart run build_runner build -d`.

---

### Task 6: Sincronização de Nodes no Frontend (Flutter)

**Arquivos:**
- Modify: `lib/core/sync/sync_mapper.dart`
- Modify: `lib/core/sync/sync_service.dart`

- [ ] **Step 1: Mapear Nodes no SyncMapper**
Adicionar funções `noteNodeToJson` e `noteNodeFromJson` para converter os registros Drift do Flutter no formato wire da API do Go.

- [ ] **Step 2: Sync de Nodes no SyncService**
Atualizar o loop de sync do Flutter para puxar nós sujos (`isDirty = true`) da tabela `note_nodes`, empacotar no payload do HTTP push, e aplicar no banco local os nós baixados pelo pull.

---

### Task 7: Acoplar o Editor Flutter nos Nodes

**Arquivos:**
- Modify: `lib/features/notes/presentation/controllers/notes_providers.dart`
- Modify: `lib/features/notes/presentation/note_editor_screen.dart`
- Modify: `lib/features/notes/presentation/widgets/note_editor.dart`

- [ ] **Step 1: Criar Provider de Nodes**
Criar `noteNodesProvider` que escuta e reage a mudanças na tabela `note_nodes` do banco local para uma nota específica.

- [ ] **Step 2: Alterar NoteEditor para usar Nodes**
Atualizar `NoteEditor` para aceitar `List<NoteNodeData> nodes` no construtor em vez de `String content`.

- [ ] **Step 3: Plugar inicialização no Editor**
Na tela `NoteEditorScreen`, aguardar o `noteNodesProvider` e passar os nós para o widget. O widget chamará `controller.initFromNodes(nodes: widget.nodes)` em vez do `init(content)`.

---

### Task 8: Tradução de Nodes/Markdown no Backend para o Agente

**Arquivos:**
- Create: `backend/internal/notes/parser.go`
- Modify: `backend/internal/notes/service.go`
- Modify: `backend/internal/agent/tools/notes_tools.go`

- [ ] **Step 1: Criar Parser no Backend**
Escrever em `backend/internal/notes/parser.go` um parser de Markdown estruturado para converter strings Markdown escritas pelo Agente em fatias de Nós (`InsertNodeParams`). Ele deve identificar parágrafos, cabeçalhos (`#`, `##`, `###`), divisores (`---`) e tarefas (`- [ ]`, `- [x]`).

- [ ] **Step 2: Atualizar Métodos de Escrita do Notes Service**
Ajustar `CreateNote` e `AppendToNoteContent` para usar o novo parser e salvar como nós na tabela `note_nodes` do PostgreSQL.

- [ ] **Step 3: Atualizar Tools de Leitura do Agente**
Ajustar as ferramentas `get_note` e `get_inbox_note` em `notes_tools.go` para:
  1. Buscar os nós da nota do banco.
  2. Converter esses nós para Markdown on-demand usando `notes.RenderNoteToMarkdown`.
  3. Retornar a string de Markdown resultante para o LLM.
