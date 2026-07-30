# 04 — Expor edição completa de blocos pelo MCP

**What to build:** Um agent deve conseguir criar, editar, mover, transformar e excluir blocos de uma nota, mantendo o documento REST/OT consistente com o app.

**Blocked by:** 02 — Criar o comando documental compartilhado entre app e MCP; 03 — Expor leitura canônica de notas e documentos pelo MCP.

**Status:** ready-for-agent

- [x] Expor criação de bloco com tipo, identificador, posição, texto e metadados válidos.
- [x] Expor edição de texto de bloco.
- [x] Expor movimentação de bloco.
- [x] Expor alteração de tipo de bloco.
- [x] Expor alteração parcial de metadados.
- [x] Expor exclusão de bloco.
- [x] Exigir `noteId`, `blockId` quando aplicável e revisão-base.
- [x] Retornar snapshot canônico e revisão final após cada mutação.
- [x] Testar concorrência, retry idempotente e sincronização posterior no Flutter.
