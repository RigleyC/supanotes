# Auditoria de autenticação e sessão

Data: 2026-08-01  
Escopo: Flutter client, API Go, refresh/logout, sincronização e integração OAuth da Alexa.  
Método: leitura read-only do código atual, execução dos testes focados e comparação com especificações e documentação primárias.

## Conclusão

O fluxo não é uma gambiarra completa. Há decisões corretas: access token curto, refresh token opaco, hash do refresh token no banco, rotação no refresh, single-flight no cliente e armazenamento em `FlutterSecureStorage`.

Mas há uma falha real de lifecycle que explica o sintoma atual das notas não carregarem. Ao falhar o refresh, o cliente tenta fechar sessões de notas através de um provider que depende do estado de autenticação que está sendo alterado. Isso produz `CircularDependencyError`. O teste existente passa, mas imprime exatamente o erro porque não cobre a expiração com um coordinator autenticado.

Também existem problemas independentes no desenho de sessão e na integração OAuth. A correção deve separar três responsabilidades: transporte de tokens, transição de sessão e encerramento dos recursos de notas/sync.

## Evidência do incidente atual

O fluxo atual é:

1. `AuthInterceptor` recebe 401 e chama `_refreshOnce()` em `lib/core/api/auth_interceptor.dart:88-119`.
2. O backend retorna 401 para o refresh inválido em `backend/internal/auth/handler.go:121-134`.
3. O interceptor chama `onAuthFailure`.
4. `lib/core/di/providers.dart:51-53` dispara `onSessionExpired()` sem aguardar a Future retornada.
5. `AuthController._clearSession()` chama `_closeActiveNoteSessions()` antes de limpar o estado em `lib/features/auth/presentation/controllers/auth_controller.dart:64-91`.
6. `_closeActiveNoteSessions()` lê `noteSessionCoordinatorProvider` em `auth_controller.dart:94-100`.
7. Esse provider observa `currentUserIdProvider` em `lib/core/di/providers.dart:142-158`, que observa `authControllerProvider` em `lib/core/auth/current_user.dart:8-10`.

Durante a transição do próprio `authControllerProvider`, a leitura do coordinator pode recriar ou avaliar um provider que depende dele. O log observado foi `CircularDependencyError`; os testes também imprimem `ProviderException: NoteSessionCoordinator requires an authenticated user`, embora terminem verdes.

Isso também explica por que limpar a fila de sync não resolveu: a investigação local encontrou notas e documentos locais, zero `pending_note_operations` e zero `note_sync_errors`. O bloqueio ocorre no lifecycle de sessão antes de a UI completar a carga remota/local.

## O que está correto

### Cliente

- `AuthInterceptor` possui single-flight para refresh e para a notificação de falha (`auth_interceptor.dart:71-73, 133-157`). Isso evita uma tempestade de refreshes para vários 401 concorrentes.
- O replay usa diretamente o access token recém-recebido (`auth_interceptor.dart:121-126`), e não uma leitura potencialmente obsoleta do storage.
- Uma falha transitória 5xx no refresh não encerra a sessão (`auth_interceptor.dart:107-113`). Essa distinção é correta.
- O access token e o refresh token são armazenados via `FlutterSecureStorage` (`lib/features/auth/data/auth_local_storage.dart:22-44`). O uso de armazenamento seguro do sistema é compatível com a recomendação das plataformas; o Keychain da Apple é destinado a pequenos segredos e credenciais.
- Logout local limpa tokens mesmo quando o endpoint remoto falha (`lib/features/auth/data/auth_repository.dart:99-113`). Isso evita deixar a conta acessível em um dispositivo sem rede.

### Backend

- A senha é armazenada com Argon2id, conforme evidência nos testes de `backend/internal/auth/service_test.go:310-317`.
- Refresh tokens são aleatórios, opacos e apenas o hash é persistido (`backend/internal/auth/service.go:185-199` e `backend/pkg/auth/refresh.go`).
- O access token dura 15 minutos e o refresh token 30 dias (`backend/pkg/auth/jwt.go:11-14`), uma separação razoável para uma aplicação de notas.
- O refresh revoga o token anterior e cria outro (`backend/internal/auth/service.go:134-159`). Isso é a base correta para rotation.

