# Apple Notes Inline Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the separate search screen with an Apple Notes-style inline search experience on the notes home screen that updates the visible notes list from title, content, and semantic context.

**Architecture:** Keep the backend `/api/v1/search` endpoint and default to hybrid search so lexical matches and note embeddings are fused server-side. Move the search UI state into `NotesListScreen` as local widget state, reuse the existing `searchResultsProvider`, and remove the standalone `/search` route plus obsolete frontend search-mode UI. Keep the home screen's normal Drift stream as the source of truth when the search field is empty.

**Tech Stack:** Flutter, Riverpod 3 manual providers, GoRouter, Dio, Go/Echo backend, PostgreSQL FTS, pgvector embeddings, Flutter widget tests, Go unit tests.

---

## Current State

- `lib/features/notes/presentation/notes_list_screen.dart` shows `activeNotesProvider` and opens `AppRoutes.search` when the search icon is tapped.
- `lib/features/search/presentation/search_screen.dart` is a separate full-screen route with a mode toggle.
- `lib/features/search/data/search_repository.dart` already calls `POST /api/v1/search`.
- `backend/internal/search/service.go` already supports `fts`, `semantic`, and `hybrid`; `hybrid` is the desired user-facing behavior.
- `backend/db/queries/search.sql` excludes deleted, archived, and inbox notes from search.
- The term "context" in this feature means semantic retrieval via note embeddings, not the `context_id` category field.

## File Structure

- Modify `lib/features/notes/presentation/notes_list_screen.dart`
  - Owns inline search UI state: collapsed/open, debounced query, loading/error/result rendering.
  - Uses normal note list when query is empty.
  - Uses `searchResultsProvider` when query is non-empty.
- Modify `lib/features/search/presentation/controllers/search_controller.dart`
  - Remove `searchModeProvider` and `SearchModeNotifier`.
  - Keep a single `searchResultsProvider` family that always calls hybrid search.
- Modify `lib/features/search/data/search_repository.dart`
  - Simplify public API to `search({required query, limit})`.
  - Always sends `mode: 'hybrid'`.
- Modify `lib/features/search/domain/search_result_model.dart`
  - Remove `SearchMode` from the domain model.
  - Keep id, title, excerpt, score.
- Modify `lib/features/search/presentation/widgets/search_result_tile.dart`
  - Remove mode badge and score label from user-facing UI.
  - Render as a note-like row/card suitable for inline results.
- Keep or move `lib/features/search/presentation/widgets/search_bar.dart`
  - Reuse it as the inline search input.
  - Add optional `onCancel` only if the AppBar layout needs it.
- Delete `lib/features/search/presentation/search_screen.dart`
  - Standalone screen is no longer used.
- Delete `lib/features/search/presentation/widgets/search_mode_toggle.dart`
  - User should not choose FTS/semantic/hybrid in the main app.
- Modify `lib/core/router/app_router.dart`
  - Remove `SearchScreen` import and `/search` route.
- Modify `lib/core/router/app_routes.dart`
  - Remove `AppRoutes.search`.
- Modify `lib/core/router/last_route_store.dart`
  - Remove `/search` from persistable routes.
- Modify tests:
  - `test/features/notes/presentation/notes_list_screen_test.dart`
  - `test/core/router/app_router_test.dart`
  - `test/core/router/last_route_store_test.dart`
- Backend cleanup:
  - Keep `/api/v1/search`, `backend/internal/search`, and `backend/db/queries/search.sql`; they are still needed.
  - No backend deletion unless a symbol becomes unused after frontend simplification.

## Tasks

### Task 1: Simplify Search Domain and Repository to Hybrid Only

**Files:**
- Modify: `lib/features/search/domain/search_result_model.dart`
- Modify: `lib/features/search/data/search_repository.dart`
- Modify: `lib/features/search/presentation/controllers/search_controller.dart`

- [ ] **Step 1: Write the failing controller/repository expectations by updating call sites mentally first**

The final controller shape must be:

```dart
final searchResultsProvider = FutureProvider.autoDispose
    .family<List<SearchResultModel>, String>((ref, query) async {
  return ref.read(searchRepositoryProvider).search(query: query);
});
```

