# Spec: Preferências de Notas por Usuário (User Note Preferences)

**Data**: 2026-06-21  
**Autor**: Antigravity  
**Status**: Proposto / Aguardando Revisão  

---

## 1. Descrição e Objetivos

O objetivo desta especificação é permitir que cada usuário que tenha acesso a uma nota (seja como proprietário, editor ou apenas leitor) possa customizar suas preferências de visualização de tarefas concluídas e filtros sem interferir na exibição dos demais colaboradores.

1. **Persistência e Sincronização**: As preferências de exibição (como ocultar concluídos) devem ser lembradas ao fechar a nota e sincronizadas com o servidor para estarem disponíveis em múltiplos dispositivos do mesmo usuário.
2. **Visualização Individual**: Usuários compartilhados (incluindo usuários com acesso apenas de leitura) podem controlar seus próprios filtros e exibição sem modificar o estado compartilhado da nota original.
3. **Escalabilidade**: A solução deve ser genérica o suficiente para permitir a adição futura de novos filtros e preferências específicas da nota por usuário (ex: ordenação de tarefas, cores de cartão) sem exigir novas migrações de banco de dados.

---

## 2. Mudanças de Esquema e Arquitetura

### 2.1 Backend Go (PostgreSQL)

* **Migration**: Criação de `backend/db/migrations/000017_user_note_preferences.up.sql`:
  ```sql
  BEGIN;

  CREATE TABLE IF NOT EXISTS user_note_preferences (
      user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      note_id          UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
      hide_completed   BOOLEAN NOT NULL DEFAULT FALSE,
      filters          JSONB NOT NULL DEFAULT '{}'::jsonb,
      created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (user_id, note_id)
  );

  CREATE INDEX IF NOT EXISTS idx_user_note_prefs_user_id ON user_note_preferences(user_id);

  -- Copia os dados existentes de hide_completed para a nova tabela
  INSERT INTO user_note_preferences (user_id, note_id, hide_completed, created_at, updated_at)
  SELECT user_id, id, hide_completed, created_at, updated_at FROM notes
  ON CONFLICT (user_id, note_id) DO NOTHING;

  COMMIT;
  ```

* **Queries (SQLC)**: Adição em `backend/db/queries/sync.sql`:
  ```sql
  -- name: GetSyncUserNotePreferences :many
  SELECT * FROM user_note_preferences
  WHERE user_id = $1 AND updated_at > sqlc.arg('last_synced_at')
  ORDER BY updated_at ASC
  LIMIT sqlc.arg('limit');

  -- name: UpsertUserNotePreference :one
  INSERT INTO user_note_preferences (user_id, note_id, hide_completed, filters, created_at, updated_at)
  VALUES ($1, $2, $3, $4, $5, NOW())
  ON CONFLICT (user_id, note_id) DO UPDATE
  SET hide_completed = EXCLUDED.hide_completed,
      filters = EXCLUDED.filters,
      updated_at = NOW()
  RETURNING *;
  ```
* **Regeneração**: Executar `sqlc generate` no backend.

### 2.2 Frontend Flutter (Drift SQLite)

* **Nova Tabela**: Criação de `lib/core/database/tables/user_note_preferences.dart`:
  ```dart
  import 'package:drift/drift.dart';

  @DataClassName('UserNotePreferenceData')
  class UserNotePreferences extends Table {
    TextColumn get userId => text()();
    TextColumn get noteId => text()();
    BoolColumn get hideCompleted => boolean().withDefault(const Constant(false))();
    TextColumn get filters => text().withDefault(const Constant('{}'))();
    
    DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
    DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
    BoolColumn get isDirty => boolean().withDefault(const Constant(true))();

    @override
    Set<Column> get primaryKey => {userId, noteId};
  }
  ```

* **Database Class**: Incremento do `schemaVersion` para `9` em `lib/core/database/database.dart` e atualização da estratégia de migration:
  ```dart
  if (from < 9) {
    await m.createTable(userNotePreferences);
  }
  ```
