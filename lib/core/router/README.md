# Navegação

`app_routes.dart` concentra nomes e parâmetros de rotas. `app_router.dart`
monta `GoRouter` e o shell adaptativo de notes. `auth_guard.dart` traduz o
estado de autenticação em redirecionamento.

Uma rota escolhe a tela; ela não deve carregar dados de domínio nem repetir a
autorização do backend. Telas recebem o identificador da rota e observam o
provider da própria feature.
