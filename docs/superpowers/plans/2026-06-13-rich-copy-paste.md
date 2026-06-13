# Copiar e Colar com Formatação (Rich Copy/Paste) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Habilitar a cópia e colagem mantendo a formatação rica (negritos, itálicos, títulos e listas/tarefas) tanto dentro do SupaNotes quanto na interação com aplicativos externos.

**Architecture:** Substituir as operações padrão de texto plano por atalhos de teclado e delegados de menus flutuantes ricos providos pela biblioteca `super_editor_clipboard`. Criaremos a classe `RichCommonEditorOperations` para unificar a cópia, recorte e colagem ricas de forma multiplataforma.

**Tech Stack:** `super_editor`, `super_editor_clipboard`, `super_clipboard`, `html2md`

---

### Task 1: Criar a classe de Operações Ricas do Editor

**Files:**
- Create: `lib/features/notes/presentation/widgets/rich_common_editor_operations.dart`

- [ ] **Step 1: Criar o arquivo de operações de cópia/colagem ricas**

Criar o arquivo `lib/features/notes/presentation/widgets/rich_common_editor_operations.dart` com a implementação de `RichCommonEditorOperations` que herda de `CommonEditorOperations` para interceptar as chamadas nos menus e delegar para a área de transferência rica.

```dart
import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_clipboard/super_editor_clipboard.dart';

class RichCommonEditorOperations extends CommonEditorOperations {
  RichCommonEditorOperations({
    required super.editor,
    required super.document,
    required super.composer,
    required super.documentLayoutResolver,
  });

  @override
  void copy() {
    if (composer.selection != null && !composer.selection!.isCollapsed) {
      document.copyAsRichTextWithPlainTextFallback(
        selection: composer.selection!,
      );
    }
  }

  @override
  void cut() {
    if (composer.selection != null && !composer.selection!.isCollapsed) {
      document.copyAsRichTextWithPlainTextFallback(
        selection: composer.selection!,
      );
      deleteSelection(TextAffinity.downstream);
    }
  }

  @override
  void paste() {
    pasteIntoEditorFromNativeClipboard(editor);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/notes/presentation/widgets/rich_common_editor_operations.dart
git commit -m "feat(notes): add RichCommonEditorOperations for rich copy, paste and cut"
```

---

### Task 2: Criar Atalhos de Teclado Ricos

**Files:**
- Create: `lib/features/notes/presentation/widgets/rich_keyboard_actions.dart`

- [ ] **Step 1: Criar o atalho rico de recortar e construtor de atalhos**

Criar o arquivo `lib/features/notes/presentation/widgets/rich_keyboard_actions.dart`. Este arquivo definirá a instrução de teclado customizada `cutAsRichTextWhenCmdXOrCtrlXIsPressed` e a função auxiliar `buildRichKeyboardActions` que prepend os atalhos ricos de cópia, recorte e colagem na lista padrão.

```dart
import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_clipboard/super_editor_clipboard.dart';

ExecutionInstruction cutAsRichTextWhenCmdXOrCtrlXIsPressed({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (!keyEvent.isPrimaryShortcutKeyPressed || keyEvent.logicalKey != LogicalKeyboardKey.keyX) {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }
  if (editContext.composer.selection!.isCollapsed) {
    return ExecutionInstruction.haltExecution;
  }

  editContext.document.copyAsRichTextWithPlainTextFallback(
    selection: editContext.composer.selection!,
  );
  editContext.commonOps.deleteSelection(TextAffinity.downstream);

  return ExecutionInstruction.haltExecution;
}

List<SuperEditorKeyboardAction> buildRichKeyboardActions({
  required List<SuperEditorKeyboardAction> baseActions,
}) {
  return [
    copyAsRichTextWhenCmdCOrCtrlCIsPressed,
    cutAsRichTextWhenCmdXOrCtrlXIsPressed,
    pasteRichTextOnCmdCtrlV,
    ...baseActions,
  ];
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/notes/presentation/widgets/rich_keyboard_actions.dart
git commit -m "feat(notes): add rich keyboard actions for copy, cut, and paste"
```

