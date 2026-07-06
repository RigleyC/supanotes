# Task Touch Area & Simplification — Design

**Date:** 2026-07-06
**Status:** Approved (pending spec review)
**Scope:** `TaskTile` (lista) + `CustomTaskComponent` (editor) + checkbox compartilhado

---

## Metas

1. **Touch targets de 48px** em todos os pontos de toque de tarefa (Material minimum).
2. **Comportamento unificado de toque** entre lista e editor:
   - Tap no node inteiro conclui/reabre a tarefa.
   - Long‑press abre o modal de metadata.
   - No editor, tap no texto **edita** (preservado pelo super_editor); tap fora do texto conclui.
3. **Eliminar duplicação de checkbox**: hoje existem `TaskCheckbox` (círculo) e `AnimatedTaskCheckbox` (quadrado arredondado com `CustomPaint`). Substituir por um único `AppTaskCheckbox`.
4. **Reduzir `CustomTaskComponent`** de ~394 linhas para ~100 isolando animação de exit e resolvedor de estilos.
5. **Preservar a micro‑animação do check** "sendo desenhado" via `CustomPaint` + `AnimationController`.

## Não‑Metas (YAGNI)

- Não reintroduzir swipe de excluir na `TaskTile` (removido; exclusão via long‑press → modal).
- Não adicionar gestures novos (drag‑to‑reorder, swipe entre datas, etc.) neste ciclo.
- Não refatorar `CustomTaskComponentBuilder` (permanece onde está, apenas enxuto).

---

## Componentes

### 1. `AppTaskCheckbox` (novo)

**Local:** `lib/shared/widgets/app_task_checkbox.dart`
**Tipo:** `StatefulWidget` (precisa de `AnimationController`).
**Linhas esperadas:** ~120 (incluindo `_CheckmarkPainter`, sem lógica de gesture).

#### API

```dart
enum AppTaskCheckboxShape { circle, rounded }

class AppTaskCheckbox extends StatefulWidget {
  const AppTaskCheckbox({
    super.key,
    required this.value,
    this.accentColor,
    this.inactiveColor,
    this.size = 22.0,
    this.shape = AppTaskCheckboxShape.circle,
  });

  final bool value;
  final Color? accentColor;            // default: ColorScheme.primary
  final Color? inactiveColor;         // default: ColorScheme.outline @ 0.6
  final double size;
  final AppTaskCheckboxShape shape;
}
```

#### Comportamento

- **Puramente visual** — não tem `GestureDetector`, `onChanged` ou `onLongPress`. Todos os gestures são responsabilidade do `TaskTile`/`CustomTaskComponent` (parent).
- `AnimationController` duration **300ms**, `SingleTickerProviderStateMixin`.
  - `forward()` ao marcar (`didUpdateWidget` detecta `value: false → true`).
  - `reverse()` ao desmarcar.
- Duas camadas animadas em paralelo:
  1. **Fundo + borda** interpolados pelo controller (cor do fill vai de transparente → accentColor; borda de outline → accentColor). Pode usar `AnimatedContainer` ou `Tween<Color>` com `Color.lerp` no builder — decisão de implementação, prefira `Color.lerp` pra alinhar com o progresso do check.
  2. **Path do check** desenhado por `_CheckmarkPainter` com `progress = _checkAnim.value`, onde `_checkAnim` é `Interval(0.2, 0.7, curve: easeOut)` (igual ao `AnimatedTaskCheckbox` atual).
- `shape`:
  - `circle` → `BoxShape.circle` (lista).
  - `rounded` → `BorderRadius.circular(8)` (editor).
- `Semantics(checked: value, label: 'Tarefa ${value ? 'concluída' : 'pendente'}')` mantido do `TaskCheckbox` atual.

#### `_CheckmarkPainter`

Reaproveitar literalmente o `_CheckmarkPaint` de `animated_task_checkbox.dart:124-159` (path start → mid → end + `extractPath` por progress). Movido pra arquivo privado no fim do `app_task_checkbox.dart`.

### 2. `TaskTile` (refatorado)

**Local:** `lib/features/tasks/presentation/widgets/task_tile.dart` (mesma path — editar, não criar).
**Linhas esperadas:** ~110 (hoje 167; ganho vem de remover `Dismissible` + `_SwipeBackground` + `_MetaRow`).

