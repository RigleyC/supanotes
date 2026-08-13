# Comparação de modelos de tarefas: Superlist, Todoist, Things e Microsoft To Do

Data: 2026-08-12

## Escopo e método

Esta pesquisa compara o contrato observável de tarefas em quatro produtos:
Superlist, Todoist, Things e Microsoft To Do. O foco é:

- identidade da tarefa;
- fronteira entre tarefa e nota ou descrição;
- datas, recorrência e lembretes;
- conclusão e ocorrências;
- subtarefas e checklists;
- metadados da tarefa versus metadados de uma ocorrência ou projeção.

Foram usados apenas páginas oficiais de produto, ajuda e documentação de API dos
próprios fornecedores. Não foram consultados bancos privados, APIs internas,
tráfego de rede ou código não documentado. Cada seção separa:

- **Fato documentado**: comportamento ou campo descrito pela fonte oficial.
- **Desconhecido público**: a documentação consultada não define o ponto.
- **Inferência**: leitura limitada do contrato de produto; não é uma afirmação
  sobre o banco ou a implementação interna.

“Ocorrência” significa uma execução agendada de uma tarefa recorrente. Quando a
fonte não usa esse termo, o relatório descreve o comportamento documentado sem
atribuir um modelo interno.

## Resumo executivo

