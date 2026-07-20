# Plano de Implementacao: recorrencias por ocorrencia e historico esparso

## Objetivo

Preservar cada ocorrencia prevista de uma tarefa recorrente sem criar uma nova
linha de `tasks` para cada periodo. Uma tarefa recorrente permanece um unico
template no YDoc; uma ocorrencia e considerada concluida somente quando existe
um registro de conclusao para sua data programada. A ausencia do registro
significa que ela continua pendente ou atrasada.

Isso substitui o comportamento atual que, ao concluir uma recorrencia, move o
`dueDate` do proprio no para a proxima data e usa `catchUpDueDate`, descartando
as ocorrencias perdidas.

## Decisoes de dominio

### Template

O no de tarefa existente continua sendo o template e conserva:

- `nodeId` / `taskId`
- texto e posicao na nota
- `dueDate` como data ancora da recorrencia
- `hasTime`, hora, timezone e `recurrence`
- `reminder`

Para tarefas sem recorrencia, o comportamento atual de `completed` permanece.
Para tarefas recorrentes, `completed` e `lastCompletedAt` deixam de representar
o estado global do template e nao devem ser usados para avancar a data.

### Ocorrencia

Uma ocorrencia e derivada, nao uma task armazenada:

```
OccurrenceKey = taskId + scheduledAtUtc
```

Campos persistidos somente quando houver evento:

- `task_id`
- `scheduled_at` (a data/hora prevista, nao a hora do clique)
- `completed_at`
- `id` deterministico ou chave unica `(task_id, scheduled_at)`

Estado derivado na UI:

- ha completion para `scheduled_at`: concluida
- nao ha completion e `scheduled_at` passou: atrasada
- nao ha completion e esta no periodo atual/futuro: pendente

Futuramente, uma dispensa explicita pode ser outro evento (`skipped_at`), sem
confundir omissao com conclusao.

## Fonte de verdade e sync

O YDoc permanece a fonte de verdade do editor. Para que uma conclusao feita em
um dispositivo apareca em outro, o evento de conclusao precisa estar no YDoc,
em uma colecao propria por tarefa, por exemplo:

```
taskCompletions/<taskId>/<scheduledAtUtc> = completedAtUtc
```

SQLite e PostgreSQL projetam essa colecao para `local_task_completions` e
`task_completions`. Eles nao decidem qual e a proxima ocorrencia nem alteram o
template. A chave por data programada torna a operacao idempotente entre
retries, reconexao e convergencia CRDT.

## Etapas de implementacao

### 1. Definir e testar o calculo de ocorrencias

- Criar um modulo de dominio para enumerar ocorrencias entre uma ancora e uma
  janela de consulta, preservando hora e timezone.
- Remover `catchUpDueDate` do fluxo de conclusao de recorrencias; ele pode ser
  removido por completo se nao houver outro consumidor valido.
- Definir uma janela limitada para a listagem, por exemplo pendencias desde a
  ancora e proximas ocorrencias ate 30 dias. A consulta deve paginar/limitar
  recorrencias antigas para nao gerar listas infinitas.
- Cobrir diariamente, semanalmente, mensalmente, dias uteis, virada de mes,
  horario de verao e tarefas sem hora.

Arquivos iniciais:

- `lib/core/utils/recurrence.dart`
- `lib/features/tasks/domain/task_completion_command.dart`
- novos testes de dominio em `test/features/tasks/domain/`

### 2. Introduzir eventos de conclusao no YDoc

- Adicionar nomes de campos/raizes a `YjsNoteSchema`.
- Criar uma API pequena no bridge: registrar, remover para desfazer e ler
  conclusoes de uma tarefa por `scheduledAt`.
- Ao concluir uma recorrencia, gravar o evento com a data da ocorrencia que o
  usuario marcou. Nao modificar `dueDate`, `recurrence` ou `completed` do
  template.
- Manter a leitura de `lastCompletedAt` somente durante a migracao; nao criar
  novos valores desse campo para recorrencias.
- Atualizar codec e reconciliacao para que a colecao de eventos sobreviva a
  reload, merge remoto e compactacao.

Arquivos iniciais:

- `lib/features/notes/domain/yjs_note_schema.dart`
- `lib/features/notes/domain/yjs_doc_editor_bridge.dart`
- `lib/features/notes/domain/yjs_node_codec.dart`
- `lib/features/notes/presentation/controllers/note_editor_controller.dart`

### 3. Corrigir a projecao local

