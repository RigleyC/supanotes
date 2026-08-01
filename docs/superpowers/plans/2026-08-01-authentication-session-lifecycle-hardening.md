# Plano de Implementacao: lifecycle de autenticacao e sync

## Objetivo

Garantir que a sessao autenticada tenha uma fronteira unica no backend e no
Flutter, sem perder dados locais, misturar contas ou esconder conflitos de
sync como uma fila vazia.

## Entregas desta fatia

- Commitar a revogacao de toda a familia quando houver reuse de refresh token.
- Tornar issuer e audience obrigatorios na API JWT.
- Manter o construtor de producao do `ApiClient` em um unico caminho de
  refresh baseado no `AuthTokenManager`.
- Limpar buckets expirados do rate limiter e aplicar a politica ao OAuth Alexa.
- Serializar login, registro, logout e expiracao no `AuthController`.
- Impedir que uma leitura inicial tardia sobrescreva o token em memoria.
- Preservar o proprietario real de notas compartilhadas no catalogo local.
- Expor estado explicito para uma sessao de sync pertencente a outra conta.
- Cobrir revogacao de reuse por uma transacao PostgreSQL real em teste opt-in.

## Verificacao

- Testes Go focados de auth, JWT e Alexa.
- Testes Flutter de token manager, auth state e sync characterization.
- `flutter analyze` nos modulos alterados.
- Suite completa Flutter e Go antes do commit.

## Pendencias conhecidas

- Persistir `ownerUserId` nos erros de sync exige nova migracao Drift e fica
  como proxima fatia, sem alterar o contrato REST/OT canonico.
- A rotacao de refresh tokens da Alexa ainda precisa de deteccao de reuse por
  familia, separada da rotacao atomica do authorization code.
