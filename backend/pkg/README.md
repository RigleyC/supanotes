# Pacotes técnicos do backend

`pkg/` não conhece regras específicas de notas. Ele fornece adaptadores para:

- `auth/`: JWT, senha e refresh token;
- `config/`: variáveis de ambiente e configurações derivadas;
- `db/`: conexão pgx;
- `migrate/`: execução de migrations;
- `uid/`: geração de identificadores.

Uma regra de negócio não deve viver aqui. Se algo precisa conhecer nota, tarefa
ou compartilhamento, ele pertence a `internal/`.