#### API

```dart
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    this.onToggleComplete,
    this.onOpenMetadata,
    this.onDelete,
    this.dense = false,
  });

  final TaskModel task;
  final ValueChanged<bool>? onToggleComplete;
  final VoidCallback? onOpenMetadata;
  final VoidCallback? onDelete;        // mantido p/ uso futuro no modal
  final bool dense;
}
```

- `onTap` removido (não havia quem usasse — verificar uso interno).
- `onToggleComplete(bool)` mantém semântica (true = concluir).
- `onOpenMetadata` novo (long‑press).
- `onDelete` mantido (ainda válido p/ o modal que abre via long‑press).

#### Estrutura do `build`

```
Material(
  color: taskColor @ 8%,
  borderRadius: radiusMd,
  clipBehavior: antiAlias,
  child: GestureDetector(                 // substitui InkWell
    behavior: opaque,
    onTap: () => onToggleComplete?.call(!task.isCompleted),
    onLongPress: onOpenMetadata,
    child: Padding(
      // padding simétrico (igual hoje)
      child: Row(
        children: [
          AppTaskCheckbox(
            value: task.isCompleted,
            accentColor: taskColor,
            shape: circle,
          ),
          SizedBox(width: md),
          Expanded(Column[
            Text(task.title, com lineThrough se concluída),
            if (dueDate ou recurrence) TaskMetadataBadges(...),   // direto
          ]),
        ],
      ),
    ),
  ),
)
```

> **Decisão de implementação:** checkbox visual é `AppTaskCheckbox(onChanged: null)`. Como `onTap` é null quando `onChanged` é null, o checkbox não consome toque — dispensa `IgnorePointer`.

- **Removido:** `Dismissible`, `_SwipeBackground`, `_MetaRow`.
- **Tap area:** toda a linha (height ≈ 56–72px dependendo de `dense` e badges). Acima dos 48px mínimos.

### 3. `CustomTaskComponent` (slim)

**Local:** `lib/features/notes/presentation/widgets/custom_task_component.dart` (mesma path).
**Linhas esperadas:** ~100 (hoje 394).

#### Splits

| Novo arquivo | Responsabilidade | Linhas |
|---|---|---|
| `widgets/task_exit_animator.dart` | `AnimationController` + `SizeTransition`/`FadeTransition` + delay 300ms. `StatefulWidget` expõe `forward()/reverse()` via key ou `onComplete`. Tempos (`_exitAnimationDelay`, `_exitAnimationDuration`) movidos p/ cá como consts. | ~60 |
| `widgets/task_text_style_resolver.dart` | `TextStyle resolveTaskTextStyle(Set<Attribution>, TextStyle base, bool isComplete)` — função pura. Inclui o cálculo de mute (50% alpha) + lineThrough. | ~30 |

#### `build` resultante (esqueleto)

```
@override
Widget build(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;
  final semantics = Theme.of(context).extension<AppSemanticColors>();
  final taskColor = semantics?.task ?? AppColors.taskAccent;

  final content = Directionality(
    textDirection: viewModel.textDirection,
    child: GestureDetector(                        // novo — captura taps fora do texto
      behavior: translucent,
      onTap: () => viewModel.setComplete?.call(!viewModel.isComplete),
      onLongPress: onLongPress,
      child: Row(
        children: [
          SizedBox(width: indent),
          AppTaskCheckbox(
            value: viewModel.isComplete,
            accentColor: taskColor,
            inactiveColor: colorScheme.outline,
            shape: rounded,
          ),
          SizedBox(width: _taskCheckboxGap),
          Expanded(Column[
            TextComponent(textKey, ...),
            if (metadata) TaskMetadataBadges(...),
          ]),
        ],
      ),
    ),
  );

  return TaskExitAnimator(
    hideCompleted: hideCompleted,
    isComplete: viewModel.isComplete,
    onAnimationComplete: onAnimationComplete,
    child: content,
  );
}
```

