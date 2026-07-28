# Shared: apresentação reutilizável

`shared` é a biblioteca visual interna. Não contém regra de sync, acesso ao
banco ou políticas de domínio.

- `theme/`: cores, tipografia, espaçamento e `ThemeData` do aplicativo.
- `widgets/`: `AppButton`, `AppInput`, `AppErrorView`, bottom sheet, diálogo de
  confirmação, snackbars e controles comuns.

Uma feature usa esses componentes para manter acessibilidade e aparência
consistentes. Se um componente precisar conhecer uma regra de uma feature, ele
não deve entrar em `shared`; coloque-o na feature e reutilize somente quando
houver uma necessidade real em mais de um domínio.
