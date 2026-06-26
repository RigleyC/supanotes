# Design: AppMessenger Global

## Goal
Refatorar o `AppMessenger` para permitir chamadas globais sem `BuildContext`, simplificando a API para `showSnackBar(text: '...')` e permitindo extensões como o botão "Desfazer".

## Contexto Atual
- `AppMessenger` é uma classe com métodos estáticos que recebem `BuildContext`.
- Chamar de um `Service`/`Provider` exige propagar `context` ou usar `GlobalKey`.

## Proposta: Abordagem A (GlobalKey Estático)

### Arquitetura
```
AppMessenger (global key holder)
  ├── key: GlobalKey<ScaffoldMessengerState> (static)
  ├── showSuccess(String message, {Duration? duration})
  ├── showError(String message, {VoidCallback? onRetry, Duration? duration})
  ├── showInfo(String message, {Duration? duration})
  └── showAction(String message, {required SnackBarAction action, Duration? duration})

MaterialApp
  └── scaffoldMessengerKey: AppMessenger.key  // wiring único
```

### Regras de Design
1. **Não receber `BuildContext`**: A classe é totalmente autônoma.
2. **Tratar currentState nulo**: Se `AppMessenger.key.currentState` for nulo (App não montado), logar em debug e ignorar. Não lançar exceção.
3. **Manter `SnackBarThemeData`**: O tema global do `SnackBar` continua definido no `AppTheme`. `AppMessenger` apenas completa o `behavior` e a cor base.
4. **Limpar `completeTaskWithFeedback`**: Remover daqui e devolver à camada de tarefas (responsabilidade única).
5. **Testabilidade**: A `GlobalKey` pode ser mockada/setada manualmente em testes.

### API Pública
```dart
/// Mostra um SnackBar de sucesso (verde)
AppMessenger.showSuccess('Salvo com sucesso!');

/// Mostra um SnackBar de erro (vermelho)
AppMessenger.showError('Falha na conexão', onRetry: () => refetch());

/// Mostra um SnackBar informativo (padrão do tema)
AppMessenger.showInfo('Sync realizado');

/// Mostra um SnackBar com ação customizada
AppMessenger.showAction(
  'Nota excluída',
  action: SnackBarAction(label: 'Desfazer', onPressed: () => undo()),
);
```

### Benefícios
- **Simplicidade**: API direta, sem necessidade de `context`.
- **Descentralização**: Services e Providers podem notificar sem acoplamento à árvore de widgets.
- **Testabilidade**: Chave mockável.