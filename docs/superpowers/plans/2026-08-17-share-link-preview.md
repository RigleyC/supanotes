# Share Link Preview Implementation Plan

> For Claude: REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Permitir compartilhar uma URL pelo share sheet nativo do iOS/Android, escolher uma nota do SupaNotes sem abrir o app principal, persistir a intenção com segurança, enviar ao backend de forma idempotente e adicionar um card rico no final da versão mais recente da nota.

**Architecture:** A UI de share é nativa em cada plataforma e lê um índice leve de notas em JSON. O share é persistido primeiro em `share_inbox.json` e enviado ao backend. O backend valida permissão/idempotência, reutiliza `linkpreview.Service` para metadata e entra pelo pipeline canônico de `noteoperations` com um `create_block` do tipo `rich_link`. O Flutter reutiliza o `RichLinkNode` que já existe no contrato do documento e apenas adiciona um componente visual customizado. O sync atual entrega a nova revisão ao app.

**Tech Stack:** Flutter/Dart + Super Editor, Riverpod, Drift, Swift/SwiftUI + App Groups/Keychain/URLSession, Kotlin Android + WorkManager, Go + pgx/sqlc, PostgreSQL.

---

## Implementation clarification

A spec chama o bloco de `LinkPreviewNode`. O código atual já possui exatamente o contrato necessário como `RichLinkNode` / bloco `rich_link` em `NoteDocumentCodec`, incluindo `url`, `title`, `description`, `imageUrl` e `domain`. Não criar um segundo tipo de node. Implementar o visual aprovado em cima de `RichLinkNode` e manter `rich_link` como wire type canônico.

## Task 1: Lock the rich-link document contract with tests

**Files:**
- Modify: `test/features/notes/editor/document/note_document_codec_test.dart` (ou o arquivo de teste equivalente já existente para `NoteDocumentCodec`)
- Modify only if tests expose a gap: `lib/features/notes/editor/document/note_document_codec.dart`

**Step 1: Write failing contract tests**

Adicionar testes que comprovem que um bloco canônico:

```json
{
  "id": "link-1",
  "type": "rich_link",
  "delta": [],
  "metadata": {
    "url": "https://example.com/post",
    "title": "Título",
    "description": "Descrição",
    "imageUrl": "https://example.com/image.jpg",
    "domain": "example.com"
  }
}
```

é decodificado para `RichLinkNode` e volta ao mesmo contrato via `encodeNode`/snapshot.

Adicionar também um caso fallback só com `url` + `domain`.

**Step 2: Run the focused test**

Run:

```bash
flutter test test/features/notes/editor/document/note_document_codec_test.dart
```

Expected: os novos testes passam com o contrato existente ou falham apenas em pequenas lacunas de round-trip.

**Step 3: Make the minimal codec fix if necessary**

Não adicionar `LinkPreviewNode`, nova schema version nem nova tabela local. Se algum metadata necessário for perdido no round-trip, preservar somente os campos aprovados do `rich_link`.

**Step 4: Re-run tests**

```bash
flutter test test/features/notes/editor/document/note_document_codec_test.dart
```

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/features/notes/editor/document/note_document_codec.dart test/features/notes/editor/document/note_document_codec_test.dart
git commit -m "test(editor): lock rich link document contract"
```

## Task 2: Build the compact RichLink component in Super Editor

**Files:**
- Create: `lib/features/notes/editor/presentation/widgets/custom_rich_link_component.dart`
- Modify: `lib/features/notes/editor/presentation/widgets/note_editor.dart`
- Create: `test/features/notes/editor/presentation/widgets/custom_rich_link_component_test.dart`

**Step 1: Write widget tests first**

Cobrir:
- imagem à esquerda quando `imageUrl` existe;
- título à direita, no máximo 2 linhas;
- descrição abaixo, no máximo 2 linhas;
- domínio abaixo da descrição;
- sem imagem, texto ocupa a largura;
- fallback com domínio + URL;
- tap no card abre/delega a URL;
- o componente representa o node como bloco atômico, sem editor de texto interno.

**Step 2: Run failing widget tests**

```bash
flutter test test/features/notes/editor/presentation/widgets/custom_rich_link_component_test.dart
```

Expected: FAIL porque o builder/componente ainda não existe.

**Step 3: Implement `CustomRichLinkComponentBuilder`**

Reconhecer apenas `RichLinkNode` e produzir um componente compacto. Registrar o builder antes de `...defaultComponentBuilders` em `_initStableBuilders()`:

```dart
_componentBuilders = [
  const CustomDividerComponentBuilder(),
  _taskComponentBuilder!,
  const CustomListItemComponentBuilder(),
  CustomRichLinkComponentBuilder(onOpenUrl: _openExternalUrl),
  AttachmentComponentBuilder(...),
  ...defaultComponentBuilders,
];
```

Usar os padrões de seleção/layout já adotados pelos componentes customizados do projeto; não duplicar lógica de editor que o Super Editor já oferece.

**Step 4: Re-run tests**

```bash
flutter test test/features/notes/editor/presentation/widgets/custom_rich_link_component_test.dart
```

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/features/notes/editor/presentation/widgets/custom_rich_link_component.dart lib/features/notes/editor/presentation/widgets/note_editor.dart test/features/notes/editor/presentation/widgets/custom_rich_link_component_test.dart
git commit -m "feat(editor): render compact rich link cards"
```

