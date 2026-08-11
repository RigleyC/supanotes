# SupaNotes: matriz de cenários E2E

Esta matriz define a cobertura executável do fluxo ativo REST/OT. “Todos os
casos” significa todas as transições previstas pelo contrato atual do app; não
é possível provar todos os estados de rede, dispositivos e ações humanas com
um conjunto finito de testes.

## Garantia principal

Para cada nota aberta, o estado visível é:

```text
snapshot confirmado + operações pendentes da outbox
```

Uma operação local deve chegar ao SQLite antes de depender da rede. Reinício,
timeout, falha HTTP e troca de conta não podem apagar uma operação nem expô-la
à conta errada.

## Matriz

| Área | Cenário | Resultado esperado | Cobertura |
| --- | --- | --- | --- |
| Inicialização | Abrir nota com rede e snapshot remoto | snapshot local e projeções são hidratados | catálogo + contrato HTTP |
| Inicialização | Abrir nota cacheada sem rede | editor abre do snapshot local sem bloquear em HTTP | `integration_test/full_suite_test.dart` |
| Inicialização | Nota nova sem snapshot, editar, matar e reabrir sem rede | outbox pendente é reaplicada sobre o documento vazio | `integration_test/full_suite_test.dart` |
| Inicialização | Projeção de tarefas lenta durante a abertura | editor fica pronto com o documento local; a projeção termina em segundo plano | `test/features/notes/domain/sync_characterization_test.dart` |
| Inicialização | Edição local ocorre enquanto o snapshot remoto carrega | edição local permanece; hidratação remota obsoleta não é aplicada | `note_catalog_sync_test.dart` |
| Inicialização | Nota nova vazia ao sair | nota local-only é apagada; não há push vazio | catálogo/repositório |
| Persistência | Edição dentro do debounce seguida de dispose | edição é gravada antes do dispose | sessão/adapter |
| Persistência | Processo morre com operação `in_flight` | próxima sessão retoma a sessão persistida | sync service |
| Persistência | Falha de rede, retry, reconexão | operação mantém o mesmo ID, é aceita uma vez e a outbox esvazia | sync service + cliente HTTP |
| Persistência | Rede intermitente e resposta lenta | filas por nota permanecem serializadas; outra nota continua | sync service |
| Persistência | Ack duplicado/idempotência | não duplica bloco, revisão ou operação | backend + cliente |
| Integridade | 401/403/404/erro de protocolo | estado de erro é explícito; outbox não é descartada | auth/HTTP/sessão |
| Integridade | Payload inválido ou snapshot incompatível | erro de protocolo, sem sobrescrever estado local | adapter/backend |
| Integridade | Nota é removida entre a leitura local e a gravação remota | snapshot e tarefas não ficam órfãos sem linha no catálogo | `task_projection_engine_test.dart` |
| Documento | inserir, apagar, mover bloco | IDs e ordem convergem após polling/restart | adapter + OT |
| Documento | texto rico, heading, listas, divisor | delta e metadata preservam o conteúdo | codec/contrato |
| Tarefas | criar/editar/marcar/desmarcar task offline | task é operação do documento; projeção local é derivada | editor/projeção |
| Tarefas | duas ocorrências concorrentes e reabrir uma | uma ocorrência não apaga a outra | sync service/backend |
| Colaboração | dois usuários editam blocos distintos | ambos convergem para o snapshot canônico | cliente HTTP + backend |
| Colaboração | dois usuários editam o mesmo bloco | OT determinístico preserva as duas edições | backend OT + rebase |
| Colaboração | usuário com `edit` trabalha offline e reconecta | alteração é aceita após reconexão | compartilhamento + outbox |
| Colaboração | usuário com `view` abre nota | conteúdo é visível, captura local fica desativada e POST é recusado | catálogo/editor/backend |
| Colaboração | permissão é revogada durante edição | novas alterações não são enviadas; estado remoto não é sobrescrito | provider/sessão |
| Isolamento | duas contas no mesmo dispositivo | outbox, snapshot, sessão e projeção não vazam entre usuários | account-scope tests |
| Isolamento | logout com sessão aberta | sessão antiga fecha e callbacks tardios não alteram a nova conta | coordinator/auth |
| Concorrência | abrir a mesma nota duas vezes | um único owner e um único polling por `noteId` | coordinator |
| Concorrência | trocar A→B→A rapidamente | não há conteúdo residual nem cleanup tardio destrutivo | editor/provider |
| Concorrência | catálogo sincroniza enquanto editor está aberto | catálogo não sobrescreve a sessão ativa | catálogo/activity tracker |
| Concorrência | hidratação remota compete com uma edição local | comparação de versão recusa o remoto e preserva `isDirty` | `note_catalog_sync_test.dart` |
| Catálogo | remote delete, local tombstone e retry | exclusão é segura e recuperável durante falha | catálogo |
| Catálogo | sincronização inicial com muitas notas | todas as páginas são baixadas e o catálogo local é atualizado sem bloquear uma nota aberta | `test/features/notes/catalog/data/note_catalog_sync_provider_test.dart` |

## Limites que exigem validação em dispositivo

Os testes automatizados simulam queda de rede, latência e morte do processo
criando uma nova sessão sobre o mesmo SQLite. Ainda é necessário um smoke test
manual em Android/iOS para: forçar encerramento pelo sistema durante
digitação, suspensão/retomada, troca real de Wi-Fi/dados móveis e falta de
espaço no disco. Esses testes não devem substituir as asserções de outbox e
snapshot desta matriz.

Os testes não usam YDoc/Yjs, WebSocket, presença ou escrita direta na projeção
`tasks`; o caminho testado é o contrato REST/OT vigente.
