# 08 — Adicionar segurança operacional do MCP

**What to build:** O MCP deve oferecer credenciais controláveis e proteger operações sensíveis do agent.

**Blocked by:** 03 — Expor leitura canônica de notas e documentos pelo MCP; 04 — Expor edição completa de blocos pelo MCP; 05 — Expor tarefas, metadados e ocorrências recorrentes; 06 — Expor anexos pelo MCP; 07 — Expor compartilhamento e preferências.

**Status:** ready-for-agent

- [ ] Substituir o token MCP fixo de longa duração por credencial identificável, expirável, revogável e rotacionável.
- [ ] Adicionar escopos separados para leitura e escrita.
- [ ] Registrar agent, usuário, tool, recurso, resultado e horário das operações.
- [ ] Exigir confirmação para exclusões, alteração de permissões e outras operações destrutivas.
- [ ] Garantir que `userId` seja derivado da credencial e não de argumentos enviados pela tool.
- [ ] Testar token ausente, expirado, revogado, escopo insuficiente e confirmação recusada.
