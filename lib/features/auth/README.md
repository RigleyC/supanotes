# Autenticação

`auth` obtém e renova a sessão, mas a identidade corrente é publicada por
`core/auth/current_user.dart` para que todas as features usem a mesma fonte.

- `data/auth_local_storage.dart`: persiste tokens no dispositivo.
- `data/auth_repository.dart`: fala com endpoints de registro, login, refresh e logout.
- `data/session_cache.dart`: mantém dados da sessão no processo.
- `presentation/controllers/auth_controller.dart`: `AsyncNotifier<User?>` que
  coordena bootstrap, login, refresh e logout.
- telas de login, cadastro e splash só mostram o estado fornecido pelo
  controller; não são donas da sessão.

O router observa o estado de autenticação. Ao mudar usuário, os providers que
dependem da identidade são recriados, inclusive a infraestrutura de notes.
