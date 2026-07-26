# 08 — Serializar e versionar preferências otimistas

**What to build:** Permitir alterações rápidas de preferências sem que uma falha antiga restaure um snapshot obsoleto ou apague mudanças mais recentes.

**Blocked by:** None — can start immediately.

**Status:** done

- [x] A fonte reativa das preferências continua sendo o cache da sessão.
- [x] Mutações concorrentes são serializadas ou identificadas por versão.
- [x] Um rollback só ocorre quando o valor atual ainda pertence à operação que falhou.
- [x] O rollback altera somente os campos da mutação.
- [x] Alterações mais novas em outros campos são preservadas.
- [x] A UI observa `idle`, `saving` e `error`, ou estados equivalentes.
- [x] Duas alternâncias rápidas produzem resultado determinístico.
- [x] Falha da primeira operação após sucesso da segunda não desfaz a segunda.
- [x] Testes cobrem concorrência, rollback seletivo e nova tentativa.