## Task 3: Add backend idempotency storage for external shares

**Files:**
- Create: `backend/db/migrations/000052_shared_link_ingestions.up.sql`
- Create: `backend/db/migrations/000052_shared_link_ingestions.down.sql`
- Create: `backend/db/queries/shared_link_ingestions.sql`
- Regenerate: `backend/internal/db/sqlcgen/*` as produced by sqlc
- Create: backend DB/query tests following the existing migration/query test pattern

**Step 1: Write the DB test first**

A tabela deve aceitar um `share_id` por usuário e impedir retry duplicado:

```sql
CREATE TABLE shared_link_ingestions (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    share_id UUID NOT NULL,
    note_id UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    operation_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, share_id)
);
```

A query principal deve permitir reservar idempotentemente `(user_id, share_id)` e recuperar o `operation_id` existente em retry.

**Step 2: Run DB/sqlc tests**

Use os comandos já padronizados no `backend/Makefile`; no mínimo:

```bash
cd backend
go test ./internal/db/... ./...
```

Expected: novo teste falha antes da migration/query existir.

**Step 3: Add migration + sqlc query and regenerate**

Gerar o código com o comando do projeto (`make sqlc` ou equivalente definido no Makefile). Não editar arquivos `sqlcgen` manualmente.

**Step 4: Re-run**

```bash
cd backend
go test ./...
```

Expected: PASS.

**Step 5: Commit**

```bash
git add backend/db/migrations backend/db/queries backend/internal/db/sqlcgen
git commit -m "feat(backend): persist shared link idempotency"
```

## Task 4: Add a server-side semantic append through noteoperations

**Files:**
- Modify: `backend/internal/noteoperations/service.go`
- Modify: `backend/internal/noteoperations/service_test.go`
- Possibly add a small exported method in the same package; do not create a parallel document persistence path

**Step 1: Write service tests first**

Adicionar testes para uma API interna como:

```go
func (s *Service) AppendRichLink(
    ctx context.Context,
    noteID pgtype.UUID,
    userID pgtype.UUID,
    operationID string,
    metadata map[string]any,
) (int64, error)
```

O teste deve provar que:
- `owner` e `edit` podem adicionar;
- `view` é rejeitado;
- o bloco é anexado depois do último bloco da revisão atual;
- uma operação concorrente já aceita permanece no documento;
- a mutação cria uma operação `create_block`, incrementa revisão e atualiza snapshot/content/excerpt na mesma transação;
- retry do mesmo `operationID` não cria segundo bloco.

**Step 2: Run focused Go tests**

```bash
cd backend
go test ./internal/noteoperations -run 'Test.*AppendRichLink'
```

Expected: FAIL.

**Step 3: Implement using the existing canonical pipeline**

Dentro da transação:
1. `EnsureNote` / `LockNote` / `CheckNotePermission`;
2. carregar `Document` atual;
3. montar `create_block` com `type: "rich_link"`, `delta: []`, metadata e `afterBlockId` igual ao ID do último bloco;
4. validar/aplicar com os mesmos contratos de `noteoperations`;
5. persistir `note_operations`, revisão e `notes.document` juntos;
6. deduplicar por `operationID` como o sync já faz.

