# Configurações

`settings/` trata preferências da conta, diferentes das preferências de uma
nota em `notes/preferences/`.

- `data/settings_repository.dart`: adaptador HTTP e cache de configurações.
- `data/settings_models.dart`: modelos transportados entre API, repositório e UI.
- `presentation/controllers/preferences_controller.dart`: estado compartilhado
  de preferências da interface, como modo de grade/lista.
- `settings_screen.dart`: tela principal; `mcp_screen.dart`: instruções e token
  para clientes MCP.

Use esta feature para uma preferência do usuário que faz sentido sem uma nota
aberta. Use `notes/preferences` quando a preferência depende de `noteId`.
