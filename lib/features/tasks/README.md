# Tarefas: projeções e interação

Uma tarefa é um bloco do documento de uma nota. `tasks/` oferece uma projeção
relacional para consultas e UI, sem tomar posse da escrita canônica.

## Camadas

- `domain/note_document_projector.dart`: calcula `content`, `excerpt` e tarefas
  a partir do snapshot REST/OT sem conhecer banco ou ciclo de vida do editor.
- `domain/task_projection_engine.dart`: recebe o documento/snapshot, delega o
  cálculo ao `NoteDocumentProjector` e grava `tasks` e `task_completions` na
  mesma transação. É a fronteira de persistência para alterações vindas do
  editor; a hidratação remota do catálogo usa `AppDatabase.saveRemoteNote`.
- `domain/task_occurrence.dart` e `task_recurrence.dart`: calculam ocorrências
  de recorrência. Conclusões são eventos por ocorrência, não deslocamentos do
  template.
- `data/`: repositório e consultas locais para listas de hoje, atrasadas e sem
  data.
- `presentation/`: sheet de metadados, badges, tiles e feedback de conclusão.

## Fluxo de conclusão

O checkbox pede ao controller do editor para alterar o bloco. A captura gera
uma operação REST/OT; quando o snapshot é confirmado ou atualizado localmente,
`TaskProjectionEngine` recalcula a projeção. Um botão não deve escrever direto
em `TasksDao` para concluir uma tarefa criada no editor.

Veja [Notes editor](../notes/editor/README.md) para a origem e [database](../../core/database/README.md) para o destino da projeção.
