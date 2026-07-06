# Spec: Remoção da Feature de Braindump (Inbox Note)

**Data**: 2026-07-06  
**Status**: Proposto  

Esta especificação define o design técnico para a remoção completa da feature de **Braindump** (também conhecida como **Inbox Note** ou **Rascunho**) do projeto SupaNotes, tanto no Backend (Go) quanto no Frontend (Flutter).

---

## 1. Contexto e Motivação

A feature de Braindump permitia que o usuário fizesse capturas rápidas de texto em uma nota especial única (`is_inbox = true`), que depois era analisada por um agente de IA para propor a divisão e organização desse conteúdo em notas novas ou existentes.

Com a remoção dessa feature, o fluxo do app se concentrará exclusivamente em Notas normais, simplificando a interface, o sincronismo offline e as consultas de IA (RAG/Embeddings), que antes precisavam filtrar e ignorar a Inbox Note.

---

## 2. Banco de Dados e Esquema

### Backend (PostgreSQL)
* **Migração SQL (`000028_remove_braindump.up.sql`)**:
  ```sql
  ALTER TABLE notes DROP CONSTRAINT IF EXISTS chk_inbox_not_archived;
  DELETE FROM notes WHERE is_inbox = true;
  DROP INDEX IF EXISTS idx_notes_single_inbox;
  ALTER TABLE notes DROP COLUMN IF EXISTS is_inbox;
  ```
* **Migração SQL de Down (`000028_remove_braindump.down.sql`)**:
  ```sql
  ALTER TABLE notes ADD COLUMN is_inbox BOOLEAN NOT NULL DEFAULT false;
  CREATE UNIQUE INDEX idx_notes_single_inbox ON notes (user_id) WHERE is_inbox = true AND deleted_at IS NULL;
  ALTER TABLE notes ADD CONSTRAINT chk_inbox_not_archived CHECK (is_inbox = false OR archived = false);
  ```

* **Queries SQLC (`backend/db/queries/`)**:
  * Em `notes.sql`, remover as queries `GetInboxNote`, `AppendToInbox` e `SetInboxContent`. Remover o parâmetro `is_inbox` de `CreateNote` e `UpsertNote`.
  * Em `notes.sql`, `ai.sql`, `search.sql` e `sync.sql`, remover todas as cláusulas `is_inbox = false` ou `NOT is_inbox`.

### Frontend (SQLite via Drift)
* **Tabela Notes (`lib/core/database/tables/notes.dart`)**: Remove a coluna `isInbox`.
* **Database (`lib/core/database/database.dart`)**:
  * Incrementa `schemaVersion` para `15`.
  * Adiciona lógica de migração no `onUpgrade`:
    ```dart
    if (from < 15) {
      await customStatement('DELETE FROM notes WHERE is_inbox = 1;');
      await customStatement('ALTER TABLE notes DROP COLUMN is_inbox;');
    }
    ```
* **Notes DAO (`lib/core/database/daos/notes_dao.dart`)**:
  * Remove `getInboxNote` e `watchInboxNote`.
  * Remove mapeamento e filtros que referenciam `is_inbox` ou `isInbox`.

---

## 3. Alterações no Backend (Go)

### Endpoints (Handlers e Rotas)
* Remover os seguintes handlers em `backend/internal/notes/handler.go`:
  * `GetInbox`
  * `AppendToInbox`
  * `PlanOrganization`
  * `ApplyOrganization`
* Remover o registro dessas rotas em `backend/cmd/server/main.go`:
  * `GET /notes/inbox`
  * `POST /notes/inbox/append`
  * `POST /notes/inbox/organize/plan`
  * `POST /notes/inbox/organize/apply`

### Regras de Negócio e Serviços
* Remover do `notes.Service` os métodos correspondentes às operações acima.
* Remover a validação `ErrInboxRule` (que impedia arquivamento/deleção/edição direta de inbox notes).

### Agente AI e Ferramentas
* Deletar do diretório `backend/internal/agent/tools/` as ferramentas:
  * `get_inbox_note`
  * `append_to_inbox`
  * `plan_inbox_organization`
  * `apply_inbox_organization`
* Remover o registro destas em `backend/internal/agent/tools/registry.go`.
* Renomear a tarefa de LLM `TaskTypeInboxOrganize` para `TaskTypeAgentHelper` (ou similar) em `factory.go` e configs, uma vez que ela continuará a ser usada para a execução leve do agente (intent classification, planning).

---

## 4. Alterações no Frontend (Flutter)

### Remoção de Telas e Diálogos
* Deletar `lib/features/notes/presentation/inbox_screen.dart`.
* Deletar `lib/features/notes/presentation/widgets/inbox_organize_sheet.dart`.
* Deletar `lib/features/notes/presentation/widgets/brain_dump_tile.dart`.
* Deletar `lib/features/agent/data/inbox_organize_repository.dart`.
* Deletar `lib/features/agent/domain/organization_plan.dart` e `destination_type.dart`.

### Ajustes na Interface Existente
* Em `lib/features/notes/presentation/notes_list_screen.dart`, remover o widget `BrainDumpTile` que aparecia acima da lista de notas.

### Ajustes de Rotas e Repositórios
* Em `app_router.dart` e `app_routes.dart`, remover o caminho `/inbox`.
* Em `notes_repository.dart`, remover os métodos `watchInbox`, `ensureInbox` e `appendToInbox`.
* Em `notes_providers.dart`, remover o `inboxProvider`.
* Em `sync_mapper.dart`, remover a serialização do campo `is_inbox`.

---

## 5. Plano de Verificação

### Testes Automatizados
* Rodar os testes do backend Go: `go test ./...`
* Rodar os testes do frontend Flutter: `flutter test`

### Verificação Manual
1. Iniciar o backend e frontend localmente.
2. Certificar-se de que a migração de banco de dados rodou com sucesso.
3. Verificar na tela principal do app se o item "Brain Dump" não é mais renderizado.
4. Tentar interagir com o agente e verificar se ele não sugere ferramentas de inbox.
