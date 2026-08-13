# Design: projeção incremental de tarefas no fluxo REST/OT

Data: 2026-08-12  
Status: superseded by `2026-08-12-task-document-native-design.md`

Este documento fica preservado como histórico da alternativa de projeção
incremental. Ele não deve ser executado: o design atual remove a dependência
runtime da projeção relacional de tasks.

## Contexto

O item 1 da revisão arquitetural propõe projetar somente o que a operação
alterou. Hoje, depois do debounce de uma edição, o fluxo:

1. serializa o documento inteiro;
2. percorre todos os blocos;
3. carrega todas as tarefas ativas da nota;
4. marca como removidas as tarefas ausentes;
5. faz upsert de todas as tarefas.

O documento REST/OT continua sendo a fonte canônica. A tabela `tasks` é uma
projeção local e não pode se tornar uma segunda fonte de verdade.

Esta especificação cobre alterações locais, remotas e operações pendentes após
rebase. O relatório de pesquisa externa está em
[`docs/research/2026-08-12-incremental-projection-market-practices.md`](../../research/2026-08-12-incremental-projection-market-practices.md).

## Objetivos

- reduzir leituras, upserts e deletes de tarefas para mudanças pequenas;
- preservar a projeção atual de `content` e `excerpt` no primeiro corte;
- usar o mesmo modelo de impacto para operações locais, remotas e rebased;
- manter rebuild determinístico para hydration, recovery, repair e inconsistências;
- provar que a projeção incremental é igual à projeção completa;
- não alterar o contrato REST/OT nem adicionar um índice durável por bloco.

## Não objetivos

- projetar `content` ou `excerpt` incrementalmente nesta fase;
- criar uma tabela de índice por bloco;
- alterar o formato ou a semântica das operações REST/OT;
- adicionar uma camada de compatibilidade para versões antigas;
- permitir escritas diretas na tabela `tasks` fora do caminho de projeção;
- refatorar outras partes do sync que não sejam necessárias para transportar o
  change set.

## Decisões

### 1. Estratégia híbrida

O caminho normal usa um change set derivado das operações. O caminho completo
continua existindo para:

- primeira hidratação;
- recovery de sessão ou fila pendente;
- repair explícito;
- snapshot remoto sem operações classificáveis;
- operação desconhecida ou inválida;
- falha em determinar identidade, ordem ou dependência;
- divergência de revisão ou de projeção.

`requiresFullRebuild` é explícito. Uma falha incremental não deve ser escondida
por um fallback silencioso que mascare perda de contexto. A transação falha e o
erro permanece observável; um recovery ou repair posterior pode solicitar o
rebuild.

### 2. Change set dirigido por operações

O change set é criado na fronteira editor/sync, onde ainda há contexto da
operação e do rebase. O projetor de tarefas não interpreta wire operations. Ele
recebe somente um snapshot final imutável e o impacto calculado.

O mesmo contrato vale para local, remoto e rebased. A origem pode ser registrada
para telemetry, mas não muda a regra de seleção de tarefas.

### 3. Fase inicial limitada às tarefas

`content` e `excerpt` continuam sendo calculados a partir de todos os blocos.
Isso mantém uma única regra para conteúdo agregado e evita uma otimização
separada para o limite de 200 caracteres do excerpt.

Somente as linhas de tarefas afetadas são lidas e gravadas incrementalmente.

### 4. Mudanças estruturais usam um sufixo conservador

O campo atual `tasks.position` deriva do índice do bloco. Portanto, inserir,
remover ou mover um bloco pode alterar a posição de tarefas que não foram
editadas diretamente.

Para esses casos, a projeção recalcula todos os blocos a partir da menor posição
afetada até o fim do documento. Se essa posição não puder ser calculada com
segurança, o change set exige rebuild completo.

### 5. Nenhum índice durável nesta fase

