# Authentication Session Lifecycle Hardening

## Problem Statement

Quando o access token expira e o refresh token não pode mais ser usado, o SupaNotes encerra a sessão de forma incompleta. O fluxo de expiração tenta fechar recursos de notas por meio de uma dependência que observa o próprio estado de autenticação em transição. Isso gera erro de dependência circular, interrompe a inicialização/sincronização das notas e pode deixar a UI em estado de loading.

Os testes atuais cobrem o refresh básico e passam, mas não cobrem a expiração com editor aberto, coordinator já criado, stream ativa, operação pendente ou troca de conta. O controller também não aguarda corretamente a limpeza da sessão. Além disso, o backend possui rotação básica de refresh tokens sem detecção de reuse da família, e a integração OAuth da Alexa precisa de controles mais rigorosos.

O problema não é a ausência de dados locais: uma investigação do dispositivo encontrou notas e documentos locais, nenhuma operação pendente e nenhum erro persistido de sync. O problema é a coordenação entre autenticação, recursos de notas e sincronização.

## Solution

Criar uma fronteira única e explícita para o lifecycle de sessão. Essa fronteira deve:

- manter o access token atual em memória e o refresh token em armazenamento seguro;
- serializar login, refresh, logout e expiração;
- aguardar a conclusão do refresh ou invalidá-lo de forma segura durante logout;
- fechar recursos autenticados já existentes sem resolver providers dependentes do estado que está mudando;
- publicar a transição para não autenticado apenas depois de fechar ou suspender os recursos;
- preservar dados locais e outbox durante expiração involuntária, mas impedir que operações sejam enviadas para outra conta;
- retomar a outbox somente depois de confirmar a identidade da sessão reautenticada.

No backend, fortalecer refresh token rotation com consumo atômico, relação entre tokens da mesma família, detecção de reuse e revogação da família quando necessário. Adicionar controles de abuso para endpoints de autenticação.

Corrigir a integração OAuth da Alexa com redirect URIs pré-registrados, consumo atômico do authorization code e validação consistente do fluxo OAuth.

## User Stories

1. As a SupaNotes user, I want my notes to remain visible when my access token expires, so that a session problem does not look like lost data.
2. As a SupaNotes user, I want the app to distinguish an offline server problem from an expired session, so that I know whether to wait or sign in again.
3. As a SupaNotes user, I want an expired session to close the editor cleanly, so that the app does not remain stuck in loading.
4. As a SupaNotes user, I want an in-progress note edit to be preserved when reauthentication is required, so that I do not lose local work.
5. As a SupaNotes user, I want pending operations to remain associated with my account, so that another account cannot send them after a login switch.
6. As a SupaNotes user, I want the outbox to resume automatically after I reauthenticate as the same account, so that sync continues without manual recovery.
7. As a SupaNotes user, I want the app to require an explicit confirmation before discarding local data during logout, so that a temporary token failure does not delete my notes.
8. As a SupaNotes user, I want explicit logout to remove local credentials even when the server is unreachable, so that the device is not left authenticated.
9. As a SupaNotes user, I want logout followed by login as another account to use only the new account token, so that account data is never mixed.
10. As a SupaNotes user, I want concurrent API requests to share one refresh attempt, so that token rotation does not create duplicate refresh requests.
11. As a SupaNotes user, I want a failed refresh to trigger one predictable session transition, so that the router, notes catalog and sync service do not race.
12. As a SupaNotes user, I want a lost refresh response to be recoverable within a short concurrency window, so that a network interruption does not force an unnecessary login.
13. As a SupaNotes user, I want a reused or stolen refresh token to invalidate the affected session family, so that a compromised credential cannot continue minting tokens.
14. As an account owner, I want logout to revoke the current refresh credential, so that the server stops accepting that session.
15. As an account owner, I want security-sensitive events to be able to revoke all sessions, so that a password or account compromise can be contained.
16. As a backend operator, I want refresh failures and token reuse to be observable without logging secrets, so that incidents can be investigated safely.
17. As a backend operator, I want login and registration endpoints to be rate-limited, so that brute force and credential stuffing are constrained.
18. As a backend operator, I want access tokens to identify their intended issuer and audience, so that tokens are not accepted by an unintended service.
19. As an Alexa user, I want authorization codes to return only to the registered redirect URI, so that codes cannot be sent to an arbitrary HTTPS host.
20. As an Alexa user, I want an authorization code to be usable only once, so that replay cannot create another session.
21. As an Alexa integration, I want refresh token rotation to be atomic, so that concurrent exchanges cannot issue inconsistent credentials.
22. As a developer, I want session resource cleanup to use an explicit lifecycle contract, so that auth transitions do not depend on providers that are being invalidated.
23. As a developer, I want the token manager to expose explicit install, replace and clear operations, so that in-memory and persisted credentials cannot drift.
24. As a developer, I want auth tests to exercise real authenticated resource ownership, so that caught exceptions do not make broken lifecycle tests pass.
25. As a developer, I want sync tests to cover account switching and session expiry, so that local data and remote operations remain correctly scoped.

