# 02 — Proteger e limitar prévias de links

**What to build:** Permitir prévias somente para endereços HTTP e HTTPS públicos. Impedir acesso à rede interna, limitar o trabalho remoto e manter um cache previsível.

**Blocked by:** None — can start immediately.

**Status:** done

- [x] URLs não absolutas, com esquema não permitido ou credenciais embutidas são rejeitadas.
- [x] Loopback, redes privadas, link-local, multicast, endereços não especificados e faixas reservadas são bloqueados.
- [x] Todos os endereços retornados pela resolução seguem uma política segura e testada.
- [x] A conexão usa somente um destino que passou pela validação.
- [x] Cada redirecionamento repete a validação completa.
- [x] A cadeia de redirecionamentos tem limite.
- [x] Conexão, cabeçalhos e resposta total têm timeout.
- [x] A resposta tem limite estrito de bytes e somente HTML é analisado.
- [x] O cache usa chave normalizada, TTL e capacidade máxima.
- [x] Chamadas simultâneas da mesma URL compartilham uma única busca em andamento.
- [x] Testes usam servidor e resolução controlados, sem acesso à internet real.