O snapshot canônico e os IDs estáveis dos blocos são suficientes para validar o
primeiro corte. Um índice durável adicionaria estado derivado, invalidação,
migração e outro caminho de repair. Ele só deve ser considerado se o benchmark
mostrar que a faixa afetada ainda é insuficiente.

## Contrato do `ProjectionChangeSet`

O objeto é interno ao app e não altera o contrato REST/OT:

```dart
class ProjectionChangeSet {
  final Set<String> changedBlockIds;
  final Set<String> deletedBlockIds;
  final int? firstAffectedIndex;
  final bool hasStructuralChange;
  final bool requiresFullRebuild;
  final int? canonicalRevision;
  final Set<String> operationIds;
}
```

Semântica:

- `changedBlockIds`: blocos criados ou alterados cujo estado final deve ser
  lido. O ID pode representar uma linha nova, uma linha atualizada ou uma
  conversão entre tarefa e bloco comum.
- `deletedBlockIds`: IDs que não existem no snapshot final e cujas linhas devem
  deixar de ser ativas.
- `firstAffectedIndex`: início do sufixo estrutural. É nulo para alterações
  não estruturais.
- `hasStructuralChange`: indica que os IDs posteriores também podem ter
  recebido uma nova posição.
- `requiresFullRebuild`: quando verdadeiro, os demais campos servem apenas
  para diagnóstico.
- `canonicalRevision`: revisão canônica conhecida. Em uma alteração local, é a
  revisão-base confirmada que contém as operações pendentes; não representa uma
  nova revisão do servidor.
- `operationIds`: identificadores usados para coalescência, telemetry e
  diagnóstico.

As seguintes invariantes devem ser normalizadas pelo builder:

- um ID em `deletedBlockIds` não permanece em `changedBlockIds`;
- um ID alterado deve existir no snapshot final, salvo se o conjunto for marcado
  para rebuild;
- uma mudança estrutural sem `firstAffectedIndex` exige rebuild;
- um conjunto que exige rebuild não deve ser aplicado pelo caminho incremental.

## Classificação de operações

| Operação | Change set |
| --- | --- |
| `text_delta` | `changedBlockIds` com o bloco alvo |
| `set_block_type` | `changedBlockIds` com o bloco alvo; pode criar ou remover uma tarefa |
| `set_block_metadata` | `changedBlockIds` com o bloco alvo |
| `complete_task_occurrence` | `changedBlockIds` com o bloco alvo |
| `create_block` | novo ID em `changedBlockIds` e sufixo a partir do novo índice |
| `delete_block` | ID em `deletedBlockIds` e sufixo a partir do índice anterior |
| `move_block` | ID em `changedBlockIds` e sufixo a partir de `min(oldIndex, newIndex)` |
| operação desconhecida ou payload inválido | `requiresFullRebuild = true` |

O impacto estrutural deve ser calculado no ponto que conhece a ordem anterior e
a ordem final. O índice não deve ser inferido somente de uma posição textual
posterior ao rebase.

## Fluxo e ownership

### Alterações locais

1. `EditorOperationCapture` identifica IDs alterados e o impacto estrutural a
   partir do mesmo `DocumentChangeLog` que gera as operações.
2. `NoteOperationAdapter` associa a revisão-base confirmada e os IDs das
   operações.
3. O outbox é persistido.
4. Depois de o outbox confirmar, o change set entra na fila da sessão.
5. A sessão coalesce conjuntos consecutivos antes da execução.

Se a persistência do outbox falhar, a operação permanece no adapter para retry e
nenhum callback de projeção é confirmado para aquela tentativa.

### Alterações remotas e rebase

1. O sync recebe o snapshot canônico, as operações remotas e as operações locais
   pendentes após o rebase.
2. O adapter aplica o snapshot e as operações pendentes ao editor.
3. O impacto remoto e o impacto rebased são unidos em um único change set.
4. A projeção usa o estado final, nunca uma operação remota isolada sobre um
   estado antigo.
