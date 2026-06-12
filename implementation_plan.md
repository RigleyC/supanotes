# Implementation Plan: Apple Notes-style Inline Search

Plano principal: `docs/superpowers/plans/2026-06-12-apple-notes-inline-search.md`

## Goal

Substituir a tela separada de busca por uma busca inline na tela de notas, estilo Apple Notes: o usuário toca na lupa, digita na própria tela, e a lista atualiza com resultados por título, conteúdo e relevância semântica.

## Decisions

1. A experiência principal usa busca híbrida (`fts` + embeddings) sempre que houver query.
2. A query digitada é estado local do widget, não provider.
3. A lista normal continua vindo do Drift local quando a query está vazia.
4. A tela/rota separada `/search` e os controles técnicos de modo (`Texto`, `Semântica`, `Híbrida`) serão removidos.
5. O backend `/api/v1/search` permanece, porque a busca inline depende dele.

## Verification

- `rtk flutter test test/features/notes/presentation/notes_list_screen_test.dart`
- `rtk flutter test test/core/router/app_router_test.dart test/core/router/last_route_store_test.dart`
- `rtk flutter analyze lib/features/notes lib/features/search lib/core/router`
- `rtk go test ./backend/internal/search`