The final repository interface must be:

```dart
abstract class ISearchRepository {
  static const int defaultLimit = 10;

  Future<List<SearchResultModel>> search({
    required String query,
    int limit = defaultLimit,
  });
}
```

- [ ] **Step 2: Remove `SearchMode` from `SearchResultModel`**

Replace the constructor and JSON factory in `lib/features/search/domain/search_result_model.dart` with this shape:

```dart
@immutable
class SearchResultModel {
  const SearchResultModel({
    required this.id,
    required this.title,
    required this.excerpt,
    required this.score,
  });

  final String id;
  final String title;
  final String excerpt;
  final double score;

  factory SearchResultModel.fromJson(Map<String, dynamic> json) {
    return SearchResultModel(
      id: (json['ID'] ?? '') as String,
      title: (json['Title'] ?? '') as String,
      excerpt: (json['Excerpt'] ?? '') as String,
      score: _readScore(json['Score']),
    );
  }

  static double _readScore(Object? raw) {
    if (raw is num) return raw.toDouble();
    return 0.0;
  }
}
```

Also update the file comments so they no longer mention exposed modes or badges.

- [ ] **Step 3: Simplify `SearchRepository.search`**

In `lib/features/search/data/search_repository.dart`, change the method signature and body to always send hybrid mode:

```dart
@override
Future<List<SearchResultModel>> search({
  required String query,
  int limit = defaultLimit,
}) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return const [];

  try {
    final response = await _api.post<List<dynamic>>(
      '/search',
      data: {
        'query': trimmed,
        'mode': 'hybrid',
        'limit': limit,
      },
    );
    final body = response.data ?? const [];
    return body
        .whereType<Map<String, dynamic>>()
        .map(SearchResultModel.fromJson)
        .toList(growable: false);
  } on DioException catch (e) {
    throw fromDioError(e);
  }
}
```

- [ ] **Step 4: Remove the mode provider**

In `lib/features/search/presentation/controllers/search_controller.dart`, leave only:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/search/data/search_repository.dart';
import 'package:supanotes/features/search/domain/search_result_model.dart';

final searchResultsProvider = FutureProvider.autoDispose
    .family<List<SearchResultModel>, String>((ref, query) async {
  return ref.read(searchRepositoryProvider).search(query: query);
});
```

- [ ] **Step 5: Run targeted Dart analysis**

Run:

```powershell
rtk flutter analyze lib/features/search
```

Expected: failures for existing UI files that still reference `SearchMode`; fix those in later tasks, do not restore `SearchMode`.

### Task 2: Make Search Result Rows User-Facing Instead of Technical

**Files:**
- Modify: `lib/features/search/presentation/widgets/search_result_tile.dart`

- [ ] **Step 1: Remove mode badge and score display**

Replace the footer section in `SearchResultTile` with no footer. The row should show title and excerpt only:

```dart
return Card(
  elevation: 0,
  clipBehavior: Clip.antiAlias,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    side: BorderSide(color: scheme.outlineVariant),
  ),
  child: InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (excerpt.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            _HighlightedText(
              text: excerpt,
              query: query,
              baseStyle: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              highlightStyle: textTheme.bodyMedium?.copyWith(
                color: semantic?.highlightForeground,
                backgroundColor: semantic?.highlightBackground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    ),
  ),
);
```

- [ ] **Step 2: Delete `_ModeBadge`**

Remove the private `_ModeBadge` class and any `SearchMode` import references. Keep `_HighlightedText`.

- [ ] **Step 3: Run targeted analyzer**

Run:

```powershell
rtk flutter analyze lib/features/search/presentation/widgets/search_result_tile.dart
```

Expected: PASS.

### Task 3: Add Inline Search State to Notes Home

**Files:**
- Modify: `lib/features/notes/presentation/notes_list_screen.dart`
- Test: `test/features/notes/presentation/notes_list_screen_test.dart`

- [ ] **Step 1: Extend home strings**

Add these constants to `_Strings` in `notes_list_screen.dart`:

```dart
static const String searchTooltip = 'Buscar notas';
static const String closeSearchTooltip = 'Fechar busca';
static const String searchHint = 'Buscar notas';
static const String searchErrorTitle = 'Erro na busca';
static const String emptySearchTitle = 'Nenhum resultado';
static const String emptySearchSubtitle = 'Tente outro termo.';
```

- [ ] **Step 2: Add local UI state**

Inside `_NotesListScreenState`, add:

```dart
bool _isSearching = false;
String _searchQuery = '';

