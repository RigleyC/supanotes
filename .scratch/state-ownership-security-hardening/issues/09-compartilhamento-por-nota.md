# 09 — Isolar comandos de compartilhamento por nota

**What to build:** Fazer cada nota observar somente o loading, sucesso e erro das operações de compartilhamento que pertencem a ela.

**Blocked by:** None — can start immediately.

**Status:** done

- [x] Compartilhar uma nota não altera o estado visual de outra nota.
- [x] Revogar acesso em uma nota não substitui o resultado de outra operação.
- [x] Operações antigas não substituem resultados mais novos da mesma nota.
- [x] A lista de compartilhamentos continua a ser uma consulta independente por nota.
- [x] A invalidação atualiza somente a lista da nota afetada.
- [x] A UI interpreta o resultado da operação que ela iniciou.
- [x] Owner, `edit` e `view` mantêm suas regras atuais.
- [x] Testes executam operações simultâneas em duas notas e validam isolamento completo.
