# 03 — Expor leitura canônica de notas e documentos pelo MCP

**What to build:** Um agent autenticado deve conseguir localizar notas e consultar o snapshot REST/OT, a revisão, as operações e as permissões aplicáveis.

**Blocked by:** 01 — Definir o contrato MCP atual e remover o escopo legado; 02 — Criar o comando documental compartilhado entre app e MCP.

**Status:** ready-for-agent

- [x] Implementar listagem paginada de notas.
- [x] Implementar leitura de nota por identificador.
- [x] Implementar leitura do documento canônico por identificador de nota.
- [x] Implementar consulta de revisão e operações desde uma revisão informada.
- [x] Restringir todos os resultados ao usuário autenticado e às permissões de compartilhamento válidas.
- [x] Retornar erros estruturados para nota inexistente, acesso negado e argumentos inválidos.
- [x] Testar leitura de nota própria, nota compartilhada e nota sem permissão.
