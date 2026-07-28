# 12 - Adicionar observabilidade e executar os portoes finais

**What to build:** Tornar falhas operacionais identificaveis e concluir a entrega com verificacoes completas, separadas e honestamente reportadas.

**Blocked by:** 01 - Proteger upload e ciclo de vida de anexos; 02 - Proteger e limitar previas de links; 07 - Contrair e remover o ciclo de vida legado; 08 - Serializar e versionar preferencias otimistas; 09 - Isolar comandos de compartilhamento por nota; 10 - Vincular metadados de tarefa ao ciclo do modal; 11 - Validar colaboracao e recuperacao de ponta a ponta.

**Status:** partial

- [x] Logs de sessao incluem correlacao, nota, transicao e classe do erro.
- [x] Logs nao incluem tokens, conteudo completo da nota ou URLs sensiveis completas.
- [x] E possivel observar sessoes ativas, tamanho da outbox e falhas de sincronizacao.
- [x] E possivel observar recusas de anexos, destinos bloqueados e ocupacao do cache de previas.
- [x] A analise estatica Flutter termina sem erros.
- [x] Testes Flutter focados de sessao, sincronizacao, preferencias, compartilhamento e tarefas passam.
- [x] Testes Go de anexos, previas, autenticacao, compartilhamento e operacoes de nota passam.
- [ ] O teste de integracao de cliente com dois bancos locais, HTTP local, dois clientes offline, reinicio, rebase e reabertura passa.
- [x] Verificacoes Flutter e Go sao executadas separadamente quando necessario.
- [x] Teste interrompido ou encerrado por timeout nao e registrado como aprovado.
- [x] O relatorio final lista comandos observados, resultados, duracao e lacunas restantes.

## Relatorio observado

- `flutter analyze` - passou em 11,1s (0 erros, 0 avisos).
- `flutter test test/features/notes/presentation/controllers/note_editor_provider_test.dart test/features/notes/domain/note_session_coordinator_test.dart test/features/notes/domain/note_sync_session_test.dart` - passou em 4,0s (21 testes; ownership por nota, isolamento somente leitura, fechamento/reabertura em erro e classificacao de erro).
- `flutter test test/features/notes/presentation/controllers/note_editor_provider_test.dart test/features/notes/domain/note_session_coordinator_test.dart test/features/notes/domain/note_sync_session_test.dart test/features/notes/presentation/note_editor_screen_test.dart test/features/tasks/presentation/task_completion_snackbar_test.dart` - passou em 11,0s (33 testes, 1 skip).
- `go test ./... -count=1` em `backend/` - passou em 107,6s (210 testes em 23 pacotes).
- `flutter test` completo - falhou em 163,8s (453 passed, 1 skipped, 13 failed). Falhas observadas incluem asset ausente `assets/brand/splash.png`, fonte `BricolageGrotesque-Regular` nao disponivel para testes e expectativas do agendador de notificacoes de tarefas. Estas falhas nao foram resolvidas neste ticket.
- Nao ha teste observado contra backend Go/PostgreSQL real para o fluxo de dois clientes offline, reinicio, rebase e reabertura. Os testes HTTP locais existentes usam fixture Dart ou mock repository.