Não fazer `UPDATE notes.document` fora de `noteoperations`.

**Step 4: Re-run full noteoperations suite**

```bash
cd backend
go test ./internal/noteoperations
```

Expected: PASS.

**Step 5: Commit**

```bash
git add backend/internal/noteoperations
git commit -m "feat(noteoperations): append server rich link blocks"
```

## Task 5: Implement the authenticated shared-link endpoint

**Files:**
- Create: `backend/internal/shareintake/handler.go`
- Create: `backend/internal/shareintake/service.go`
- Create: `backend/internal/shareintake/service_test.go`
- Create: `backend/internal/shareintake/handler_test.go`
- Modify: `backend/cmd/server/main.go`
- Reuse/modify only if needed: `backend/internal/linkpreview/service.go`, `backend/internal/linkpreview/service_test.go`

**Step 1: Write service and HTTP tests**

Contrato:

```http
POST /api/v1/notes/:noteId/shared-links
Authorization: Bearer <token>
Content-Type: application/json

{
  "shareId": "uuid",
  "url": "https://example.com/post",
  "createdAt": "2026-08-17T18:10:00Z"
}
```

Cobrir:
- 401 sem auth;
- 400 URL não HTTP(S);
- 403 sem permissão edit;
- 404 nota ausente;
- 200/201 sucesso;
- retry do mesmo `shareId` retorna sucesso sem novo node;
- mesma URL com outro `shareId` adiciona de novo;
- metadata falha => ainda cria `rich_link` fallback com `url` + `domain`;
- metadata OK => grava `title`, `description`, `imageUrl`, `domain`.

**Step 2: Run tests and confirm failure**

```bash
cd backend
go test ./internal/shareintake ./internal/linkpreview ./internal/noteoperations
```

**Step 3: Implement `shareintake.Service`**

Ordem:
1. validar URL;
2. reservar/consultar `shareId` idempotente;
3. chamar o `linkpreview.Service` existente — ele já possui timeout, limite de body, redirects limitados, cache/singleflight e proteção de destinos inseguros;
4. em erro de metadata, derivar `domain` da URL sem transformar isso em falha do share;
5. chamar `noteoperations.AppendRichLink` com um `operationID` estável associado ao `shareId`;
6. finalizar a reserva idempotente.

Não adicionar favicon/site-name nesta V1: o layout aprovado precisa de domínio, que o serviço já fornece.

**Step 4: Register route**

Registrar sob o grupo autenticado já usado pelo backend em `backend/cmd/server/main.go`.

**Step 5: Run backend suite**

```bash
cd backend
go test ./...
```

Expected: PASS.

**Step 6: Commit**

```bash
git add backend/internal/shareintake backend/internal/linkpreview backend/cmd/server/main.go
git commit -m "feat(api): accept shared links for notes"
```

## Task 6: Add Flutter-to-native share bridge and note index

**Files:**
- Create: `lib/features/notes/share/application/native_share_bridge.dart`
- Create: `lib/features/notes/share/domain/share_note_index.dart`
- Modify the existing notes-list/session orchestration that owns the current ordered note projection
- Modify: `lib/features/auth/data/auth_local_storage.dart` or the smallest session boundary needed to mirror native share credentials
- Create: `test/features/notes/share/application/native_share_bridge_test.dart`

**Step 1: Write Dart tests for pure contracts**

Definir envelope versionado, account-scoped:

```json
{
  "schemaVersion": 1,
  "ownerUserId": "user-id",
  "notes": [
    {
      "noteId": "note-id",
      "title": "Ideias",
      "preview": "Texto inicial...",
      "updatedAt": "...",
      "canEdit": true
    }
  ]
}
```

Cobrir ordenação `updatedAt DESC`, filtro de notas não editáveis, serialização e limpeza em logout.

**Step 2: Run failing test**

```bash
flutter test test/features/notes/share/application/native_share_bridge_test.dart
```

**Step 3: Implement a narrow platform boundary**