- Alterar `LocalTaskCompletions` para incluir `scheduledAt`.
- Criar indice/constraint unico por `(taskId, scheduledAt)`.
- Gerar migracao Drift e atualizar o DAO para upsert idempotente, em vez de
  apenas anexar por horario de conclusao.
- Fazer `YjsSyncManager.projectNodes` projetar os eventos do YDoc para SQLite.
- Remover o caminho legado que adiciona completions diretamente a partir de
  `TasksDao.completeTask`, ou limita-lo a tarefas nao editadas pelo YDoc. O
  editor nao pode executar os dois caminhos.

Arquivos iniciais:

- `lib/core/database/tables/task_completions.dart`
- `lib/core/database/database.dart`
- `lib/core/database/daos/task_completions_dao.dart`
- `lib/core/database/daos/tasks_dao.dart`
- `lib/core/sync/yjs_sync_manager.dart`

### 4. Corrigir a projecao no backend

- Adicionar `scheduled_at TIMESTAMPTZ NOT NULL` a `task_completions`.
- Criar constraint unica `(task_id, scheduled_at)` e indice para consultas por
  tarefa/data.
- Atualizar SQL, sqlc e a projecao Go para receber os eventos do YDoc.
- Remover a heuristica atual que cria uma completion apenas na transicao
  `completedAt` nulo para preenchido. Ela nao representa repeticoes.
- Garantir que reprocessar o mesmo YDoc nao duplica eventos e que apagar uma
  tarefa segue preservando o historico conforme a regra atual.

Arquivos iniciais:

- `backend/db/migrations/`
- `backend/db/queries/sync.sql`
- `backend/internal/sync/projection.go`
- `backend/internal/sync/task_projection.go`
- arquivos sqlc gerados

### 5. Montar a lista a partir de templates + eventos

- Criar um read model de ocorrencia para a listagem e para a nota.
- Enumerar datas previstas, cruzar com completions por `scheduledAt` e expor
  itens `pendente`, `atrasada` e `concluida`.
- Definir uma apresentacao que nao polua a nota: mostrar a ocorrencia atual e
  pendencias antigas, agrupando historico concluido quando necessario.
- O comando de concluir deve receber a ocorrencia selecionada, nao apenas o
  `taskId` do template.

Arquivos iniciais:

- `lib/features/tasks/`
- listagens e widgets que chamam `completeTaskInYDoc`
- `lib/features/notes/presentation/note_editor_screen.dart`

### 6. Migracao de dados existentes

- Para cada tarefa recorrente existente, manter o `dueDate` atual como ancora
  mais segura disponivel. Nao tentar inventar ocorrencias anteriores.
- Converter o `lastCompletedAt` atual, quando houver, em no maximo um evento:
  associar a ocorrencia derivada mais proxima que seja anterior ou igual a
  `lastCompletedAt`.
- Executar a conversao de forma idempotente no primeiro carregamento/projecao
  e registrar uma versao de schema no YDoc para que ela nao se repita.
- Validar manualmente notas com recorrencias ja concluidas antes do rollout.

## Testes obrigatorios

1. Semanal: conclui 07/jul, nao conclui 14/jul, abre em 21/jul. Devem existir
   14/jul atrasada e 21/jul pendente.
2. Concluir atrasada nao altera nem remove a ocorrencia atual.
3. Concluir a mesma ocorrencia em dois dispositivos converge para um unico
   completion por `taskId + scheduledAt`.
4. Retry de sync, reload do app e compactacao YDoc nao criam duplicatas.
5. Desfazer remove somente o evento da ocorrencia selecionada.
6. Mensal em dias inexistentes, dias uteis, fuso e horario configurado mantem
   as datas esperadas.
7. Migracao de tarefa recorrente antiga preserva o template e nao apaga
   historico existente.
8. Integracao Flutter/Go confirma que a mesma lista e exibida apos sync em um
   segundo dispositivo.

## Criterios de aceite

- Nenhuma ocorrencia atrasada e substituida por uma futura.
- Nenhuma conclusao duplica em sync concorrente.
- A recorrencia nao cria uma linha de `tasks` por periodo.
- O banco armazena apenas templates e eventos de conclusao/dispensa.
- A alteracao de uma recorrencia futura nao reescreve o historico concluido.
- O fluxo continua offline-first: a conclusao aparece localmente de imediato e
  converge pelo YDoc quando a conexao retorna.

## Fora de escopo desta entrega

- Interface de "dispensar" uma ocorrencia, embora o contrato deixe espaco para
  isso.
- Remodelacao visual do modal de data/recorrencia. Ela deve ser tratada depois
  que o contrato de recorrencia estiver estabilizado.
