# Plan 005: Migrar tasks para o documento canônico da nota

> **Executor instructions:** Execute este plano em ordem. Não remova uma rota,
> tabela ou campo antes de concluir o inventário de produção e a etapa de
> preservação correspondente. Se uma condição da seção **STOP** ocorrer, pare
> e reporte o caso; não invente uma conversão.
>
> **Drift check:** `rtk git diff --stat 0656c720..HEAD -- lib backend test plans`
> Se algum caminho em escopo mudou desde o commit planejado, compare o estado
> atual antes de executar a etapa.

## Status

- **Priority:** P1
- **Effort:** L
- **Risk:** HIGH
- **Depends on:** none
- **Category:** migration | tech-debt | correctness
- **Planned at:** commit `0656c720`, 2026-08-12
- **Design:** [tasks nativas do documento](../docs/superpowers/specs/2026-08-12-task-document-native-design.md)
- **Plan status:** design aprovado; implementação local concluída; gates de
  produção e limpeza física ainda pendentes
- **Operational runbook:**
  [task-document-migration-runbook](../docs/operations/task-document-migration-runbook.md)

Este plano executa o design aprovado. Ele substitui a alternativa de projeção
incremental descrita em `docs/superpowers/specs/2026-08-12-incremental-task-projection-design.md`.
O documento antigo permanece apenas como histórico e não deve ser executado.

## Objetivo

Fazer com que uma task exista apenas como um `TaskNode` dentro do documento da
nota. O documento REST/OT continua sendo a fonte canônica. A tabela relacional
`tasks`, `TaskModel`, os providers globais e as rotas antigas deixam de fazer
parte do caminho de runtime.

## Arquitetura alvo

```text
Documento canônico da nota
  ├── TaskNode usado pelo editor
  ├── snapshot confirmado local para sync
  ├── snapshot efetivo local para offline e notificações
  └── REST/OT para persistência e colaboração
```

O snapshot efetivo local é o documento confirmado mais as operações locais
pendentes. Ele é uma materialização genérica do documento, não uma tabela de
tasks e não uma segunda fonte de verdade. Ele é necessário porque o snapshot
confirmado pode estar antigo enquanto o usuário edita offline.

As notificações leem tasks do snapshot efetivo e recebem somente um DTO pequeno
de leitura, por exemplo:

```dart
class TaskNotificationEntry {
  const TaskNotificationEntry({
    required this.id,
    required this.title,
    required this.dueDate,
    required this.hasTime,
    required this.reminder,
  });

  final String id;
  final String title;
  final DateTime dueDate;
  final bool hasTime;
  final String? reminder;
}
```

Esse DTO não substitui o `TaskNode` como modelo do produto. Ele existe apenas
na borda do scheduler para evitar que o scheduler dependa de Drift, `TaskModel`
ou de uma tabela global.

## Contrato de dados

Antes de remover qualquer fallback, registrar e aplicar este contrato:

- O ID da task é o ID estável do bloco (`TaskNode.id`).
- O texto do bloco é o título.
- `isCompleted` é o estado canônico para task não recorrente.
- `dueDate` é a âncora da série recorrente. A ocorrência efetiva é calculada
  por um único `TaskOccurrencePolicy` usando a âncora e `completions`; uma
  leitura nunca grava a data calculada de volta no documento.
- `hasTime` distingue uma data com hora de uma data de dia inteiro.
- `recurrenceRule` é a única chave de recorrência em runtime. O alias
  `recurrence` é normalizado antes da nova versão e não é lido como fallback.
- Os valores de recorrência canônicos são os nomes suportados por
  `TaskRecurrence` (`daily`, `weekdays`, `weekly`, `monthly`). Valores antigos
  como `FREQ=DAILY` precisam ser convertidos antes do cutover ou classificados
  como não convertidos.
- `reminder` continua sendo metadado do bloco e mantém os valores aceitos pelo
  `TaskNotificationScheduler`.
- `completions` continua no documento para ocorrências recorrentes. Cada chave
  é a identidade de calendário de `scheduledAt`, sem offset de fuso, e cada
  valor é `completedAt`, o instante real de conclusão em UTC.
