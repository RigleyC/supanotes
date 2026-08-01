# Walkthrough: authentication session lifecycle hardening

## Resultado

O backend agora commit a revogacao da familia antes de retornar erro de reuse,
exige issuer e audience em todos os tokens e aplica rate limit tambem ao login
da Alexa. O rate limiter remove buckets fora da janela.

No Flutter, operacoes de sessao sao serializadas. O token manager protege a
leitura inicial contra leituras atrasadas, e o sync informa explicitamente uma
sessao bloqueada por outra conta. O catalogo local grava o proprietario remoto
da nota compartilhada. O `ApiClient` de producao usa somente o caminho de
refresh do `AuthTokenManager`; os callbacks legados nao sao expostos pelo
construtor de producao do cliente. O `AuthInterceptor` tambem nao expoe mais o
construtor legado: testes que precisam simular armazenamento usam um helper
exclusivo de teste que adapta o contrato atual. Assim, o codigo de producao
tem somente o caminho de refresh baseado em `RefreshSessionHandler`.

O token manager agora serializa tambem a leitura do refresh token. Erros
persistidos de sync passaram a carregar `ownerUserId`, e a telemetria e os
queries de erro respeitam esse escopo. Linhas antigas so sao adotadas quando a
propriedade local da nota confirma a conta.

Na integracao OAuth da Alexa, o refresh agora guarda o hash anterior e marca o
vinculo como revogado quando esse hash e reutilizado. Isso cobre a corrida em
que a resposta da primeira troca se perde: a segunda tentativa nao cria outra
credencial utilizavel.

Tambem existe agora `POST /api/v1/auth/revoke-sessions`, protegido por JWT,
que revoga todas as sessoes do usuario identificado pelo token. O endpoint nao
aceita um user ID no corpo ou na URL.

Falhas ao limpar preferencias ou o banco local durante logout explicito agora
tambem entram no estado de erro da sessao, depois que as credenciais ja foram
removidas.

Reuse de refresh tokens gera um evento estruturado com identificadores de
usuario e familia, sem registrar o token em claro.

O teste de expiração agora abre um `NoteEditorSession` real dentro de um
`NoteSessionCoordinator` registrado no lifecycle registry e verifica que o
dispose termina antes da transição para sessão anônima.

## Evidencia

- `go test ./pkg/auth ./internal/auth ./internal/alexa` passou.
- `flutter test test/core/auth/auth_token_manager_test.dart` passou.
- `flutter test test/features/auth/domain/auth_state_test.dart` passou.
- `flutter test test/core/sync/note_operations_sync_service_characterization_test.dart` passou.
- `flutter analyze` nos modulos alterados passou sem issues.
- O teste PostgreSQL opt-in cobre duas chamadas concorrentes com o mesmo
  refresh token e pula de forma explicita quando
  `SUPANOTES_AUTH_TEST_DATABASE_URL` nao esta configurado.
- A execucao `flutter run -d windows --debug --no-pub` atingiu o timeout de
  124 segundos sem devolver logs de inicializacao ou de stream de notas; o
  comportamento em runtime continua sem evidencia neste ambiente.
- `go test ./...` passou.
- `flutter test` passou com 515 testes e 1 skip existente.
- A migracao Drift para o escopo dos erros de sync foi gerada como schema 25.
- A migracao `000046_alexa_refresh_family` e o teste PostgreSQL opt-in cobrem
  a revogacao apos duas trocas concorrentes.
- Os testes de auth cobrem a revogacao de sessoes e o isolamento do usuario
  obtido do contexto autenticado.
