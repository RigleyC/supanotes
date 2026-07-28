# Injeção de dependências

`providers.dart` é o grafo de composição do cliente. Ele declara qual objeto
é criado, de que depende e em qual ciclo de vida ele vive.

Não instancie `AppDatabase`, `ApiClient`, `NoteOperationsSyncService` ou
`NoteSessionCoordinator` dentro de widgets. Leia o provider apropriado. Ao
precisar adicionar uma dependência de aplicativo, declare-a aqui, defina seu
descarte com `ref.onDispose` quando necessário e mantenha-a `autoDispose` salvo
uma razão explícita para a duração maior.
