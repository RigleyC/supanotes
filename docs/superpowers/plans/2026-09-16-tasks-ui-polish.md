# Tasks UI polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajustar a apresentação da aba Tasks sem alterar o componente de task do editor de notas.

**Architecture:** A lista global usará seu próprio `TaskListTile`, com checkbox e conteúdo textual em uma composição simples de `Padding`, `Row` e `Column`. A navegação continuará adaptativa; o shell exibirá destinos sem texto, e a tela de Tasks usará o FAB compartilhado e um espaçador inferior compatível com a navbar sobreposta.

**Tech Stack:** Flutter, `adaptive_platform_ui`, Riverpod manual e componentes compartilhados de `lib/shared/widgets`.

**Spec:** `docs/superpowers/specs/2026-09-03-standalone-tasks-tabs-design.md`

## Global Constraints

- `CustomTaskComponent` permanece exclusivo do editor de notas.
- Não escrever diretamente na tabela de tasks para tasks que pertencem a notas.
- Não adicionar testes de pixels, geometria ou aparência visual.
- Usar `AppButton` para o FAB e preservar os componentes compartilhados existentes.
- Preservar mudanças não relacionadas já presentes no worktree.

---

### Task 1: Refinar o tile da lista global

**Files:**
- Modify: `lib/features/tasks/presentation/widgets/task_list_tile.dart`
- Modify: `lib/features/tasks/presentation/tasks_screen.dart`
- Test: `test/features/tasks/presentation/tasks_screen_test.dart`

**Interfaces:**
- `TaskListTile` continua recebendo um `TaskListItem`, callbacks de conclusão e abertura, e renderiza somente a lista global.
- O lado esquerdo mantém alvo de toque mínimo de 48×48 e o lado direito abre o editor/modal correspondente.

- [x] Confirmar que o tile não importa `CustomTaskComponent` nem dependências do SuperEditor.
- [x] Organizar o conteúdo com `Padding`, `Row`, checkbox à esquerda e `Column` textual à direita.
- [x] Renderizar cada metadado apenas quando seu valor opcional estiver presente.
- [x] Preservar a ordenação por data e a conclusão das tasks de nota pelo controlador canônico já existente.
- [x] Rodar `flutter test test/features/tasks/presentation/tasks_screen_test.dart`.

### Task 2: FAB e espaçamento da lista

**Files:**
- Modify: `lib/features/tasks/presentation/tasks_screen.dart`
- Test: `test/features/tasks/presentation/tasks_screen_test.dart`

**Interfaces:**
- A tela fornece `floatingActionButton: AppButton(variant: AppButtonVariant.fab, ...)`.
- O fim do `CustomScrollView` reserva espaço para a área segura/navbar sobreposta antes do link de concluídas.

- [x] Remover o botão inline “Nova task” do corpo.
- [x] Posicionar o FAB no `AdaptiveScaffold` usando `AppButtonVariant.fab`.
- [x] Adicionar espaçamento inferior baseado no `MediaQuery`/inset disponível, mantendo o item de concluídas clicável.
- [x] Rodar o teste comportamental da tela e `git diff --check`.

### Task 3: Navbar somente com ícones

**Files:**
- Modify: `lib/shared/widgets/app_navigation_shell.dart`
- Test: testes comportamentais de roteamento existentes, sem assertions visuais

**Interfaces:**
- As duas destinations continuam com os mesmos ícones, índices e callbacks, mas sem nomes exibidos.
- O comportamento de minimização/blur da navbar não será alterado.

- [x] Remover os textos visíveis “Tasks” e “Notas” da configuração dos destinos, usando destinos sem label visível.
- [x] Manter `useNativeBottomBar` e o comportamento de scroll existentes.
- [x] Rodar os testes de roteamento/navegação relacionados.

### Task 4: Corrigir fundo da AppBar adaptativa

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/features/tasks/presentation/tasks_screen.dart`
- Test: testes comportamentais de tasks existentes

**Interfaces:**
- O tema Cupertino recebe as mesmas cores semânticas do tema Material atual.
- A AppBar continua adaptativa e sem título, mas não troca para branco quando o conteúdo passa sob a barra.

- [x] Injetar `CupertinoTheme` no builder da aplicação para light/dark.
- [x] Definir explicitamente as cores de fundo da navegação Cupertino usadas pela tela Tasks.
- [x] Preservar o popup de filtro e os ícones adaptativos.
- [x] Rodar `flutter analyze` nos arquivos alterados e os testes focados de tasks.

---
