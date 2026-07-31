# 02 — Criar o comando documental compartilhado entre app e MCP

**What to build:** O app e o MCP devem usar a mesma camada de comandos para aplicar operações no documento REST/OT, sem duplicar regras de negócio ou escrever diretamente em projeções.

**Blocked by:** 01 — Definir o contrato MCP atual e remover o escopo legado.

**Status:** completed

- [x] Reutilizar `backend/internal/noteoperations` como dono da aplicação e persistência das operações.
- [x] Criar uma interface de aplicação reutilizável para comandos documentais.
- [x] Suportar revisão-base, `clientId`, `operationId`, validação, transformação concorrente e idempotência.
- [x] Persistir operação, revisão e snapshot canônico na mesma transação.
- [x] Impedir que comandos documentais escrevam diretamente em `tasks` ou em projeções locais.
- [x] Cobrir a seam com testes de integração usando PostgreSQL real.