- Conclusões antecipadas consecutivas são permitidas: concluir 12 no dia 10,
  depois 19 no dia 10, avança a série para 26.
- A recorrência mensal preserva o dia da âncora: 31 de janeiro, 28 de
  fevereiro e 31 de março pertencem à mesma série.
- `lastCompletedAt`, se continuar sendo usado para tasks não recorrentes, deve
  ser incluído explicitamente no contrato Dart, Go e de compartilhamento. Não
  depender de metadado desconhecido para preservar uma informação importante.
- `checked`, quando existir sem `isCompleted`, é convertido para
  `isCompleted`. Depois da normalização, o runtime não mantém os dois nomes.

Para documentos antigos em que o controller já avançou `dueDate` após uma
conclusão, o valor atual de `dueDate` será adotado como a base da nova série e
as entradas existentes de `completions` serão preservadas. Não se tenta
reconstruir uma âncora histórica ausente a partir da projeção relacional.

## Por que esta migração é necessária

O código atual possui três problemas concretos:

- [ARCHITECTURE.md](../ARCHITECTURE.md:51) define o documento como fonte
  canônica, mas o backend ainda expõe CRUD direto para `tasks` em
  `backend/cmd/server/main.go:197` e `backend/internal/tasks/service.go:56`.
- O editor usa uma projeção `TaskModel` para editar um `TaskNode` em
  `lib/features/notes/editor/presentation/note_editor_screen.dart:48`.
- O scheduler lê `TaskData` da tabela `tasks` em
  `lib/features/tasks/domain/task_notification_scheduler.dart:16`, enquanto
  o snapshot confirmado local não contém as operações offline pendentes.

O último ponto é o principal risco da proposta inicial: ler apenas
`local_note_documents.documentJson` faria uma alteração offline de lembrete,
data ou recorrência desaparecer das notificações até a confirmação remota.

## Estado atual que o executor deve confirmar

- `lib/core/database/tables/local_note_documents.dart` armazena o snapshot
  confirmado. `NoteOperationsDao.watchNoteDocument` é usado pelo sync.
- `lib/features/notes/editor/sync/note_operation_adapter.dart:124-150`
  reconstrói o documento efetivo aplicando operações pendentes ao snapshot
  confirmado.
- `lib/features/notes/editor/sync/note_operation_adapter.dart:236-275`
  persiste as operações, mas não persiste um snapshot efetivo completo.
- `lib/features/notes/editor/sync/note_sync_session.dart:124-153` envia o
  documento vivo para `TaskProjectionEngine` depois de alterações locais.
- `lib/features/tasks/domain/note_document_projector.dart:63-102` transforma
  blocos em `ProjectedTask` e calcula uma data derivada.
- `lib/core/database/database.dart:101-155` grava conteúdo e projeção de tasks
  na mesma transação.
- `lib/features/notes/editor/presentation/note_editor_screen.dart:88-112`
  carrega `NoteWithTasks`; `:403-497` passa o mapa de `TaskModel` para o editor.
- `lib/features/notes/editor/presentation/widgets/custom_task_component.dart:32`
  recebe o mapa de `TaskModel` para badges, recorrência e visibilidade.
- `lib/features/tasks/domain/task_notification_scheduler.dart:37-117`
  mantém cache por usuário, cancela notificações antigas e reage ao stream de
  tasks abertas.
- `lib/core/database/daos/note_lifecycle_dao.dart:43-78` remove tasks e
  snapshots ao apagar uma nota.
- `backend/internal/mcp/tools_notes.go:250-267` ainda lista tasks diretamente
  pela tabela relacional. Os demais comandos MCP de task já usam operações do
  documento e devem ser mantidos.

## Comandos de verificação disponíveis

Estes comandos são gates para a execução futura. Eles não foram executados ao
escrever este plano.

| Objetivo | Comando | Resultado esperado |
|---|---|---|
| Analisar Flutter | `rtk flutter analyze --no-fatal-infos` | exit 0, sem erro |
| Suite Flutter focada | `rtk flutter test test/features/notes test/features/tasks` | todos os testes passam |
| Backend curto | `rtk go test -count=1 -short ./...` a partir de `backend` | exit 0 |
| Backend vet | `rtk go vet ./...` a partir de `backend` | exit 0 |
| Regenerar Drift | `rtk dart run build_runner build --delete-conflicting-outputs` | codegen concluído |
| Regenerar sqlc | `rtk make sqlc` a partir de `backend` | bindings atualizados |
| Espaços no diff | `rtk git diff --check` | nenhuma saída |

