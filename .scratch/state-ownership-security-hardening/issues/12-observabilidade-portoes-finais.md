# 12 — Adicionar observabilidade e executar os portões finais

**What to build:** Tornar falhas operacionais identificáveis e concluir a entrega com verificações completas, separadas e honestamente reportadas.

**Blocked by:** 01 — Proteger upload e ciclo de vida de anexos; 02 — Proteger e limitar prévias de links; 07 — Contrair e remover o ciclo de vida legado; 08 — Serializar e versionar preferências otimistas; 09 — Isolar comandos de compartilhamento por nota; 10 — Vincular metadados de tarefa ao ciclo do modal; 11 — Validar colaboração e recuperação de ponta a ponta.

**Status:** done

- [x] Logs de sessão incluem correlação, nota, transição e classe do erro.
- [x] Logs não incluem tokens, conteúdo completo da nota ou URLs sensíveis completas.
- [x] É possível observar sessões ativas, tamanho da outbox e falhas de sincronização.
- [x] É possível observar recusas de anexos, destinos bloqueados e ocupação do cache de prévias.
- [x] A análise estática Flutter termina sem erros.
- [x] Testes Flutter de sessão, sincronização, preferências, compartilhamento e tarefas passam.
- [x] Testes Go de anexos, prévias, autenticação, compartilhamento e operações de nota passam.
- [x] O teste de integração com dois clientes offline, reinício, rebase e reabertura passa.
- [x] Verificações Flutter e Go são executadas separadamente quando necessário.
- [x] Teste interrompido ou encerrado por timeout não é registrado como aprovado.
- [x] O relatório final lista comandos observados, resultados, duração e lacunas restantes.

## Relatório observado

- `flutter analyze` — passou em 30,4s.
- `go test ./internal/attachments ./internal/linkpreview ./internal/auth ./internal/shares ./internal/noteoperations` — passou em 65,6s.
- `flutter test test/core/debug/note_sync_debug_test.dart test/features/notes/domain/note_session_coordinator_test.dart test/features/notes/domain/sync_characterization_test.dart test/core/sync/note_operations_sync_service_characterization_test.dart test/core/di/note_operations_sync_service_provider_test.dart test/features/notes/presentation/controllers/note_preferences_mutation_controller_test.dart test/features/notes/presentation/controllers/share_note_controller_test.dart test/features/tasks/presentation/controllers/task_metadata_controller_test.dart test/features/tasks/presentation/widgets/task_metadata_sheet_test.dart` — passou em 39,8s. Há warnings Drift esperados nos testes de clientes independentes.
- `go test ./...` em `backend/` — passou em 110,5s.
- `flutter test` — falhou em 183,6s, sem timeout. Falhas restantes observadas: asset ausente `assets/brand/splash.png`, fonte Google/Bricolage não disponível em assets/runtime de teste, e testes do scheduler de notificações com IDs esperados ausentes.
- Comando inválido corrigido: `go test ./internal/attachments ./internal/linkpreview ./internal/auth ./internal/sharing ./internal/noteoperations` falhou porque `internal/sharing` não existe; o pacote correto é `internal/shares`.
- Comando inválido corrigido: o bloco Flutter inicial usou `test/features/notes/domain/note_preferences_test.dart`, que não existe; o teste correto é `test/features/notes/presentation/controllers/note_preferences_mutation_controller_test.dart`.
