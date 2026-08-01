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
construtor de producao do cliente. O interceptor ainda os aceita para manter
compatibilidade com testes antigos, mas o caminho de producao exige
`RefreshSessionHandler`.

## Evidencia

- `go test ./pkg/auth ./internal/auth ./internal/alexa` passou.
- `flutter test test/core/auth/auth_token_manager_test.dart` passou.
- `flutter test test/features/auth/domain/auth_state_test.dart` passou.
- `flutter test test/core/sync/note_operations_sync_service_characterization_test.dart` passou.
- `flutter analyze` nos modulos alterados passou sem issues.
- O teste PostgreSQL opt-in cobre duas chamadas concorrentes com o mesmo
  refresh token e pula de forma explicita quando
  `SUPANOTES_AUTH_TEST_DATABASE_URL` nao esta configurado.
- `go test ./...` passou.
- `flutter test` passou com 512 testes e 1 skip existente.