## Escopo

### Em escopo

- Contrato canônico de metadados de task.
- Snapshot efetivo local para alterações offline.
- Fonte de notificações baseada em documentos de nota.
- Editor e sheet de metadados sem `TaskModel`.
- Remoção dos providers e repositórios globais sem consumidores.
- Remoção das rotas backend e do MCP `list_tasks` que escrevem ou leem a
  tabela antiga.
- Reconciliação e preservação dos dados de produção existentes.
- Remoção posterior das tabelas e bindings relacionais quando não houver dados
  não classificados nem consumidores.
- Documentação viva de arquitetura e lifecycle.

### Fora de escopo

- Criar uma tela global de tasks.
- Alterar o contrato REST/OT de operações de documento sem necessidade.
- Trocar o provedor de notificações locais.
- Redesenhar a UI da task.
- Mudar a política de timezone ou a regra de lembretes.
- Fazer uma nova otimização incremental da tabela `tasks`; este plano remove
  essa dependência e supersede o plano de projeção incremental.
- Apagar dados antigos antes da reconciliação aprovada.

## Processo de preservação de dados de produção

Esta etapa é obrigatória antes de remover o runtime antigo.

### 1. Criar backup verificável

- Criar um backup consistente do PostgreSQL usando o procedimento de produção.
- Exportar separadamente `tasks` e `task_completions`, incluindo linhas soft
  deleted, para armazenamento seguro fora do repositório.
- Incluir no preflight do banco local uma contagem de rows de `tasks` e
  `local_task_completions` sem correspondência no snapshot efetivo da nota.
  Essa contagem deve ser zero antes do drop; caso contrário, conservar as
  tabelas locais e reportar o banco para reconciliação.
- Registrar apenas contagens, hashes de IDs e resultados agregados no projeto;
  não gravar títulos, e-mails, tokens ou conteúdo de notas em arquivos do repo.
- Restaurar o backup em staging e confirmar que as tabelas e o JSONB de
  `notes.document` podem ser lidos. Um arquivo de backup não verificado não é
  uma proteção suficiente.

### 2. Executar inventário somente leitura

Criar um relatório SQL operacional com transação `READ ONLY` que:

- conte tasks por usuário, nota e status;
- conte completions por task;
- extraia `notes.document.blocks[*]` para localizar blocos `type = 'task'`;
- compare `tasks.id` com o ID do bloco;
- compare título, status, data, recorrência, `has_time` e `reminder`;
- compare `task_completions` com `metadata.completions`;
- identifique tasks sem nota, tasks de nota soft deleted, IDs duplicados,
  recorrências não suportadas, datas inválidas e aliases de metadados.

Classificar cada linha legada em uma destas categorias:

1. **Correspondente:** existe bloco canônico com o mesmo ID. O documento é a
   fonte; diferenças viram relatório de divergência, nunca sobrescrita
   automática.
2. **Órfã com nota viva:** não existe bloco, mas existe nota ativa. Criar uma
   proposta de importação usando o ID legado somente quando título, posição e
   metadados forem suficientes. A importação deve ocorrer pelo caminho
   canônico e ser registrada.
3. **Órfã sem nota ativa:** preservar no export/backup e não anexar a uma nota
   por inferência.
4. **Conflitante:** há bloco correspondente, mas o documento e a tabela têm
   valores diferentes. Parar a remoção até a política do caso ser aprovada.

As completions legadas seguem a mesma regra. Quando houver correspondência
segura, elas podem ser incorporadas ao mapa canônico sem substituir uma
ocorrência já registrada. Conflitos ficam no relatório e no backup; não são
resolvidos por `MAX(completed_at)` ou outra heurística silenciosa.

### 3. Normalizar antes do novo runtime

- Converter `recurrence` para `recurrenceRule` somente quando a chave canônica
  estiver ausente.
