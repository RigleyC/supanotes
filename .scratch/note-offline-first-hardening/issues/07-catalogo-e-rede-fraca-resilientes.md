# 07 — Catálogo e rede fraca resilientes

**What to build:** O catálogo deve continuar seguro e previsível com latência alta, rede intermitente, timeout e muitos documentos. A sincronização deve evitar ciclos longos sem controle, apagar dados por engano ou bloquear o uso de uma nota aberta.

**Blocked by:** 01 — Persistência atômica da nota local; 03 — Coordenador único de persistência e sincronização por nota; 04 — Estado de sincronização visível e recuperável.

**Status:** ready-for-agent

- [ ] Rede offline ou lenta não impede abrir uma nota que já possui estado local.
- [ ] Pull de várias notas usa trabalho controlado, cancelamento e retry/backoff adequados.
- [ ] Falha de um documento não corrompe nem remove as outras notas locais.
- [ ] Nota ativa não é sobrescrita pelo catálogo em segundo plano.
- [ ] Exclusão remota só remove a cópia local depois de uma lista remota completa e confiável.
- [ ] Tombstone local permanece para retry quando a exclusão remota falha.
- [ ] Ack duplicado, resposta lenta e queda depois da aplicação no servidor não duplicam operações.
- [ ] Testes cobrem rede ausente, fraca, intermitente e recuperação.