Criar uma interface Dart que só faça:
- `publishNotesIndex(...)`;
- `publishSessionCredentials(...)`;
- `clearShareSession()`;
- `retryPendingShares()` no launch/resume quando aplicável.

Usar `MethodChannel` (ou o mecanismo nativo já adotado pelo projeto, se existir) e manter JSON/credenciais fora do Drift.

Atualizar o índice quando a projeção da lista atual mudar, reutilizando a mesma fonte que já fornece título/preview/`updatedAt` — não criar uma segunda derivação de notas.

**Step 4: Wire auth lifecycle**

Ao login/refresh, espelhar somente os dados necessários ao código nativo seguro; ao logout, limpar índice e credenciais nativas antes de permitir outra conta.

**Step 5: Re-run tests**

```bash
flutter test test/features/notes/share/application/native_share_bridge_test.dart
```

Expected: PASS.

**Step 6: Commit**

```bash
git add lib/features/notes/share lib/features/auth test/features/notes/share
git commit -m "feat(share): publish native note index and session"
```

## Task 7: Implement iOS Share Extension + App Group durability

**Files:**
- Modify: `ios/Runner.xcodeproj/project.pbxproj`
- Modify/Create: `ios/Runner/Runner.entitlements`
- Create: `ios/ShareExtension/Info.plist`
- Create: `ios/ShareExtension/ShareViewController.swift`
- Create: `ios/ShareExtension/ShareView.swift`
- Create: `ios/ShareExtension/SharedShareStore.swift`
- Create: `ios/ShareExtension/ShareAPIClient.swift`
- Create shared native bridge files under `ios/Runner/` as needed
- Add XCTest coverage for pure JSON/store logic

**Step 1: Add tests for the shared store first**

Cobrir:
- leitura do `notes_index.json`;
- escrita atômica `tmp + replace` do `share_inbox.json`;
- mesmo `ownerUserId` obrigatório;
- item só é removido da inbox após confirmação HTTP;
- erro de escrita não retorna sucesso.

**Step 2: Configure App Group and shared Keychain access group**

Adicionar a mesma entitlement ao Runner e à Share Extension. O App Group contém apenas `notes_index.json` e `share_inbox.json`. Credenciais ficam no Keychain access group compartilhado — nunca em JSON/UserDefaults plaintext.

**Step 3: Build SwiftUI picker**

UI:
- search field;
- lista `updatedAt DESC`;
- título + preview;
- somente `canEdit`;
- tap persiste inbox, mostra `Salvo em <nota>` e fecha.

**Step 4: Background delivery**

Usar `URLSessionConfiguration.background` com `sharedContainerIdentifier` do App Group. O request usa o mesmo `shareId` persistido. Em 401, não apagar inbox; o app principal poderá refrescar credenciais e chamar retry no próximo launch/resume.

**Step 5: Run iOS tests/build**

```bash
flutter build ios --debug --no-codesign
```

Expected: Runner + extension compilam sem code signing local.

**Step 6: Commit**

```bash
git add ios lib/features/notes/share
git commit -m "feat(ios): add SupaNotes share extension"
```

## Task 8: Implement Android native ShareActivity + WorkManager retry

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/build.gradle.kts`
- Create: `android/app/src/main/kotlin/com/example/supanotes/share/ShareActivity.kt`
- Create: `android/app/src/main/kotlin/com/example/supanotes/share/SharedShareStore.kt`
- Create: `android/app/src/main/kotlin/com/example/supanotes/share/ShareUploadWorker.kt`
- Create: native bridge/credential helper under the same package
- Add Android unit tests under `android/app/src/test/...`

**Step 1: Add native unit tests first**

Cobrir JSON parse/write, account scoping, retry idempotente e terminal-vs-retryable HTTP errors.

**Step 2: Add dependencies minimally**

O módulo hoje não usa Compose/AppCompat. Não introduzir Compose só para esta tela. Usar uma Activity nativa leve com Views/RecyclerView ou adicionar apenas as AndroidX dependências mínimas necessárias. Adicionar WorkManager para entrega durável.

**Step 3: Register share intent**

Em `AndroidManifest.xml`, registrar Activity exportada para:

```xml
<intent-filter>
    <action android:name="android.intent.action.SEND" />
    <category android:name="android.intent.category.DEFAULT" />
    <data android:mimeType="text/plain" />
