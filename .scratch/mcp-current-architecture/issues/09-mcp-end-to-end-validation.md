# 09 — Validar o MCP de ponta a ponta

**What to build:** O MCP deve ser comprovadamente capaz de executar operações completas e produzir o mesmo estado no snapshot REST/OT, nas projeções e no Flutter.

**Blocked by:** 05 — Expor tarefas, metadados e ocorrências recorrentes; 06 — Expor anexos pelo MCP; 07 — Expor compartilhamento e preferências; 08 — Adicionar segurança operacional do MCP.

**Status:** completed

- [x] Executar fluxo completo pelo transporte MCP em memória, equivalente ao protocolo usado pelo Inspector.
- [x] Expor as tools de nota, blocos, metadados e exclusão pelo seam REST/OT.
- [x] Expor tarefas, recorrência e ocorrências pelo snapshot canônico, sem mutação direta da projeção.
- [x] Expor o ciclo de anexos com autorização no serviço.
- [x] Expor compartilhamento e verificar a permissão no serviço existente.
- [x] Consultar o mesmo estado pelo seam REST/OT canônico usado pelo Flutter.
- [x] Testar retry idempotente e sessões MCP independentes no SDK.
- [x] Executar `go test ./...`, `go vet ./...`, `flutter analyze` e testes Flutter focados.
- [x] Registrar explicitamente capacidades fora do produto atual.

**Evidence:** `backend/internal/mcp/mcp_e2e_test.go`; `go test ./...` (235 passed); `go vet ./...` (no issues); `flutter analyze` (no issues); focused Flutter tests (21 passed).

**Scope note:** live MCP Inspector execution and live PostgreSQL/Flutter visual verification require a configured authenticated runtime. The repository validation uses the official Go SDK in-memory transport and the same server/tool registration path. Memories, souls, tags, contexts, embeddings, routines, Telegram and Yjs/YDoc remain intentionally unsupported because they are not part of the current app structure.
