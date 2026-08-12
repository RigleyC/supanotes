# Pesquisa: práticas de mercado para projeção incremental

Data: 2026-08-12

## Escopo

Esta pesquisa explora o item 1 da revisão arquitetural de 2026-08-12:
projetar somente o que a operação alterou.

O foco é comparar:

- change sets derivados de operações;
- diffs entre snapshots;
- índices duráveis por bloco;
- reconciliação remota, rebase e movimentos estruturais;
- rebuild completo para hydration, recovery, repair e verificação.

As fontes são documentação oficial, código de primeira parte ou artigos técnicos
dos próprios autores. Cada seção separa fatos da fonte e inferências para o
SupaNotes. Nenhum código da aplicação foi alterado.

## Contexto local observado

Fatos no repositório:

- A revisão chama o item 1 de **Projetar somente o que a operação alterou**.
  Ela observa que o flush local serializa todos os blocos, projeta todos os
  blocos e sincroniza todas as tarefas da nota. A direção proposta é usar IDs e
  dependências locais, mantendo rebuild para hydration, recovery e repair. Fonte:
  [relatório local da revisão](file:///C:/Users/rigleyc/AppData/Local/Temp/supanotes-architecture-review-2026-08-12.html).
- [`NoteDocumentProjector`](../../lib/features/tasks/domain/note_document_projector.dart)
  percorre todos os blocos, calcula texto, `content`, `excerpt` e tarefas.
- [`TaskProjectionEngine`](../../lib/features/tasks/domain/task_projection_engine.dart)
  recebe um snapshot ou um documento completo e grava a projeção inteira.
- [`TasksDao`](../../lib/core/database/daos/tasks_dao.dart) carrega as tarefas
  ativas da nota, marca como removidas as que não aparecem na lista recebida e
  faz upsert de todas as tarefas projetadas.
- A operação de sync já possui a informação necessária para separar origens:
  operações locais, `remoteOperations` e operações pendentes depois do rebase
  em [`NoteOperationsSyncService`](../../lib/core/sync/note_operations_sync_service.dart).
- O README da feature define a tabela `tasks` como projeção relacional. O
  documento REST/OT continua sendo a fonte canônica:
  [`lib/features/tasks/README.md`](../../lib/features/tasks/README.md).

Inferência: o primeiro corte pode otimizar a projeção de tarefas sem alterar o
documento canônico. `content` e `excerpt` têm dependência global: um bloco no
início pode alterar todo o texto concatenado e os primeiros 200 caracteres.
Eles devem continuar no caminho completo até existir uma estratégia própria.

## Resumo executivo

O padrão mais forte nas fontes é híbrido:

1. Aplicar mudanças pequenas por operação, ID, chave ou faixa afetada.
2. Manter contexto suficiente para mapear posições e dependências.
3. Persistir as mudanças em uma transação ou checkpoint consistente.
4. Usar snapshot completo para bootstrap, checkpoint, repair, checksum inválido
   ou quando o change set não descreve com segurança o impacto.

Não encontrei evidência de que editores colaborativos maduros dependam, como
primeira solução, de um índice durável completo por bloco. Eles usam estruturas
indexadas ou grafos de dependência quando a escala exige isso, mas mantêm uma
representação canônica e uma rota de reconstrução.

## 1. ProseMirror: operações, mapas e estado derivado

### Fatos

- O ProseMirror converte cada edição em uma transação. A transação descreve a
  mudança e produz o novo estado; não há mutação implícita do documento:
  [ProseMirror Guide — Transactions](https://prosemirror.net/docs/guide/#state.transactions).
- As mudanças são decompostas em `Step`. Um `Step` pode ser aplicado, invertido
  e mapeado através de outros passos. Cada passo fornece um `StepMap` para
  converter posições do documento anterior para o novo documento:
  [ProseMirror Guide — Steps, Mapping e Rebasing](https://prosemirror.net/docs/guide/#transform).
- O guia recomenda manter estado derivado, como `DecorationSet`, dentro do
  estado do plugin e mapeá-lo pela mudança. A estrutura em árvore permite
  reconstruir somente as partes tocadas pela alteração, em vez de criar tudo de
  novo:
  [ProseMirror Guide — Decorations](https://prosemirror.net/docs/guide/#view.decorations).
- A documentação de `Step` define `apply`, `invert`, `map` e `getMap` como
  operações fundamentais para registrar, reproduzir e reordenar mudanças:
  [ProseMirror Reference — Step](https://prosemirror.net/docs/ref/#transform.Step).
- A versão atual do módulo adicionou `Transform.changedRange`, que retorna uma
  faixa que inclui as mudanças da transformação:
  [ProseMirror Changelog](https://prosemirror.net/docs/changelog/).
- Para carregar um documento novo, o guia trata a criação de um estado novo
  como exceção ao fluxo normal de derivar o estado anterior por transação:
  [ProseMirror Guide — Editor state](https://prosemirror.net/docs/guide/#state).

### Inferências

- A unidade útil para um projection change set não é apenas “o bloco que a
  operação nomeia”. É também a faixa ou posição que a operação desloca.
- Uma operação de texto pode atualizar apenas a tarefa identificada. Uma
  inserção, remoção, split, join ou move precisa mapear a ordem e pode afetar
  um sufixo de tarefas.
- O modelo de ProseMirror favorece um change set gerado no mesmo ponto em que a
  operação é aplicada. Um diff posterior perde contexto de posição e de rebase.
- A regra de rebuild completo para carregar um documento novo ou quando o
  mapeamento falha é compatível com a prática documentada.

## 2. Yjs: updates incrementais, state vectors e eventos de dependência

### Fatos

- Updates Yjs são binários e são comutativos, associativos e idempotentes. Um
  documento converge quando recebe todos os updates:
  [Yjs — Document Updates](https://docs.yjs.dev/api/document-updates).
- `encodeStateAsUpdate` pode receber o state vector do destino e produzir
  somente as diferenças que faltam. O state vector descreve o estado conhecido
  de cada cliente:
  [Yjs — Document Updates](https://docs.yjs.dev/api/document-updates).
- Observers de Yjs são chamados depois de cada transação. A documentação
  recomenda agrupar várias mudanças em uma transação para reduzir chamadas de
  observer e updates enviados aos peers:
  [Yjs — Working with Shared Types](https://docs.yjs.dev/getting-started/working-with-shared-types).
- `Y.Event` expõe o tipo alterado, o caminho até o tipo, a transação e deltas de
  array ou texto. Para mapas, `changes.keys` informa `add`, `update` e `delete`:
  [Yjs — Y.Event](https://docs.yjs.dev/api/y.event).
- O update possui origem de transação. O provider pode distinguir o update
  local do remoto por essa origem:
  [Yjs — Document Updates](https://docs.yjs.dev/api/document-updates).

### Inferências

- Yjs mostra uma separação clara entre transporte incremental e leitura do
  estado atual. O update identifica o que chegou; a projeção ainda lê o valor
  final do tipo afetado.
- Para SupaNotes, a origem remota não deve causar uma segunda regra de projeção.
  Local, remoto e rebased devem convergir para o mesmo `ProjectionChangeSet`.
- O caminho completo continua necessário quando só existe um snapshot ou quando
  o cliente detecta que perdeu updates. O state vector e a idempotência reduzem
  esse risco, mas não eliminam a necessidade de repair.

## 3. Lexical: listeners por update e mutação por node key

### Fatos

- `registerUpdateListener` recebe o `editorState` novo, o `prevEditorState` e
  as tags da atualização:
  [Lexical — Listeners](https://lexical.dev/docs/concepts/listeners#registerupdatelistener).
- `registerMutationListener` observa um tipo de node e informa um `Map` por
  `NodeKey`, com estados `created`, `destroyed` e `updated`. A API também expõe
  contexto como tags e `prevEditorState`:
  [Lexical — Mutation listeners](https://lexical.dev/docs/concepts/listeners#registermutationlistener).
- O listener de conteúdo textual só notifica quando o texto realmente mudou.
  Uma atualização que não altera o texto não dispara esse listener:
  [Lexical — Text content listener](https://lexical.dev/docs/concepts/listeners#registertextcontentlistener).
- A documentação alerta que agendar outra atualização dentro de um update
  listener cria uma atualização em cascata e pode produzir dois updates de DOM.
  Node transforms são a alternativa indicada quando a transformação pode ser
  feita no mesmo update:
  [Lexical — Waterfall updates](https://lexical.dev/docs/concepts/listeners#waterfall-updates).

### Inferências

- Lexical usa identidade estável de node para reduzir o trabalho downstream.
  Isso é mais próximo de um change set por ID do que de um diff textual global.
- O listener de mutation não prova que todos os descendentes dependentes sejam
  independentes. Um transform pode alterar um node e exigir trabalho em um
  elemento pai ou em um índice derivado.
- A separação entre listener de update, listener de mutation e listener de
  conteúdo sugere que SupaNotes também deve separar tarefas de `content` e
  `excerpt`, em vez de tratar toda alteração como a mesma projeção.

## 4. SQLite: changesets, snapshot diff e limites de views

### Fatos

- A Session Extension grava mudanças de tabelas em um changeset ou patchset e
  permite aplicar essas mudanças a outro banco com schema e dados iniciais
  compatíveis:
  [SQLite — Session Extension](https://www.sqlite.org/sessionintro.html).
- Um changeset contém `INSERT`, `DELETE` e `UPDATE`. Cada mudança identifica a
  linha por chave primária; um `UPDATE` carrega apenas as colunas alteradas e
  seus valores antigo e novo:
  [SQLite — Changesets and Patchsets](https://www.sqlite.org/sessionintro.html#_2_1_changesets_and_patchsets).
- A aplicação de changesets detecta conflitos como linha ausente, valor antigo
  diferente ou violação de constraint. O chamador escolhe entre omitir,
  abortar ou aplicar a mudança conforme o conflito:
  [SQLite — Conflicts](https://www.sqlite.org/sessionintro.html#_2_2_conflicts).
- `sqlite3session_diff` compara duas tabelas compatíveis por chave primária e
  gera inserts, deletes e updates para transformar a tabela `from` na tabela
  `to`:
  [SQLite — sqlite3session_diff](https://www.sqlite.org/session/sqlite3session_diff.html).
- SQLite `VIEW` é somente leitura. Um `INSTEAD OF` trigger pode fornecer uma
  escrita indireta, mas a view não é uma tabela materializada nativa:
  [SQLite — CREATE VIEW](https://sqlite.org/lang_createview.html) e
  [SQLite — omitted features](https://www.sqlite.org/omitted.html).
- A Session Extension também documenta rebase de um changeset local depois da
  aplicação de um changeset remoto e da resolução de conflitos:
  [SQLite — Rebasing changesets](https://www.sqlite.org/session.html#rebasings_changesets).

### Inferências

- Operação-driven e snapshot-diff são técnicas complementares. O changeset é
  melhor para o caminho normal; `sqlite3session_diff` é um modelo para fallback,
  repair ou validação entre uma projeção conhecida e uma projeção reconstruída.
- O diff não substitui o evento original. Ele precisa de duas versões
  compatíveis e de uma chave estável. No SupaNotes, isso corresponde a manter
  IDs estáveis de bloco e não inferir identidade apenas pela posição.
- Como SQLite não materializa views por conta própria, uma projection table como
  `tasks` precisa de uma política explícita de manutenção e de reconstrução.

## 5. PowerSync e WatermelonDB: sync incremental com checkpoint completo

### PowerSync — fatos

- O protocolo usa a mesma ideia para sync inicial, download em lote após
  offline e streaming incremental. Cada bucket mantém uma lista ordenada de
  operações de linha, normalmente `PUT` e `REMOVE`:
  [PowerSync — Protocol](https://docs.powersync.com/architecture/powersync-protocol).
- Cada checkpoint representa um ponto consistente. Cliente e servidor calculam
  checksum por bucket; se o checksum não confere, o cliente baixa o bucket
  inteiro novamente:
  [PowerSync — Checksums](https://docs.powersync.com/architecture/powersync-protocol#checksums-for-verifying-data-integrity).
- Enquanto há mutações na fila de upload, o cliente não avança para o próximo
  checkpoint. Depois do reconhecimento e do download do checkpoint, a base local
  avança para o estado consistente:
  [PowerSync — Consistency](https://docs.powersync.com/architecture/consistency).
- O write checkpoint evita aplicar no cliente um estado remoto que ainda não
  contém a própria mutação local. Se a persistência no backend for assíncrona,
  o cliente pode ver a mudança desaparecer e reaparecer:
  [PowerSync — Custom Write Checkpoints](https://docs.powersync.com/handling-writes/custom-write-checkpoints).

### WatermelonDB — fatos

- O pull inicial deve devolver todos os registros quando `lastPulledAt` é nulo
  ou zero. Pulls seguintes devolvem mudanças desde o marcador e precisam formar
  uma visão consistente:
  [WatermelonDB — Sync backend](https://watermelondb.dev/docs/Sync/Backend).
- O push deve ser transacional. Se houver conflito porque o registro mudou no
  servidor depois de `lastPulledAt`, o backend deve abortar e forçar novo pull:
  [WatermelonDB — Push endpoint](https://watermelondb.dev/docs/Sync/Backend#implementing-push-endpoint).
- A documentação recomenda um marcador monotônico de mudança, como
  `last_modified` ou um contador global, e uma política explícita para deletes.

### Inferências

- O mercado de sync local não escolhe entre “só operações” e “só snapshot”. Ele
  usa operações incrementais para o caminho comum e checkpoint completo para
  consistência, checksum, inicialização e recuperação.
- A projeção incremental do SupaNotes deve estar vinculada à revisão/estado que
  originou o change set. Não é seguro aplicar um delta de tarefas sobre um
  documento que já avançou para outra revisão.
- O rebuild completo deve ser uma ação normal e observável, não um fallback
  silencioso que mascara perda de operações.

## 6. Produtos colaborativos maduros

### Figma

#### Fatos

- O primeiro modelo de persistência do Figma baixava o documento, editava localmente
  e fazia upload periódico do documento inteiro. A empresa descreve esse modelo
  como incompatível com colaboração porque saves concorrentes podiam sobrescrever
  trabalho ou mostrar uma versão antiga:
  [Figma — Multiplayer Editing](https://www.figma.com/blog/multiplayer-editing-in-figma/).
- O multiplayer atual recebe e transmite mudanças. O serviço é autoritativo e
  trata validação, ordenação e resolução de conflitos:
  [Figma — Making multiplayer more reliable](https://www.figma.com/blog/making-multiplayer-more-reliable/).
- O Figma adicionou um journal durável de mudanças com número de sequência e
  manteve checkpoints do arquivo inteiro. Na recuperação, carrega o último
  checkpoint e reaplica as entradas posteriores do journal:
  [Figma — Journal and checkpoints](https://www.figma.com/blog/making-multiplayer-more-reliable/#introducing-the-journal).
- O próprio artigo distingue o custo: journal grava mudanças incrementais,
  enquanto checkpoint depende do tamanho do arquivo inteiro. Os dois mecanismos
  coexistem:
  [Figma — Incremental journal versus checkpoint](https://www.figma.com/blog/making-multiplayer-more-reliable/#introducing-the-journal).
- Para carregamento parcial, o Figma mantém um `QueryGraph` de dependências de
  leitura. Para edição, também considera dependências de escrita porque uma
  alteração pode exigir recomputar caches de objetos downstream. A empresa
  alerta que omitir uma dependência pode causar inconsistência de dados:
  [Figma — Dynamic loading and write dependencies](https://www.figma.com/blog/speeding-up-file-load-times-one-page-at-a-time/).

#### Inferências

- Figma é evidência forte para um desenho híbrido: delta/journal durante a
  operação e snapshot/checkpoint para recuperação.
- A unidade de trabalho não é sempre o objeto alterado. Dependências de escrita
  podem ampliar o conjunto afetado, do mesmo modo que um move ou alteração de
  ordem amplia a faixa de tarefas em SupaNotes.
- O `QueryGraph` é uma estrutura de dependência em memória, não evidência de que
  SupaNotes deva começar com um índice durável por bloco. O ganho foi necessário
  para uma escala muito maior e para carregamento parcial de páginas.

### Google Docs

#### Fatos

- O material oficial do Google descreve que os novos editores foram projetados
  para colaboração e que o mecanismo usa Operational Transformation para
  mesclar edições em tempo real:
  [Google Cloud Blog — Google Docs collaboration](https://cloud.googleblog.com/2010/09/whats-different-about-new-google-docs.html).

#### Inferência

- Para SupaNotes, a lição útil não é copiar a implementação do Google Docs. É
  manter a operação transformada como unidade de reconciliação e derivar as
  projeções do estado final após o rebase.

## 7. Índices duráveis e incremental view maintenance

### Fatos

- A literatura de incremental view maintenance define algoritmos para calcular
  alterações de uma view materializada em resposta a inserts, deletes e updates
  nas relações de origem. O objetivo é atualizar somente as tuplas afetadas,
  em vez de recomputar a view inteira:
  [Gupta, Mumick e Subrahmanian — Maintaining views incrementally](https://doi.org/10.1145/170036.170066).
- O mesmo trabalho descreve `DRed` para views recursivas: remove primeiro um
  conjunto possivelmente maior e depois rederiva o que continua válido. Isso
  mostra que a manutenção incremental pode precisar de uma fase conservadora de
  rederivação.
- Em uma projeção local, índices auxiliares podem reduzir o custo de encontrar
  dependências, mas também se tornam estado derivado que precisa ser mantido e
  reconstruído.

### Inferências

- Um índice durável por bloco só vale a complexidade se o benchmark mostrar que
  localizar e reprocessar a faixa afetada continua caro.
- Se for adotado depois, o índice deve ser uma projeção explícita com:
  `blockId` estável, ordem atual, tipo, identidade do pai, texto/metadata usados
  por tarefas e uma revisão do documento. Ele deve ter rebuild determinístico a
  partir de `notes.document`.
- A primeira implementação não deve transformar esse índice em uma segunda
  fonte de verdade nem exigir que o sync confie nele para reconstruir o editor.

## Comparação das estratégias

| Estratégia | Prática observada | Vantagem | Risco principal | Uso indicado no SupaNotes |
|---|---|---|---|---|
| Change set por operação | ProseMirror Steps/Maps, Yjs events/updates, SQLite changesets, PowerSync row operations | Usa contexto causal e pode trabalhar em O(delta) | O impacto real pode incluir dependências, pais ou sufixos | Caminho normal local, remoto e rebased |
| Diff entre snapshots | SQLite `session_diff`, comparação `from`/`to`, checkpoints e checksum | Funciona quando a origem do evento foi perdida; útil para verificar e reparar | Custa O(N), precisa de duas versões e pode perder a causa | Hydration, recovery, repair, mismatch e fallback seguro |
| Índice durável por bloco | Estruturas de IVM e grafos de dependência em sistemas de escala | Reduz busca de dependências e permite projeções maiores | Duplicação de estado, migração, invalidação e repair próprios | Segunda fase, somente após benchmark |
| Rebuild completo | Checkpoints Figma, re-download de bucket PowerSync, novo estado ProseMirror | Determinístico e simples de auditar | Custo proporcional ao documento | Rota obrigatória de bootstrap e recuperação |

## Implicações concretas para o item 1

### Decisão recomendada

Adotar um change set dirigido por operações, com fallback conservador para
rebuild completo.

O change set deve ser produzido na seam que conhece a operação e deve conter, no
mínimo:

- IDs de blocos criados, alterados e removidos;
- IDs de tarefas afetadas;
- indicação de alteração estrutural;
- menor posição estrutural afetada e, se necessário, a posição final;
- ancestrais ou descendentes que recebem dependência da alteração;
- revisão do documento ao qual o change set pertence;
- `requiresFullRebuild` quando a operação não puder ser classificada com
  segurança.

### Regras de projeção

1. **Texto ou metadata de uma tarefa:** ler o bloco final por ID e atualizar
   somente essa tarefa.
2. **Inserção, remoção, split, join ou move:** recalcular o trecho conservador
   a partir da menor posição afetada. Como `tasks.position` hoje é derivado do
   índice do bloco, a ordem de tarefas posteriores pode mudar mesmo quando elas
   não foram editadas diretamente.
3. **Mudança de pai ou dependência:** incluir o fechamento de dependências; não
   confiar somente no ID da operação.
4. **Delete:** remover ou marcar a tarefa como removida e recalcular a faixa que
   pode ter mudado de posição.
5. **Rebase:** construir o change set a partir do estado final após aplicar as
   operações remotas e as pendências rebased. Não projetar a operação remota
   isoladamente sobre um estado anterior.
6. **`content` e `excerpt`:** manter o recálculo completo no primeiro corte. Uma
   fase posterior pode criar uma estratégia incremental separada, pois o
   `excerpt` tem limite de 200 caracteres e depende da concatenação ordenada.
7. **Persistência:** gravar o documento local, a projeção de tarefas e os
   metadados de revisão em uma transação atômica. O change set não deve ser
   confirmado se a projeção falhar.

### Quando fazer rebuild completo

Fazer rebuild completo em qualquer um destes casos:

- primeira hidratação de uma nota;
- recovery de uma sessão ou de uma fila pendente;
- repair explícito;
- snapshot remoto sem operações classificáveis;
- operação desconhecida, ID ausente ou identidade duplicada;
- falha ao mapear posição, ordem ou dependência;
- revisão do documento diferente da revisão esperada pelo change set;
- checksum, contagem ou comparação de projeção inconsistente.

O rebuild deve ser explícito no telemetry/log. Não deve ser um fallback silencioso
que esconda a perda do contexto da operação.

### Validação e benchmark

O benchmark acordado para o design deve medir o caminho atual contra o caminho
incremental com notas de 1, 100 e 1.000 blocos.

Casos mínimos:

- alteração de texto em tarefa no início, meio e fim;
- alteração de metadata de tarefa;
- inserção e remoção de bloco não-tarefa;
- inserção, remoção e move de tarefa;
- mudança de pai/ancestral;
- lote remoto seguido de rebase de operações pendentes;
- delete remoto de tarefa localmente pendente;
- operação desconhecida que deve cair no rebuild.

Medir separadamente:

- tempo de serialização/decodificação;
- tempo de projeção;
- alocações, quando o harness permitir;
- número de leituras, upserts e deletes SQLite;
- tempo total da transação;
- número de rebuilds completos;
- igualdade entre a projeção incremental e a projeção completa de referência.

O critério de correção é mais importante que um percentual de ganho: depois de
cada caso, a projeção incremental deve ser byte-a-byte ou campo-a-campo igual à
projeção completa equivalente. O ganho de escala deve ser medido antes de
introduzir um índice durável.

## Conclusão

As melhores práticas encontradas não recomendam escolher entre operação e
snapshot como alternativas exclusivas. O desenho de produção mais consistente é:

```text
operação local/remota/rebased
  -> change set + revisão + dependências
  -> projeção mínima segura
  -> transação local

hydration/recovery/repair/mismatch
  -> snapshot canônico
  -> rebuild completo determinístico
```

Para o SupaNotes, isso confirma o escopo já explorado: projetar tarefas
incrementalmente para mudanças locais e remotas, recalcular uma faixa maior para
mudanças estruturais, manter `content`/`excerpt` completos na primeira fase e
preservar o rebuild como autoridade de recuperação. Um índice durável por bloco
é uma possível segunda fase, não um pré-requisito para validar o item 1.

## Fontes consultadas

- [ProseMirror Guide](https://prosemirror.net/docs/guide/)
- [ProseMirror Reference](https://prosemirror.net/docs/ref/)
- [ProseMirror Changelog](https://prosemirror.net/docs/changelog/)
- [Yjs Document Updates](https://docs.yjs.dev/api/document-updates)
- [Yjs Working with Shared Types](https://docs.yjs.dev/getting-started/working-with-shared-types)
- [Yjs Event API](https://docs.yjs.dev/api/y.event)
- [Lexical Listeners](https://lexical.dev/docs/concepts/listeners)
- [SQLite Session Extension](https://www.sqlite.org/sessionintro.html)
- [SQLite `sqlite3session_diff`](https://www.sqlite.org/session/sqlite3session_diff.html)
- [SQLite `CREATE VIEW`](https://sqlite.org/lang_createview.html)
- [PowerSync Protocol](https://docs.powersync.com/architecture/powersync-protocol)
- [PowerSync Consistency](https://docs.powersync.com/architecture/consistency)
- [PowerSync Custom Write Checkpoints](https://docs.powersync.com/handling-writes/custom-write-checkpoints)
- [WatermelonDB Sync Backend](https://watermelondb.dev/docs/Sync/Backend)
- [Figma Multiplayer Editing](https://www.figma.com/blog/multiplayer-editing-in-figma/)
- [Figma Making multiplayer more reliable](https://www.figma.com/blog/making-multiplayer-more-reliable/)
- [Figma Speeding Up File Load Times](https://www.figma.com/blog/speeding-up-file-load-times-one-page-at-a-time/)
- [Google Cloud Blog on Google Docs collaboration](https://cloud.googleblog.com/2010/09/whats-different-about-new-google-docs.html)
- [Maintaining views incrementally, ACM SIGMOD Record](https://doi.org/10.1145/170036.170066)
