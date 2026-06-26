# AppMessenger Global - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refatorar `AppMessenger` para permitir chamadas globais sem `BuildContext`, simplificando a API para `showSnackBar(text: '...')` e permitindo extensões como o botão "Desfazer".

**Architecture:** Abordagem A — `GlobalKey<ScaffoldMessengerState>` registrado em `MaterialApp`, `AppMessenger` transformado em classe estática sem `炮塔内 BuildContext`. `completeTaskWithFeedback` movido para o domínio de Tarefas.

**Tech Stack:** Flutter SDK, Material Design, Riverpod (para lógica de tarefas eventualmente), `intl` para formatação de datas.

---

### Task 1: Refatorar `AppMessenger` para Global Key

**Files:**
- Modify: `lib/shared/widgets/app_snackbar.dart`
- Test: `test/shared/widgets/app_snackbar_test.dart`

- [ ] **Step 1: Alterar `AppMessenger` para usar `GlobalKey`**

```dart
import 'package:flutter/material.dart';

/// Singleton para exibir na interface
/// sem necessidade de [BuildContext].
class AppMessenger {
  AppMessenger._();

  static final GlobalKey<ScaffoldMessengerState> key =
      GlobalKey<ScaffoldMessengerState>();

  static void showSuccess(String message, {Duration? duration}) {
    _show(
      message,
      backgroundColor: Colors.green.shade700,
      duration: duration,
    );
  }

  static void showError(
    String message, {
    VoidCallback? onRetry,
    Duration? duration,
  }) {
    _show(
      message,
      backgroundColor: Colors.red.shade700, // ou Theme do navigator
      duration: duration,
      action: onRetry != null
          ? SnackBarAction(label: 'Tentar novamente', onPressed: onRetry)
          : null,
    );
  }

  static void showInfo(String message, {Duration? duration}) {
    _show(message, duration: duration);
  }

  static void showAction(
    String message, {
    required SnackBarAction action,
    Duration? duration,
  }) {
    _show(message, duration: duration, action: action);
  }

  static void _show(
    String message, {
    Color? backgroundColor,
    Duration? duration,
    SnackBarAction? action,
  }) {
    final messenger = key.currentState;
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
          duration: duration ?? const Duration(seconds: 4),
          action: action,
        ),
      );
  }
}
```

- [ ] **Step 2: Escrever teste unitário para `AppMessenger`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

void main() {
  testWidgets('AppMessenger.showSuccess exibe SnackBar', (tester) async {
    // Arrange
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppMessenger.key,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    // Act
    AppMessenger.showSuccess('Salvo!');
    await tester.pumpAndSettle();

    // Assert
    expect(find.text('Salvo!'), findsOneWidget);
  });

  testWidgets('AppMessenger.showAction exibe SnackBar com ação', (tester) async {
    bool pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppMessenger.key,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    AppMessenger.showAction(
      'Desfazer?',
      action: SnackBarAction(label: 'Sim', onPressed: () => pressed = true),
    );
    await tester.pumpAndSettle();

    expect(find.text('Desfazer?'), findsOneWidget);
    expect(find.text('Sim'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Rodar testes e verificar**

```bash
flutter test test/shared/widgets/app_snackbar_test.dart
```

Expected: PASS (2/2)

- [ ] **Step 4: Commit parcial**

```bash
git add lib/shared/widgets/app_snackbar.dart test/shared/widgets/app_snackbar_test.dart
git commit -m "feat(app_messenger): refactor to global key for context-free calls"
```

---

### Task 2: Registrar `AppMessenger.key` no `MaterialApp`

**Files:**
- Modify: `lib/main.dart`
- Test: `test/main_test.dart` (atualizar se existir)

- [ ] **Step 1: Adicionar `scaffoldMessengerKey` ao `MaterialApp.router`**

```dart
return MaterialApp.router(
  title: AppConstants.appName,
  debugShowCheckedModeBanner: false,
  routerConfig: router,
  scaffoldMessengerKey: AppMessenger.key, // <-- Adicionar esta linha
  builder: (context, child) { ... },
  theme: AppTheme.lightTheme,
  darkTheme: AppTheme.darkTheme,
);
```

- [ ] **Step 2: Adicionar `import`**

```dart
import 'package:supanotes/shared/widgets/app_snackbar.dart';
```

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat(main): wire AppMessenger global key to MaterialApp"
```

---

### Task 3: Refatorar `completeTaskWithFeedback` (Extrair Domínio)

**Files:
- Modify: `lib/shared/widgets/app_snackbar.dart` (remover método)
- Create (ou Modify): `lib/features/tasks/presentation/controllers/task_completion_controller.dart` ou similar
- Modify: `lib/features/notes/presentation/note_editor_screen.dart` e outros usos de `completeTaskWithFeedback`

- [ ] **Step 1: Remover `completeTaskWithFeedback` de `AppMessenger`**

```dart
// REMOVER:
// static Future<DateTime?> completeTaskWithFeedback(...) { ... }
```

- [ ] **Step 2: Criar helper no módulo de Tarefas**

```dart
// lib/features/tasks/presentation/controllers/task_snackbar_helper.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

class TaskSnackBarHelper {
  static Future<DateTime?> completeTaskWithFeedback({
    required Future<DateTime?> Function() onComplete, // ou use ref.read(tasksProvider).
    required VoidCallback onUndo,
  }) async {
    final nextDue = await onComplete();

    final message = nextDue != null
        ? 'Tarefa concluída! Próx. ocorrência: ${DateFormat('dd/MM/yyyy').format(nextDue)}'
        : 'Tarefa concluída!';

    AppMessenger.showAction(
      message,
      action: SnackBarAction(label: 'Desfazer', onPressed: onUndo),
      duration: const Duration(seconds: 5),
    );

    return nextDue;
  }
}
```

- [ ] **Step 3: Atualizar call sites**

Em cada arquivo que usa `AppMessenger.completeTaskWithFeedback(...)`, substituir por `TaskSnackBarHelper.completeTaskWithFeedback(...)`.

- [ ] **Step 4: Commit**

```bash
git add lib/shared/widgets/app_snackbar.dart lib/features/tasks/presentation/controllers/task_snackbar_helper.dart ...
git commit -m "慢跑) domain extracted"
```

---

### Task 4: Obsoletas & Cleanup

- [ ] **Step 1: Remover `BuildContext` de todos os call sites de `AppMessenger`**

Simplificar todas as chamadas de:
```dart
AppMessenger.showSuccess(context, '...');
// PARA:
AppMessenger.showSuccess('...');
```

- [ ] **Step 2: Remover imports desnecessários de `BuildContext`** se nenhuma outra parte do arquivo use.

- [ ] **Step 3: Commit**

```bash
git commit -m "refactor: remove BuildContext from AppMessenger call sites"
```

---

### Self-Review Checklist

- [x] Nenhum `TBD` ou `TODO`.
- [x] Completa implementação do `AppMessenger` está contida.
- [x] `completeTaskWithFeedback` tem um destino definido.
- [x] Testes unitários cobrem sucesso e ação customizada.
- [x] `main.dart` é modificado para registrar a chave.