## Implementation Decisions

- Introduce one session lifecycle boundary at the application composition layer. It is the owner of session transitions and registered authenticated resources.
- Authenticated resources, including note editor sessions, catalog sync and operations sync, register a close/suspend callback with that boundary when they are created.
- Session cleanup uses references to already-created resources. It must not construct an auth-dependent provider while the auth state is transitioning.
- Session transitions are serialized. A refresh started before logout cannot write tokens after logout completes.
- The token boundary exposes explicit operations equivalent to `installSession`, `replaceTokens` and `clearSession`.
- The access token is kept in memory as the hot value. The refresh token remains in secure platform storage. Logout and expiry clear both values from the active token boundary.
- The auth failure callback is awaited end to end. The original unauthorized request remains an unauthorized result, but the session transition completes deterministically.
- Involuntary expiry preserves local note data and pending operations. The app marks the outbox as suspended until authentication is restored.
- Every pending operation must be scoped to its account or session owner. A different authenticated user must never be allowed to flush the previous account's operations.
- Explicit logout clears the local database according to the existing product decision. Involuntary expiry does not perform that destructive local-data operation.
- Backend refresh token records gain enough family/parent and consumption state to detect reuse and revoke the affected family.
- Refresh consumption is atomic and checks the affected row count or equivalent transaction result. A concurrent request receives a defined retry or reauthentication result.
- A short, documented reuse/leeway window may be used to handle lost responses and legitimate serialization races. Reuse outside that policy revokes the active family.
- Refresh token values are never logged. Metrics and audit events contain token family identifiers or one-way event identifiers only.
- Login, registration and refresh endpoints receive endpoint-specific rate limits, with both source-based and account/identifier-based controls.
- JWTs include issuer and audience appropriate to the service. Verification checks signature, algorithm, issuer, audience and time claims.
- Alexa redirect URIs are exact allowlist entries associated with the client. Generic “any HTTPS host” validation is not allowed.
- Alexa authorization-code consumption is atomic and requires exactly one successful update. The stored redirect URI is compared with the token request.
- The existing REST/OT note document remains the canonical source of note content and task metadata. This work does not introduce YDoc/Yjs or a second note mutation path.
- If a future external identity provider is adopted for native apps, use Authorization Code with PKCE and an external user agent. This spec does not require replacing the current first-party email/password UI.

## Testing Decisions

- Tests verify externally observable session behavior, not Riverpod implementation details.
- Add client lifecycle tests for:
  - session expiry with an authenticated note coordinator already created;
  - session expiry with an editor session and active sync;
  - one refresh failure producing one awaited session transition;
  - logout while refresh is in flight;
  - logout followed by login as another account;
  - preserved local outbox after involuntary expiry;
  - blocked outbox for a different account;
  - resumed outbox after same-account reauthentication.
- Extend interceptor tests to verify that clear/install operations invalidate stale in-memory access tokens and that a refresh result cannot be written after a completed logout.
- Extend backend auth service tests for:
  - atomic refresh consumption;
  - concurrent refresh requests using one token;
  - reuse of an old family token;
  - family revocation after reuse;
  - expiry and logout behavior;
  - issuer and audience validation.
- Add handler tests for login/refresh rate-limit responses without depending on timing-sensitive sleeps.
- Add Alexa OAuth tests for exact redirect allowlists, state preservation/validation, single-use authorization codes and concurrent token exchange.
- Keep existing focused tests as regression coverage. A test must fail if a provider exception is caught during the intended lifecycle path; logging an error and returning a green test is not sufficient.
- Verification gates are separate: Flutter analysis/tests, backend Go tests and an end-to-end debug run with captured auth and note-sync logs.

## Out of Scope

- Replacing Riverpod with another state-management framework.
- Replacing the first-party authentication system with Auth0, Supabase Auth, Firebase Auth or another provider.
- Rewriting the note editor or changing the REST/OT document contract.
- Introducing YDoc/Yjs or another synchronization protocol.
- Changing note permissions or sharing semantics unrelated to session ownership.
- Adding broad visual redesigns to the login, notes or editor screens.
- Deleting local data automatically during involuntary session expiry.
- Publishing exploit details or the complete security findings in a public issue without explicit maintainer approval.

## Further Notes

- The current access token and refresh token design is a valid foundation. The main defect is lifecycle ownership and ordering, not the use of Dio or Flutter Secure Storage.
- The current focused tests passing does not prove the lifecycle is correct because they do not create the authenticated note resource graph used in production.
- The local sync queue was empty during the incident investigation. Future diagnostics must still inspect both persisted outbox state and cross-device/session changes before classifying a note as missing.
- The implementation should preserve unrelated worktree changes and update the implementation plan and walkthrough after the fix is delivered.
- This spec is intentionally stored locally first because the repository is public and contains a project rule requiring approval before publishing open vulnerability details to a public tracker.
