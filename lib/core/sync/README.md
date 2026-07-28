# Sincronização REST/OT

`NoteOperationsSyncService` é o adaptador entre a outbox Drift e os endpoints
de operações. Ele não conhece widgets nem `MutableDocument`.

## Interface útil

| Método | Efeito |
| --- | --- |
| `enqueueOperation` | persiste uma operação local ordenada na outbox |
| `syncPending` | envia todas as operações pendentes de uma nota e confirma o snapshot |
| `pollAndReconcile` | busca operações posteriores à revisão confirmada |
| `getConfirmedDocument` | lê o snapshot local confirmado |
| `loadPendingProjection` | lê as operações ainda não confirmadas para rebase |

## Por que há uma sessão de sync persistida?

Antes do HTTP, as operações são marcadas `in_flight` e uma `sync_session` é
gravada na mesma transação. Se o processo morrer, a próxima tentativa retoma
ou devolve essas operações a `pending`; assim uma operação não desaparece por
uma queda entre envio e resposta.

## Ligações

- O editor produz operações em [Notes editor](../../features/notes/editor/README.md).
- O transporte é `NoteSyncClient`.
- O servidor aplica o contrato em [noteoperations](../../../backend/internal/noteoperations/README.md).