---

### Task 3: Criar Controlador customizado para iOS

**Files:**
- Create: `lib/features/notes/presentation/widgets/rich_ios_controls_controller.dart`

- [ ] **Step 1: Criar o controlador de popover rico para iOS**

Criar o arquivo `lib/features/notes/presentation/widgets/rich_ios_controls_controller.dart` implementando `RichSuperEditorIosControlsController` que estende o controlador nativo de colagem do iOS da biblioteca para injetar a nossa classe `RichCommonEditorOperations`.

```dart
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_clipboard/super_editor_clipboard.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_common_editor_operations.dart';

class RichSuperEditorIosControlsController extends SuperEditorIosControlsControllerWithNativePaste {
  RichSuperEditorIosControlsController({
    required super.editor,
    required super.documentLayoutResolver,
  });

  @override
  DocumentFloatingToolbarBuilder? get toolbarBuilder => (context, mobileToolbarKey, focalPoint) {
        if (editor.composer.selection == null) {
          return const SizedBox();
        }

        return iOSSystemPopoverEditorToolbarWithFallbackBuilder(
          context,
          mobileToolbarKey,
          focalPoint,
          RichCommonEditorOperations(
            document: editor.document,
            editor: editor,
            composer: editor.composer,
            documentLayoutResolver: documentLayoutResolver,
          ),
          SuperEditorIosControlsScope.rootOf(context),
        );
      };
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/notes/presentation/widgets/rich_ios_controls_controller.dart
git commit -m "feat(notes): add RichSuperEditorIosControlsController to override native iOS paste with rich formatting"
```

---

### Task 4: Integrar os Controladores Ricos na Interface do Editor

**Files:**
- Modify: `lib/features/notes/presentation/note_editor_screen.dart`

- [ ] **Step 1: Importar as dependências ricas em note_editor_screen.dart**

Adicionar os imports dos novos widgets e da biblioteca `super_editor_clipboard` no topo de `lib/features/notes/presentation/note_editor_screen.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:super_editor_clipboard/super_editor_clipboard.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_keyboard_actions.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_ios_controls_controller.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_common_editor_operations.dart';
```

- [ ] **Step 2: Declarar os controladores para iOS e Android em _NoteEditorScreenState**

Substituir a declaração de `late final SuperEditorIosControlsController _iosController;` em `_NoteEditorScreenState` pelas declarações dos dois controladores como mutáveis/nuláveis, e remover a inicialização do `_iosController` do `initState`:

```dart
  SuperEditorIosControlsController? _iosController;
  SuperEditorAndroidControlsController? _androidController;
  final _docLayoutKey = GlobalKey();

  @override
  void initState() {
    super.initState();
  }
```

- [ ] **Step 3: Atualizar o método dispose()**

Atualizar o método `dispose()` de `_NoteEditorScreenState` para limpar ambos os controladores de forma segura:

```dart
  @override
  void dispose() {
    _iosController?.dispose();
    _androidController?.dispose();
    _controller?.dispose();
    super.dispose();
  }
```

- [ ] **Step 4: Atualizar o método _buildIosToolbar**

Atualizar a construção da barra de ferramentas flutuante do iOS para utilizar a versão rica de operações:

```dart
  Widget _buildIosToolbar(
    BuildContext context,
    Key toolbarKey,
    LeaderLink focalPoint,
  ) {
    final ctrl = _controller;
    if (ctrl?.editor == null) return const SizedBox.shrink();

    return iOSSystemPopoverEditorToolbarWithFallbackBuilder(
      context,
      toolbarKey,
      focalPoint,
      RichCommonEditorOperations(
        editor: ctrl!.editor!,
        document: ctrl.editor!.document,
        composer: ctrl.composer!,
        documentLayoutResolver: () => _docLayoutKey.currentState as DocumentLayout,
      ),
      SuperEditorIosControlsScope.rootOf(context),
    );
  }
```

- [ ] **Step 5: Inicializar os controladores e configurar as Scopes no método build()**

