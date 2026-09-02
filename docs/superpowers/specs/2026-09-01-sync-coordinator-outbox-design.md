# Sync Coordinator + Global Outbox — Design

## Status

Implementado na branch `codex/fix-all-editor-sync`. O change-feed/inbox que era
uma etapa posterior foi incorporado durante a correção completa; as tabelas
locais agora fazem parte do schema Drift (v31).

## Problema

O editor persiste operações locais rapidamente na `pending_note_operations`, mas o envio ao servidor ainda depende do ciclo de vida de uma `NoteSyncSession` aberta. Ao fechar a nota, `dispose()` garante a durabilidade local e deixa o retry para uma futura sessão, porém o `NoteCatalogSync` não drena a outbox de operações. Isso permite que uma edição fique segura no SQLite, mas sem chegar ao servidor até a nota ser reaberta.

Além disso, cada flush local de 50 ms pode disparar `syncPending()` imediatamente, gerando lotes de rede pequenos durante digitação contínua. O polling da nota aberta também usa intervalo fixo de 2 s, sem backoff para falhas transitórias.

## Objetivos desta etapa

1. Drenar a outbox de notas fechadas sem depender da tela do editor.
2. Nunca fazer o worker global competir com a sessão de uma nota aberta.
3. Manter persistência local rápida (50 ms) e desacoplar isso do ritmo de envio para a rede.
4. Coalescer envios de uma nota aberta por uma pequena janela de rede.
5. Aplicar retry com backoff e jitter no worker global.
6. Acordar o worker ao voltar conectividade, ao retornar ao foreground e por timer de segurança.
7. Não alterar o protocolo REST/OT nem a lógica de rebase nesta etapa.
8. Consumir mudanças remotas por um change-feed global durável, sem aplicar
   eventos diretamente no widget do editor.

## Não objetivos

- Não substituir REST/OT por Yjs, WebSocket ou SSE.
- Não adicionar SSE/WebSocket nesta etapa; o cursor HTTP continua sendo o
  mecanismo confiável de recuperação.
- Não mudar o formato wire das operações.
- Não fazer background execution nativa quando o processo do app estiver encerrado.
- Não aplicar sync do worker global em notas atualmente ativas no editor.

## Arquitetura

### 1. `NoteOutboxWorker`

Novo serviço app-scoped responsável por procurar notas com operações pendentes e chamar `NoteOperationsSyncService.syncPending(noteId)` para notas inativas.

O worker possui uma fila lógica por nota no próprio `NoteOperationsSyncService`, portanto não precisa reimplementar locking de sync. Ele deve consultar `NoteSessionActivityTracker` e ignorar notas ativas; essas continuam sendo responsabilidade da `NoteSyncSession`, que possui o callback de reconciliação necessário para atualizar o `MutableDocument` visível quando chegam operações remotas.

### 2. Descoberta de trabalho

`NoteOperationsDao` ganha uma consulta para listar `noteId`s distintos que possuem linhas `pending` ou `in_flight` para o usuário atual. `in_flight` precisa ser incluído porque um crash/restart pode deixar `sync_session` persistida e `syncPending()` sabe retomar exatamente esse lote.

### 3. Wake-ups

O provider app-scoped do worker deve reagir a:

- início de sessão autenticada;
- `Connectivity().onConnectivityChanged` quando existir qualquer transporte disponível;
- retorno do app para foreground, via método explícito `wake()` chamado pelo root app;
- timer de segurança enquanto autenticado.

O worker também pode ser acordado por código que acabou de persistir uma operação, mas isso é opcional nesta etapa porque notas abertas já sincronizam pela própria sessão. O wake de foreground/conectividade cobre notas fechadas.

### 4. Backoff

Falhas transitórias são rastreadas por `noteId` em memória no worker. A próxima tentativa usa sequência aproximada `1s, 2s, 5s, 10s, 30s, 60s`, com jitter pequeno. Um sucesso limpa o backoff da nota. Erros de protocolo 4xx não entram em loop agressivo; o worker os mantém fora até um novo wake significativo ou restart, sem apagar a outbox.

O estado persistente existente (`attemptCount`, `lastAttemptAt`, `note_sync_errors`) permanece fora desta etapa para evitar duplicar política entre worker e sessão. Uma etapa posterior pode consolidar telemetria persistida.

### 5. Coalescing da nota aberta

`NoteOperationAdapter` continua gravando localmente depois de 50 ms. `NoteSyncSession` deixa de chamar rede imediatamente a cada callback `onLocalOperations`. Em vez disso agenda um sync de rede após 350 ms sem novo lote. `flushNow()` e fechamento continuam forçando apenas a persistência local; não passam a aguardar a rede.

O polling continua servindo para colaboração remota, mas um sync já agendado/rodando usa a fila existente e não pode se sobrepor a outro request da mesma nota.

### 6. Semântica de durabilidade

A invariável central passa a ser explícita:

- `persisted locally`: operação saiu do buffer em memória e foi confirmada pela transação SQLite que grava outbox + documento materializado;
- `synced`: operação deixou a outbox após ack do servidor.

O fechamento da nota só depende de `persisted locally`. A rede nunca bloqueia a navegação para trás.

## Fluxos

### Edição e fechamento rápido

```text
editor change
  -> 50 ms
  -> SQLite transaction (outbox + materialized document)
  -> usuário fecha a nota
  -> sessão encerra sem esperar rede
  -> NoteOutboxWorker encontra noteId inativo
  -> syncPending(noteId)
  -> servidor confirma
  -> outbox esvazia
```

### Nota aberta

```text
editor change
  -> 50 ms persistência local
  -> agenda network sync 350 ms
  -> novas teclas reiniciam janela
  -> POST com lote maior
  -> reconcile no próprio NoteSyncSession
```

### Offline

```text
worker tenta
  -> erro transitório
  -> backoff por nota
  -> conectividade volta
  -> wake imediato
  -> retry
```

## Segurança de concorrência

- `NoteOperationsSyncService._syncQueue` continua sendo a autoridade de serialização por `noteId`.
- O worker global não toca nota ativa.
- Escrita/rebase da outbox continua protegida por `_outboxQueue`.
- Uma `sync_session` órfã continua sendo retomada por `syncPending()` com deduplicação do servidor.

## Testes obrigatórios

1. DAO lista notas com `pending` e `in_flight`, sem duplicatas e filtradas por usuário.
2. Worker sincroniza nota inativa com outbox.
3. Worker ignora nota ativa.
4. Worker continua para a próxima nota quando uma falha transitoriamente.
5. Sucesso limpa backoff e permite novo sync imediato.
6. Callback de operações locais em sessão aberta é coalescido em uma janela de 350 ms.
7. `flushNow()` continua garantindo persistência local sem exigir sucesso de rede.
8. Fechar sessão offline deixa a operação na outbox e o worker consegue enviá-la posteriormente.

## Próxima etapa: retenção e wake-up remoto

O feed e a inbox já estão implementados. Uma política de retenção/compactação
do feed exige protocolo adicional de acknowledgement/expiração de cursor; não
foi adicionado um TTL especulativo que poderia fazer clientes offline pularem
eventos. SSE continua opcional apenas como mecanismo de wake-up, mantendo o
cursor HTTP como recuperação.
