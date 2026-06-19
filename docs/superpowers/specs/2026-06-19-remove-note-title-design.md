# Spec: Remover campo de Title (Estilo Apple Notes)

**Data**: 2026-06-19  
**Autor**: Antigravity  
**Status**: Proposto / Aguardando Revisão  

---

## 1. Descrição e Objetivos
O objetivo desta especificação é alinhar a experiência de criação e edição de notas com o padrão do Apple Notes:
1. **Sem campo de título separado**: A nota é editada em um único fluxo de texto. A primeira linha da nota atua visualmente e logicamente como o título.
2. **Formatação H1 automática**: Quando uma nota é criada ou editada, a primeira linha é estilizada automaticamente como Cabeçalho 1 (`header1` / H1). As linhas seguintes são texto comum.
3. **Preservação de Formatação**: Ao apagar todo o texto da primeira linha (título), a formatação H1 é mantida ativa para que o cursor permaneça grande e em negrito.
4. **Remoção de Redundância no Banco/API**: A coluna `title` é completamente eliminada do banco de dados SQLite local, do PostgreSQL remoto, do payload de sincronização e das APIs do backend Go. O título passa a ser extraído dinamicamente do conteúdo markdown.

---

## 2. Mudanças de Esquema e Arquitetura

### 2.1 Backend Go (PostgreSQL)
* **Migration**: Criação de `backend/db/migrations/000008_remove_note_title.up.sql`:
  ```sql
  ALTER TABLE notes DROP COLUMN IF EXISTS title;
  
  DROP TRIGGER IF EXISTS tsvectorupdate ON notes;
  CREATE TRIGGER tsvectorupdate BEFORE INSERT OR UPDATE OF content ON notes
  FOR EACH ROW EXECUTE FUNCTION notes_search_trigger();
  ```
* **Queries (SQLC)**:
  * Remoção do campo `title` de `UpsertNote` em `backend/db/queries/sync.sql`.
  * Remoção de referências a `title` nos arquivos de queries.
  * Regeneração do código com `sqlc generate`.

### 2.2 Frontend Flutter (Drift SQLite)
* **Tabela Notes**: Remoção de `title` em `lib/core/database/tables/notes.dart`.
* **Database Class**: Incremento do `schemaVersion` para `8` em `lib/core/database/database.dart` e atualização da estratégia de migration.
* **Regeneração**: Executar Drift codegen (`dart run build_runner build --delete-conflicting-outputs`).

---

## 3. Comportamento do Editor (Flutter)

### 3.1 Preservação de H1 na Primeira Linha
* **EditReaction**: Criação de `KeepFirstLineAsTitleReaction` em `lib/features/notes/domain/note_editor_commands.dart`. Essa reação monitora se o primeiro nó é um parágrafo comum e, se for, o converte/mantém como `header1`.
* **Inicialização**: Em `parseNoteToMarkdown` (`lib/features/notes/data/markdown_serializer.dart`), forçamos o primeiro nó a possuir o metadado `blockType: header1`.

### 3.2 Extração Dinâmica do Título
* **Mapeamento de Modelos**: No model `NoteModel` (`lib/features/notes/domain/note_model.dart`), o título é extraído em tempo de execução:
  ```dart
  static String extractTitle(String content) {
    if (content.isEmpty) return 'Sem título';
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        return trimmed.replaceFirst(RegExp(r'^#+\s+'), '');
      }
    }
    return 'Sem título';
  }
  ```

---

## 4. Busca, Listagem e API de Sincronização

### 4.1 SQL de Busca Dinâmica (Backend Go)
Para manter retrocompatibilidade com o app de busca e não quebrar o endpoint, as queries de busca em `backend/db/queries/search.sql` retornarão a primeira linha do conteúdo markdown como `title`:
```sql
regexp_replace(split_part(n.content, E'\n', 1), '^#+\s+', '') AS title
```

### 4.2 Sincronização
* **DTOs de Sincronização**: O campo `title` da struct Note é removido da API do backend.
* **Flutter Sync Client**: Paramos de enviar/receber o campo `title` no mapeamento JSON das notas.

---

## 5. Plano de Verificação

### Testes Manuais
1. Criar uma nova nota e digitar texto. Verificar se a primeira linha tem estilo H1 maior/bold e as seguintes têm estilo regular.
2. Apagar todo o texto da primeira linha. O cursor deve permanecer com o estilo visual H1.
3. Voltar para a tela inicial e verificar se o título correto (extraído do texto) é exibido no card da listagem.
4. Realizar a busca e conferir se as notas são localizadas e exibidas com os títulos extraídos dinamicamente.
5. Realizar sincronização e garantir que nenhuma nota vazia ou com erro seja enviada.
