# Design: tasks independentes e navegação Tasks/Notas

Data: 2026-09-03  
Status: aguardando revisão final antes do planejamento

## Decisão resumida

O aplicativo passa a ter duas seções principais, **Tasks** e **Notas**, com
Tasks como primeira aba. Uma task criada nessa seção é uma entidade canônica
independente de notas, funciona offline e sincroniza entre os dispositivos do
proprietário.

Tasks que continuam existindo como blocos dentro de notas não são convertidas,
copiadas nem relacionadas automaticamente às tasks independentes. A aba Tasks
pode incluí-las na mesma lista por meio da opção **Mostrar tarefas das notas**.
A composição e a ordenação dessa lista são locais, a partir das duas fontes já
sincronizadas.

Compartilhamento de uma task independente com outras pessoas não faz parte
desta entrega. O contrato nasce com identidade estável e proprietário para que
participantes e permissões possam ser adicionados depois sem mudar a identidade
da task.

## Objetivos

- adicionar as seções principais Tasks e Notas;
- criar, editar, concluir, reabrir e excluir tasks independentes;
- preservar edição offline e sincronização entre dispositivos do usuário;
- usar as mesmas regras de data, hora, recorrência, reminder e ocorrências já
  usadas pelos blocos de task das notas;
- misturar opcionalmente tasks de notas na lista principal;
- exibir um histórico simples de conclusões;
- retirar as tabelas relacionais legadas do runtime e reutilizar o nome `tasks`
  somente depois dos gates de retenção e da quarentena segura.

## Não objetivos

- compartilhar uma task independente com outras pessoas;
- transformar blocos de task existentes em tasks independentes;
- vincular uma task independente a uma nota;
- sincronizar a composição visual da lista como um terceiro recurso remoto;
- criar modos separados de visualização e edição;
- adicionar testes de aparência ou geometria visual.

## Fontes de verdade

Existem duas entidades distintas:

1. **Task independente**: a linha remota de `tasks` é a autoridade entre
   dispositivos; a linha Drift é a cópia local-first e a outbox preserva
   mutações ainda não confirmadas.
2. **Task de nota**: o `TaskNode` no documento REST/OT da nota continua sendo a
   única fonte de verdade para aquele bloco.

O resultado exibido na aba Tasks é um DTO de leitura. Ele discrimina
`standalone` e `note`, mas nunca é persistido como uma terceira representação.
Uma mutação é encaminhada ao repositório da origem correspondente.

O invariante de documento continua valendo somente para tasks que são blocos
de uma nota. A tabela local `tasks` desta especificação pertence exclusivamente
às tasks independentes; ela não é uma projeção de `TaskNode` e não recebe
escritas de operações do editor.

## Nomenclatura de código

Como a task independente é o recurso principal da aba e da API, seu modelo de
domínio será chamado simplesmente `Task`, em `task.dart`. A operação de sync
será `TaskOperation`, o repositório será `TaskRepository` e os componentes de
persistência usarão `tasks.dart`/`tasks_dao.dart`.

Um bloco de task dentro de uma nota será representado somente na borda de
leitura por `NoteTask`, em `note_task_list_reader.dart`. `NoteTask` não é uma
entidade persistida nem uma cópia sincronizável; ele carrega `noteId` e
`blockId` para a lista, histórico e navegação de volta ao documento.

`TaskListItem` continua sendo a união de apresentação entre `Task` e
`NoteTask`. O código não usará `StandaloneTask`, `TaskNote` ou
`NoteTaskEntity`.

## Navegação

Um shell autenticado contém duas abas persistentes:

1. **Tasks**, rota inicial após autenticação;
2. **Notas**, que mantém o catálogo atual.

As rotas de editor de nota, configurações, MCP e Share Link continuam fora da
troca comum entre abas quando isso for exigido pelo fluxo atual. A rota de uma
nota aceita opcionalmente um `blockId`; ao abrir uma task originada em nota, o
editor localiza esse bloco e posiciona a seleção nele.

A navegação usa as rotas centrais do app. A tela não cria caminhos literais.

## Tela principal de tasks

`TasksScreen` segue a convenção do projeto: `Scaffold`, `CustomScrollView`,
`SliverAppBar.medium`, `SliverPadding` e `SliverList`. Estados de dados usam
`AsyncValue.when(data:loading:error:)`.

A lista padrão contém apenas tasks independentes. A ação **Mostrar tarefas das
notas** inclui ou exclui a segunda fonte e é mantida como preferência local do
usuário. Quando ativa, as duas fontes são misturadas na mesma sequência e uma
task de nota mostra discretamente o título da nota de origem.

A ordenação é:

1. ocorrências atrasadas, da mais antiga para a mais recente;
2. ocorrências de hoje;
3. ocorrências futuras, em ordem crescente;
4. tasks sem data, por `createdAt` crescente.

O FAB compartilhado cria somente uma task independente. No final da página,
um ListTile compartilhado chamado **Concluídas** abre a rota de histórico.

## Criação e edição

A criação abre uma interface dedicada de edição e não introduz um modo de
visualização. Título, data, hora, recorrência e reminder usam componentes
públicos da feature; a seleção de metadados reaproveita a sheet atual.

Tocar numa task independente abre essa interface. Tocar numa task de nota abre
a nota e o bloco correspondente. A nova tabela nunca recebe uma escrita para
uma task de nota.

Excluir uma task independente exige o diálogo compartilhado de confirmação e
gera um tombstone sincronizável. Excluir uma task de nota continua pertencendo
ao fluxo de operações do documento.

## Contrato da task independente

A entidade canônica contém:

| Campo | Semântica |
| --- | --- |
| `id` | UUID estável criado no cliente. |
| `ownerUserId` | Proprietário atual; base da autorização e colaboração futura. |
| `title` | Texto não vazio da task. |
| `dueDate` | Âncora da agenda, no mesmo formato canônico usado por `TaskNode`. |
| `hasTime` | Distingue agenda com hora de agenda de dia inteiro. |
| `recurrenceRule` | `daily`, `weekdays`, `weekly`, `monthly` ou nulo. |
| `reminder` | Opção canônica compartilhada ou nula. |
| `completions` | Mapa `scheduledAt -> completedAt` de ocorrências recorrentes. |
| `isCompleted` | Estado de uma task não recorrente. |
| `lastCompletedAt` | Instante UTC da conclusão não recorrente. |
| `revision` | Revisão monotônica confirmada pelo servidor. |
| `createdAt` | Instante de criação. |
| `updatedAt` | Instante da última alteração aceita. |
| `deletedAt` | Tombstone de exclusão ou nulo. |

O código reutiliza `TaskOccurrencePolicy`, `TaskRecurrence`,
`TaskReminderOption`, a identidade `scheduledAt` e o cálculo de notificações.
Não cria uma segunda implementação de recorrência.

## Persistência local

O Drift passa a registrar:

- `tasks`, como cópia local observável das tasks independentes;
- `pending_task_operations`, como outbox durável;
- o cursor/feed e a inbox compartilhados já existentes, estendidos para
  reconhecer mudanças de task.

O repositório executa a mutação da task e a inserção da operação pendente na
mesma transação. Providers são manuais e `.autoDispose`. A lista observa
streams Drift; não usa `.first` em `build()` e não duplica loading/error dentro
de um state próprio.

As instalações existentes são classificadas antes da atualização:

- banco novo: cria todas as tabelas da versão atual;
- banco na versão 31 sem restos: cria as novas tabelas normalmente;
- banco com restos vazios: move as tabelas físicas antigas para nomes de
  quarentena, registra a limpeza e cria o schema novo;
- banco com restos não vazios: preserva as tabelas em quarentena, sinaliza a
  migração como bloqueada e mantém o app operável em modo sem tasks
  independentes até uma rotina explícita de exportação/limpeza;
- falha no meio: a transação de migração reverte e não apaga a outbox de
  notas.

O app nunca pede para o usuário apagar o banco como estratégia de migração.

## API e sincronização

A API autenticada usa o prefixo `/api/v1/tasks`. Handlers permanecem finos e
delegam validação, autorização, revisão e persistência ao serviço.

Cada mutação é enviada por `POST /api/v1/tasks/:id/mutations` e inclui:

- `operationId` idempotente;
- `taskId`;
- `observedRevision`, apenas como diagnóstico e ordenação local;
- o tipo (`upsert`, `complete_occurrence`, `reopen_occurrence` ou `delete`);
- o payload canônico;
- `scheduleGeneration` nas operações de ocorrência.

O servidor bloqueia a linha da task numa transação, registra a combinação
`taskId + operationId + hash do payload`, incrementa `revision` e publica
`task_changed` ou `task_deleted` em `sync_changes` para o proprietário. O
resultado da própria mutação sempre devolve `operationId`, `revision` e a task
canônica; receber um evento do feed nunca confirma uma operação por inferência.
Repetir o mesmo `operationId` com o mesmo hash devolve o resultado original;
repetir com payload diferente retorna erro de protocolo.

O servidor aceita alterações de metadados com qualquer `observedRevision` e
usa a ordem de chegada serializada por task como last-writer-wins para os
campos enviados no patch. Não há rejeição silenciosa nem substituição do
estado local antes do resultado da outbox.