5. Uma resposta que seja somente confirmação de operações já projetadas não
   cria trabalho adicional.
6. Se um snapshot for aplicado sem operações capazes de explicar seu impacto,
   o resultado exige rebuild completo.

### Fila da sessão

Cada unidade de trabalho contém:

- um snapshot imutável dos blocos no início da projeção;
- o `ProjectionChangeSet` correspondente;
- a revisão canônica conhecida.

Ao coalescer conjuntos:

- os IDs alterados são unidos;
- os IDs removidos são unidos e prevalecem sobre IDs alterados;
- `hasStructuralChange` é a disjunção dos conjuntos;
- `firstAffectedIndex` é o menor índice conhecido;
- `requiresFullRebuild` prevalece;
- a revisão e o snapshot mais recentes são usados;
- os IDs de operação são unidos para diagnóstico.

Novas edições ocorridas durante uma transação de banco entram no próximo
conjunto. Isso evita misturar um snapshot antigo com IDs de uma edição posterior.

## Algoritmo de projeção

O `TaskProjectionEngine` deve receber o snapshot final e o change set.

1. Percorrer o snapshot uma vez para calcular `content` e `excerpt`.
2. Se o conjunto exigir rebuild, usar o caminho completo atual para todas as
   tarefas.
3. Se a mudança não for estrutural, projetar somente os blocos em
   `changedBlockIds`.
4. Se for estrutural, projetar todos os blocos a partir de
   `firstAffectedIndex`.
5. Incluir `deletedBlockIds` na lista de IDs afetados, mesmo que não apareçam no
   snapshot final.
6. Para cada bloco projetado como `task`, produzir um `ProjectedTask` com a
   posição final.
7. Para cada bloco afetado que não seja `task`, remover a linha antiga com o
   mesmo ID.

O projetor puro deve compartilhar a mesma regra de conversão usada pelo rebuild
completo. A diferença é a seleção dos blocos, não a semântica de título,
completion, recurrence, due date ou reminder.

## Persistência incremental

Adicionar uma operação de banco específica, sem abrir uma segunda transação
interna:

```dart
applyProjectedTaskChanges(
  noteId: noteId,
  affectedBlockIds: affectedBlockIds,
  deletedBlockIds: changeSet.deletedBlockIds,
  projectedTasks: projectedTasks,
  userId: userId,
)
```

Dentro de `AppDatabase.saveIncrementalProjectedDocument`:

1. atualizar `notes.content` e `notes.excerpt`;
2. consultar somente tarefas ativas cujos IDs estejam em
   `affectedBlockIds`;
3. marcar como removidas as tarefas consultadas que não estejam em
   `projectedTasks`;
4. fazer upsert das tarefas projetadas;
5. confirmar conteúdo e tarefas na mesma transação.

`TasksDao` não classifica operações e não acessa o documento canônico. Ele
aplica apenas os IDs e tarefas já calculados pelo engine.

Não editar código gerado pelo Drift. Esta fase não requer alteração de schema.

## Rebuild e falhas

Solicitar rebuild completo para:

- hydration inicial;
- recovery de sessão ou fila;
- repair explícito;
- snapshot remoto sem operações classificáveis;
- operação desconhecida, payload inválido ou ID ausente;
- falha ao determinar ordem anterior ou final;
- revisão incompatível com o change set;
- divergência detectada entre a projeção incremental e a projeção de referência.

O motivo do rebuild deve ser registrado em telemetry. Falhas de banco devem
causar rollback atômico e permanecer observáveis para retry ou repair. O caminho
incremental não deve capturar uma exceção e executar um rebuild silencioso.

## Correção e testes

### Testes unitários