- Converter valores conhecidos como `FREQ=DAILY` para o enum canônico.
- Converter `checked` para `isCompleted` somente quando necessário.
- Preservar `completions` e `lastCompletedAt` durante a reescrita.
- Parar diante de qualquer valor desconhecido, documento inválido ou conflito.

Essa normalização deve ser uma operação única, transacional e observável antes
do deploy que remove os fallbacks. Não adicionar fallback permanente no app ou
no backend.

### 4. Cutover e retenção

- Confirmar que não há tráfego do app atual ou de integrações autorizadas para
  `/tasks` antes de remover as rotas.
- Fazer o novo app e o backend lerem o documento canônico.
- Manter o export e o backup pelo período de retenção definido pela operação.
- Remover as tabelas somente depois de todas as categorias do inventário terem
  destino documentado e o período de observação ter terminado.
- Se uma linha não puder ser importada sem adivinhação, manter seu registro no
  arquivo de preservação. Não fabricar uma task dentro de uma nota errada.

## Etapas de implementação

### Step 1: Fechar o contrato e o inventário de dados

**Files:**

- Create: `backend/db/maintenance/task_document_inventory.sql` — relatório
  `READ ONLY`, sem dados de conteúdo na saída versionada.
- Create: `docs/architecture/task-document-contract.md` — contrato final de
  chaves, recorrência, ocorrência, lembrete e classificação de legado.
- Read: `ARCHITECTURE.md`, `lib/core/database/README.md`,
  `lib/features/tasks/README.md`, `backend/internal/noteoperations/README.md`.

**Actions:**

- Registrar os resultados agregados do inventário de produção fora do código.
- Aprovar a disposição de todas as tasks órfãs e completions órfãs.
- Confirmar que `dueDate` passa a ser a âncora da nova série, preservando o
  futuro observável dos documentos legados que já usavam um cursor avançado.
  - Confirmar que cada cliente autorizado com a nota local pode agendar o
  reminder compartilhado; Share Link de leitura não cria agenda local.

**Verify:** executar o SQL com transação somente leitura e gerar contagens de
`correspondente`, `órfã`, `conflitante` e `não convertida`. Resultado esperado:
nenhuma categoria sem decisão e nenhum valor secreto no relatório.

### Step 2: Normalizar o contrato de task no documento

**Files:**

- Modify: `lib/features/notes/editor/document/note_document_codec.dart`.
- Modify: `lib/features/tasks/domain/task_recurrence.dart`.
- Modify: `lib/features/notes/editor/application/note_editor_controller.dart`.
- Modify: `backend/internal/noteoperations/public_document.go`.
- Modify: `backend/internal/noteoperations/document.go` e os contratos de
  operação relacionados.
- Modify: `contracts/note_document/corpus.json` se o corpus estiver alinhado ao
  contrato atual.

**Actions:**

- Escrever somente `recurrenceRule` no controller.
- Escrever somente `isCompleted` para o estado principal.
- Fazer o codec validar `completions` e `lastCompletedAt` com tipos explícitos
  se esses campos forem mantidos.
- Fazer o backend validar e preservar os mesmos campos.
- Colocar a normalização de dados antigos no backfill operacional da Step 1,
  antes de retirar os leitores antigos.

**Verify:** `rtk rg -n "metadata\['recurrence'\]|metadata\['checked'\]" lib backend`
deve mostrar somente o normalizador operacional ou documentação de legado; o
runtime deve escrever apenas as chaves canônicas.

### Step 3: Persistir o documento efetivo local

**Files:**

- Modify: `lib/core/database/tables/local_note_documents.dart` — adicionar
  `materializedDocumentJson` e `materializedUpdatedAt`, mantendo
  `documentJson` como snapshot confirmado. Os novos campos podem ser
  nullable durante a migração, mas rows existentes devem ser inicializadas a
  partir de `documentJson` e `updatedAt` antes de o novo source ser ativado.
- Modify: `lib/core/database/daos/note_operations_dao.dart` — leitura e escrita
  separadas para confirmado e efetivo.
- Modify: `lib/core/database/database.dart` — transações do agregado.
- Modify: `lib/core/sync/note_operations_sync_service.dart` — persistir a
  materialização local junto da outbox e atualizar após rebase.
