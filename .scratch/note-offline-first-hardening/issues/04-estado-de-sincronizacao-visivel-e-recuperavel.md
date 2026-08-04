# 04 — Estado de sincronização visível e recuperável

**What to build:** O usuário deve continuar vendo o conteúdo local, mas também deve saber quando existe uma alteração pendente, erro temporário, bloqueio ou revogação de permissão. Estados de sincronização devem ter uma recuperação clara.

**Blocked by:** 03 — Coordenador único de persistência e sincronização por nota.

**Status:** ready-for-agent

- [ ] Conteúdo local continua visível durante offline, timeout e erro de servidor.
- [ ] A interface diferencia pronto, sincronizando, pendente, erro temporário, bloqueado e permissão revogada.
- [ ] Erro temporário agenda retry seguro ou oferece retry manual sem duplicar operações.
- [ ] Erro 403 desativa a captura local e explica ao usuário o que aconteceu.
- [ ] A outbox pendente permanece preservada até confirmação ou ação explícita do usuário.
- [ ] Testes de tela verificam os estados e as ações de recuperação.
