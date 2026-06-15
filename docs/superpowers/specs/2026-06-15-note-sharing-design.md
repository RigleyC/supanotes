# Spec: Compartilhamento de Notas (Note Sharing)

Permite que os usuários compartilhem notas diretamente com outros usuários do SupaNotes por e-mail, definindo permissões de apenas visualização (`view`) ou edição (`edit`). A nota compartilhada é sincronizada no banco de dados local do destinatário e integrada na lista de notas principal com um indicador visual de autoria. O editor se adapta para ser somente-leitura se a permissão for apenas de visualização.

## User Review Required

> [!IMPORTANT]
> - O compartilhamento é **direto por e-mail**. O e-mail do destinatário deve corresponder a um usuário cadastrado no sistema SupaNotes.
> - O gerenciamento de quem tem acesso à nota (adicionar, alterar permissão ou remover compartilhamento) é feito de forma online (requer internet) diretamente com a API do servidor ao abrir o modal de compartilhamento dentro da nota.
> - O sincronismo (sync) offline foi estendido: tarefas, tags e links de notas compartilhadas serão sincronizados no dispositivo dos destinatários para que eles possam ler/editar a nota inteira offline.

## Proposed Changes

Abaixo estão as modificações propostas divididas por camada técnica:

---

### 1. Banco de Dados & Schema (Backend)

#### [NEW] [000013_note_sharing.up.sql](file:///c:/Users/rigleyc/projects/supanotes/backend/db/migrations/000013_note_sharing.up.sql)
Criação da tabela `note_shares` para associar notas a usuários convidados:
```sql
CREATE TABLE note_shares (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    note_id     UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    permission  TEXT NOT NULL CHECK (permission IN ('view', 'edit')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (note_id, user_id)
);

CREATE INDEX idx_note_shares_user_id ON note_shares(user_id);
```

#### [NEW] [000013_note_sharing.down.sql](file:///c:/Users/rigleyc/projects/supanotes/backend/db/migrations/000013_note_sharing.down.sql)
```sql
DROP TABLE IF EXISTS note_shares;
```

---

### 2. Queries do Banco de Dados (Backend - SQLC)

#### [MODIFY] [sync.sql](file:///c:/Users/rigleyc/projects/supanotes/backend/db/queries/sync.sql)
Atualizar consultas de sync para trazer notas, tarefas, tags e links compartilhados:
* **GetSyncNotes:** Modificar para incluir notas em que o usuário é destinatário em `note_shares`, trazendo permissão e dados do proprietário via `LEFT JOIN`.
* **GetSyncTasks / GetSyncTaskCompletions / GetSyncNoteTags / GetSyncNoteLinks:** Estender para trazer registros associados a notas compartilhadas (`note_id IN (SELECT note_id FROM note_shares WHERE user_id = $1)`).

#### [NEW] [shares.sql](file:///c:/Users/rigleyc/projects/supanotes/backend/db/queries/shares.sql)
Consultas de gerenciamento para a API:
```sql
-- name: CreateNoteShare :one
INSERT INTO note_shares (note_id, user_id, permission)
VALUES ($1, $2, $3)
ON CONFLICT (note_id, user_id) DO UPDATE
SET permission = EXCLUDED.permission,
    updated_at = NOW()
RETURNING *;

-- name: GetNoteShares :many
SELECT ns.*, u.email, u.name
FROM note_shares ns
JOIN users u ON u.id = ns.user_id
WHERE ns.note_id = $1;

-- name: DeleteNoteShare :exec
DELETE FROM note_shares
WHERE note_id = $1 AND user_id = $2;

-- name: GetNoteShareForUser :one
SELECT * FROM note_shares
WHERE note_id = $1 AND user_id = $2;
```

---

### 3. Sincronização & Segurança (Backend Go)

#### [MODIFY] [service.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/sync/service.go)
- No método `Push`, validar se as notas enviadas pertencem ao usuário (`note.user_id == userID`) ou se ele possui permissão `'edit'` na tabela `note_shares`. Caso contrário, ignorar ou rejeitar com erro de conflito.
- Fazer a mesma validação para as tarefas e outros elementos editados.