void _openSearch() {
  setState(() => _isSearching = true);
}

void _closeSearch() {
  setState(() {
    _isSearching = false;
    _searchQuery = '';
  });
}

void _onSearchQueryChanged(String query) {
  setState(() => _searchQuery = query.trim());
}
```

This is widget-local state by design; do not create a Riverpod provider for the text field.

- [ ] **Step 3: Replace the AppBar search action**

Change the AppBar actions so the search icon toggles inline search:

```dart
IconButton(
  icon: Icon(_isSearching ? Icons.close : Icons.search),
  tooltip: _isSearching
      ? _Strings.closeSearchTooltip
      : _Strings.searchTooltip,
  onPressed: _isSearching ? _closeSearch : _openSearch,
),
```

Remove `context.push(AppRoutes.search)` from this file.

- [ ] **Step 4: Add the search input to `headerSlivers`**

Import the existing search bar:

```dart
import 'package:supanotes/features/search/presentation/widgets/search_bar.dart';
```

When `_isSearching` is true, insert a `SearchInputBar` before the Brain Dump tile:

```dart
final headerSlivers = [
  const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
  if (_isSearching)
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: SearchInputBar(
          key: const ValueKey('notes-inline-search-field'),
          initialQuery: _searchQuery,
          hintText: _Strings.searchHint,
          onQueryChanged: _onSearchQueryChanged,
        ),
      ),
    ),
  SliverToBoxAdapter(
    child: BrainDumpTile(
      title: _Strings.brainDump,
      onTap: () => context.push(AppRoutes.inbox),
    ),
  ),
  const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
  const SliverToBoxAdapter(
    child: SectionTitle(title: _Strings.notesSection),
  ),
];
```

- [ ] **Step 5: Branch the body by query**

Import the search provider and result model:

```dart
import 'package:supanotes/features/search/domain/search_result_model.dart';
import 'package:supanotes/features/search/presentation/controllers/search_controller.dart';
import 'package:supanotes/features/search/presentation/widgets/search_result_tile.dart';
import 'package:supanotes/shared/widgets/empty_state.dart';
```

In `build`, compute:

```dart
final trimmedSearchQuery = _searchQuery.trim();
final searchAsync = trimmedSearchQuery.isEmpty
    ? null
    : ref.watch(searchResultsProvider(trimmedSearchQuery));
```

Change the `body:` selection to:

```dart
body: trimmedSearchQuery.isEmpty
    ? notesAsync.when(
        loading: () => _NotesLoadingView(headerSlivers: headerSlivers),
        error: (e, _) => AppErrorView(
          title: _Strings.errorTitle,
          subtitle: e.toString(),
        ),
        data: (notes) => _buildNotesBody(notes, headerSlivers),
      )
    : searchAsync!.when(
        loading: () => _SearchLoadingView(headerSlivers: headerSlivers),
        error: (e, _) => _SearchErrorView(
          headerSlivers: headerSlivers,
          error: e.toString(),
        ),
        data: (results) => _SearchResultsView(
          headerSlivers: headerSlivers,
          query: trimmedSearchQuery,
          results: results,
          onTap: (result) => context.push(AppRoutes.note(result.id)),
        ),
      ),
```

Then extract the existing notes list rendering into:

```dart
Widget _buildNotesBody(List<NoteModel> notes, List<Widget> headerSlivers) {
  return Cue.onChange(
    value: _viewMode,
    motion: .smooth(),
    acts: [.fadeIn()],
    child: _viewMode == _NotesViewMode.grid
        ? NotesGridView(
            key: const ValueKey('grid'),
            notes: notes.toList(),
            headerSlivers: headerSlivers,
            onTap: _openNote,
            onDelete: _deleteNote,
            onToggleFavorite: _toggleFavorite,
          )
        : NotesListView(
            key: const ValueKey('list'),
            notes: notes.toList(),
            headerSlivers: headerSlivers,
            onTap: _openNote,
            onDelete: _deleteNote,
            onToggleFavorite: _toggleFavorite,
          ),
  );
}
```

- [ ] **Step 6: Add search result sliver views**

Add these private widgets near `_NotesLoadingView`:

```dart
class _SearchLoadingView extends StatelessWidget {
  const _SearchLoadingView({required this.headerSlivers});

