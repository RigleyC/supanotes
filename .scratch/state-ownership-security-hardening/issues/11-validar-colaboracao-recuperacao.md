# 11 — Validar colaboração e recuperação de ponta a ponta

**What to build:** Demonstrar que sessões locais exclusivas continuam a receber e reconciliar atualizações de outros usuários na mesma nota compartilhada.

**Blocked by:** 07 — Contrair e remover o ciclo de vida legado; 09 — Isolar comandos de compartilhamento por nota; 10 — Vincular metadados de tarefa ao ciclo do modal.

**Status:** done

- [x] Dois usuários com permissão `edit` editam a mesma nota e convergem pelo REST/OT.
- [x] Cada usuário mantém somente uma sessão local para a nota no próprio processo.
- [x] Atualização enviada por um usuário chega ao documento visível do outro.
- [x] Usuário `view` recebe atualizações, mas não consegue emitir mutações.
- [x] Duas edições offline distintas permanecem na outbox e convergem após reconexão.
- [x] Reabrir durante fechamento não duplica callbacks, polling ou projeção.
- [x] Reinício com outbox e sessão persistida reconstrói o documento visível correto.
- [x] Reabertura de ocorrência de tarefa converge sem substituir ocorrência distinta de outro cliente.
- [x] Logout e entrada com outra conta não reutilizam sessão, fila ou identidade anterior.
- [x] O teste usa clientes e bancos locais independentes e o backend real de teste.