Conclusões recorrentes operam somente sobre a chave canônica `scheduledAt` e
preservam chaves diferentes concluídas em dois dispositivos. A reabertura
remove somente a chave solicitada. Cada mudança de `dueDate`, `hasTime` ou
`recurrenceRule` incrementa `scheduleGeneration` e limpa `completions`; uma
operação de ocorrência com geração antiga retorna `409 SCHEDULE_CHANGED` e o
cliente a marca como conflito explícito, sem reintroduzir histórico de uma
série antiga. Uma exclusão aceita cria tombstone; mutações posteriores daquele
ID retornam `410 TASK_DELETED` e são removidas da outbox após registrar o
conflito.

O repositório mantém uma fila serializada por `taskId`. Depois de receber uma
resposta, ele confirma apenas a operação cujo `operationId` veio no resultado,
aplica a task canônica recebida e recompõe as operações posteriores ainda
pendentes sobre ela. Uma falha de rede deixa a operação em `pending`; uma
resposta de protocolo deixa a operação `blocked` e visível para diagnóstico.

### Rollout compatível do feed

O feed atual não pode começar a emitir tipos desconhecidos para clientes
antigos, pois o coordenador existente exige `noteId` e falha em tipos não
reconhecidos. A API preserva o comportamento antigo quando a consulta omite o
escopo:

- `/api/v1/sync/changes` continua retornando apenas eventos de nota;
- clientes novos enviam `scope=all` e recebem também `task_changed` e
  `task_deleted` com `taskId` e sem `noteId`;
- a tabela `sync_changes` aceita os novos tipos e mantém ambos os identificadores
  opcionais;
- o cliente novo só muda seu cursor global para o modo `all` depois de concluir
  o bootstrap de tasks;
- uma versão antiga nunca vê eventos de task e continua processando o feed.

O `SyncInbox` local passa a armazenar `taskId` e `scope` não é persistido como
estado de cada evento. A aplicação roteia o evento por `type`, sem exigir
`noteId` para tasks.

### Bootstrap e atualização de instalações

O cursor atual `bootstrapComplete` não prova que tasks foram carregadas. A
versão nova adiciona `bootstrapVersion` e exige `2` para habilitar o feed
`scope=all`. O primeiro bootstrap novo:

1. lê um watermark estável do feed;
2. baixa o catálogo de notas existente;
3. baixa todas as tasks independentes, incluindo tombstones retidos;
4. grava tasks, notas, cursor e `bootstrapVersion = 2` numa transação local;
5. só então começa a ingerir eventos `scope=all`.

Se qualquer etapa falhar, a versão permanece abaixo de `2`, o cursor não é
avançado de forma irreversível e a tentativa pode ser retomada. O endpoint de
bootstrap de tasks calcula o snapshot e seu watermark numa transação de leitura
repetível; eventos posteriores ao watermark são consumidos normalmente pelo
feed.

Não haverá `GET /tasks?includeNoteTasks=true`. As tasks de nota já chegam pelo
sync de documentos, inclusive com operações locais pendentes, portanto a
composição no cliente é mais correta para o comportamento offline.

## Lista agregada local

O provider de apresentação recebe `includeNoteTasks` e combina:

- a stream de tasks independentes abertas;
- quando habilitada, a extração de `TaskNode`s dos documentos efetivos locais
  das notas visíveis ao usuário.

Notas visíveis são as notas ativas que o usuário possui ou às quais tem acesso
de leitura/edição, incluindo compartilhadas materializadas localmente. Notas
excluídas, revogadas ou sem documento efetivo não entram. A preferência
`hide_completed` da nota continua valendo para a extração, assim como o estado
de arquivamento na seleção padrão do catálogo.

O provider agenda uma invalidação temporal no próximo limite que possa mudar a
classificação da lista (meia-noite ou horário da ocorrência), mesmo sem uma
escrita no Drift. O relógio é injetável nos testes.

Cada item inclui a origem, a identidade composta necessária para evitar
colisões, os metadados de agenda e, para a origem `note`, `noteId`, `blockId` e
título da nota. A identidade de UI nunca presume que UUIDs de fontes distintas
são globalmente exclusivos.

## Histórico de concluídas

A rota **Concluídas** lista conclusões pela data real `completedAt`, da mais
recente para a mais antiga.

- task não recorrente: uma entrada baseada em `lastCompletedAt`;
- task recorrente: uma entrada por item de `completions`;
- task de nota: incluída somente quando **Mostrar tarefas das notas** estiver
  ativo.

Reabrir uma task não recorrente remove sua entrada atual do histórico. Reabrir
uma ocorrência recorrente remove apenas a chave `scheduledAt` escolhida. A
passagem do tempo não cria entradas de histórico.