No método `build()`, logo após a verificação onde garantimos que `controller.editor != null`, inicializar os controladores `_iosController` e `_androidController` caso ainda não tenham sido criados. Em seguida, envolver o `SuperEditor` em ambos os escopos de controle e passar a propriedade `keyboardActions` customizada:

```dart
    if (controller.document == null ||
        controller.editor == null ||
        controller.composer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    _iosController ??= RichSuperEditorIosControlsController(
      editor: controller.editor!,
      documentLayoutResolver: () => _docLayoutKey.currentState as DocumentLayout,
    );

    _androidController ??= SuperEditorAndroidControlsController(
      toolbarBuilder: (overlayContext, mobileToolbarKey, focalPoint) => defaultAndroidEditorToolbarBuilder(
        overlayContext,
        mobileToolbarKey,
        RichCommonEditorOperations(
          editor: controller.editor!,
          document: controller.editor!.document,
          composer: controller.composer!,
          documentLayoutResolver: () => _docLayoutKey.currentState as DocumentLayout,
        ),
        SuperEditorAndroidControlsScope.rootOf(overlayContext),
        controller.composer!.selectionNotifier,
        focalPoint,
      ),
    );
```

E alterar a renderização do `SuperEditor` para:

```dart
                    SuperEditorAndroidControlsScope(
                      controller: _androidController!,
                      child: SuperEditorIosControlsScope(
                        controller: _iosController!,
                        child: SuperEditor(
                          editor: controller.editor!,
                          focusNode: controller.focusNode,
                          documentLayoutKey: _docLayoutKey,
                          stylesheet: noteStylesheet(context),
                          keyboardActions: buildRichKeyboardActions(
                            baseActions: defaultTargetPlatform == TargetPlatform.iOS ||
                                    defaultTargetPlatform == TargetPlatform.android
                                ? defaultImeKeyboardActions
                                : defaultKeyboardActions,
                          ),
                          componentBuilders: [
                            ...defaultComponentBuilders,
                            CustomTaskComponentBuilder(
                              controller.editor!,
                              focusNode: controller.focusNode,
                              onTaskLongPress: (taskId) =>
                                  _openTaskActions(controller, taskId),
                            ),
                          ],
                        ),
                      ),
                    ),
```

- [ ] **Step 6: Commit**

```bash
git add lib/features/notes/presentation/note_editor_screen.dart
git commit -m "feat(notes): integrate rich keyboard and controls scope for rich copy/paste on iOS & Android"
```

---

### Task 5: Escrever Teste Unitário para as Ações Ricas

**Files:**
- Create: `test/features/notes/presentation/widgets/rich_clipboard_test.dart`

- [ ] **Step 1: Escrever teste unitário**

Criar o arquivo `test/features/notes/presentation/widgets/rich_clipboard_test.dart` para verificar se `buildRichKeyboardActions` adiciona corretamente as ações de copiar, colar e recortar de rich text no topo do pipeline de eventos.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_clipboard/super_editor_clipboard.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_keyboard_actions.dart';

void main() {
  group('Rich Keyboard Actions', () {
    test('buildRichKeyboardActions prepends rich clipboard actions at the start of actions list', () {
      final baseActions = <SuperEditorKeyboardAction>[
        doNothingWhenThereIsNoSelection,
      ];

      final richActions = buildRichKeyboardActions(baseActions: baseActions);

      expect(richActions.length, equals(4));
      expect(richActions[0], equals(copyAsRichTextWhenCmdCOrCtrlCIsPressed));
      expect(richActions[1], equals(cutAsRichTextWhenCmdXOrCtrlXIsPressed));
      expect(richActions[2], equals(pasteRichTextOnCmdCtrlV));
      expect(richActions[3], equals(doNothingWhenThereIsNoSelection));
    });
  });
}
```

- [ ] **Step 2: Executar testes para validar sucesso**

Executar os testes:
Run: `flutter test test/features/notes/presentation/widgets/rich_clipboard_test.dart`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add test/features/notes/presentation/widgets/rich_clipboard_test.dart
git commit -m "test(notes): add unit tests for rich clipboard keyboard actions builder"
```
