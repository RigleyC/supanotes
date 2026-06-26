# Spec: Redesign da Tela de Seleção de Data e Recorrência

## Goal

Redesenhar a UI de seleção de data e recorrência dentro do `TaskEditSheet`, substituindo o layout atual de chips (`Wrap` + `AppChoiceChip`) por uma lista vertical de **tiles largos** (`AppSelectionTile`).

O objetivo é melhorar a acessibilidade, a clareza visual e a experiência de toque, permitindo que o usuário selecione rapidamente opções pré-definidas ou expanda um calendário inline para uma data customizada.

## Design Details

### 1. Overview (Bottom Sheet)

O `TaskEditSheet` manterá sua estrutura de bottom sheet, mas o conteúdo de data e recorrência será reorganizado em seções verticais de tiles.

**Estrutura Geral:**
```
┌──────────────────────────────────┐
│  Editar tarefa                  │
│                                  │
│  [Input de título...]           │
│                                  │
│  ── DATA DE VENCIMENTO ───────   │
│  ┌────────────────────────────┐  │
│  │ 📅 Hoje                    │  │
│  ├────────────────────────────┤  │
│  │ 📅 Amanhã                  │  │
│  ├────────────────────────────┤  │
│  │ 📅 Próx. segunda           │  │
│  ├────────────────────────────┤  │
│  │ 📅 Escolher data           │  │
│  │                            │  │
│  │   [Calendário inline       │  │
│  │    quando expandido]       │  │
│  ├────────────────────────────┤  │
│  │ 🚫 Sem data                │  │
│  └────────────────────────────┘  │
│                                  │
│  ── REPETIÇÃO ────────────────   │
│  ┌────────────────────────────┐  │
│  │ 🔄 Nenhuma                 │  │
│  ├────────────────────────────┤  │
│  │ 🔁 Diária                  │  │
│  ├────────────────────────────┤  │
│  │ 📅 Dias úteis              │  │
│  ├────────────────────────────┤  │
│  │ 📊 Semanal                 │  │
│  ├────────────────────────────┤  │
│  │ 📅 Mensal                  │  │
│  └────────────────────────────┘  │
│                                  │
│  [Cancelar]      [Salvar]       │
└──────────────────────────────────┘
```

### 2. Componente Reutilizável: `AppSelectionTile`

Um novo widget reutilizável será criado em `lib/shared/widgets/app_selection_tile.dart` para padronizar o visual dos tiles de seleção.

```dart
class AppSelectionTile extends StatelessWidget {
  const AppSelectionTile({
    super.key,
    required this.label,
    this.icon,
    this.isSelected = false,
    this.onTap,
    this.trailing,
  });

  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback? onTap;
  final Widget? trailing;
}
```

**Especificações Visuais:**
- **Fundo**: `ColorScheme.surfaceContainer` (padrão) ou `ColorScheme.primaryContainer` + `ColorScheme.primary` para o estado selecionado.
- **Borda**: `BorderRadius.circular(AppSpacing.radiusMd)` (12px).
- **Padding**: `EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm)`.
- **Layout Interno**: `Row` com `[Icon, SizedBox(width: AppSpacing.sm), Expanded(Text(label)), trailing?, _SelectionIndicator]`.
- **Ícone**: `Icons.today_rounded`, cor `onSurfaceVariant` (padrão) ou `onPrimaryContainer` (selecionado).
- **Texto**: `labelLarge`, fonte com peso `w500`.
- **Indicador de Seleção**: Um `Icon(Icons.check_circle, ...)` à direita quando `isSelected` for verdadeiro.
- **Animações**: `AnimatedContainer` para a transição suave de cores ao selecionar/deselecionar.

### 3. Seção de Seleção de Data (`DueDatePicker` refatorado)

O widget `DueDatePicker` será refatorado para usar `AppSelectionTile` em vez de `AppChoiceChip`.

**Tiles disponíveis:**

| Rótulo | Ícone | Ação |
| --- | --- | --- |
| Hoje | `Icons.today_rounded` | Define `_dueDate = hoje` (start of day). |
| Amanhã | `Icons.wb_sunny_outlined` | Define `_dueDate = amanhã` (start of day). |
| Próx. segunda | `Icons.date_range_rounded` | Calcula a próxima segunda-feira e define como `_dueDate`. |
| Escolher data | `Icons.calendar_month_outlined` | Expande o calendário inline. |
| Sem data | `Icons.block` | Limpa `_dueDate` e `_recurrence` para `null`. |

**Comportamento de "Escolher data":**
- **Estado do Tile**: Exibe o texto padrão `Escolher data`.
- **Expansão**: Ao tocar, um calendário inline (`CalendarDatePicker` do Flutter) expande abaixo do tile usando um `AnimatedSize` + `ClipRect`. O tile `Escolher data` permanece visível acima do calendário.
- **Seleção no Calendário**: Quando o usuário seleciona uma data, `_dueDate` é atualizado, o calendário colapsa automaticamente e o rótulo do tile é atualizado para a data selecionada (ex: `15 Jul`).

