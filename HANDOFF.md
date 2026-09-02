# SupaNotes editor and sync hardening handoff

## Goal

Corrigir os problemas confirmados na auditoria do editor e do sync, verificar
todo o projeto e deixar a branch sem achados acionáveis na revisão
thermo-nuclear.

## Current Progress

- Branch de trabalho: `codex/fix-all-editor-sync`.
- Correções do editor, outbox/inbox, projeção e documentação estão commitadas
  no `HEAD` (`34f1478f`, após `f116c6cf` e `944de593`).
- O plano detalhado e seu checklist estão em
  `docs/superpowers/plans/2026-09-02-editor-sync-hardening.md`.
- A spec antiga foi atualizada para refletir o change-feed/inbox já entregue.

## What Worked

- Hidden tasks deixam de ser barreiras invisíveis: backspace/delete move o
  caret entre blocos visíveis, mas mutações diretas e deleções em range que
  atingiriam uma task oculta continuam protegidas.
- Paste captura a seleção antes dos awaits, restaura o destino para todos os
  formatos e reporta falhas assíncronas; bitmap paste também usa o pipeline do
  editor.
- Toolbar, lifecycle de task e escala dos marcadores têm regressões cobertas.
- Super Editor monorepo está fixado no commit
  `3bb857bc423240b61dc0fb799f3c269e71feb24a`.
- Fechar uma sessão acorda o outbox global sem consultar `Ref` depois do
  descarte do provider; `pollNow` não faz GET redundante após POST útil.
- `sync_inbox` e `sync_feed_cursors` são tabelas Drift na schema v31, com
  migração v30→v31 testada e cursor/inbox transacionais.
- O provider legado de polling do catálogo foi removido; o runtime incremental
  é o único owner da orquestração remota. A projeção efetiva agora é reutilizada
  pelo applier do editor, e o decoder do feed valida payloads antes dos casts.
- O workflow temporário `sync-feed-test.yml`, que apontava para uma branch
  antiga, foi removido.

## What Didn't Work

- A primeira migração armazenou DateTime como milliseconds; Drift usa Unix
  seconds para colunas DateTime integer. O teste de migração detectou isso e a
  conversão foi corrigida.
- A primeira versão do wake de fechamento capturava `ref.read` no callback
  tardio e gerava erro de provider descartado. A instância do worker agora é
  capturada durante a construção do provider.
- `flutter analyze --no-pub --no-fatal-infos` ainda retorna exit 1 por 2.348
  infos/avisos preexistentes do repositório (principalmente documentação,
  estilo e inferência em testes); não há erro novo nos arquivos alterados.
- Go não está instalado nem no PATH nem nos locais padrão desta máquina, então
  `go vet`, `go build` e `go test` não puderam ser executados localmente.

## Verification

- `flutter test --no-pub`: **733 passed**.
- Grupos individuais também passaram: core 169, auth 33, notes 380,
  settings 7, tasks 82, shared 50 e widget raiz 1.
- `git diff --check`: passou.
- `flutter analyze --no-pub --no-fatal-infos`: somente baseline warnings/infos;
  confirmar no CI com a versão oficial do Flutter.

## Next Steps

1. Executar `go vet ./...`, `go build ./...` e `go test -count=1 ./...` em uma
   máquina com Go instalado.
2. A retenção/compactação do feed servidor exige um protocolo de
   acknowledgement/expiração de cursor; não adicionar TTL especulativo que
   possa fazer clientes offline perderem eventos.

## Thermo-nuclear review

The review was repeated after removing the no-op inbox initialization wrapper,
centralizing retry delays, fixing the late provider callback capture, and
guarding bitmap paste progress. No actionable maintainability finding remains
in handwritten production code; generated Drift output is intentionally
excluded from the giant-file heuristic.