## Notificações

O scheduler recebe uma união das entradas abertas das duas fontes. IDs locais
de notificação incorporam `userId`, origem, `taskId` e, para notas, `noteId` e
`blockId`; isso impede colisões entre blocos iguais em notas diferentes.
Durante a migração do formato de ID, o scheduler cancela IDs antigos antes de
criar os novos. Alterar, concluir,
reabrir ou excluir uma task independente reage agenda e cancelamento da mesma
forma que uma alteração equivalente em `TaskNode`.

Desativar **Mostrar tarefas das notas** afeta apenas a lista e o histórico; não
desativa reminders pertencentes às notas.

## Remoção e reutilização das tabelas legadas

A inspeção do repositório em 2026-09-03 encontrou referências às tabelas
PostgreSQL antigas `tasks` e `task_completions` somente em migrações históricas
e scripts operacionais de inventário. Não existem handlers, services,
repositories, queries sqlc ou código Flutter de runtime que as consumam. As
tabelas SQLite antigas também não fazem parte do `@DriftDatabase` atual;
restaram apenas comandos condicionais de upgrade de versões antigas.

O runbook executado em 2026-08-14 registrou zero linhas nas duas tabelas em
produção, mas esse registro não substitui uma verificação atual. A migração de
reutilização deve:

1. exigir backup restaurável e aprovação do encerramento da retenção;
2. contar novamente `tasks` e `task_completions` imediatamente antes da
   migração;
3. executar o check imediatamente antes da migração, dentro da mesma conexão;
4. mover tabelas com linhas zero para nomes de quarentena, em vez de exigir
   que o usuário apague o banco;
5. se houver qualquer linha, manter a quarentena e bloquear somente o recurso
   de tasks independentes, sem apagar dados nem operações de notas;
6. recriar `tasks` com o contrato independente e sem `note_id` ou `position`;
7. criar `task_operations` para idempotência e índices por proprietário,
   estado e agenda;
8. remover `task_completions` somente na etapa operacional aprovada, depois do
   export protegido e do período de retenção;
9. preservar os scripts históricos como evidência, identificando-os como não
   executáveis depois da reutilização do nome;
10. remover do migrador Drift somente os upgrades condicionais antigos depois
   de confirmar o menor schema version ainda suportado; bancos locais que ainda
   contenham restos físicos recebem quarentena e diagnóstico, nunca descarte
   automático.

Nenhuma linha legada é promovida automaticamente a task independente, porque
isso criaria entidades que o usuário não solicitou e poderia duplicar blocos
canônicos de notas.

## Erros e observabilidade

- falha de rede mantém a operação na outbox e a edição visível localmente;
- conflito não resolvível mantém erro observável e não apaga a cópia local;
- payload inválido retorna `{ "error": "message" }` e não avança revisão;
- acesso a task de outro usuário retorna resposta sem vazar sua existência;
- falha ao extrair um documento de nota aparece no `AsyncValue.error`, sem
  produzir silenciosamente uma lista parcial;
- falha ao agendar notification é registrada separadamente e não desfaz uma
  task já persistida.

## Validação

Os testes cobrem resultados e contratos, não aparência:

- criação, alteração, conclusão, reabertura e tombstone locais;
- atomicidade entre task e outbox;
- idempotência, hash divergente e tombstone no backend;
- merge de conclusões por `scheduledAt`;
- conflito de `scheduleGeneration` e edição posterior à conclusão;
- sync de dois dispositivos do mesmo proprietário;
- cliente antigo consumindo feed de notas enquanto cliente novo consome
  `scope=all`;
- bootstrap de instalação nova, upgrade com cursor existente e retomada após
  falha;
- confirmação perdida, retry e edição local durante resposta remota;
- autorização e isolamento entre usuários;
- ordenação agregada, filtro de tasks das notas e identidades entre fontes;
- histórico de tasks simples e ocorrências recorrentes;
- navegação para `noteId` e `blockId` corretos;
- união de notificações sem colisão entre fontes;
- contratos JSON equivalentes em Go e Dart;
- migração com restos SQLite vazios e não vazios, usando quarentena;
- `flutter analyze`, testes Flutter focados e `go test ./...`.

Testes que validem apenas geometria, posição de pixels ou aparência visual não
serão adicionados. Se um teste visual antigo bloquear a mudança sem proteger
comportamento útil, ele será removido conforme a convenção do projeto.

## Fases futuras

O compartilhamento adicionará participantes e permissões ao redor do mesmo
`taskId`. Ele exigirá convites, revogação, fan-out de `sync_changes` e regras de
conflito entre usuários, mas não mudará uma task independente para dentro de
uma nota nem alterará sua identidade.
