# Core: infraestrutura compartilhada do Flutter

`core` não implementa uma tela ou um caso de uso de produto. Ele oferece os
adaptadores que várias features usam.

| Pasta | Responsabilidade | Ligações |
| --- | --- | --- |
| `api/` | `ApiClient`, interceptador de autenticação e mapeamento de erros | Backend HTTP e `auth` |
| `auth/` | Identidade autenticada corrente | DI, router e repositórios por usuário |
| `database/` | Drift, tabelas e DAOs do dispositivo | Catálogo, tarefas e sync |
| `di/` | Providers de longa duração e composição de dependências | Todas as features |
| `router/` | Rotas, guarda de autenticação e shell desktop | Telas de `features` |
| `sync/` | Outbox e protocolo REST/OT independente da UI | Editor de notes |
| `notifications/` | Agendamento local de lembretes | Tasks |
| `utils/`, `validators/`, `constants/`, `debug/` | Funções puras, validação e observabilidade | Chamadores específicos |

## DI e duração de objetos

[di/providers.dart](di/providers.dart) é o lugar que monta dependências que
precisam compartilhar identidade e ciclo de vida: banco, cliente HTTP,
repositório de autenticação, `NoteOperationsSyncService` e
`NoteSessionCoordinator`. Providers comuns usam `autoDispose`; somente os
objetos de aplicativo ou de sessão autenticada ficam vivos.

## Banco e sync

Leia [database](database/README.md) antes de alterar uma tabela ou DAO. Leia
[sync](sync/README.md) antes de alterar a outbox ou o protocolo de notas.

## Router

`app_router.dart` declara as rotas; `auth_guard.dart` impede que rotas
protegidas renderizem antes de a autenticação resolver. O router somente
decide a composição de telas: regras de acesso a uma nota continuam no dado e
no backend.
