# 04 — Dar ao serviço REST/OT o escopo da sessão autenticada

**What to build:** Fazer todas as sessões de nota de um usuário compartilharem a mesma instância do serviço REST/OT, preservando uma fila independente por nota e encerrando o escopo na troca de usuário.

**Blocked by:** 03 — Caracterizar o ciclo de vida atual da sessão de nota.

**Status:** done

- [x] O serviço REST/OT nasce quando existe uma identidade autenticada válida.
- [x] O serviço permanece a mesma instância durante toda a sessão autenticada.
- [x] Abrir duas notas usa o mesmo serviço e filas diferentes por nota.
- [x] Duas chamadas da mesma nota passam pela mesma fila mesmo quando vêm de consumidores diferentes.
- [x] Dependências que precisam permanecer vivas não são obtidas de um provider descartável sem vínculo de ciclo de vida.
- [x] Logout invalida o serviço e impede novos trabalhos com a identidade anterior.
- [x] Troca de conta cria um novo serviço somente após invalidar o escopo anterior.
- [x] A outbox persistida continua disponível após recriação do serviço.
- [x] Testes validam identidade da instância, serialização por nota e paralelismo entre notas.