- Modify: `lib/features/notes/editor/sync/note_operation_adapter.dart` —
  codificar o documento vivo no flush e após reconstrução.
- Modify: `lib/features/notes/editor/sync/note_sync_session.dart` — publicar a
  materialização depois de alterações locais, hydration e reconciliação.
- Modify: `lib/core/database/daos/note_lifecycle_dao.dart` — apagar a
  materialização junto do agregado da nota.

**Actions:**

- Não sobrescrever o snapshot confirmado com operações não confirmadas.
- Ao persistir operações locais, gravar a versão efetiva na mesma transação
  da outbox.
- Ao fazer rebase, gravar o snapshot confirmado recebido e o documento efetivo
  resultante da aplicação das operações restantes.
- Para drafts sem snapshot confirmado, guardar um documento confirmado vazio e
  o documento efetivo local; não perder o conteúdo local.
- Na abertura, reconstruir a materialização se ela estiver ausente ou atrás da
  outbox. O processo deve usar a mesma aplicação de operações da sessão.
- Manter `revision` do confirmado separado de `materializedUpdatedAt`.

**Verify:** desligar a rede em uma sessão de nota, alterar lembrete/data de uma
task, fechar o editor, reabrir a aplicação e ler a materialização local. O
documento efetivo deve conter a alteração, enquanto o snapshot confirmado deve
continuar com a revisão remota original até o sync.

### Step 4: Criar a fonte de tasks para notificações

**Files:**

- Create: `lib/features/tasks/domain/task_notification_entry.dart` — DTO
  mínimo de leitura.
- Create: `lib/features/tasks/domain/note_task_notification_source.dart` —
  stream dos snapshots efetivos locais.
- Create: `lib/features/tasks/domain/note_task_reader.dart` — extrator de
  `TaskNode`/bloco canônico e metadados.
- Modify: `lib/features/tasks/domain/task_occurrence.dart` — único resolver
  usado pelo editor, source e scheduler.
- Modify: `lib/features/tasks/domain/task_notification_scheduler.dart` —
  remover `TaskData`, `TasksLocalRepository` e `openTasksStreamProvider`.
- Modify: `lib/main.dart` somente se o bootstrap precisar ouvir o novo
  provider.

**Actions:**

- Ler snapshots efetivos de notas não deletadas e materializadas.
- Incluir notas compartilhadas para todos os clientes autorizados que possuem
  uma cópia local; não usar `notes.userId` como filtro de ownership.
- Não criar notificações para visitantes de Share Link, que não possuem uma
  sessão local da nota.
- Usar o documento vivo/materializado da nota aberta, não um snapshot remoto
  antigo enquanto houver sessão ativa.
- Cancelar notificações quando a nota for deletada, o bloco desaparecer, a
  task for concluída, o lembrete for removido ou o usuário mudar.
- Preservar o limite de 30 notificações, o cache por usuário, os IDs derivados
  de `userId + taskId`, os horários locais e o comportamento de DST.
- Não gravar a próxima ocorrência durante uma leitura. Toda alteração
  canônica deve vir da operação do editor ou do comando REST/OT.

**Verify:** o scheduler não pode importar `TaskData`, `TasksDao`,
`TasksLocalRepository` ou `TaskModel`. A reconciliação deve manter o mesmo ID
para uma task existente e cancelar IDs ausentes.

### Step 5: Remover `TaskModel` do editor da nota

**Files:**

- Create: `lib/features/tasks/presentation/controllers/task_metadata_draft.dart`
  — objeto pequeno da interface da sheet; não é entidade persistida.
- Create: `lib/features/notes/editor/document/task_node_metadata.dart` —
  leitura somente do `TaskNode` e parser dos metadados canônicos.
- Modify: `lib/features/notes/editor/presentation/note_editor_screen.dart` —
  remover `_taskForMetadata`, `NoteWithTasks` e o mapa de `TaskModel`.
- Modify: `lib/features/notes/editor/presentation/widgets/note_editor.dart` —
  ler metadata do node ou do snapshot específico do editor.
- Modify: `lib/features/notes/editor/presentation/widgets/custom_task_component.dart`
  — derivar data, hora e recorrência do `TaskNode` atual.
