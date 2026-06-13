# Especificação de Design: Copiar e Colar com Formatação (Rich Copy/Paste)

Este documento descreve a arquitetura e o design técnico para permitir que a cópia e colagem dentro do aplicativo SupaNotes (e na interação com aplicativos externos) preserve a formatação rica, como negritos, itálicos, títulos e listas.

## Problema e Contexto

Atualmente, o `SuperEditor` no SupaNotes utiliza a classe padrão `CommonEditorOperations` e atalhos que transferem texto simples. Isso faz com que toda a formatação (estilos visuais, tarefas, cabeçalhos, etc.) seja descartada durante operações de copiar/colar internamente ou na troca de conteúdo com outros aplicativos (como Word, Notion ou navegadores web).

## Solução Proposta

Utilizaremos o pacote `super_editor_clipboard` (e seu motor de baixo nível `super_clipboard`) para interceptar e gerenciar a transferência do conteúdo da área de transferência em formato rico (HTML/Markdown) com suporte a fallback em texto plano.

## Alterações Propostas

### 1. Atalhos de Teclado Ricos

Implementaremos comportamentos customizados para interceptar atalhos físicos de teclado:
* **Cópia (Cmd/Ctrl + C)**: Mapeado para `copyAsRichTextWhenCmdCOrCtrlCIsPressed`.
* **Colagem (Cmd/Ctrl + V)**: Mapeado para `pasteRichTextOnCmdCtrlV`.
* **Recorte (Cmd/Ctrl + X)**: Implementaremos a função `cutAsRichTextWhenCmdXOrCtrlXIsPressed` para copiar no formato rico e apagar o trecho selecionado em seguida.

### 2. Ações na Barra de Ferramentas (Menus Flutuantes)

Implementaremos a classe `RichCommonEditorOperations` herdando de `CommonEditorOperations` para que os cliques nos botões flutuantes executem cópias e colagens ricas.

### 3. Integração em Sistemas Operacionais (iOS/Android)

Modificaremos o arquivo `note_editor_screen.dart`:
* Envolveremos o editor com escopos de controle específicos para Android e iOS (`SuperEditorAndroidControlsScope` e `SuperEditorIosControlsScope`).
* Criaremos um controlador customizado para iOS (`RichSuperEditorIosControlsController` herdando de `SuperEditorIosControlsControllerWithNativePaste`) para interceptar e permitir colagens com formatação a nível de sistema operacional (iOS 16+).
* Criaremos um controlador customizado para Android (`SuperEditorAndroidControlsController`), configurando o `toolbarBuilder` padrão do Android para usar `RichCommonEditorOperations`.

---

## Verificação e Testes

### Verificação Manual
1. **Copiar e Colar Interno**: Copiar um trecho de uma nota com formatação (título, negrito, itálico e item de checklist) e colar na mesma nota ou em outra nota no app. O conteúdo deve reter o mesmo estilo.
2. **Copiar do App para o Exterior**: Copiar uma nota formatada no SupaNotes e colar em um editor de rich text externo (como Notion ou Google Docs). O conteúdo deve ser colado mantendo o estilo (em vez de em Markdown cru).
3. **Copiar do Exterior para o App**: Copiar um texto formatado de uma página da web e colar no SupaNotes. O conteúdo deve ser traduzido apropriadamente em nós de texto formatados.