  final List<Widget> headerSlivers;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        ...headerSlivers,
        const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
      ],
    );
  }
}

class _SearchErrorView extends StatelessWidget {
  const _SearchErrorView({
    required this.headerSlivers,
    required this.error,
  });

  final List<Widget> headerSlivers;
  final String error;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        ...headerSlivers,
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.cloud_off,
            title: _Strings.searchErrorTitle,
            subtitle: error,
          ),
        ),
      ],
    );
  }
}

class _SearchResultsView extends StatelessWidget {
  const _SearchResultsView({
    required this.headerSlivers,
    required this.query,
    required this.results,
    required this.onTap,
  });

  final List<Widget> headerSlivers;
  final String query;
  final List<SearchResultModel> results;
  final ValueChanged<SearchResultModel> onTap;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return CustomScrollView(
        slivers: [
          ...headerSlivers,
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.search_off,
              title: _Strings.emptySearchTitle,
              subtitle: _Strings.emptySearchSubtitle,
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      slivers: [
        ...headerSlivers,
        SliverPadding(
          padding: const EdgeInsets.all(AppSpacing.md),
          sliver: SliverList.separated(
            itemCount: results.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final result = results[index];
              return SearchResultTile(
                result: result,
                query: query,
                onTap: () => onTap(result),
              );
            },
          ),
        ),
      ],
    );
  }
}
```

If `SliverList.separated` is not available in the Flutter SDK version, use:

```dart
SliverList(
  delegate: SliverChildBuilderDelegate(
    (context, index) {
      if (index.isOdd) return const SizedBox(height: AppSpacing.sm);
      final result = results[index ~/ 2];
      return SearchResultTile(
        result: result,
        query: query,
        onTap: () => onTap(result),
      );
    },
    childCount: results.length * 2 - 1,
  ),
)
```

- [ ] **Step 7: Add widget tests for inline search**

In `test/features/notes/presentation/notes_list_screen_test.dart`, import:

```dart
import 'package:supanotes/features/search/domain/search_result_model.dart';
import 'package:supanotes/features/search/presentation/controllers/search_controller.dart';
```

Add this test:

```dart
testWidgets('search action opens inline search field on notes home', (tester) async {
  final notesRepository = _FakeNotesRepository();
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (_, _) => const NotesListScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [notesRepositoryProvider.overrideWithValue(notesRepository)],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byTooltip('Buscar notas'));
  await tester.pump();

  expect(find.byKey(const ValueKey('notes-inline-search-field')), findsOneWidget);
  expect(find.byTooltip('Fechar busca'), findsOneWidget);
});
```

Add this test:

```dart
testWidgets('inline search renders hybrid backend results', (tester) async {
  final notesRepository = _FakeNotesRepository();
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (_, _) => const NotesListScreen(),
      ),
      GoRoute(
        path: AppRoutes.note(':id'),
        builder: (_, state) => Scaffold(
          body: Text('Opened ${state.pathParameters['id']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notesRepositoryProvider.overrideWithValue(notesRepository),
        searchResultsProvider.overrideWith((ref, query) async {
          expect(query, 'comida');
          return const [
            SearchResultModel(
              id: 'note-shopping',
              title: 'Lista de compras',
              excerpt: 'Comprar arroz, feijao e legumes',
              score: 0.91,
            ),
          ];
        }),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byTooltip('Buscar notas'));
  await tester.pump();
  await tester.enterText(find.byType(TextField), 'comida');
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();

  expect(find.text('Lista de compras'), findsOneWidget);
  expect(find.textContaining('Comprar arroz'), findsOneWidget);

  await tester.tap(find.text('Lista de compras'));
  await tester.pumpAndSettle();

  expect(find.text('Opened note-shopping'), findsOneWidget);
});
```

- [ ] **Step 8: Run notes home tests**

Run:

```powershell
rtk flutter test test/features/notes/presentation/notes_list_screen_test.dart
```

Expected: PASS.

### Task 4: Remove Standalone Search Route and Dead Frontend Files

**Files:**
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/core/router/app_routes.dart`
- Modify: `lib/core/router/last_route_store.dart`
- Delete: `lib/features/search/presentation/search_screen.dart`
- Delete: `lib/features/search/presentation/widgets/search_mode_toggle.dart`
- Test: `test/core/router/app_router_test.dart`
- Test: `test/core/router/last_route_store_test.dart`

- [ ] **Step 1: Remove search route from router**

In `lib/core/router/app_router.dart`, delete:

```dart
import 'package:supanotes/features/search/presentation/search_screen.dart';
```

Delete this route:

```dart
GoRoute(
  path: AppRoutes.search,
  builder: (_, _) => const SearchScreen(),
),
```

- [ ] **Step 2: Remove `AppRoutes.search`**

In `lib/core/router/app_routes.dart`, delete:

```dart
static const search = '/search';
```

- [ ] **Step 3: Remove `/search` from persisted routes**

In `lib/core/router/last_route_store.dart`, remove:

```dart
location == AppRoutes.search ||
```

- [ ] **Step 4: Delete dead frontend files**

Delete:

```powershell
Remove-Item -LiteralPath 'lib/features/search/presentation/search_screen.dart'
Remove-Item -LiteralPath 'lib/features/search/presentation/widgets/search_mode_toggle.dart'
```

Use PowerShell `Remove-Item -LiteralPath`; do not delete the whole `lib/features/search` directory because repository, model, controller, bar, and result tile remain used.

- [ ] **Step 5: Update router tests**

In `test/core/router/app_router_test.dart`, replace the test named `router persists protected route navigation` so it navigates to a route that still exists:

```dart
testWidgets('router persists protected route navigation', (tester) async {
  final stub = AsyncValue<User?>.data(
    const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
  );
  final container = await _makeContainer(stub);

  await tester.pumpWidget(_wrapRouter(container));
  await settleRedirect(tester);

  final router = container.read(goRouterProvider);
  router.go(AppRoutes.settings);
  await settleRedirect(tester);

  final store = container.read(lastRouteStoreProvider);
  expect(store.initialLocation(), AppRoutes.settings);
});
```

In `test/core/router/last_route_store_test.dart`, replace `AppRoutes.search` with `AppRoutes.settings` in the clear test:

```dart
await store.save(AppRoutes.settings);
await store.clear();

expect(store.initialLocation(), AppRoutes.home);
```

- [ ] **Step 6: Search for leftover route references**

Run:

```powershell
rtk rg -n "AppRoutes\\.search|SearchScreen|search_mode_toggle|SearchModeToggle" lib test
```

Expected: no output.

- [ ] **Step 7: Run router tests**

Run:

```powershell
rtk flutter test test/core/router/app_router_test.dart test/core/router/last_route_store_test.dart
```

Expected: PASS.

### Task 5: Backend Search Cleanup and Contract Check

**Files:**
- Modify only if needed: `backend/internal/search/service.go`
- Modify only if needed: `backend/internal/search/handler.go`
- Modify only if needed: `backend/internal/search/service_test.go`
- Do not delete: `backend/internal/search`, `backend/db/queries/search.sql`

- [ ] **Step 1: Confirm backend endpoint is still required**

Keep `backend/internal/search` and `backend/db/queries/search.sql`. The inline home UI still calls `POST /api/v1/search`, so this is not dead backend code.

- [ ] **Step 2: Make unknown mode default to hybrid**

The frontend will always send `hybrid`, but the backend should also default unknown or empty modes to hybrid because hybrid is now the product behavior.

In `backend/internal/search/service.go`, change:

```go
default:
	return s.searchFTS(ctx, userID, query, limit)
```

to:

```go
default:
	return s.searchHybrid(ctx, userID, query, limit)
```

- [ ] **Step 3: Update backend default-mode test**

In `backend/internal/search/service_test.go`, update `TestService_SearchDefaultMode` so it expects hybrid:

```go
func TestService_SearchDefaultMode(t *testing.T) {
	userID := makeUUID(1)
	var called bool
	svc := NewService(&mockQuerier{
		searchHybrid: func(_ context.Context, arg sqlcgen.SearchNotesHybridParams) ([]sqlcgen.SearchNotesHybridRow, error) {
			called = true
			if arg.UserID != userID {
				t.Errorf("expected userID %v, got %v", userID, arg.UserID)
			}
			if arg.Query != "test" {
				t.Errorf("expected query test, got %q", arg.Query)
			}
			return nil, nil
		},
	}, llm.NewEmbeddingClient("", "", ""))

	_, err := svc.Search(context.Background(), userID, "test", "unknown", 10)
	if err != nil {
		t.Fatal(err)
	}
	if !called {
		t.Fatal("expected hybrid as default mode")
	}
}
```

- [ ] **Step 4: Run backend search tests**

Run:

```powershell
rtk go test ./backend/internal/search
```

Expected: PASS.

- [ ] **Step 5: Check for dead backend symbols**

Run:

```powershell
rtk rg -n "SearchNotesFTS|SearchNotesSemantic|SearchNotesHybrid|SearchNotesByEmbedding|RegisterRoutes\\(protected, searchH\\)" backend
```

Expected: all search SQL methods remain referenced by backend search service, agent RAG/tooling, tests, or route registration. Do not remove them if referenced.

### Task 6: Full Cleanup, Analysis, and Regression Verification

**Files:**
- No planned source edits unless verification exposes leftovers.

- [ ] **Step 1: Search for obsolete frontend concepts**

Run:

```powershell
rtk rg -n "SearchMode|searchModeProvider|SearchModeNotifier|mode: mode|mode\\.wireValue|AppRoutes\\.search|/search'|/search\"" lib test
```

Expected:
- No `SearchMode`, `searchModeProvider`, `SearchModeNotifier`, `AppRoutes.search`.
- `/search` may still appear in `lib/features/search/data/search_repository.dart` as the backend API path. That is expected and must remain.

- [ ] **Step 2: Run Dart analyzer on touched frontend**

Run:

```powershell
rtk flutter analyze lib/features/notes lib/features/search lib/core/router test/features/notes/presentation/notes_list_screen_test.dart test/core/router/app_router_test.dart test/core/router/last_route_store_test.dart
```

Expected: PASS or only unrelated pre-existing warnings. Fix any issues introduced by this plan.

- [ ] **Step 3: Run focused Flutter tests**

Run:

```powershell
rtk flutter test test/features/notes/presentation/notes_list_screen_test.dart test/core/router/app_router_test.dart test/core/router/last_route_store_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run backend search tests**

Run:

```powershell
rtk go test ./backend/internal/search
```

Expected: PASS.

- [ ] **Step 5: Optional manual runtime check**

Run the app and verify:

```powershell
rtk flutter run
```

Manual checks:
- Notes home opens normally.
- Tapping the search icon shows a search field in the current screen.
- Typing `comida` shows backend search results without navigating to another page.
- Clearing or closing the field restores the normal notes list.
- Result tap opens the note editor.
- There is no user-visible FTS/Semantic/Hybrid toggle or score badge.

## Cleanup Requirements

- Remove the standalone frontend search route, screen, and search mode toggle.
- Remove `SearchMode` and mode-specific frontend state.
- Keep the backend search endpoint because inline search depends on it.
- Keep backend FTS, semantic, and hybrid SQL methods because hybrid search uses both FTS and semantic branches.
- Do not remove agent semantic search tooling (`SearchNotesByEmbedding`) unless a separate agent/RAG refactor proves it unused.
- Do not add a provider for the search text; it is local UI state under the project's Riverpod rules.

## Self-Review

- Spec coverage: The plan implements Apple Notes-style inline search, uses title/content/semantic hybrid backend search, updates the current notes screen with results, and removes obsolete frontend route/mode code.
- Placeholder scan: No unresolved placeholders. All commands, files, and expected outcomes are explicit.
- Type consistency: `searchResultsProvider` accepts `String`; `SearchResultModel` no longer carries `SearchMode`; `SearchResultTile` consumes the simplified model.