#### Removidos
- `_TaskCheckboxHitTarget` (vira o `AppTaskCheckbox`).
- Lógica de `_cachedFirstLineHeight` (não precisa mais alinhar checkbox à 1ª linha; `Row` com `crossAxisAlignment: start` + checkbox no topo é suficiente quando o texto é multiline — verificar regressão visual no plano).
- `AnimationController`, `_fadeAnimation`, `_sizeAnimation`, `_exitController` listeners (movidos).
- `_computeStyles` (movido p/ `task_text_style_resolver.dart`).
- Constantes `_taskCheckboxPadding`, `_taskCheckboxSize` (consolidadas em `AppTaskCheckbox`).

### 4. Delete
- `lib/features/tasks/presentation/widgets/task_checkbox.dart`
- `lib/shared/widgets/animated_task_checkbox.dart`

### 5. Testes

| Arquivo | Estado | Cobertura |
|---|---|---|
| `test/shared/widgets/app_task_checkbox_test.dart` | **Novo** | Renderiza conforme `value` (filled/outline). `didUpdateWidget` dispara `forward()`/`reverse()` no controller. `shape: circle` vs `rounded` produzem `BoxShape.circle`/`BorderRadius.circular(8)`. Sem gesture — não consome tap (validar com `tester.tap` não propagar erro). |
| `test/features/tasks/presentation/widgets/task_tile_test.dart` | **Atualizar** | Tap no título (fora do checkbox) → `onToggleComplete(true)`. Tap quando já concluída → `onToggleComplete(false)`. Long‑press → `onOpenMetadata`. Remover testes de swipe. |
| `test/features/tasks/presentation/widgets/task_metadata_badges_test.dart` | Mantido | — |
| `test/features/notes/.../custom_task_component_test.dart` | **Novo ou estendido** | Tap fora do texto → `setComplete(!isComplete)`. Long‑press → callback. Texto editável preservado (pump, focar, digitar). |
| `test/features/tasks/presentation/task_completion_snackbar_test.dart` | **Atualizar** | Hoje usa `AnimatedTaskCheckbox` por import — trocar por `AppTaskCheckbox`. |

### 6. Ordem de implementação
1. Criar `AppTaskCheckbox` + `_CheckmarkPainter` + testes (rodar isolado).
2. Migrar `TaskTile` pra `AppTaskCheckbox` circle + novo gesture; atualizar testes.
3. Extrair `TaskExitAnimator` + `resolveTaskTextStyle`.
4. Slim do `CustomTaskComponent` + `AppTaskCheckbox` rounded; testes.
5. Deletar `TaskCheckbox` e `AnimatedTaskCheckbox`.
6. Rodar `flutter analyze` + `flutter test` + adaptar testes que quebrarem.
7. Rodar app e validar regressão visual (círculo na lista, quadrado arredondado no editor, animação do check em ambos).

---

## Decisões registradas

- **Swipe removido** da `TaskTile`. Exclusão via long‑press → modal (já existe `TaskMetadataSheet` com delete).
- **`onTap` antigo da `TaskTile`** (abrir detalhes) some; vira `onToggleComplete`. Detalhes agora só via long‑press.
- **Animação "sendo desenhada" do check**: preservada (Mover `_CheckmarkPainter` p/ o novo widget).
- **Hit area editor**: definida pelo `Row` inteiro (parent `GestureDetector` translucidam), não pelo checkbox — que é puramente visual.
- **Sem codegen** (AGENTS.md §Riverpod — código manual).
- **Sem `_FooStrings`**: labels vão inline (`const Text('Concluir')` etc.) — não há neste design.

## Pontos de risco (a observar no plano)

- **Tap concorrente texto vs row no editor:** super_editor consome tap na `TextComponent` antes do `GestureDetector` parent? Precisa validar. Estratégia: `behavior: translucent` + `GestureDetector` envolvendo só as regiões não‑texto (indent + checkbox + gap), não o `Expanded` de texto. Ajustar no plano se regressão.
- **Perda de alinhamento do checkbox** no editor multiline: `_cachedFirstLineHeight` era computed pra isso. Medir regressão visual.
- **Acessibilidade:** `Semantics` do checkbox precisa anunciar ação (recomendado `Semantics(button: true, enabled: onChanged != null)`).
- **Suporte a teclado/mouse:** desktop usa double‑tap? Long‑press com mouse = right‑click? Possível adicionar `onSecondaryTap` no `GestureDetector` da `TaskTile` mapeando pra `onOpenMetadata`. Anotar como nice‑to‑have no plano.