# Tarefas: documento e interação

Uma tarefa é um bloco `task` do documento canônico da nota. O snapshot efetivo
local também é a fonte das notificações offline.

## Camadas

- `domain/task_occurrence.dart`: resolve a ocorrência atual e suas transições.
- `domain/note_task_reader.dart`: extrai entradas de notificação do snapshot.
- `presentation/`: sheet de metadados, badges e feedback de conclusão.

## Fluxo de conclusão

O checkbox pede ao controller do editor para alterar o bloco. A captura gera
uma operação REST/OT e atualiza a materialização local junto da outbox. Nenhuma
tabela relacional recebe escrita de task.