- Modify: `lib/features/tasks/presentation/controllers/task_metadata_controller.dart`
  e `task_metadata_sheet.dart` — receber um snapshot de edição, não
  `TaskModel`, e salvar somente quando houver mudança.
- Modify: `lib/features/notes/catalog/data/notes_repository.dart`,
  `lib/features/notes/catalog/application/notes_providers.dart`,
  `lib/core/database/daos/notes_dao.dart` — substituir `watchNoteWithTasks`
  pelo stream da nota sem join relacional de tasks.
- Delete after callers are removed: `lib/features/notes/catalog/model/note_with_tasks.dart`.

**Actions:**

- A sheet deve abrir com os valores do `TaskNode` atual da sessão.
- A sheet recebe e devolve `TaskMetadataDraft`, com `scheduleAnchor`,
  `hasTime`, `recurrence` e `reminder`; não recebe `TaskModel`, `TaskData`,
  `NoteModel` ou timestamps do banco.
- O draft deve conservar distinção entre “não alterar” e “limpar” data,
  recorrência e lembrete.
- O fechamento sem alteração não deve emitir `ReplaceNodeRequest`.
- A ação de salvar deve chamar somente `updateTaskMetadataInEditor`.
- O texto, estado de conclusão, ordem e ID continuam no documento/editor.

**Verify:** `rtk rg -n "TaskModel|NoteWithTasks|watchNoteWithTasks" lib/features/notes lib/core/database`
não deve encontrar uso ativo no editor; qualquer ocorrência restante deve
estar em um arquivo explicitamente em remoção.

### Step 6: Parar de criar a projeção relacional de tasks

**Files:**

- Modify: `lib/features/notes/editor/application/note_editor_provider.dart`
  e `note_sync_session.dart` — remover `TaskProjectionEngine` da sessão.
- Modify: `lib/core/database/database.dart` — remover argumentos e transações
  de `ProjectedTask`.
- Modify: `lib/features/notes/catalog/data/note_catalog_sync.dart` — manter
  apenas projeção de conteúdo/excerpt e snapshot efetivo; não gerar rows de
  tasks.
- Split or delete: `lib/features/tasks/domain/note_document_projector.dart`
  e `projected_document.dart` para que conteúdo e tasks tenham fronteiras
  separadas.
- Delete after search is clean: `lib/features/tasks/domain/task_model.dart`,
  `projected_task.dart`, `task_projection_engine.dart`,
  `lib/core/database/daos/tasks_dao.dart`,
  `lib/core/database/tables/tasks.dart`,
  `lib/core/database/daos/task_completions_dao.dart`,
  `lib/core/database/tables/task_completions.dart`,
  `lib/features/tasks/data/tasks_repository.dart`,
  `lib/features/tasks/data/local/tasks_local_repository.dart`,
  `lib/features/tasks/domain/task_date_filter.dart` e widgets/providers sem
  consumidor.

**Actions:**

- Não remover as tabelas no mesmo commit em que o writer deixa de ser usado.
- Primeiro deixar o novo source de notificações e o editor independentes.
- Em seguida adicionar uma migração Drift forward-only para remover as tabelas
  locais depois de confirmar que snapshots, outbox e materializações estão
  preservados.
- Atualizar `clearAllData` e o lifecycle da nota para não depender das tabelas
  removidas.

**Verify:** `rtk rg -n "TaskProjectionEngine|ProjectedTask|TasksDao|TaskData|TaskModel|task_completions" lib --glob '*.dart' --glob '!**/*.g.dart'`
não deve encontrar runtime ativo fora do relatório/migração em execução.

### Step 7: Remover as escritas e leituras backend antigas

**Files:**

- Modify: `backend/cmd/server/main.go` — remover `tasks.NewRepository`,
  `tasks.NewService`, handlers e rotas `/tasks`.
- Modify: `backend/internal/mcp/server.go`, `tools.go`, `tools_notes.go` e
  contratos — remover a dependência de `tasks.Service` e o tool `list_tasks`.
- Keep: ferramentas MCP de criar bloco, atualizar metadados, concluir e
  reabrir ocorrência, porque elas usam `DocumentCommandService`.
