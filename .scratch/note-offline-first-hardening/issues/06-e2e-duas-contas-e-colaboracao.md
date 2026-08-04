# 06 — E2E de duas contas e colaboração

**What to build:** Validar a colaboração completa entre duas contas autenticadas usando o contrato HTTP real ou um servidor de teste equivalente. O fluxo deve cobrir permissões, edição simultânea, offline e troca de conta.

**Blocked by:** 02 — Escopo local por conta e compartilhamento; 03 — Coordenador único de persistência e sincronização por nota; 05 — Harness E2E do fluxo local-first.

**Status:** ready-for-agent

- [ ] Usuário com permissão view abre o conteúdo, mas não envia mutações.
- [ ] Usuário com permissão edit altera offline e sincroniza depois da reconexão.
- [ ] Dois usuários editando blocos distintos convergem para o documento canônico.
- [ ] Dois usuários editando o mesmo bloco seguem o contrato OT sem apagar silenciosamente uma edição.
- [ ] Revogar a permissão durante a edição impede novas operações remotas e preserva o estado local.
- [ ] A sequência A → B → A não reaproveita conteúdo, outbox ou sessão da conta errada.
- [ ] O teste verifica o estado remoto final, não apenas chamadas de mocks.