| Produto | Identidade observável | Tarefa e nota | Recorrência e conclusão | Subtarefas e metadados |
|---|---|---|---|---|
| Superlist | A ajuda descreve tarefas e listas, mas não publica um esquema de objeto ou uma regra de ID estável. [Basics](https://help.superlist.com/en/articles/10050-superlist-basics-lists-tasks-sections-meetings-explained) | Listas são documentos ricos; a página de detalhes de uma tarefa pode conter texto, outras tarefas, imagens, anexos e discussões. [Create tasks](https://help.superlist.com/en/articles/23853-create-tasks-and-subtasks) | Repetir preserva os detalhes e, ao concluir, reabre a tarefa com uma nova data. [Repeating tasks](https://help.superlist.com/en/articles/78873-repeating-tasks) | Subtarefas são tarefas aninhadas com indicador de progresso; o vínculo interno e a persistência da ocorrência não são publicados. |
| Todoist | A API expõe `id` de tarefa e `parent_id` para hierarquia. [API v1](https://developer.todoist.com/api/v1/) | `content` e `description` são campos distintos da tarefa; comentários, lembretes e outros recursos têm contratos próprios. [Task view](https://www.todoist.com/help/articles/use-the-task-view-to-manage-tasks-in-todoist-eDeRDO0C) | A tarefa recorrente avança para a próxima data quando é concluída; a API não expõe uma entidade de ocorrência no recurso de tarefa. [Recurring dates](https://www.todoist.com/help/articles/introduction-to-recurring-dates-YUYVJJAV) | Subtarefas são tarefas com `parent_id`; lembretes são recursos separados vinculados por `task_id`. [API v1](https://developer.todoist.com/api/v1/) |
| Things | Não há API pública; URLs e automações locais usam um ID opaco de to-do/lista. [No public API](https://culturedcode.com/things/support/articles/2967034/), [URL Scheme](https://culturedcode.com/things/support/articles/2803573/) | To-dos têm título, notas e checklist; projetos transformam etapas em to-dos próprios. [Notes](https://culturedcode.com/things/support/articles/4438545/), [Checklists and projects](https://culturedcode.com/things/support/articles/8491676/) | A recorrência usa um template e cria cópias futuras; alterações no template afetam cópias futuras, e a cópia tem estado próprio. [Repeating to-dos](https://culturedcode.com/things/support/articles/2803564/) | Checklist é uma decomposição leve; projeto é uma decomposição em to-dos. O vínculo público entre template e cópia não é definido como um ID de ocorrência. |
| Microsoft To Do | Microsoft Graph expõe `todoTask.id`; a documentação avisa que o ID pode mudar quando o item é movido entre listas. [todoTask](https://learn.microsoft.com/en-us/graph/api/resources/todotask?view=graph-rest-1.0) | `title` e `body` são campos distintos; `checklistItems` são filhos de `todoTask`. [todoTask](https://learn.microsoft.com/en-us/graph/api/resources/todotask?view=graph-rest-1.0), [checklistItem](https://learn.microsoft.com/en-us/graph/api/resources/checklistitem?view=graph-rest-1.0) | A ajuda documenta que a próxima tarefa recorrente é criada depois da conclusão da anterior; Graph não publica a relação da série. [Recurring reminder troubleshooting](https://support.microsoft.com/en-us/ToDo/troubleshoot-reminder-issues-in-microsoft-to-do-for-android) | Datas, lembrete, recorrência, status e conclusão pertencem a `todoTask`; um `checklistItem` tem estado de marcado, mas não data ou lembrete próprios no esquema documentado. |

O padrão mais explícito de separação entre template e cópia é o Things ([repeating
to-dos](https://culturedcode.com/things/support/articles/2803564/)). Todoist mantém
uma tarefa ativa com uma data recorrente que avança ([recurring dates](https://www.todoist.com/help/articles/introduction-to-recurring-dates-YUYVJJAV)),
enquanto Microsoft To Do documenta a criação de uma nova tarefa para a próxima
repetição ([recurring reminder troubleshooting](https://support.microsoft.com/en-us/ToDo/troubleshoot-reminder-issues-in-microsoft-to-do-for-android)).
Superlist documenta uma tarefa que reabre com os detalhes preservados ([repeating tasks](https://help.superlist.com/en/articles/78873-repeating-tasks)). Nenhuma dessas três
descrições, por si só, publica a identidade interna de uma ocorrência.

## Contexto local observado: SupaNotes

### Fatos no repositório

O contrato local trata uma tarefa como um bloco do documento de uma nota. O README
da feature diz que a tabela relacional `tasks` é uma projeção para consultas e UI,
sem ser dona da escrita canônica: [`lib/features/tasks/README.md`](../../lib/features/tasks/README.md).
O README do banco repete que `notes.document` é a origem dos dados e que
`tasks`/`task_completions` são projeções derivadas: [`lib/core/database/README.md`](../../lib/core/database/README.md).

O codec canônico decodifica um `TaskNode` com identidade de bloco, texto,
conclusão e indentação. A validação e a codificação também reconhecem metadados
de tarefa como `dueDate`, `hasTime`, `recurrenceRule`/`recurrence` e `reminder`:
[`note_document_codec.dart`](../../lib/features/notes/editor/document/note_document_codec.dart).
Isso coloca texto e metadados da tarefa dentro do documento REST/OT, junto dos
demais blocos da nota.

`TaskProjectionEngine` lê o snapshot canônico e grava a projeção relacional:
[`task_projection_engine.dart`](../../lib/features/tasks/domain/task_projection_engine.dart).
O projetor calcula título, data, recorrência, lembrete e estado de conclusão a
partir do bloco; ele não é o proprietário do ciclo de vida do editor ou do banco:
[`note_document_projector.dart`](../../lib/features/tasks/domain/note_document_projector.dart).
As colunas projetadas incluem `id`, `noteId`, título, status, posição, data,
recorrência, lembrete e timestamps: [`tasks.dart`](../../lib/core/database/tables/tasks.dart).

Há uma separação explícita para conclusão recorrente. A tabela
`task_completions` guarda `taskId`, `scheduledAt` e `completedAt`, com unicidade
por `(taskId, scheduledAt)`; o comentário da tabela diz que o template da tarefa
recorrente permanece inalterado: [`task_completions.dart`](../../lib/core/database/tables/task_completions.dart).
O contrato de operação inclui `complete_task_occurrence` com `taskId`,
`scheduledAt` e `completedAt`: [`note_operation_contract.dart`](../../lib/features/notes/editor/sync/note_operation_contract.dart).

### Leitura do limite local

O contrato observado do SupaNotes é híbrido:

1. o documento REST/OT é canônico para conteúdo e metadados do bloco;
2. `tasks` é uma projeção relacional para leitura e consulta;
3. a conclusão de uma ocorrência pode ser registrada separadamente em
   `task_completions`.

Esta é uma descrição do código e da documentação do repositório. Ela não afirma
que os produtos comparados usem o mesmo modelo interno.

## 1. Superlist

### Fatos documentados

- A Superlist define listas como documentos ricos que podem conter tarefas,
  texto, imagens e outros conteúdos. Uma tarefa pode ser simples ou ter várias
  etapas. A página de detalhes de uma tarefa pode conter texto, tarefas
  adicionais, imagens, anexos e discussões: [Superlist Basics](https://help.superlist.com/en/articles/10050-superlist-basics-lists-tasks-sections-meetings-explained).
- Uma tarefa pode existir dentro de uma lista ou ser criada fora de uma lista,
  por exemplo na Inbox ou no Today. A tarefa recebe data, etiqueta e responsável;
  subtarefas mostram progresso e uma tarefa concluída mantém a posição atual: [Create tasks and subtasks](https://help.superlist.com/en/articles/23853-create-tasks-and-subtasks).
- A data da tarefa pode incluir hora. O usuário pode configurar “Remind me”, e a
  notificação é entregue entre dispositivos no horário especificado: [Reminders](https://help.superlist.com/en/articles/106335-reminders).
- A repetição oferece opções como diária, dias úteis, semanal, quinzenal,
  mensal e anual. A documentação afirma que os detalhes da tarefa permanecem os
  mesmos e que, quando a tarefa é concluída, ela é reaberta com a data atualizada:
  [Repeating tasks](https://help.superlist.com/en/articles/78873-repeating-tasks).
- A área Done reúne tarefas concluídas e permite filtros por responsável, data,
  origem, lista e outros atributos: [View and sort all tasks](https://help.superlist.com/en/articles/10058-view-and-sort-all-tasks).
- A documentação oficial do MCP descreve ações de alto nível, como criar,
  consultar e reagendar tarefas, mas os exemplos são orientados a nomes e não
  publicam um esquema REST de tarefa ou de ocorrência: [Superlist MCP Server](https://help.superlist.com/en/articles/658028-superlist-mcp-server).

### Desconhecidos públicos

Nas páginas oficiais consultadas, não foi encontrado um contrato público que
defina o ID estável de uma tarefa, a identidade de uma ocorrência, o histórico de
conclusões ou a localização formal de cada metadado entre tarefa e ocorrência.
Isso é uma lacuna da documentação consultada, não uma afirmação de que esses
dados não existam.

Também não é possível determinar, a partir das páginas de ajuda, se uma tarefa
recorrente conserva o mesmo identificador, se uma nova ocorrência recebe um
identificador ou como uma série é relacionada ao histórico.

### Inferências limitadas

A superfície do produto trata uma tarefa como uma unidade acionável dentro de um
documento rico: a tarefa pode ter seu próprio texto e novas tarefas aninhadas.
O comportamento de repetição parece, para o usuário, uma tarefa lógica que é
reaberta e recebe uma nova data, porque os detalhes permanecem iguais. A fonte
não permite transformar essa observação em uma afirmação sobre identidade ou
persistência interna.

## 2. Todoist

### Fatos documentados

- A API pública expõe a tarefa por um `id` string. O recurso inclui `content`,
  `description`, `project_id`, `parent_id`, estado de conclusão, `due`,
  `deadline`, prioridade, etiquetas e outros campos. `parent_id` representa a
  relação hierárquica entre tarefas: [Todoist API v1](https://developer.todoist.com/api/v1/).
- A ajuda separa o nome da tarefa da descrição. A visão da tarefa também expõe
  data, duração, deadline, responsável, prioridade, etiquetas, lembretes,
  comentários, arquivos e subtarefas: [Task view](https://www.todoist.com/help/articles/use-the-task-view-to-manage-tasks-in-todoist-eDeRDO0C).
- O objeto `due` da API tem a data atual e indica se a tarefa é recorrente. A
  API também trata `deadline` como campo separado. Criar ou atualizar a tarefa
  aceita data, data-hora, duração e a string de recorrência: [Todoist API v1](https://developer.todoist.com/api/v1/).
- Lembretes são um recurso separado. O endpoint de criação recebe `task_id` e
  pode representar um lembrete relativo ou absoluto; a resposta tem seu próprio
  ID: [Create a reminder](https://developer.todoist.com/api/v1/).
- Fechar uma tarefa comum a conclui e a move para o arquivo. Fechar uma tarefa
  recorrente agenda a próxima ocorrência. A API documenta também operações para
  concluir e resetar subtarefas ou concluir a tarefa recorrente definitivamente:
  [Close a task](https://developer.todoist.com/api/v1/), [Task view](https://www.todoist.com/help/articles/use-the-task-view-to-manage-tasks-in-todoist-eDeRDO0C).
- A ajuda diz que ocorrências futuras ficam ocultas por padrão e que a repetição
  pode ser calculada a partir da data original ou da data de conclusão. Ao
  concluir uma tarefa recorrente atrasada, a data é movida para a próxima data
  futura: [Recurring dates](https://www.todoist.com/help/articles/introduction-to-recurring-dates-YUYVJJAV).

### Desconhecidos públicos

O recurso de tarefa documentado expõe a tarefa ativa por `id` e a sua data
recorrente, mas não expõe uma entidade pública de ocorrência nem um
`occurrence_id` no contrato citado. A documentação consultada não define se o
mesmo `id` é mantido quando a data avança, como o histórico completo é
persistido, ou quais campos são copiados para cada futura ocorrência.

O fato de lembretes serem recursos separados também não informa como o serviço
associa, internamente, um lembrete a uma ocorrência específica de uma tarefa
recorrente. O contrato público só garante o vínculo documentado por `task_id`.

### Inferências limitadas

Na superfície pública, Todoist apresenta uma tarefa identificável com uma data
recorrente que avança quando a tarefa é concluída. Isso é compatível com um
modelo de tarefa lógica mais ocorrência atual, mas a API pública citada não
permite confirmar essa identidade entre ocorrências. Já a separação de
subtarefas por `parent_id` e de lembretes por recurso próprio é explícita no
contrato, não uma inferência.

## 3. Things

### Fatos documentados

- A Cultured Code afirma que o Things não oferece uma API pública. Os meios
  oficiais de integração incluem Things URLs, Apple Shortcuts, AppleScript no
  Mac e Mail; a página alerta contra acesso direto ao banco ou ao Cloud:
  [Things does not have a public API](https://culturedcode.com/things/support/articles/2967034/).
- A URL Scheme permite criar, mostrar, atualizar e buscar to-dos e projetos. A
  operação de atualização usa `id`; a documentação também explica como obter o
  ID de um to-do ou lista por Copy Link. O formato de criação inclui título,
  notas, itens de checklist, `when`, deadline, etiquetas e datas:
  [Things URL Scheme](https://culturedcode.com/things/support/articles/2803573/).
- Notas são uma seção separada do título do to-do ou projeto. Checklists ficam
  dentro do item; projetos usam etapas que se tornam to-dos individuais, e esses
  to-dos podem ter suas próprias notas, etiquetas e datas: [Notes](https://culturedcode.com/things/support/articles/4438545/), [Checklists and projects](https://culturedcode.com/things/support/articles/8491676/).
- Things separa “When”, o dia em que a tarefa deve começar, de deadline, a data
  até a qual deve terminar. Um lembrete é configurado com “When” e horário; a
  documentação diz que deadline não pode ter lembrete: [When and deadlines](https://culturedcode.com/things/support/articles/2803579/), [Reminders](https://culturedcode.com/things/support/articles/2803585/).
- Uma tarefa recorrente pode seguir um cronograma fixo ou ser criada depois da
  conclusão da anterior. A documentação descreve um template que gera novos
  to-dos; alterações no template afetam cópias futuras, enquanto alterações na
  cópia não alteram o template. Itens de checklist só podem ser marcados na
  cópia: [Repeating to-dos](https://culturedcode.com/things/support/articles/2803564/).
- To-dos e projetos concluídos ou cancelados permanecem no Logbook:
  [Logbook](https://culturedcode.com/things/support/articles/4001304/).

### Desconhecidos públicos

Como não há API pública, as fontes consultadas não definem um esquema HTTP ou
um contrato de sincronização. Os IDs usados pelas URLs e automações não
documentam, por si só, a estrutura interna do Cloud, o vínculo persistente entre
template e cópia, ou um ID público de ocorrência.

Também não é possível afirmar, a partir da ajuda, se todas as propriedades do
template são copiadas por um mesmo mecanismo ou como o histórico de uma série é
representado internamente.

### Inferências limitadas

Entre os produtos comparados, Things descreve com mais clareza uma separação de
produto entre regra/template e cópia executável: o template define o futuro, e a
cópia recebe seu próprio estado de checklist e conclusão. Essa é uma inferência
sobre o contrato de uso; não é uma afirmação de que exista uma tabela ou uma
classe interna específica para “occurrence”.

## 4. Microsoft To Do

### Fatos documentados

- No Microsoft Graph, `todoTask` é um recurso de primeira classe dentro de uma
  lista. Ele tem `id`, `title`, `body`, `status`, `completedDateTime`,
  `startDateTime`, `dueDateTime`, `reminderDateTime`, `isReminderOn` e
  `recurrence`, entre outros campos. A documentação informa que o ID muda por
  padrão quando o item é movido entre listas: [todoTask resource](https://learn.microsoft.com/en-us/graph/api/resources/todotask?view=graph-rest-1.0).
- `body` é o corpo informativo da tarefa, separado do título. O produto também
  oferece notas formatadas e etapas para dividir uma tarefa maior:
  [Add steps, notes, tags and categories](https://support.microsoft.com/en-US/ToDo/add-steps-importance-notes-tags-and-categories-to-your-tasks).
- `checklistItems` são recursos filhos de `todoTask`, com `id`, nome, estado
  `isChecked` e `checkedDateTime`. O esquema público de `checklistItem` não
  inclui data de vencimento ou lembrete: [checklistItem resource](https://learn.microsoft.com/en-us/graph/api/resources/checklistitem?view=graph-rest-1.0).
- A ajuda do produto oferece data de vencimento, lembrete e repetição diária,
  semanal, mensal, anual ou personalizada: [Due dates and reminders](https://support.microsoft.com/en-US/ToDo/add-due-dates-and-reminders-in-microsoft-to-do).
- Para Android, a documentação de suporte diz que uma nova tarefa da série
  recorrente só aparece depois que a tarefa anterior da série é concluída:
  [Recurring reminder troubleshooting](https://support.microsoft.com/en-us/ToDo/troubleshoot-reminder-issues-in-microsoft-to-do-for-android).
- Microsoft descreve To Do como um aplicativo pessoal de tarefas e informa que
  ele sincroniza por meio da Microsoft Tasks API e se integra ao Outlook:
  [Set up Microsoft To Do](https://support.microsoft.com/en-us/todo/set-up-microsoft-to-do).

### Desconhecidos públicos

O recurso Graph `todoTask` documenta recorrência e estado da tarefa, mas não
publica uma relação de série, um `occurrence_id` ou um campo que ligue a nova
tarefa recorrente à anterior. A documentação consultada também não define o
histórico completo de ocorrências nem garante quais metadados são herdados pela
próxima tarefa.

O aviso de mudança de ID ao mover uma tarefa entre listas também deixa
indefinida, para este estudo, a estabilidade do ID como identidade global do
usuário. O fato documentado é apenas a mudança de ID nessa operação.

### Inferências limitadas

O comportamento de produto é compatível com materializar a próxima repetição
como uma nova tarefa depois da conclusão da anterior. O Graph, contudo, só
expõe o contrato da tarefa individual e não permite verificar a relação entre
essas tarefas. É mais seguro tratar “nova tarefa” como comportamento documentado
de produto, não como prova de um modelo interno de ocorrências.

## Comparação por contrato

| Pergunta | Superlist | Todoist | Things | Microsoft To Do | SupaNotes observado |
|---|---|---|---|---|---|
| Qual é a identidade? | O produto expõe tarefas, mas as fontes consultadas não definem um ID ou uma ocorrência pública. [Basics](https://help.superlist.com/en/articles/10050-superlist-basics-lists-tasks-sections-meetings-explained) | `id` de tarefa; `parent_id` para hierarquia. [API v1](https://developer.todoist.com/api/v1/) | ID opaco usado por URL Scheme/Copy Link; sem API pública. [URL Scheme](https://culturedcode.com/things/support/articles/2803573/), [No public API](https://culturedcode.com/things/support/articles/2967034/) | `todoTask.id`, com mudança documentada ao mover entre listas. [todoTask](https://learn.microsoft.com/en-us/graph/api/resources/todotask?view=graph-rest-1.0) | O ID do `TaskNode` identifica o bloco; a projeção repete a identidade com `noteId`. [`note_document_codec.dart`](../../lib/features/notes/editor/document/note_document_codec.dart), [`tasks.dart`](../../lib/core/database/tables/tasks.dart) |
| Onde termina a tarefa e começa a nota? | A tarefa e sua página de detalhes podem conter texto e conteúdo rico. [Basics](https://help.superlist.com/en/articles/10050-superlist-basics-lists-tasks-sections-meetings-explained) | `content` e `description` são distintos; comentários e anexos têm superfícies próprias. [Task view](https://www.todoist.com/help/articles/use-the-task-view-to-manage-tasks-in-todoist-eDeRDO0C) | Título, notas e checklist ficam no to-do; projetos criam to-dos filhos. [Notes](https://culturedcode.com/things/support/articles/4438545/), [Checklists and projects](https://culturedcode.com/things/support/articles/8491676/) | `title`, `body` e `checklistItems` são distintos. [todoTask](https://learn.microsoft.com/en-us/graph/api/resources/todotask?view=graph-rest-1.0) | A tarefa é um bloco dentro do documento canônico; o texto do bloco e os outros blocos compartilham a nota. [`lib/features/tasks/README.md`](../../lib/features/tasks/README.md) |
| Como datas são modeladas? | Data e hora de vencimento são configuráveis. [Reminders](https://help.superlist.com/en/articles/106335-reminders) | `due` e `deadline` são campos diferentes. [API v1](https://developer.todoist.com/api/v1/) | “When”/início e deadline são conceitos diferentes. [When and deadlines](https://culturedcode.com/things/support/articles/2803579/) | `startDateTime`, `dueDateTime` e `reminderDateTime` são propriedades de `todoTask`. [todoTask](https://learn.microsoft.com/en-us/graph/api/resources/todotask?view=graph-rest-1.0) | `dueDate` e `hasTime` ficam no metadado do bloco e são projetados em `tasks`. [`note_document_codec.dart`](../../lib/features/notes/editor/document/note_document_codec.dart), [`note_document_projector.dart`](../../lib/features/tasks/domain/note_document_projector.dart) |
| O que acontece na recorrência? | Ao concluir, a tarefa reabre com nova data e mantém detalhes; identidade da ocorrência é desconhecida. [Repeating tasks](https://help.superlist.com/en/articles/78873-repeating-tasks) | A tarefa recorrente avança para a próxima data; futuras ficam ocultas por padrão. [Recurring dates](https://www.todoist.com/help/articles/introduction-to-recurring-dates-YUYVJJAV) | Template gera cópias futuras; estado da cópia é separado do template na experiência. [Repeating to-dos](https://culturedcode.com/things/support/articles/2803564/) | A próxima tarefa da série aparece depois da conclusão da anterior. [Recurring reminder troubleshooting](https://support.microsoft.com/en-us/ToDo/troubleshoot-reminder-issues-in-microsoft-to-do-for-android) | Regra/data ficam no bloco; conclusão da ocorrência é separada por `taskId` e `scheduledAt`. [`task_completions.dart`](../../lib/core/database/tables/task_completions.dart), [`note_operation_contract.dart`](../../lib/features/notes/editor/sync/note_operation_contract.dart) |
| Onde ficam lembretes? | Na configuração da tarefa e do horário. [Reminders](https://help.superlist.com/en/articles/106335-reminders) | Recurso separado vinculado a `task_id`. [API v1](https://developer.todoist.com/api/v1/) | Lembrete ligado a “When”; deadline não recebe lembrete. [Reminders](https://culturedcode.com/things/support/articles/2803585/) | Campos de lembrete pertencem a `todoTask`; checklist não tem esses campos. [todoTask](https://learn.microsoft.com/en-us/graph/api/resources/todotask?view=graph-rest-1.0), [checklistItem](https://learn.microsoft.com/en-us/graph/api/resources/checklistitem?view=graph-rest-1.0) | `reminder` é metadado canônico do bloco e campo da projeção. [`note_document_projector.dart`](../../lib/features/tasks/domain/note_document_projector.dart), [`tasks.dart`](../../lib/core/database/tables/tasks.dart) |
| Como são subtarefas? | Tarefas e subtarefas podem ficar no detalhe da tarefa, com progresso. [Create tasks and subtasks](https://help.superlist.com/en/articles/23853-create-tasks-and-subtasks) | Tarefas filhas por `parent_id`. [API v1](https://developer.todoist.com/api/v1/) | Checklist é leve; projeto cria to-dos filhos completos. [Checklists and projects](https://culturedcode.com/things/support/articles/8491676/) | `checklistItem` é filho separado com ID e marcado próprio. [checklistItem](https://learn.microsoft.com/en-us/graph/api/resources/checklistitem?view=graph-rest-1.0) | A hierarquia é representada por blocos, incluindo `indent`; tarefas continuam dentro do documento da nota. [`note_document_codec.dart`](../../lib/features/notes/editor/document/note_document_codec.dart) |

## O que é relevante para a pergunta do SupaNotes

As fontes sustentam os seguintes pontos de comparação, sem prescrever uma mudança
de implementação:

1. **Identidade e localização são dimensões separadas.** Todoist expõe ID e
   hierarquia; Things expõe IDs para automação local; Microsoft To Do expõe ID,
   mas documenta uma mudança ao mover entre listas; Superlist não publica o
   contrato equivalente. O SupaNotes já tem identidade de bloco e a replica na
   projeção. A comparação é útil para testar se o ID representa a tarefa, a
   posição na nota ou ambos; as fontes externas não resolvem essa escolha
   ([Todoist API v1](https://developer.todoist.com/api/v1/), [Things URL Scheme](https://culturedcode.com/things/support/articles/2803573/), [todoTask](https://learn.microsoft.com/en-us/graph/api/resources/todotask?view=graph-rest-1.0)).

2. **“Nota da tarefa” tem limites diferentes em cada produto.** Todoist usa
   descrição separada; Things usa notas e checklist; Microsoft To Do usa body e
   checklist; Superlist permite uma página de detalhes rica. O SupaNotes leva o
   texto da tarefa dentro do bloco e mantém outros blocos no mesmo documento.
   Portanto, “tarefa versus nota” é uma decisão de contrato de conteúdo, não
   apenas uma decisão de tabela ([Todoist task view](https://www.todoist.com/help/articles/use-the-task-view-to-manage-tasks-in-todoist-eDeRDO0C), [Things notes](https://culturedcode.com/things/support/articles/4438545/), [Microsoft To Do steps and notes](https://support.microsoft.com/en-US/ToDo/add-steps-importance-notes-tags-and-categories-to-your-tasks), [Superlist Basics](https://help.superlist.com/en/articles/10050-superlist-basics-lists-tasks-sections-meetings-explained)).

3. **Recorrência não tem um único padrão de mercado.** Things documenta
   template e cópias futuras; Microsoft To Do documenta uma nova tarefa depois
   da conclusão; Todoist documenta o avanço da data da tarefa recorrente;
   Superlist documenta reabertura com detalhes preservados. Nenhuma fonte
   pública consultada exige que regra, tarefa lógica e ocorrência tenham o mesmo
   ID ([Things repeating to-dos](https://culturedcode.com/things/support/articles/2803564/), [Microsoft To Do recurring tasks](https://support.microsoft.com/en-us/ToDo/troubleshoot-reminder-issues-in-microsoft-to-do-for-android), [Todoist recurring dates](https://www.todoist.com/help/articles/introduction-to-recurring-dates-YUYVJJAV), [Superlist repeating tasks](https://help.superlist.com/en/articles/78873-repeating-tasks)).

4. **Conclusão por ocorrência aparece com graus diferentes de explicitude.** No
   SupaNotes, `task_completions` e `complete_task_occurrence` tornam
   `scheduledAt` explícito. Todoist expõe operações especiais para tarefas
   recorrentes, mas não uma entidade de ocorrência no recurso citado. Things
   expõe cópias futuras na experiência. Microsoft To Do expõe o comportamento de
   criação da próxima tarefa, mas não a relação da série no Graph ([Todoist API v1](https://developer.todoist.com/api/v1/), [Things repeating to-dos](https://culturedcode.com/things/support/articles/2803564/), [Microsoft To Do todoTask](https://learn.microsoft.com/en-us/graph/api/resources/todotask?view=graph-rest-1.0)).

5. **Subtarefa pode ser tarefa completa ou item leve.** Todoist usa tarefas
   filhas; Things diferencia checklist de projeto; Microsoft To Do usa
   `checklistItem`; Superlist descreve tarefas aninhadas. O SupaNotes usa blocos
   e indentação no mesmo documento. Essas categorias são comparáveis no produto,
   mas não provam que os fornecedores compartilhem o mesmo modelo de dados ([Todoist API v1](https://developer.todoist.com/api/v1/), [Things checklists and projects](https://culturedcode.com/things/support/articles/8491676/), [Microsoft checklistItem](https://learn.microsoft.com/en-us/graph/api/resources/checklistitem?view=graph-rest-1.0), [Superlist subtasks](https://help.superlist.com/en/articles/23853-create-tasks-and-subtasks)).

### Conclusão curta

O contrato atual observado do SupaNotes combina duas práticas que têm paralelo
na documentação de mercado: conteúdo e metadados de tarefa permanecem ligados à
unidade editável da nota, enquanto consultas rápidas usam uma representação
relacional derivada; e a conclusão recorrente pode ter um registro separado da
regra da tarefa. O paralelo mais direto para a separação entre regra e execução é
o template/cópia documentado pelo Things ([repeating to-dos](https://culturedcode.com/things/support/articles/2803564/)). Todoist, Superlist e Microsoft To Do
mostram que o usuário também pode perceber a recorrência como avanço ou criação
da próxima tarefa sem que a API pública revele a estrutura de ocorrências ([Todoist recurring dates](https://www.todoist.com/help/articles/introduction-to-recurring-dates-YUYVJJAV), [Superlist repeating tasks](https://help.superlist.com/en/articles/78873-repeating-tasks), [Microsoft To Do recurring tasks](https://support.microsoft.com/en-us/ToDo/troubleshoot-reminder-issues-in-microsoft-to-do-for-android)).

Assim, a evidência ajuda a distinguir três contratos — identidade da tarefa,
regra recorrente e ocorrência concluída — mas não fornece base para inferir
internals privados nem para prescrever uma alteração no SupaNotes.

## Fontes oficiais consultadas

### Superlist

- [Superlist Basics: lists, tasks, sections and meetings](https://help.superlist.com/en/articles/10050-superlist-basics-lists-tasks-sections-meetings-explained)
- [Create tasks and subtasks](https://help.superlist.com/en/articles/23853-create-tasks-and-subtasks)
- [Reminders](https://help.superlist.com/en/articles/106335-reminders)
- [Repeating tasks](https://help.superlist.com/en/articles/78873-repeating-tasks)
- [View and sort all tasks](https://help.superlist.com/en/articles/10058-view-and-sort-all-tasks)
- [Superlist MCP Server](https://help.superlist.com/en/articles/658028-superlist-mcp-server)

### Todoist

- [Todoist API v1](https://developer.todoist.com/api/v1/)
- [Use the task view to manage tasks](https://www.todoist.com/help/articles/use-the-task-view-to-manage-tasks-in-todoist-eDeRDO0C)
- [Introduction to recurring dates](https://www.todoist.com/help/articles/introduction-to-recurring-dates-YUYVJJAV)

### Things / Cultured Code

- [Does Things have a public API?](https://culturedcode.com/things/support/articles/2967034/)
- [Things URL Scheme](https://culturedcode.com/things/support/articles/2803573/)
- [Repeating to-dos and projects](https://culturedcode.com/things/support/articles/2803564/)
- [When dates and deadlines](https://culturedcode.com/things/support/articles/2803579/)
- [Reminders](https://culturedcode.com/things/support/articles/2803585/)
- [Notes](https://culturedcode.com/things/support/articles/4438545/)
- [Checklists and projects](https://culturedcode.com/things/support/articles/8491676/)
- [Logbook](https://culturedcode.com/things/support/articles/4001304/)

### Microsoft To Do / Microsoft Graph

- [todoTask resource](https://learn.microsoft.com/en-us/graph/api/resources/todotask?view=graph-rest-1.0)
- [checklistItem resource](https://learn.microsoft.com/en-us/graph/api/resources/checklistitem?view=graph-rest-1.0)
- [Add steps, importance, notes, tags and categories](https://support.microsoft.com/en-US/ToDo/add-steps-importance-notes-tags-and-categories-to-your-tasks)
- [Add due dates and reminders](https://support.microsoft.com/en-US/ToDo/add-due-dates-and-reminders-in-microsoft-to-do)
- [Troubleshoot reminder issues for recurring tasks](https://support.microsoft.com/en-us/ToDo/troubleshoot-reminder-issues-in-microsoft-to-do-for-android)
- [Set up Microsoft To Do](https://support.microsoft.com/en-us/todo/set-up-microsoft-to-do)