- Delete after the data gate: `backend/internal/tasks`,
  `backend/db/queries/tasks.sql` e bindings sqlc gerados exclusivamente para
  tasks.
- Create after production reconciliation: forward migration that removes
  `task_completions` and `tasks` only after their export/archive is verified.

**Actions:**

- Antes do deploy, consultar logs de acesso às rotas antigas. Se houver tráfego
  real, parar e identificar o cliente; não reintroduzir uma segunda fonte.
- Remover as rotas em uma versão de corte explícita. Não deixar handlers que
  apenas fazem fallback para o banco antigo.
- Manter os comandos MCP canônicos para operações dentro de uma nota.
- Não alterar a autorização do `DocumentCommandService`.

**Verify:** `rtk rg -n "internal/tasks|/tasks|list_tasks|tasksSvc|CreateTask|UpdateTask|CompleteTask" backend --glob '*.go' --glob '!internal/db/sqlcgen/**'`
não deve encontrar runtime antigo. `rtk make sqlc` deve gerar somente bindings
ainda referenciados.

### Step 8: Migrar e remover o armazenamento relacional em produção

**Files:**

- Modify: `lib/core/database/database.dart` — migração Drift para o banco local.
- Create: `backend/db/migrations/000051_remove_legacy_task_storage.up.sql` —
  somente depois da aprovação do inventário e da retenção.
- Keep: migrations antigas sem alteração; nunca editar uma migration já
  aplicada.
- Update: `lib/core/database/README.md`, `lib/features/tasks/README.md`,
  `ARCHITECTURE.md` e `backend/internal/noteoperations/README.md`.

**Actions:**

- No dispositivo, migrar primeiro o snapshot efetivo e verificar a outbox;
  somente depois remover `tasks` e `local_task_completions`.
- O preflight local deve comparar cada ID legado com os IDs extraídos dos
  snapshots efetivos. Se houver qualquer row sem correspondência, a migração
  não remove as tabelas e deixa o banco em estado recuperável.
- No PostgreSQL, fazer o drop em uma migration posterior ao cutover, após:
  backup restaurável, inventário sem categoria não classificada, tráfego das
  rotas antigas zerado e retenção aprovada.
- Remover primeiro `task_completions`, depois `tasks`, respeitando as foreign
  keys.
- Se os dados órfãos não puderem ser importados, manter o export arquivado e
  registrar a disposição; não apagá-los por conveniência.

**Verify:** abrir uma cópia atualizada de um banco local existente e confirmar
que todas as notas, snapshots confirmados, operações pendentes e
materializações continuam presentes após a migração. No staging, aplicar a
migration em uma cópia restaurada da produção e confirmar que o backend
inicia sem consultas às tabelas removidas.

### Step 9: Fechar documentação e limpeza

**Files:**

- Update: `ARCHITECTURE.md`, `lib/features/tasks/README.md`,
  `lib/core/database/README.md`, `lib/features/notes/catalog/README.md`,
  `lib/features/notes/editor/README.md` e `backend/internal/noteoperations/README.md`.
- Delete: documentação ativa que descreve tasks como entidade independente ou
  CRUD relacional, mantendo somente histórico explicitamente marcado.

**Actions:**

- Documentar que tasks são blocos do documento e que a tabela antiga não é
  fonte de escrita.
- Documentar o snapshot confirmado versus o snapshot efetivo local.
- Documentar a política de exclusão, logout, conta compartilhada, recorrência,
  timezone e notificações.
- Atualizar o índice `plans/README.md` com o status real.

**Verify:** revisão final de referências e `rtk git diff --check` sem erros.

## Plano de verificação da execução futura

O executor deve cobrir, no mínimo:

- abrir uma nota com task sem metadados;
- adicionar/remover data;
- alternar `hasTime` sem mudar o dia;
- adicionar/remover lembrete;
- concluir e reabrir task não recorrente;
- concluir e reabrir cada tipo de recorrência;
- task recorrente atrasada com ocorrência já concluída;
- task recorrente atrasada deve manter a ocorrência visível até a próxima data,
  enquanto o scheduler usa a próxima ocorrência futura;
