# Testes Flutter

A árvore de testes espelha `lib/`: `test/core/` para infraestrutura e
`test/features/<feature>/` para comportamento de produto.

Os testes de editor e sync são especialmente importantes porque protegem
invariantes de concorrência: duas aberturas da mesma nota, descarte durante
abertura, rebase, retry e projeção de tarefas. Ao alterar uma sessão, um codec
ou a outbox, comece pelos testes mais próximos e depois execute a suíte ampla.

Um teste não é evidência de sucesso se foi interrompido ou expirou; registre o
comando e o resultado observado.
