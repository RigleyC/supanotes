# Cliente HTTP

`ApiClient` centraliza URL-base, serialização HTTP e o cliente Dio. O
`AuthInterceptor` adiciona/renova credenciais; `api_exceptions.dart` converte
erros de transporte em erros que a UI e os repositórios conseguem tratar.

Features devem depender de seus próprios repositórios, não chamar Dio em uma
tela. Um repositório usa `ApiClient` quando precisa de um endpoint e traduz a
resposta para um modelo da feature.