- classificar cada tipo de operação;
- normalizar IDs alterados e removidos;
- calcular índices para create, delete e move;
- exigir rebuild quando o impacto estrutural for desconhecido;
- projetar um único bloco de tarefa;
- projetar um intervalo estrutural;
- converter tarefa em bloco comum e bloco comum em tarefa;
- calcular recurrence, due date, reminder e completion com a mesma regra do
  caminho completo.

### Testes de persistência

- atualizar somente IDs afetados;
- remover uma tarefa que deixou de ser tarefa;
- inserir uma tarefa nova;
- preservar tarefas fora da faixa;
- atualizar posições do sufixo após insert, delete e move;
- confirmar rollback quando o upsert falhar;
- garantir que conteúdo e tarefas não sejam confirmados separadamente.

### Testes de sessão e sync

- lote local depois de persistir o outbox;
- lote remoto com operações rebased;
- delete remoto de uma operação local pendente;
- confirmação local sem nova projeção;
- snapshot remoto sem operações causando rebuild;
- coalescência de várias edições antes da transação;
- edição ocorrida enquanto uma projeção anterior está aguardando o banco.

### Oráculo de correção

Depois de cada caso de teste, comparar:

1. resultado da projeção incremental;
2. resultado de um rebuild completo do mesmo snapshot.

A comparação deve cobrir todas as colunas projetadas de tarefas e os valores de
`content` e `excerpt`. Um ganho de desempenho não compensa qualquer divergência.

## Benchmark

Criar fixtures com 1, 100 e 1.000 blocos, contendo tarefas no início, meio e
fim. Medir separadamente:

- serialização e decodificação;
- cálculo de conteúdo e excerpt;
- cálculo das tarefas;
- número de IDs consultados;
- número de leituras, upserts e deletes SQLite;
- duração total da transação;
- quantidade de rebuilds completos.

Casos mínimos:

- texto em tarefa no início, meio e fim;
- metadata de tarefa;
- criação e remoção de bloco comum;
- criação, remoção e movimento de tarefa;
- mudança de tipo;
- lote remoto com rebase local;
- operação desconhecida.

Não definir uma meta percentual antes de medir. O benchmark deve registrar o
custo atual, o custo incremental e a igualdade com o rebuild de referência.

## Telemetry

Registrar, sem conteúdo privado do documento:

```text
projectionMode
operationCount
changedBlockCount
affectedBlockCount
projectedTaskCount
rowsRead
rowsUpserted
rowsDeleted
canonicalRevision
fullRebuildReason
```

O objetivo é distinguir ganho real de projeção incremental, custo inevitável da
serialização completa e frequência de rebuilds por perda de contexto.

## Critérios de aceitação

- alterações locais, remotas e rebased usam o mesmo modelo de change set;
- uma alteração simples não carrega todas as tarefas da nota;
- uma alteração estrutural atualiza o sufixo necessário;
- `content` e `excerpt` continuam corretos;
- hydration, recovery, repair e inconsistências usam rebuild completo;
- o rebuild e a projeção incremental produzem resultados iguais;
- conteúdo e tarefas são persistidos atomicamente;
- não há escrita direta de tarefa fora do engine/DAO de projeção;
- não há alteração do contrato REST/OT, índice durável ou migração;
- o benchmark documenta custo e número de linhas afetadas para 1, 100 e 1.000
  blocos.

## Fontes

- [Revisão arquitetural local](file:///C:/Users/rigleyc/AppData/Local/Temp/supanotes-architecture-review-2026-08-12.html)
- [Pesquisa de práticas externas](../../research/2026-08-12-incremental-projection-market-practices.md)
- [ProseMirror transform](https://github.com/ProseMirror/prosemirror-transform/blob/master/src/transform.ts)
- [Yjs](https://github.com/yjs/yjs)
- [Lexical listeners](https://lexical.dev/docs/concepts/listeners)
- [PowerSync protocol](https://docs.powersync.com/architecture/powersync-protocol)
- [Figma: making multiplayer more reliable](https://www.figma.com/blog/making-multiplayer-more-reliable/)
