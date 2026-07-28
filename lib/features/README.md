# Features: comportamento do produto

Cada pasta em `features/` é dona de um conjunto de casos de uso. Uma feature
pode usar `core` e `shared`, mas não deve alcançar internals de outra feature
sem um contrato claro.

| Feature | Dono do quê | Guia |
| --- | --- | --- |
| `auth` | sessão, login, cadastro e renovação de token | [auth](auth/README.md) |
| `notes` | catálogo, documento, editor, compartilhamento e anexos | [notes](notes/README.md) |
| `tasks` | projeções, recorrência, metadados e lembretes | [tasks](tasks/README.md) |
| `settings` | preferências da conta e configuração MCP | [settings](settings/README.md) |

Uma feature normalmente separa `data` (adapta banco/API), `domain` (modelo e
regras puras), `application` ou `controllers` (coordenação de estado) e
`presentation` (widgets/telas). Notes usa submódulos nomeados porque é grande.

Para a relação arquivo/classe/método das outras features, consulte [features-file-reference](../../docs/architecture/features-file-reference.md).
