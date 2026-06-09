# Notes UI — Dois Features

## Feature 1 — Toggle List / Grid

### Dependências

```yaml
dependencies:
  flutter_riverpod: ^2.x
  cue: ^0.x                      # animações
  flutter_staggered_grid_view: ^0.7.x  # grid com altura variável
```

### 1. Estado do view mode

```dart
// lib/features/notes/presentation/providers/notes_view_mode_provider.dart

enum NotesViewMode { list, grid }

final notesViewModeProvider = StateProvider<NotesViewMode>(
  (_) => NotesViewMode.grid,
);
```

### 2. Botão de toggle na AppBar

```dart
// Dentro do build da NotesPage
final viewMode = ref.watch(notesViewModeProvider);

IconButton(
  icon: Cue.onToggle(
    toggled: viewMode == NotesViewMode.grid,
    motion: .snappy(),
    acts: [.rotate(to: 90)],
    child: Icon(
      viewMode == NotesViewMode.grid
          ? Icons.list_rounded
          : Icons.grid_view_rounded,
    ),
  ),
  onPressed: () {
    ref.read(notesViewModeProvider.notifier).state =
        viewMode == NotesViewMode.grid
            ? NotesViewMode.list
            : NotesViewMode.grid;
  },
),
```

### 3. Conteúdo alternando com animação

```dart
// No body da NotesPage
Cue.onChange(
  value: viewMode,
  motion: .smooth(),
  acts: [.fadeIn(), .slideY(from: 0.06)],
  child: viewMode == NotesViewMode.grid
      ? const NotesGridView(key: ValueKey('grid'))
      : const NotesListView(key: ValueKey('list')),
),
```

> ⚠️ A `key` é obrigatória — sem ela o `Cue.onChange` não detecta a troca de widget.

### 4. NotesGridView

Usa `MasonryGridView` do `flutter_staggered_grid_view` para altura variável por card
(igual ao Apple Notes).

```dart
// lib/features/notes/presentation/widgets/notes_grid_view.dart

class NotesGridView extends StatelessWidget {
  const NotesGridView({super.key});

  @override
  Widget build(BuildContext context) {
    final notes = ...; // ref.watch do provider de notas

    return MasonryGridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      padding: const EdgeInsets.all(12),
      itemCount: notes.length,
      itemBuilder: (context, index) => Cue.onMount(
        motion: .smooth(),
        acts: [.fadeIn(), .scale(from: 0.96), .slideY(from: 0.08)],
        child: NoteCard(note: notes[index]),
      ),
    );
  }
}
```

### 5. NotesListView

```dart
// lib/features/notes/presentation/widgets/notes_list_view.dart

class NotesListView extends StatelessWidget {
  const NotesListView({super.key});

  @override
  Widget build(BuildContext context) {
    final notes = ...; // ref.watch do provider de notas

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: notes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) => Cue.onMount(
        motion: .smooth(),
        acts: [.fadeIn(), .slideX(from: -0.06)],
        child: NoteListTile(note: notes[index]),
      ),
    );
  }
}
```

---

## Feature 2 — Pull Down para Revelar Resumo Diário

### Como funciona

1. Usuário puxa a lista pra baixo quando já está no topo
2. Um painel desliza acima da lista, proporcional ao drag
3. Ao soltar (se passou do threshold): painel abre e dispara a chamada à API
4. O texto entra com `Cue.onMount`
5. Ao soltar antes do threshold: painel fecha

### Dependências extras

Nenhuma — usa apenas widgets nativos do Flutter + Riverpod + Cue.

### 1. Provider do resumo diário

```dart
// lib/features/notes/presentation/providers/daily_summary_provider.dart

@riverpod
class DailySummary extends _$DailySummary {
  @override
  AsyncValue<String> build() => const AsyncValue.data('');

  Future<void> fetch() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(notesRepositoryProvider).getDailySummary(),
    );
  }
}
```

### 2. Estado local do painel (na NotesPage)

```dart
double _panelHeight = 0;
bool   _panelOpen  = false;
double _dragAccum  = 0;

static const _maxPanelHeight = 180.0;
static const _threshold      = 60.0;  // px de drag pra confirmar abertura
```

### 3. Handler de scroll

```dart
void _onScroll(ScrollNotification notification) {
  if (notification is ScrollUpdateNotification) {
    final over = notification.metrics.pixels < 0
        ? notification.metrics.pixels.abs()
        : 0.0;

    setState(() {
      _dragAccum  = over;
      _panelHeight = (_dragAccum / _threshold * _maxPanelHeight)
          .clamp(0.0, _maxPanelHeight);
    });
  }

  if (notification is ScrollEndNotification) {
    final open = _dragAccum >= _threshold;
    setState(() {
      _panelOpen  = open;
      _panelHeight = open ? _maxPanelHeight : 0;
      _dragAccum  = 0;
    });

    if (open) {
      ref.read(dailySummaryProvider.notifier).fetch();
    }
  }
}
```

### 4. Layout da tela

```dart
@override
Widget build(BuildContext context) {
  return Column(
    children: [
      // Painel superior — AnimatedContainer controla a altura durante drag e snap
      AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        height: _panelHeight,
        child: const DailySummaryPanel(),
      ),

      // Lista de notas
      Expanded(
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            _onScroll(n);
            return false;
          },
          child: CustomScrollView(
            // BouncingScrollPhysics é OBRIGATÓRIO — sem ele o Android
            // usa ClampingScrollPhysics e pixels nunca fica < 0
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              // SliverGrid ou SliverList das notas
            ],
          ),
        ),
      ),
    ],
  );
}
```

### 5. DailySummaryPanel

```dart
// lib/features/notes/presentation/widgets/daily_summary_panel.dart

class DailySummaryPanel extends ConsumerWidget {
  const DailySummaryPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dailySummaryProvider);

    // ClipRect impede overflow do conteúdo enquanto o painel ainda está abrindo
    return ClipRect(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: summary.when(
            data: (text) => text.isEmpty
                ? const SizedBox.shrink()
                : Cue.onMount(        // <- aqui sim o Cue faz sentido
                    motion: .smooth(),
                    acts: [.fadeIn(), .slideY(from: -0.1)],
                    child: Text(
                      text,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const Text('Não foi possível carregar o resumo'),
          ),
        ),
      ),
    );
  }
}
```

---

## Por que Cue só entra no texto, não no painel

| Parte | Widget | Motivo |
|---|---|---|
| Altura do painel durante drag | `AnimatedContainer` | Animação contínua/scrubbed — valor muda frame a frame |
| Snap ao soltar | `AnimatedContainer` | Interpola para valor fixo com curva |
| Texto entrando no painel | `Cue.onMount` | Trigger discreto — aparece uma vez quando o widget faz mount |
| Cards entrando na lista | `Cue.onMount` | Idem |
| Ícone do toggle | `Cue.onToggle` | Estado binário, perfeito pro Cue |

---

## Estrutura de arquivos sugerida

```
lib/features/notes/presentation/
├── pages/
│   └── notes_page.dart           # Column + AnimatedContainer + NotificationListener
├── providers/
│   ├── notes_view_mode_provider.dart
│   └── daily_summary_provider.dart
└── widgets/
    ├── notes_grid_view.dart
    ├── notes_list_view.dart
    ├── note_card.dart
    ├── note_list_tile.dart
    └── daily_summary_panel.dart
```