Esses pontos estão alinhados com [RFC 9700, OAuth 2.0 Security Best Current Practice](https://www.rfc-editor.org/rfc/rfc9700.html), que recomenda proteger refresh tokens, limitar sua vida útil e usar rotação ou sender-constrained tokens para detectar replay. Também são compatíveis com o padrão documentado por [Auth0 para rotação e reuse detection](https://auth0.com/docs/secure/tokens/refresh-tokens/configure-refresh-token-rotation) e por [Supabase para rotação com uma janela curta de concorrência](https://supabase.com/docs/guides/auth/sessions).

## Problemas encontrados

### P0 — expiração de sessão acopla auth e recursos de notas

Arquivo: `lib/features/auth/presentation/controllers/auth_controller.dart:64-100`; `lib/core/di/providers.dart:142-158`.

O controller de autenticação não deve descobrir um recurso autenticado lendo um provider que observa o próprio controller durante a transição. O encerramento precisa receber uma referência já existente, ou ser coordenado por um objeto de sessão que seja dono de auth, sync e note sessions sem depender de `currentUserIdProvider` para ser fechado.

Correção recomendada para esta falha:

1. Capturar o coordinator/sessão no momento em que o usuário está autenticado.
2. Fechar a referência capturada sem construir um provider novo durante logout/expiração.
3. Só depois limpar tokens, publicar `unauthenticated` e invalidar providers autenticados.
4. Fazer `onAuthFailure` retornar `await ref.read(...).onSessionExpired()`.

Não é necessário apagar a outbox numa expiração involuntária. Porém, a outbox deve ficar marcada como suspensa enquanto não houver sessão e só deve ser retomada após confirmar que o usuário reautenticado é o mesmo proprietário dos dados.

### P0 — o callback de falha não é aguardado

Arquivo: `lib/core/di/providers.dart:51-53`.

O código atual chama `onSessionExpired()` dentro de uma função `async`, mas não usa `await`. Portanto, `AuthInterceptor` pode concluir `_notifyFailureOnce()` e propagar o 401 antes de a limpeza de sessão terminar. Isso cria uma corrida entre router, catalog sync, editor e auth state.

Esse é um defeito concreto, separado do ciclo de providers.

### P1 — access token em memória pode sobreviver a logout/login

Arquivo: `lib/core/api/auth_interceptor.dart:71-83, 159-171`.

`_latestAccessToken` é atualizado após refresh, mas não existe uma operação explícita para limpá-lo no logout/expiração ou substituí-lo após login. Como `apiClientProvider` é compartilhado, uma sequência logout → login de outra conta pode usar temporariamente o access token anterior, até receber 401 e fazer refresh com o novo refresh token.

O padrão mais seguro é um `TokenStore` único com:

- access token em memória como fonte quente;
- refresh token persistido no armazenamento seguro;
- `setSession`, `replaceTokens` e `clear` atômicos;
- invalidação do access token em toda transição de sessão;
- single-flight para refresh.

### P1 — rotação no backend não detecta reuse da família

Arquivo: `backend/internal/auth/service.go:134-159`; `backend/db/queries/auth.sql:32-52`; `backend/db/migrations/000001_init.up.sql:32-41`.

O backend revoga o row antigo e cria um novo, mas não guarda `family_id`, relação com o token pai, motivo de reuse ou estado da família. Se um refresh antigo for reutilizado, ele simplesmente falha; o token novo e os demais tokens ativos da família não são revogados.

Há também uma janela de corrida: `GetRefreshToken` e `RevokeRefreshToken` são operações separadas. Duas requisições concorrentes podem ler o mesmo token antes da revogação. O update não exige `revoked_at IS NULL` nem verifica quantidade de rows afetados.

O mercado resolve isso com uma destas políticas:

- rotação estrita + revogação da família ao detectar reuse;
- uma janela curta de reuse para perda de resposta e concorrência legítima, seguida de revogação da família fora da janela;
- operação atômica de consumo do token, com resultado explícito quando outra requisição já o consumiu.

[Supabase documenta uma janela padrão de 10 segundos para falhas de serialização e perda de resposta](https://supabase.com/docs/guides/auth/sessions). [Auth0 documenta leeway e revogação da família quando um token anterior é reutilizado](https://auth0.com/docs/secure/tokens/refresh-tokens/configure-refresh-token-rotation). A especificação recomenda rotação ou sender-constrained tokens e retenção da relação entre tokens em [RFC 9700, seção 4.14](https://www.rfc-editor.org/rfc/rfc9700.html#section-4.14).

### P1 — integração OAuth da Alexa aceita qualquer redirect HTTPS

Arquivo: `backend/internal/alexa/oauth.go:47-50, 131-136`; rotas em `backend/cmd/server/main.go:233-237`.

`validRedirect` valida apenas esquema HTTPS e presença de host. Isso permite usar qualquer domínio HTTPS como `redirect_uri`; o authorization code será enviado para esse domínio. O redirect deve ser uma allowlist exata por `client_id`, com comparação de origem, host, caminho e, conforme o cliente, porta.

O token endpoint também faz `SELECT` e depois `UPDATE ... WHERE used_at IS NULL`, mas não verifica se o update alterou exatamente uma linha. Uma dupla troca concorrente pode gerar uma resposta de token mesmo quando a segunda atualização não consumiu o código.

Para native apps, o padrão é Authorization Code com PKCE e user-agent externo, conforme [RFC 8252](https://datatracker.ietf.org/doc/html/rfc8252). Para a integração Alexa, que usa um cliente confidencial, a regra mínima continua sendo redirect URI pré-registrado, consumo atômico do código e validação rigorosa de `state`.

### P1 — endpoints de login e registro não mostram throttling

Arquivo: `backend/cmd/server/main.go:167-170`; handlers em `backend/internal/auth/handler.go:89-134`.

Não há middleware ou serviço de rate limiting evidente para login, registro ou refresh. Isso deixa a superfície exposta a brute force, credential stuffing e abuso de criação de contas. [OWASP recomenda throttling por conta e por origem, além de controles contra automação](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html).

O Argon2id é um bom começo, mas não substitui rate limiting, telemetria de falhas, recuperação de conta e MFA quando o produto exigir.

### P2 — refresh apenas reativo e bootstrap otimista sem validação

O cliente espera um 401 para atualizar o access token. Esse modelo é válido, mas produz uma falha visível em toda primeira requisição após expiração e é mais sensível a corridas em streams. Clientes maduros calculam `exp`, renovam com margem e mantêm o 401 como fallback.

No bootstrap, `AuthController.build()` considera a sessão autenticada apenas porque há access token e usuário em cache (`auth_controller.dart:19-35`). O token não é validado até uma chamada protegida falhar. Isso é aceitável como bootstrap otimista, mas a UI deve ter um estado claro de “sessão sendo validada” e uma transição garantida para login; não deve ficar em loading indefinido.

### P2 — claims JWT mínimos demais para crescer com segurança

Arquivo: `backend/pkg/auth/jwt.go:18-33, 35-50`.

O JWT usa apenas `sub`, `iat` e `exp`; `iss` e `aud` são vazios. Para um único backend isso não é a causa do incidente, mas audience e issuer reduzem o risco de aceitar um token emitido para outro serviço ou ambiente. Deve entrar no hardening se o ecossistema crescer.

## Decisão recomendada

Manter o modelo atual de access + refresh tokens, mas corrigir o lifecycle antes de investigar novamente a UI de notas. Não recomendo trocar de pacote ou reescrever toda a autenticação para resolver este incidente.

### Ordem de implementação

1. Corrigir o await do callback e remover a leitura auth-dependente durante o fechamento de sessões.
2. Criar testes de expiração com usuário autenticado, coordinator já criado, editor aberto, stream ativa e outbox contendo operação.
3. Adicionar clear/set explícito do access token em memória e teste logout → login com outra conta.
4. Tornar consumo de refresh atômico e adicionar família/reuse detection com janela curta para resposta perdida.
5. Adicionar rate limiting, métricas de login/refresh/reuse e mensagens distintas para offline versus reautenticação necessária.
6. Corrigir allowlist/consumo atômico do OAuth Alexa.
7. Depois, opcionalmente, adicionar refresh proativo, claims `iss`/`aud` e um fluxo Authorization Code + PKCE se a autenticação for externalizada para um Identity Provider.

## Verificação executada

- `flutter test test/core/api/auth_interceptor_test.dart test/features/auth/domain/auth_state_test.dart`: 22 testes passaram, mas os testes imprimiram `ProviderException` durante o fechamento de sessões. Isso confirma uma lacuna: o teste está verde porque o erro é capturado pelo controller.
- `go test ./internal/auth ./pkg/auth`: passou.
- O backend possui teste de rotação simples, mas não teste de reuse de família nem de duas chamadas concorrentes com o mesmo refresh token.

## Fontes primárias consultadas

- [RFC 9700 — OAuth 2.0 Security Best Current Practice](https://www.rfc-editor.org/rfc/rfc9700.html)
- [RFC 8252 — OAuth 2.0 for Native Apps](https://datatracker.ietf.org/doc/html/rfc8252)
- [RFC 7009 — OAuth 2.0 Token Revocation](https://datatracker.ietf.org/doc/rfc7009/)
- [Auth0 — Configure Refresh Token Rotation](https://auth0.com/docs/secure/tokens/refresh-tokens/configure-refresh-token-rotation)
- [Supabase — User Sessions](https://supabase.com/docs/guides/auth/sessions)
- [Apple — Using the Keychain to Manage User Secrets](https://developer.apple.com/documentation/Security/using-the-keychain-to-manage-user-secrets)
- [OWASP — Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)
