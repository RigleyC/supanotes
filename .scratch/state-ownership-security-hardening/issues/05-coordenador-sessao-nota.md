# 05 — Introduzir o coordenador exclusivo de sessão por nota

**What to build:** Criar uma autoridade única que abra, reutilize, feche e substitua a sessão local de cada nota dentro da sessão autenticada.

**Blocked by:** 04 — Dar ao serviço REST/OT o escopo da sessão autenticada.

**Status:** done

- [x] O coordenador pertence à sessão autenticada e usa `noteId` como chave dentro desse escopo.
- [x] Uma nota tem no máximo uma sessão operacional no mesmo container.
- [x] Abrir uma nota pronta reutiliza a sessão existente.
- [x] Abrir uma nota que está fechando aguarda o fechamento antes de criar outra sessão.
- [x] A sessão expõe `opening`, `ready`, `syncing`, `closing`, `closed` e `error`, ou estados equivalentes completos.
- [x] O fechamento é idempotente e chamadas repetidas compartilham o mesmo resultado.
- [x] A sessão deixa de aceitar mutações quando começa a fechar.
- [x] Falha de abertura executa rollback de todos os recursos já criados.
- [x] Resultado assíncrono de uma sessão antiga não substitui o estado da sessão nova.
- [x] Testes cobrem abertura dupla, reabertura durante fechamento, falha parcial e troca de usuário.