---

### 4. Endpoints da API (Backend Go)

#### [MODIFY] [handler.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/notes/handler.go) e [main.go](file:///c:/Users/rigleyc/projects/supanotes/backend/cmd/server/main.go)
Registrar e implementar os seguintes endpoints no Echo (protegidos por JWT):
- `GET /api/v1/notes/:id/shares` — Lista os compartilhamentos ativos da nota (apenas para o dono).
- `POST /api/v1/notes/:id/shares` — Compartilha a nota (busca usuário por e-mail, insere em `note_shares`).
- `DELETE /api/v1/notes/:id/shares/:user_id` — Remove o compartilhamento da nota.

---

### 5. Banco de Dados Local (Drift - Flutter)

#### [MODIFY] [notes.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/core/database/tables/notes.dart)
Adicionar colunas na tabela `Notes`:
```dart
TextColumn get permission => text().nullable()(); // 'view' ou 'edit'
TextColumn get sharedByEmail => text().nullable()();
TextColumn get sharedByName => text().nullable()();
```

#### [MODIFY] [database.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/core/database/database.dart)
- Incrementar `schemaVersion` de `5` para `6`.
- Adicionar colunas no callback `onUpgrade`:
```dart
if (from < 6) {
  await m.addColumn(notes, notes.permission);
  await m.addColumn(notes, notes.sharedByEmail);
  await m.addColumn(notes, notes.sharedByName);
}
```

---

### 6. Interface & Editor (Flutter)

#### [MODIFY] [note_model.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/domain/note_model.dart)
- Adicionar campos `permission`, `sharedByEmail` e `sharedByName` ao `NoteModel` e mapeá-los em `NoteModel.fromData`.

#### [MODIFY] [note_editor_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/note_editor_screen.dart)
- Se a nota for compartilhada (`note.permission != null`), exibir um banner ou subtítulo informando: *"Compartilhada por [E-mail]"*.
- Se `note.permission == 'view'`:
  - Passar `isReadOnly: true` para o `NoteEditor`.
  - Ocultar botões de edição na AppBar.
- Se o usuário for o dono (`note.permission == null`), exibir botão de compartilhar na AppBar que abre o `ShareNoteDialog`.

#### [NEW] [share_note_dialog.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/share_note_dialog.dart)
Caixa de diálogo que permite:
1. Digitar o e-mail de um usuário e escolher a permissão (View/Edit).
2. Botão "Adicionar" para enviar a requisição HTTP.
3. Carregar via `FutureBuilder` a lista de membros e exibir com botão de revogar acesso.

#### [MODIFY] [notes_list_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/notes_list_screen.dart)
- Modificar os cards ou itens da lista de notas para exibir um pequeno badge ou etiqueta de compartilhamento (*"De: email@proprietario.com"*) caso `note.permission` não seja nulo.

---

## Verification Plan

### Automated Tests
- Criar migração SQL e gerar código Go via `sqlc` e Drift via `build_runner`.
- Escrever teste unitário no backend Go para garantir que usuários sem permissão `'edit'` não conseguem alterar notas de terceiros no sync push.
- Escrever teste unitário para garantir que o sync pull de notas compartilhadas retorna os registros com os joins de usuário corretos.

### Manual Verification
1. Criar dois usuários (Ex: `userA@test.com` e `userB@test.com`).
2. Com o `userA`, criar uma nota e digitar o e-mail do `userB` selecionando permissão "Visualizar" no modal de compartilhamento.
3. Fazer login como `userB`, verificar que a nota aparece na lista principal com o indicador "De: userA@test.com".
4. Abrir a nota com `userB` e verificar se ela está em modo somente-leitura (sem barra de formatação e impossível de digitar).
5. Alterar a permissão no `userA` para "Editar". Aguardar o sync ou forçar o sync, e abrir como `userB`. Verificar se agora a nota permite edição.
6. Revogar o compartilhamento com `userA`. Verificar que a nota desaparece da listagem do `userB` após o sync.
