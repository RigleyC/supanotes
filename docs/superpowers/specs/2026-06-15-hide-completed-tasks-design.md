# Spec: Exibir/Esconder Tasks Concluídas na Nota

Permite que o usuário oculte ou exiba visualmente as tarefas (tasks) concluídas dentro do editor de uma nota. A configuração é persistida de forma individual (por nota) no banco de dados local SQLite (Drift).

## User Review Required

> [!IMPORTANT]
> A configuração de ocultação é salva no banco de dados local (`Notes.hideCompleted`), mas não é enviada ao backend Go nem sincronizada com outros dispositivos, pois o backend não possui esta coluna no esquema. Se a nota for limpa ou recriada remotamente, essa preferência local persistirá conforme o ID da nota no banco SQLite.

## Proposed Changes

Abaixo estão as modificações propostas divididas por camada técnica:

---

### 1. Banco de Dados Local (Drift)

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

---

### 2. Modelo de Domínio e Repositório

#### [MODIFY] [note_model.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/domain/note_model.dart)
- Adicionar o campo `final bool hideCompleted;` à classe `NoteModel`.
- Atualizar o construtor, `copyWith` e outros métodos utilitários do modelo.

#### [MODIFY] [notes_repository.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/data/notes_repository.dart)
- Atualizar a interface `INotesRepository` e a classe `NotesRepository` para incluir o campo no mapeamento de/para `NoteData` (Drift) e `NoteModel`.
- Criar o método `updateNoteHideCompleted(String noteId, bool hideCompleted)` para persistir a alteração no banco de dados local através do DAO de notas.

---

### 3. Interface do Usuário (UI)

#### [MODIFY] [note_editor_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/note_editor_screen.dart)
- Adicionar um botão de menu de opções na AppBar usando o componente `AdaptivePopupMenuButton`.
- O menu exibirá a opção dinâmica:
  - Se `note.hideCompleted == true`: "Mostrar concluídas" (com ícone correspondente).
  - Se `note.hideCompleted == false`: "Ocultar concluídas" (com ícone correspondente).
- Ao selecionar a opção, invocar o método do repositório para salvar no banco local.

---

### 4. Editor (`super_editor` Custom Component)

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
    - Isso oculta visualmente a tarefa concluída zerando seu espaço na tela, mas mantém o estado do `TextComponent` ativo na memória para evitar falhas de seleção ou caret no editor.

## Verification Plan

### Automated Tests
- Criar ou rodar testes unitários para a migração do Drift (versão 5 para 6).
- Testar o repositório de notas para garantir que `updateNoteHideCompleted` atualiza o banco de dados corretamente e emite o novo estado através do stream da nota.

### Manual Verification
1. Abrir uma nota existente.
2. Adicionar tarefas (tasks) concluídas e não concluídas.
3. Clicar nas reticências (menu de opções) na AppBar e escolher "Ocultar concluídas".
4. Verificar se as tarefas marcadas como concluídas desaparecem visualmente.
5. Marcar uma tarefa aberta como concluída e observar se ela desaparece.
6. Clicar no menu e selecionar "Mostrar concluídas". Verificar se elas voltam a ser exibidas com a marcação correspondente.
7. Fechar a nota, reabri-la e conferir se o estado de visibilidade foi lembrado corretamente.