**Datas Pré-definidas:**
- As datas são sempre calculadas em relação ao `DateTime.now().startOfDay`.
- O tile que corresponde à data atual de `_dueDate` é marcado como selecionado.
- Se `_dueDate` for uma data customizada (não é pré-definida), o tile `Escolher data` é marcado como selecionado e seu rótulo reflete a data.

### 4. Seção de Seleção de Recorrência (`RecurrencePicker` refatorado)

O widget `RecurrencePicker` também será refatorado para usar `AppSelectionTile`.

**Tiles disponíveis:**

| Rótulo | Ícone (sugestão) | Ação |
| --- | --- | --- |
| Nenhuma | `Icons.do_not_disturb_on_outlined` | Define `_recurrence = null`. |
| Diária | `Icons.today_rounded` | Define `_recurrence = TaskRecurrence.daily`. |
| Dias úteis | `Icons.work_outline` | Define `_recurrence = TaskRecurrence.weekdays`. |
| Semanal | `Icons.calendar_view_week_outlined` | Define `_recurrence = TaskRecurrence.weekly`. |
| Mensal | `Icons.calendar_month_outlined` | Define `_recurrence = TaskRecurrence.monthly`. |

**Lógica de Coupling:**
- Se uma recorrência é selecionada (`_recurrence != null`) e `_dueDate` está vazio (`null`), `_dueDate` é automaticamente definido para `DateTime.now().startOfDay`. Essa lógica atual já existia no `_onChanged` do `RecurrencePicker` e será mantida para consistência.

### 5. State Management e Data Flow

O `TaskEditSheet` continuará a gerenciar o estado local via `setState` para esta interação.

```dart
class _TaskEditSheetState extends ConsumerState<TaskEditSheet> {
  late DateTime? _dueDate;
  late TaskRecurrence? _recurrence;
  bool _isCalendarExpanded = false; // Novo estado para controle da UI

  // ... restante do state
}
```

**Fluxo de Ações:**
- **Ao selecionar um tile de data**: `_isCalendarExpanded` é setado para `false`, e `_dueDate` é atualizado. O tile correspondente é destacado.
- **Ao selecionar "Escolher data"**: `_isCalendarExpanded` é setado para `true`. O calendário renderiza.
- **Ao selecionar uma data do calendário**: A data é salva em `_dueDate`, o calendário colapsa (`_isCalendarExpanded = false`), e a UI atualiza o tile `Escolher data` com a nova data.
- **Ao selecionar "Sem data"**: `_dueDate` e `_recurrence` ambos redefinidos para `null`. `_isCalendarExpanded` também é setado para `false`.

### 6. Verificação e Testes

- **Testes de Widget (`test/features/tasks/presentation/widgets`)**:
  - Verificar se o widget `AppSelectionTile` renderiza corretamente em todos os estados (selecionado/não selecionado).
  - Verificar se `DueDatePicker` exibe os tiles corretos.
  - Simular toque em "Hoje" e verificar se `_onChanged` é chamado com a data de hoje.
  - Simular toque em "Escolher data" e verificar se o calendário é exibido.
  - Simular a seleção de uma data no calendário e verificar se o caller recebe a data correta.
  - Verificar se "Sem data" limpa `_recurrence` também.

- **Integração no `TaskEditSheet`**:
  - Assegurar que ao tocar em "Salvar", os valores de `_dueDate` e `_recurrence` são corretamente passados para a chamada de API/repositório.

### 7. Dependências

- **Novo arquivo**: `lib/shared/widgets/app_selection_tile.dart`
- **Arquivos Modificados**:
  - `lib/features/tasks/presentation/widgets/due_date_picker.dart`
  - `lib/features/tasks/presentation/widgets/recurrence_picker.dart`
  - `lib/features/tasks/presentation/widgets/task_edit_sheet.dart` (integração)
- **Dependências Pubspec**: Adicionar `table_calendar` caso a decisão final seja usá-lo (ou manter o `CalendarDatePicker` nativo para evitar dependências externas). **Confirmado uso do `CalendarDatePicker` nativo para minimizar dependências.**

## Trade-offs e Decisões

- **Lista Vertical vs. Grid**: Optou-se pela lista vertical de tiles largos ao invés de um grid horizontal, visando maior clareza visual e área de toque generosa, melhorando a experiência em dispositivos móveis.
- `CalendarDatePicker` Nativo vs. `table_calendar`: Optou-se pelo widget nativo do Flutter para manter o binário leve e evitar dependências de terceiros, aceitando o custo de menos customização visual.
- **Bottom Sheet vs. Nova Tela**: Mantido o bottom sheet por consistência com o restante do aplicativo e para não interromper o fluxo de edição do usuário.
