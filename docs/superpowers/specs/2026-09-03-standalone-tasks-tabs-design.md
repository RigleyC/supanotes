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
- remover com segurança as tabelas relacionais legadas antes de reutilizar o
  nome `tasks` para a nova entidade.

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

## API e sincronização

A API autenticada usa o prefixo `/api/v1/tasks`. Handlers permanecem finos e
delegam validação, autorização, revisão e persistência ao serviço.

Cada mutação inclui:

- `operationId` idempotente;
- `taskId`;
- a revisão conhecida pelo cliente;
- o tipo da operação e seu payload canônico.

O servidor registra operações aplicadas, incrementa `revision` e publica
`task_changed` ou `task_deleted` em `sync_changes` para o proprietário. O feed
passa a transportar `taskId`, sem tentar embutir uma cópia da task no evento.
O cliente busca a entidade alterada, aplica a resposta na inbox de forma
idempotente e confirma a outbox correspondente.

Conflitos de campos comuns obedecem à revisão aceita pelo servidor. Conclusões
recorrentes são mescladas pela chave canônica `scheduledAt`, permitindo que
ocorrências diferentes concluídas em dois dispositivos sejam preservadas. A
remoção da mesma chave representa reabertura e participa da revisão; não se
infere reabertura apenas pela ausência em uma cópia antiga.

Não haverá `GET /tasks?includeNoteTasks=true`. As tasks de nota já chegam pelo
sync de documentos, inclusive com operações locais pendentes, portanto a
composição no cliente é mais correta para o comportamento offline.

## Lista agregada local

O provider de apresentação recebe `includeNoteTasks` e combina:

- a stream de tasks independentes abertas;
- quando habilitada, a extração de `TaskNode`s dos documentos efetivos locais
  das notas visíveis ao usuário.

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
de notificação incorporam a origem para impedir colisões. Alterar, concluir,
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
3. abortar se qualquer uma contiver linhas;
4. remover `task_completions` antes de `tasks`;
5. recriar `tasks` com o contrato independente e sem `note_id` ou `position`;
6. criar a nova estrutura de operações idempotentes e índices por proprietário,
   estado e agenda;
7. preservar os scripts históricos como evidência, identificando-os como não
   executáveis depois da reutilização do nome;
8. remover do migrador Drift somente os upgrades condicionais antigos depois
   de confirmar o menor schema version ainda suportado; bancos locais que ainda
   contenham restos físicos recebem a mesma verificação vazia antes da remoção.

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
- idempotência e rejeição de revisão inválida no backend;
- merge de conclusões por `scheduledAt`;
- sync de dois dispositivos do mesmo proprietário;
- autorização e isolamento entre usuários;
- ordenação agregada, filtro de tasks das notas e identidades entre fontes;
- histórico de tasks simples e ocorrências recorrentes;
- navegação para `noteId` e `blockId` corretos;
- união de notificações sem colisão entre fontes;
- contratos JSON equivalentes em Go e Dart;
- migração abortando diante de qualquer linha legada;
- `flutter analyze`, testes Flutter focados e `go test ./...`.

Testes que validem apenas geometria, posição de pixels ou aparência visual não
serão adicionados. Se um teste visual antigo bloquear a mudança sem proteger
comportamento útil, ele será removido conforme a convenção do projeto.

## Fases futuras

O compartilhamento adicionará participantes e permissões ao redor do mesmo
`taskId`. Ele exigirá convites, revogação, fan-out de `sync_changes` e regras de
conflito entre usuários, mas não mudará uma task independente para dentro de
uma nota nem alterará sua identidade.

