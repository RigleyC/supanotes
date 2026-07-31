# 01 — Definir o contrato MCP atual e remover o escopo legado

**What to build:** O MCP deve ter um contrato oficial alinhado ao produto atual, cobrindo somente notas, documentos, blocos, tarefas, recorrência, anexos, compartilhamento e preferências.

**Blocked by:** None — can start immediately.

**Status:** completed

- [x] Registrar a matriz de capacidades MCP atuais e seus limites.
- [x] Remover do contrato e da documentação referências runtime a memories, souls, tags, contexts, embeddings, routines, Telegram, agent loop e Yjs.
- [x] Definir quais operações são leitura, escrita ou destrutivas.
- [x] Definir os formatos de identidade, `noteId`, `blockId`, revisão e `operationId`.
- [x] Confirmar que o contrato não permite tarefa independente de uma nota.
- [x] Adicionar testes que falhem se tools removidas forem registradas novamente.