</intent-filter>
```

Extrair a primeira URL HTTP(S) válida de `Intent.EXTRA_TEXT`.

**Step 4: Implement same picker semantics as iOS**

Ler o mesmo contrato de índice gerado pelo Flutter; busca no topo; título + preview; `updatedAt DESC`; somente editáveis; tap grava inbox antes de confirmar.

**Step 5: Schedule upload**

`ShareUploadWorker` lê pendências e chama o mesmo endpoint. Em sucesso idempotente remove o item; em timeout/5xx/sem rede usa `Result.retry()`; em 403/404 marca/remover como terminal para evitar loop infinito; em 401 preserva item até credenciais serem renovadas.

**Step 6: Run Android tests/build**

```bash
cd android
./gradlew testDebugUnitTest
cd ..
flutter build apk --debug
```

Expected: PASS/build successful.

**Step 7: Commit**

```bash
git add android lib/features/notes/share
git commit -m "feat(android): add native link share target"
```

## Task 9: Integrate retry/session lifecycle and existing sync behavior

**Files:**
- Modify: app startup/resume/session orchestration in `lib/main.dart` and/or existing auth bootstrap controller
- Modify: existing notes sync orchestration only where needed to trigger normal refresh after app becomes active
- Add focused tests next to those controllers

**Step 1: Write lifecycle tests**

Provar:
- launch com pendência pede retry nativo sem duplicar `shareId`;
- resume pode pedir retry;
- logout limpa índice/credenciais e nunca entrega share da conta A com sessão B;
- sync normal continua sendo o único caminho que materializa a revisão remota no Flutter.

**Step 2: Implement minimal hooks**

Não criar polling de previews. No launch/resume apenas:
1. republicar índice/sessão quando necessário;
2. pedir ao nativo para retomar pendências;
3. deixar o sync/stream existente atualizar `localNoteDocuments` e o editor.

**Step 3: Run focused + full Flutter tests**

```bash
flutter test test/features/notes/share
flutter test
```

Expected: PASS.

**Step 4: Commit**

```bash
git add lib test
git commit -m "feat(share): integrate pending share lifecycle"
```

## Task 10: End-to-end verification and hardening

**Files:**
- Add/modify backend integration tests as needed
- Add platform test fixtures as needed
- Update feature docs only if implementation differs materially from the approved design

**Step 1: Backend verification**

```bash
cd backend
go test ./...
```

Expected: PASS.

**Step 2: Flutter verification**

```bash
cd ..
flutter analyze
flutter test
```

Expected: no new analyzer errors; PASS.

**Step 3: Native verification**

```bash
flutter build apk --debug
flutter build ios --debug --no-codesign
```

Expected: both build.

**Step 4: Manual scenarios**

Validate on real/simulator devices:
1. share online -> choose note -> confirmation -> return to source app;
2. card later appears at note end with image-left/title-description-domain-right;
3. app closed during share;
4. app open on same note during remote arrival;
5. airplane mode during share then reconnect;
6. same `shareId` retried -> one card;
7. same URL shared twice deliberately -> two cards;
8. note becomes read-only/deleted before delivery -> no infinite retry;
9. metadata unavailable -> fallback domain + URL;
10. logout/account switch with pending inbox -> no cross-account delivery.

**Step 5: Final commit**

```bash
git add -A
git commit -m "test(share): verify native link sharing flow"
```

## Definition of done

- SupaNotes aparece no share sheet de iOS e Android para URLs/texto com URL.
- Picker nativo abre sem inicializar a tela Flutter principal.
- Lista segue a ordenação atual por modificação, com busca, título e preview, e só notas editáveis.
- Confirmação só ocorre depois de persistência local durável.
- O backend é idempotente por `userId + shareId` e não por URL.
- O backend usa `linkpreview.Service` existente e o pipeline transacional de `noteoperations`.
- O documento usa o `rich_link`/`RichLinkNode` existente; nenhum tipo redundante é criado.
- O card visual segue o layout aprovado.
- Retry offline funciona sem depender de abrir imediatamente o Flutter.
- O sync existente materializa a revisão no app.
- Testes Go, Flutter e nativos passam e builds debug de Android/iOS completam.