* **Regeneração**: Executar Drift codegen (`dart run build_runner build --delete-conflicting-outputs`).

---

## 3. Sincronização (Sync Payload)

### 3.1 DTOs e JSON Mappings (Backend & Frontend)
O payload da API de sincronização `/api/v1/sync` receberá o campo `user_note_preferences` (Array de objetos):

* **Go (Backend)**: Struct `SyncPayload` será expandida com `UserNotePreferences []sqlcgen.UserNotePreference`.
* **Flutter (Frontend)**: O `SyncMapper` mapeará a lista de preferências de/para JSON.

### 3.2 Validação no Backend (Push)
No serviço de sincronização do Go (`Push`), ao receber um registro de preferência, validaremos se o usuário autenticado é o dono da nota ou se a nota foi compartilhada com ele (possui entrada na tabela `note_shares`). Se o usuário não tiver acesso, o registro é rejeitado com conflito.

---

## 4. Aplicação e Interface do Usuário (Flutter)

### 4.1 Junção Reativa de Preferências (Repository)
No `NotesRepository` (`lib/features/notes/data/notes_repository.dart`), o método de escuta `watchNoteById` combinará o fluxo da nota e da preferência usando programação reativa (por exemplo, `Rx.combineLatest2` do pacote `rxdart` ou via operadores de stream do Drift):

```dart
@override
Stream<NoteModel?> watchNoteById(String id) {
  return Rx.combineLatest2<NoteData?, UserNotePreferenceData?, NoteModel?>(
    _local.watchNoteById(id),
    _localPrefs.watchPreference(userId, id),
    (note, pref) {
      if (note == null) return null;
      final model = NoteModel.fromData(note);
      return model.copyWith(
        hideCompleted: pref?.hideCompleted ?? model.hideCompleted,
      );
    },
  );
}
```

### 4.2 Alteração na Interface (NoteEditorScreen)
No arquivo `lib/features/notes/presentation/note_editor_screen.dart`:
1. O botão de três pontinhos (`AdaptivePopupMenuButton`) passará a ser exibido para **qualquer usuário** que abra a nota (sem a restrição `if (isOwner)`).
2. O item de compartilhamento (`share`) será exibido no menu apenas se o usuário for o dono (`if (isOwner)`).
3. O item de exibir/ocultar concluídos (`hide_completed`) estará sempre disponível para todos.
4. Quando selecionada, a ação de ocultar concluídos salvará a preferência no banco de dados local por meio do novo repositório `UserNotePreferencesRepository` (o que aciona a gravação do Drift e marca a flag `isDirty = true` para envio na próxima sincronização).

---

## 5. Plano de Verificação

### Testes Automatizados (Backend)
- Executar os testes de sincronização existentes (`go test ./internal/sync/...`).
- Escrever testes unitários específicos para validar que o Push de `user_note_preferences` é aceito para donos e leitores compartilhados, mas rejeitado para quem não tem acesso à nota.

### Testes Manuais (Simulação de Cenários)
1. **Dono A e Convidado B**:
   * O Dono A compartilha a nota com o Convidado B (com permissão de leitura ou edição).
   * O Convidado B abre a nota e clica para ocultar as tarefas concluídas.
   * Verificar se no dispositivo de B as tarefas concluídas desaparecem.
   * Sincronizar os dois dispositivos.
   * Verificar se no dispositivo do Dono A as tarefas concluídas continuam **visíveis** (sua preferência original não foi alterada).
2. **Persistência de B**:
   * O Convidado B multiplica a nota, fecha o aplicativo e reabre.
   * A preferência selecionada (ocultar concluídas) deve continuar ativa para B.
3. **Múltiplos Dispositivos**:
   * O Convidado B abre a nota em um segundo dispositivo com sua mesma conta de usuário.
   * Após a sincronização, a nota no segundo dispositivo deve exibir o mesmo estado (ocultar concluídas) configurado no primeiro aparelho.
