# 08 — Adicionar segurança operacional do MCP

**What to build:** O MCP deve oferecer credenciais controláveis e proteger operações sensíveis do agent.

**Blocked by:** 03 — Expor leitura canônica de notas e documentos pelo MCP; 04 — Expor edição completa de blocos pelo MCP; 05 — Expor tarefas, metadados e ocorrências recorrentes; 06 — Expor anexos pelo MCP; 07 — Expor compartilhamento e preferências.

**Status:** completed

- [x] Substituir o token MCP fixo de longa duração por credencial identificável, expirável, revogável e rotacionável.
- [x] Adicionar escopos separados para leitura e escrita.
- [x] Registrar agent, usuário, tool, recurso, resultado e horário das operações.
- [x] Exigir confirmação para exclusões, alteração de permissões e outras operações destrutivas.
- [x] Garantir que `userId` seja derivado da credencial e não de argumentos enviados pela tool.
- [x] Testar token ausente, expirado, revogado, escopo insuficiente e confirmação recusada.

**Evidence:** `000041_mcp_tokens` and `000042_mcp_security` migrations; token create/revoke/rotate routes; `MCPAuth`; `SecurityStore`; audited tool wrapper; one-time confirmation persistence; focused MCP security tests.
