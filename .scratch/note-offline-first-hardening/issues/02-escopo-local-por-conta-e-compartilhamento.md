# 02 — Escopo local por conta e compartilhamento

**What to build:** Todo estado local de nota deve pertencer à conta ativa e ao acesso que essa conta possui. Notas próprias, notas compartilhadas, snapshots, outbox, sessões e projeções não podem vazar entre contas nem permanecer acessíveis depois da revogação.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] A conta B não vê notas, snapshots, operações ou sessões persistidas pela conta A no mesmo banco local.
- [ ] Uma nota compartilhada aparece para o usuário autorizado com a permissão correta.
- [ ] A revogação remove ou bloqueia o acesso local e impede novas operações de serem enviadas.
- [ ] Expiração de sessão seguida de login com outra conta não exibe dados da conta anterior.
- [ ] O fluxo de logout explícito continua limpando os dados conforme a regra do produto.
- [ ] Testes cobrem duas contas no mesmo banco, nota compartilhada e revogação online/offline.
