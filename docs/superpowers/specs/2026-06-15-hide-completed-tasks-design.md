# Spec: Exibir/Esconder Tasks Concluídas na Nota (Sincronizado)

Permite que o usuário oculte ou exiba visualmente as tarefas (tasks) concluídas dentro do editor de uma nota. A configuração é persistida de forma individual (por nota) no banco de dados local SQLite (Drift) e sincronizada de forma bidirecional com o backend Go (banco PostgreSQL), garantindo consistência entre múltiplos dispositivos.

## User Review Required

> [!NOTE]
> Esta especificação foi revisada a pedido do usuário para que o campo de ocultação (`hide_completed`) não seja apenas local, mas também sincronizado com o banco de dados remoto e a API do backend. Isso exige uma migração de banco de dados no Go (PostgreSQL) além da migração local no Flutter (SQLite).

## Proposed Changes

Abaixo estão as modificações propostas divididas por camada técnica:

---

### 1. Migração e Consultas no Backend Go (PostgreSQL & SQLC)

#### [NEW] [000013_add_hide_completed_to_notes.up.sql](file:///c:/Users/rigleyc/projects/supanotes/backend/db/migrations/000013_add_hide_completed_to_notes.up.sql)
Criar arquivo de migração para adicionar a coluna na tabela `notes`:
```sql
ALTER TABLE notes ADD COLUMN hide_completed BOOLEAN NOT NULL DEFAULT false;
```

#### [NEW] [000013_add_hide_completed_to_notes.down.sql](file:///c:/Users/rigleyc/projects/supanotes/backend/db/migrations/000013_add_hide_completed_to_notes.down.sql)
Criar arquivo de migração para rollback:
```sql
ALTER TABLE notes DROP COLUMN hide_completed;
```

#### [MODIFY] [notes.sql](file:///c:/Users/rigleyc/projects/supanotes/backend/db/queries/notes.sql)
- Atualizar a consulta `CreateNote` para incluir a coluna `hide_completed`.
- Atualizar a consulta `UpdateNote` para incluir a atualização condicional de `hide_completed`.

#### [MODIFY] [sync.sql](file:///c:/Users/rigleyc/projects/supanotes/backend/db/queries/sync.sql)
- Atualizar a consulta `UpsertNote` para incluir e atualizar a coluna `hide_completed` em caso de conflito.

---

### 2. Modelos, Handlers e Serviços no Go

#### [MODIFY] Regeneração SQLC
Executar `sqlc generate` para regenerar os arquivos dentro de `backend/internal/db/sqlcgen/`.

#### [MODIFY] [handler.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/notes/handler.go)
- Atualizar `CreateNoteRequest` para incluir `HideCompleted bool json:"hide_completed"`.
- Atualizar `UpdateNoteRequest` para incluir `HideCompleted *bool json:"hide_completed"`.
- Atualizar `NoteResponse` para incluir `HideCompleted bool json:"hide_completed"`.
- Mapear o novo campo na função `mapToNoteResponse`.

#### [MODIFY] [service.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/notes/service.go)
- Atualizar a assinatura do método `CreateNote` para aceitar `hideCompleted bool` e adicioná-la ao struct `sqlcgen.CreateNoteParams`.
- Atualizar a assinatura do método `UpdateNote` para aceitar `hideCompleted *bool` e adicioná-la ao struct `sqlcgen.UpdateNoteParams`.

#### [MODIFY] [service_test.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/notes/service_test.go) (e outros testes de mock/stub)
- Atualizar stubs e mocks da interface `Querier` e `Service` nos arquivos de testes do backend para passar o novo argumento `hideCompleted`.

---

### 3. Banco de Dados Local no Flutter (Drift)

#### [MODIFY] [notes.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/core/database/tables/notes.dart)
Adicionar a coluna `hideCompleted` à definição da tabela `Notes`:
```dart
BoolColumn get hideCompleted => boolean().withDefault(const Constant(false))();
```

#### [MODIFY] [database.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/core/database/database.dart)
- Incrementar a versão do esquema (`schemaVersion`) de `5` para `6`.
- Adicionar o passo de migração correspondente no callback `onUpgrade`:
```dart
if (from < 6) {
  await m.addColumn(notes, notes.hideCompleted);
}
```

#### [MODIFY] [notes_dao.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/core/database/daos/notes_dao.dart)
- Atualizar o método `upsertNote` (na cláusula `DoUpdate.withExcluded`) para assegurar que `hideCompleted` também seja sobrescrito no conflito:
```dart
hideCompleted: excluded.hideCompleted,
```

---

### 4. Sincronização e Repositório no Flutter

#### [MODIFY] [note_model.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/domain/note_model.dart)
- Adicionar o campo `final bool hideCompleted;` à classe `NoteModel`.
- Atualizar o construtor, `copyWith` e outros métodos utilitários do modelo.

#### [MODIFY] [sync_mapper.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/core/sync/sync_mapper.dart)
- Mapear `hide_completed` in `noteToJson`:
```dart
'hide_completed': n.hideCompleted,
```
- Mapear `hide_completed` in `noteFromJson`:
```dart
hideCompleted: (json['hide_completed'] as bool?) ?? false,
```

#### [MODIFY] [notes_repository.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/data/notes_repository.dart)
- Atualizar o método `updateNote` para receber `bool? hideCompleted` e repassá-lo na criação do `NotesCompanion`.

---

### 5. Interface de Usuário (UI) e Componentes no Flutter

#### [MODIFY] [note_editor_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/note_editor_screen.dart)
- Adicionar um botão de menu de opções na AppBar usando o componente `AdaptivePopupMenuButton` do pacote `adaptive_platform_ui`.
- O menu exibirá a opção dinâmica:
  - Se `note.hideCompleted == true`: "Mostrar concluídas" (com ícone correspondente).
  - Se `note.hideCompleted == false`: "Ocultar concluídas" (com ícone correspondente).
- Ao selecionar a opção, invocar `repo.updateNote(widget.noteId, hideCompleted: !note.hideCompleted)`.

#### [MODIFY] [note_editor.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/note_editor.dart)
- Passar o valor de `note.hideCompleted` para o construtor de `NoteEditor`.
- Repassar o valor para `CustomTaskComponentBuilder`.

#### [MODIFY] [custom_task_component.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/custom_task_component.dart)
- Adicionar a propriedade `final bool hideCompleted;` ao construtor de `CustomTaskComponentBuilder` e `CustomTaskComponent`.
- No método `build` do `_CustomTaskComponentState`:
  - Se `widget.viewModel.isComplete` for `true` **E** `widget.hideCompleted` for `true`:
    - Envolver o `Row` retornado em um widget `Visibility` da seguinte forma:
    ```dart
    return Visibility(
      visible: false,
      maintainState: true,
      child: Row( ... ),
    );
    ```

## Verification Plan

### Automated Tests
- Rodar a suite de testes locais do Drift (`flutter test`) e testes unitários de repositórios.
- Rodar a suite de testes do Go (`go test ./...`) no backend.

### Manual Verification
1. Lançar o banco Postgres no docker e rodar as migrações do Go (`make migrate-up`).
2. Abrir o app no emulador/simulador, criar uma nota com tarefas e marcar algumas como concluídas.
3. Acionar a opção "Ocultar concluídas" na AppBar. Verificar que as tarefas sumiram visualmente.
4. Fechar e reabrir a nota para testar a persistência local.
5. Deixar rodar o processo de sync periódica (30s) e checar via banco de dados remoto ou em outra instância de app se a preferência de ocultação de concluídas da nota foi sincronizada com sucesso.