- duas conclusões antecipadas seguidas no mesmo dia;
- task mensal ancorada no dia 31 atravessando fevereiro;
- chave antiga de conclusão com offset sem conversão determinística;
- operação `complete_task_occurrence` recebida por sync/MCP;
- alteração local offline antes de fechar a nota;
- alteração remota durante uma sessão aberta;
- rebase com operações pendentes;
- nota compartilhada com reminder atualizado por outro cliente autorizado;
- Share Link sem criação de notificação local;
- soft delete e remoção remota de nota;
- logout e troca de usuário;
- limite de 30 notificações e cancelamento de IDs antigos;
- mudança de timezone/DST preservando o mesmo lembrete local;
- migração de banco local com outbox e materialização existentes;
- backend sem acesso a `tasks` após o drop;
- reconciliação de rows legadas correspondentes, órfãs e conflitantes.

Os testes devem seguir os padrões existentes em:

- `test/features/tasks/domain/task_notification_scheduler_test.dart`;
- `test/features/notes/domain/note_operation_adapter_test.dart`;
- `test/features/notes/presentation/note_editor_screen_test.dart`;
- `backend/internal/noteoperations/*_test.go`.

## Critérios de conclusão

- [x] O editor não importa nem recebe `TaskModel`.
- [x] O scheduler não lê `TaskData` nem a tabela `tasks`.
- [x] Alterações offline de task sobrevivem ao fechamento e à reabertura do
      aplicativo.
- [x] O snapshot confirmado continua separado do documento efetivo local.
- [x] Data, hora, lembrete, recorrência, conclusão e reabertura continuam
      representados no documento.
- [x] O mesmo domínio de ocorrência é usado para editor e notificações; o
      scheduler usa um alvo futuro separado quando a ocorrência visível está
      atrasada.
- [x] O codec Dart e o decoder Go rejeitam aliases legados, datas de agenda
      com offset, regras desconhecidas, reminders desconhecidos e valores
      inválidos de `completions`/`lastCompletedAt`.
- [x] IDs de notificação permanecem estáveis para tasks existentes.
- [x] Rotas backend e MCP `list_tasks` antigos foram removidos.
- [x] Cada row de produção antiga tem correspondência, importação aprovada ou
      export/arquivo verificável. A produção tinha zero rows nas tabelas
      relacionais; os 181 blocos document-only foram classificados como dados
      canônicos já existentes, e os exports permanecem no artefato protegido.
- [x] Nenhuma tabela local ou PostgreSQL foi removida nesta migração. A remoção
      física continua sendo uma mudança separada, após retenção e aprovação
      explícita.
- [x] Não há escrita direta em `tasks` no runtime.
- [x] As verificações locais definidas para a execução foram concluídas e registradas
      pelo executor; este documento não executa testes por si só.

## STOP conditions

- O inventário encontra uma task sem destino aprovado.
- Há divergência entre documento e tabela que não pode ser explicada.
- Existe `recurrence` ou formato de recorrência desconhecido.
- O snapshot efetivo não pode ser persistido junto da outbox.
- O scheduler só consegue funcionar usando uma sessão aberta.
- Uma nota compartilhada seria excluída por um filtro de usuário incorreto.
- Uma migração local pode apagar operações pendentes ou o snapshot confirmado.
- Há tráfego real nas rotas `/tasks` após a data de corte.
- Um cliente externo depende de `list_tasks` sem uma decisão explícita de remoção.
- A nova versão precisa ler um alias antigo em runtime para abrir uma nota.
- Um dispositivo offline ainda possui snapshot local com alias ou timestamp
  não canônico quando o cliente estrito é liberado.
- O backup de produção não foi restaurado com sucesso em staging.
- A alteração exige editar uma migration já aplicada.

## Notas de manutenção

Novos campos de task devem ser adicionados primeiro ao contrato do bloco e ao
número de versões do documento. Depois devem ser atualizados o codec Dart, o
validador Go, o leitor de ocorrência, o scheduler e o share reader. Não criar
uma coluna relacional para um campo que só pertence ao `TaskNode`.

O snapshot confirmado existe para rebase e sync. O snapshot efetivo existe para
offline e leituras locais. Nenhum dos dois autoriza escrita direta de task fora
das operações do documento.
