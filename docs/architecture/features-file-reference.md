# Features: referência de arquivos e classes

## Auth

| Arquivo | Classe/provider | Por que existe |
| --- | --- | --- |
| `auth/domain/user.dart` | `User`, `SessionData`, `AuthResult` | Tipos de identidade e resultado; evita que telas conheçam JSON de autenticação. |
| `auth/data/auth_local_storage.dart` | storage de tokens | Isola persistência de credenciais do controller. |
| `auth/data/auth_repository.dart` | `AuthRepository` | `login`, `register`, `refresh` e `logout` adaptam API para tipos de domínio. |
| `auth/data/session_cache.dart` | `SessionCache` | Mantém dados da sessão corrente no processo e emite mudanças quando usuário troca. |
| `auth/presentation/controllers/auth_controller.dart` | `AuthController` | `build` restaura sessão; métodos de login/register/logout/refresh alteram um único `AsyncValue<User?>`. |
| `auth/presentation/*_screen.dart` | telas | Renderizam loading, erro e dados; não persistem token nem chamam API diretamente. |

## Tasks

| Arquivo | Classe/provider | Métodos-chave e motivo |
| --- | --- | --- |
| `tasks/domain/task_occurrence.dart` | `TaskOccurrence` | `buildOccurrences` expõe a ocorrência atual em estado pending/overdue/completed; não cria uma fila de ocorrências perdidas. |
| `tasks/domain/task_recurrence.dart` | `TaskRecurrence` | Faz parse e cálculo de próxima ocorrência; concentra bordas de calendário. |
| `tasks/domain/task_completion_command.dart` | `TaskCompletionCommand` | Resultado e snapshot para completar/reabrir; mantém undo com a ocorrência correta. |
| `tasks/domain/task_date_filter.dart`, `task_date_format.dart` | filtros/formatadores | Regras puras para listas e apresentação, testáveis sem banco. |
| `tasks/domain/task_notification_scheduler.dart` | `TaskNotificationScheduler` | Observa tarefas abertas e agenda notificações locais; não altera documento. |
| `tasks/presentation/controllers/task_metadata_controller.dart` | controller de sheet | Controla seleção de data/hora/recorrência com estado local da UI. |
| `tasks/presentation/controllers/task_snackbar_helper.dart` | `TaskSnackBarHelper` | Coordena feedback/undo e chama callback que altera o editor. |
| `tasks/presentation/widgets/task_metadata_sheet.dart` e páginas | widgets | Coletam metadata; ao salvar, delegam ao controller do editor. |
| `tasks/presentation/widgets/task_metadata_badges.dart` | widget | Renderiza o estado da ocorrência; não persiste checkbox diretamente. |

## Settings

| Arquivo | Classe/provider | Por que existe |
| --- | --- | --- |
| `settings/data/settings_models.dart` | `UserSettings` | Contrato tipado de preferências da conta. |
| `settings/data/settings_repository.dart` | `ISettingsRepository`, `SettingsRepository` | Traduz GET/PUT de settings e esconde API da UI. |
| `settings/presentation/controllers/preferences_controller.dart` | `PreferencesController`, providers | Estado compartilhado de preferências visuais como grid/lista; não deve carregar preferências de `noteId`. |
| `settings/presentation/settings_screen.dart` | `SettingsScreen` | Composição da tela e ações de configuração. |
| `settings/presentation/mcp_screen.dart` | `McpScreen` | Explica token e integração MCP; token é obtido no backend, não inventado na UI. |
| `settings/presentation/widgets/settings_tile.dart` | `SettingsTile` | Componente visual reutilizável dentro da feature. |

## Shared

`shared/theme/*` define tokens visuais. `shared/widgets/app_button.dart`,
`app_input.dart`, `app_bottom_sheet.dart`, `confirm_dialog.dart`,
`app_error_view.dart`, `app_snackbar.dart` e `app_task_checkbox.dart` são
componentes profundos: recebem estado e callbacks pequenos e escondem detalhes
de aparência/acessibilidade. Eles não devem importar repositórios ou providers
de features.
