# 06 — Migrar o editor para a fachada da sessão de nota

**What to build:** Fazer a tela do editor consumir uma única fachada pronta, que possui documento, editor, captura REST/OT, polling e projeção de tarefas.

**Blocked by:** 05 — Introduzir o coordenador exclusivo de sessão por nota.

**Status:** done

- [x] A UI não acessa documento, editor ou composer parcialmente inicializados.
- [x] A sessão registra cleanup antes da primeira operação assíncrona que pode falhar.
- [x] Documento, editor, composer, adapter, timer e projeção têm o mesmo proprietário.
- [x] O estado de abertura, sincronização e erro é observável pela tela.
- [x] Erro transitório mantém a outbox e permite nova tentativa.
- [x] Erro de protocolo não é absorvido somente em log.
- [x] Fechar cancela polling, finaliza captura, persiste outbox e libera os recursos na ordem segura.
- [x] Falha de rede durante fechamento não remove operações persistidas.
- [x] Uma nota `view` recebe atualizações remotas, mas não captura nem envia mutações.
- [x] Testes de tela validam loading, pronto, erro recuperável, somente leitura e fechamento.
