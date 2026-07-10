# Sincronização e CRDT - Refatoração Arquitetural (2026-07-09)

Este documento define o design para resolver inconsistências de sync, flickering na UI, ordenação de blocos e "phantom nodes". 

## 1. YDoc como Única Fonte de Verdade (Single Source of Truth)
**Problema Atual:** O `NodeSyncManager` no Flutter escreve diretamente na tabela SQLite `note_nodes` enquanto também serializa operações para o Yjs. Isso bifurca o estado e causa conflitos de concorrência com o `pull` e eventos remotos, gerando *flicker* e dados sobrepostos.
**Design:** 
- O `NodeSyncManager` **não irá mais realizar gravações no SQLite**. Sua única responsabilidade será transformar ações do `SuperEditor` em `NodeOperations` (Insert, Update, Delete, Move) e passá-las para a ponte (Bridge).
- A ponte aplica essas mutações estritamente no `YDoc`.
- Uma única via de retorno (Projeção): Sempre que o `YDoc` mudar (seja por flush local ou por evento remoto de WebSocket), o novo `YjsSyncManager._projectToNodes` fará a tradução do `YMap` ("nodes") para as tabelas locais do SQLite. Esse é exatamente o mesmo padrão de "Projetor Único" utilizado no Backend, garantindo que o SQLite no cliente seja apenas uma **view** do estado CRDT.

## 2. Fractional Indexing de Ponta a Ponta
**Problema Atual:** O sistema utiliza `double` (`REAL`) para ordenar blocos. Inserir múltiplos itens entre o mesmo par de blocos esgota a precisão do ponto flutuante, levando a posições duplicadas e perda da garantia de ordem.
**Design:**
- **Tipo Base:** A coluna `position` nas tabelas `note_nodes` e `tasks` passará de `double precision` (SQL) / `REAL` (Drift) para `VARCHAR` / `TEXT`.
- **Implementação:** Utilizar o algoritmo clássico de Fractional Indexing (strings lexográficas ex: `a0`, `a1`, `a1b`). 
- **Golang (Backend):** Adicionar migração `.sql` alterando as tabelas e adaptando os modelos SQLC.
- **Dart (Frontend):** Atualizar o Drift para usar `TextColumn`, usar uma biblioteca de Fractional Indexing no `NodeSyncManager` para gerar as posições, e migrar dados locais antigos em memória ou descartar cache.

## 3. Colapso da Dupla Representação de Tasks
**Problema Atual:** Tasks existem no `YDoc` tanto no `YMap("nodes")` quanto no `YMap("tasks")`, forçando o código a atualizar os dois lugares simultaneamente para manter o status `completed` em sincronia.
**Design Recomendado (Task as Node):**
- **YDoc:** O mapa `tasks` é removido inteiramente do CRDT. Uma tarefa é representada exclusivamente como um item dentro do `YMap("nodes")`, possuindo a propriedade `completed: true/false` no seu campo `data` JSON.
- **Backend Projection:** O arquivo `projection.go` derivará a tabela relacional `tasks` a partir dos `note_nodes` do tipo `task`. Assim, o relacional continua existindo (para queries rápidas de pending tasks), mas a fonte da verdade fica isolada num único nó Yjs.

## 4. Merge Seguro para Persistência Yjs
**Problema Atual:** O Sync REST `pull()` substitui os dados locais brutos do `local_yjs_states` usando uma query de `insertOnConflict`, o que sobrescreve sem dó as edições locais que não subiram ainda.
**Design:**
- Toda escrita externa que toque em estados Yjs (seja no Dart pelo REST ou no Go pelo compactor) deverá obedecer à regra: **sempre fazer merge**.
- No `pull()` do Dart, a função criará um `crdt.Doc` vazio, fará `applyUpdate(local_blob)`, depois `applyUpdate(remote_blob)` e salvará o blob resultante (`encodeStateAsUpdate`) no banco. Isso garante que nenhum keystroke offline seja perdido ao recuperar conectividade.

## 5. Separação de Timers: Debounce I/O vs Real-time WS
**Problema Atual:** O envio de eventos para o WebSocket está acoplado ao debounce de persistência local (500ms), causando lentidão artificial na colaboração.
**Design:**
- **Local (SQLite):** Mantém-se um debounce (ex: 500ms) para proteger o disco e a UI de engasgos com escritas de banco de dados e recriações de provider.
- **Remoto (WS):** A ponte do Yjs deve reagir à mutação do `YDoc` instantaneamente (ou com delay mínimo de 50ms para agrupar typings). Edições vão para a rede imediatamente após serem confirmadas no documento em memória.

## 6. Projeção Incremental
**Problema Atual:** `noteNodesFromDoc` varre e recria toda a árvore a cada evento.
**Design:**
- A UI no Flutter deve ser notificada com *diffs* precisos. As chaves alteradas reveladas pelo evento de `observe` do `YMap` serão mapeadas para `EditRequests` pontuais (`InsertNode`, `DeleteNode`, etc), evitando que o editor inteiro pisque ou perca o foco do cursor.
