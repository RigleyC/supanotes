# Especificação: ownership de estado, ciclo de vida e segurança

**Data:** 2026-07-26  
**Status:** Pronta para implementação  
**Escopo:** Flutter, Riverpod, REST/OT, anexos e prévia de links

## Problem Statement

O SupaNotes usa Riverpod, objetos mutáveis do editor, Drift, uma outbox REST/OT e serviços de backend. Cada parte atende a uma necessidade válida. Porém, o projeto não define um proprietário único para a sessão ativa de cada nota.

Uma nota aberta pode ter estado simultâneo no banco local, no documento mutável, no controller do editor, na sessão de sincronização, no serviço de sincronização e na projeção de tarefas. Uma nova sessão pode iniciar antes de a sessão anterior terminar o descarte. Providers com ciclo de vida curto também podem criar mais de uma instância de serviços que deveriam coordenar trabalho por nota.

O estado temporário de preferências, compartilhamento e metadados de tarefas também tem limites inconsistentes. Algumas operações locais usam estado global. Algumas dependências de longa duração usam descarte automático. Algumas mutações otimistas podem desfazer uma alteração mais nova.

O backend tem dois problemas de segurança relacionados a esse conjunto de fluxos. O upload de anexos autentica o usuário, mas não confirma que ele pode editar a nota informada. A prévia de links busca URLs informadas pelo usuário sem restringir destinos de rede privados. O upload também não aplica um limite global ao corpo HTTP antes do processamento multipart. O cache de prévias não tem limite nem expiração.

Esses problemas podem causar edição concorrente da mesma nota, corridas durante abertura e fechamento, recursos não liberados, estados de UI incorretos, perda de preferências, acesso indevido a anexos, uso indevido da rede do servidor e crescimento contínuo de memória.

## Solution

O sistema terá regras explícitas de ownership e ciclo de vida.

Cada nota aberta terá uma única sessão de nota por usuário e por processo. Essa sessão será o único proprietário do documento mutável, editor, adapter REST/OT, polling, projeção de tarefas e descarte. Riverpod publicará o estado e administrará a identidade da sessão, mas não dividirá o ownership dos recursos internos entre vários providers.

O serviço que serializa a outbox terá duração igual à sessão autenticada. Todas as sessões de nota do mesmo usuário usarão a mesma instância. A fila continuará separada por nota. Abrir a mesma nota novamente reutilizará a sessão existente ou aguardará seu fechamento. O sistema não manterá duas sessões operacionais para a mesma nota.

A criação da sessão será transacional. Se qualquer etapa falhar, todos os recursos já criados serão liberados. O fechamento terá estados observáveis, cancelará novos trabalhos, fará o flush necessário e terminará antes de uma substituição. A UI poderá mostrar falhas de abertura, sincronização e fechamento sem depender somente de logs.

O estado global conterá somente dados globais. O estado por nota ficará na sessão da nota. Estado de formulário e modal será local ou terá descarte automático. Mutações de preferências serão serializadas ou versionadas. Operações de compartilhamento serão isoladas por nota.

No backend, o serviço de anexos receberá a identidade do usuário e exigirá permissão de edição na nota antes de enviar dados ao armazenamento. O limite de upload será aplicado na entrada HTTP e novamente no leitor enviado ao armazenamento. A prévia de links aceitará somente HTTP e HTTPS públicos, validará cada resolução e cada redirecionamento e usará um cache limitado com expiração.

## User Stories

1. Como usuário, quero que somente uma sessão edite uma nota no meu dispositivo, para que minhas alterações não sejam processadas duas vezes.
2. Como usuário, quero reabrir uma nota logo após fechá-la, para que eu não encontre uma sessão antiga ainda ativa.
3. Como usuário, quero alternar rapidamente entre notas, para que cada nota mantenha seu próprio documento e sua própria fila de operações.
4. Como usuário, quero que uma falha ao abrir uma nota libere todos os recursos, para que o aplicativo continue estável.
5. Como usuário, quero receber um estado de erro quando a sessão da nota não iniciar, para que eu possa tentar novamente.
6. Como usuário, quero que o aplicativo preserve edições locais quando eu fechar uma nota, para que nenhuma edição confirmada na interface seja perdida.
7. Como usuário, quero que o fechamento termine de forma segura, para que uma nova sessão não concorra com a anterior.
8. Como usuário, quero que edições feitas sem conexão permaneçam na outbox, para que sejam enviadas quando a conexão voltar.
9. Como usuário, quero que duas notas sincronizem de forma independente, para que uma nota lenta não bloqueie outra.
10. Como usuário, quero que todas as operações da mesma nota sejam serializadas, para que a projeção local permaneça consistente.
11. Como usuário, quero que o logout encerre as sessões do usuário anterior, para que outro usuário não receba estado ou trabalho pendente dessa conta.
12. Como usuário, quero que uma troca de conta não cause exceções de valor nulo no editor, para que o aplicativo volte à autenticação de forma segura.
13. Como usuário, quero ver quando uma nota está abrindo, pronta, sincronizando, fechando ou com erro, para que o comportamento seja previsível.
14. Como usuário, quero que uma falha temporária de sincronização seja visível e recuperável, para que eu saiba que ainda há trabalho pendente.
15. Como usuário, quero que o estado visível da nota derive do snapshot confirmado e da outbox, para que o editor represente a projeção correta.
16. Como usuário, quero que a projeção de tarefas acompanhe o documento visível, para que tarefas não fiquem diferentes do conteúdo da nota.
17. Como usuário, quero que uma falha na projeção de tarefas seja registrada e recuperável, para que o sistema não esconda uma divergência permanente.
18. Como usuário, quero alterar a visualização entre lista e grade sem perder uma mudança mais recente, para que toques rápidos não restaurem valores antigos.
19. Como usuário, quero que uma falha ao salvar preferências desfaça somente a alteração que falhou, para que outras preferências sejam preservadas.
20. Como usuário, quero ver o estado de gravação de preferências, para que a interface evite solicitações incompatíveis.
21. Como usuário, quero que o modal de compartilhamento mostre somente a operação da nota atual, para que outra nota não altere seu loading ou erro.
22. Como usuário, quero compartilhar e revogar acessos em notas diferentes, para que cada resultado seja aplicado à nota correta.
23. Como usuário, quero que o formulário de metadados de tarefa seja descartado quando o modal fechar, para que uma tarefa nova não receba dados antigos.
24. Como usuário, quero que uma falha ao salvar metadados preserve o formulário aberto, para que eu possa corrigir ou tentar novamente.
25. Como usuário, quero que cancelar um modal não grave alterações, para que o cancelamento tenha comportamento claro.
26. Como proprietário de uma nota, quero anexar arquivos à minha nota, para que o conteúdo possa incluir documentos e imagens.
27. Como colaborador com permissão de edição, quero anexar arquivos à nota compartilhada, para que eu possa contribuir com o conteúdo.
28. Como colaborador com permissão de visualização, quero que o servidor recuse uploads, para que minha permissão seja respeitada.
29. Como usuário autenticado sem acesso a uma nota, quero que o servidor recuse o upload, para que notas de terceiros fiquem protegidas.
30. Como operador do serviço, quero limitar o corpo de uploads antes do parsing, para que uma solicitação grande não consuma recursos excessivos.
31. Como operador do serviço, quero limitar também os bytes lidos e enviados ao armazenamento, para que metadados incorretos não removam a proteção.
32. Como usuário, quero receber um erro claro quando o arquivo exceder o limite, para que eu possa escolher outro arquivo.
33. Como operador do serviço, quero que falhas após o envio ao armazenamento sejam compensadas, para que objetos órfãos não se acumulem.
34. Como usuário, quero gerar prévias somente para endereços web públicos, para que o recurso seja seguro.
35. Como operador do serviço, quero bloquear loopback, redes privadas, link-local e destinos reservados, para que o servidor não seja usado para alcançar recursos internos.
36. Como operador do serviço, quero validar cada redirecionamento, para que um endereço público não redirecione para uma rede bloqueada.
37. Como operador do serviço, quero restringir os esquemas aceitos a HTTP e HTTPS, para que protocolos indevidos não sejam processados.
38. Como operador do serviço, quero limitar o tamanho e o tempo da resposta de prévia, para que servidores remotos não mantenham recursos ocupados.
39. Como operador do serviço, quero um cache de prévias com TTL e tamanho máximo, para que o uso de memória seja limitado.
40. Como operador do serviço, quero deduplicar buscas simultâneas da mesma URL, para que o backend não faça trabalho repetido.
41. Como mantenedor, quero testes de ciclo de vida no limite da sessão de nota, para que refactors internos não quebrem o comportamento.
42. Como mantenedor, quero testes HTTP de autorização de anexos, para que toda permissão seja validada no servidor.
43. Como mantenedor, quero testes de destinos bloqueados na prévia de links, para que mudanças no cliente HTTP não reabram SSRF.
44. Como mantenedor, quero uma matriz documentada de escopos de provider, para que novos providers tenham um ciclo de vida coerente.
45. Como mantenedor, quero remover registros estáticos de sessão usados como ownership, para que o container tenha uma única autoridade de ciclo de vida.
46. Como mantenedor, quero que dependências de infraestrutura não usem descarte automático sem necessidade, para que locks e filas não sejam recriados de forma inesperada.
47. Como mantenedor, quero que cada operação assíncrona tenha cancelamento ou proteção contra resultado obsoleto, para que respostas antigas não substituam estado novo.
48. Como mantenedor, quero que erros esperados façam parte do estado, para que logs não sejam a única forma de detectar falhas.

## Implementation Decisions

### 1. Modelo de ownership no Riverpod

- O projeto continuará a usar Riverpod. Esta especificação não substitui Riverpod por BLoC, Redux ou outro framework.
- O container da aplicação terá quatro classes de estado: infraestrutura, sessão autenticada, sessão de nota e estado efêmero de UI.
- Infraestrutura inclui banco local, armazenamento seguro, cliente HTTP e serviços sem estado específico de usuário. Esses providers têm duração da aplicação e fazem descarte explícito quando o recurso exigir.
- A sessão autenticada inclui identidade, cache de configurações, serviço REST/OT e coordenadores dependentes do usuário. Esses providers são recriados somente quando a identidade autenticada muda.
- A sessão de nota é uma família indexada pelo identificador da nota. Ela possui todos os recursos mutáveis necessários para editar e sincronizar essa nota.
- Estado efêmero de UI permanece no widget quando não precisa sobreviver à UI. Quando um provider for necessário, ele usa descarte automático e a chave mínima que identifica a tela ou entidade.
- Providers de consulta que apenas expõem streams do Drift podem continuar como `StreamProvider.autoDispose.family`.
- Providers de comando não usam `void` global quando duas entidades podem executar o comando em paralelo. O estado deve ser isolado por entidade ou o comando deve retornar seu resultado diretamente.
- O código não usa `ref.read` para obter uma dependência com descarte automático que precisa permanecer viva durante todo o ciclo do consumidor. A dependência deve ser observada, promovida para um escopo mais longo ou passada pelo proprietário explícito.
- O sistema não usa um mapa estático como fonte de ownership de sessões. Métricas ou inspeção podem manter registros fracos, mas eles não podem controlar o ciclo de vida.

### 2. Estado da sessão de nota

- A sessão de nota terá estados explícitos: `opening`, `ready`, `syncing`, `closing`, `closed` e `error`.
- Uma sessão `ready` expõe uma fachada estável para a UI. A UI não acessa campos parcialmente inicializados ou anuláveis do controller.
- O documento mutável, composer, editor, adapter, timer e projeção de tarefas são criados e descartados pela mesma sessão.
- O registro de cleanup ocorre antes da primeira operação assíncrona que pode falhar.
- Uma falha de inicialização executa rollback de todos os recursos já criados.
- O fechamento é idempotente. Chamadas repetidas retornam o mesmo trabalho de fechamento.
- Após iniciar o fechamento, a sessão não aceita novas mutações locais.
- O fechamento cancela polling, finaliza a captura local, persiste a outbox e libera recursos. Uma falha de rede não remove operações persistidas.
- Abrir uma nota já aberta reutiliza a sessão pronta. Se a sessão estiver fechando, a abertura aguarda o fechamento e cria uma nova sessão.
- O coordenador impede duas sessões operacionais para a mesma nota dentro do mesmo container.
- A troca de usuário encerra ou invalida todas as sessões do usuário anterior antes de expor providers dependentes do novo usuário.

### 3. Serviço REST/OT e concorrência

- O serviço REST/OT tem duração da sessão autenticada, não da tela do editor.
- Todas as sessões de nota do mesmo usuário compartilham a mesma instância do serviço.
- A fila de serialização continua separada por nota. Operações de notas diferentes podem ocorrer em paralelo.
- Enfileirar, sincronizar, consultar o servidor, reconciliar, projetar e fazer flush respeitam o mesmo limite de serialização por nota quando alteram estado relacionado.
- A outbox persistida continua a ser a fonte de recuperação após falha, fechamento ou reinício.
- A sessão não depende de polling para preservar operações locais.
- Erros transitórios mantêm a outbox e produzem estado recuperável. Erros de protocolo produzem estado de erro não silencioso.
- A projeção de tarefas não pode competir com dois documentos visíveis da mesma nota.

### 4. Preferências

- O cache da sessão continua a ser a fonte reativa das preferências confirmadas e otimistas.
- As mutações de preferências são serializadas ou recebem um número de versão.
- Um rollback só ocorre se o valor atual ainda foi produzido pela operação que falhou.
- O rollback altera somente os campos da mutação. Ele não restaura um snapshot completo que possa conter valores antigos de outros campos.
- O estado da mutação expõe `idle`, `saving` e `error` ou uma representação equivalente.
- O backend continua a aceitar o objeto flexível de preferências. A validação de valores conhecidos permanece no cliente.

### 5. Compartilhamento

- O estado de compartilhar e revogar acesso é isolado por nota.
- Uma operação mais antiga não pode substituir o resultado de uma operação mais nova da mesma nota.
- A lista de compartilhamentos continua a ser uma consulta independente e invalidável por nota.
- A UI interpreta sucesso ou erro a partir do resultado da operação que ela iniciou, não a partir de um estado global compartilhado.

### 6. Metadados de tarefas

- O formulário de metadados é estado efêmero.
- O estado é criado com os dados da tarefa ao abrir o modal e é descartado ao fechar.
- Fechar por cancelamento não persiste alterações.
- Confirmar inicia a persistência. O modal só fecha após sucesso ou mantém os valores e mostra erro.
- Solicitar permissão de notificação não impede o descarte do estado do formulário.
- Cada tarefa tem estado independente quando dois fluxos de UI coexistirem.

### 7. Autorização e limites de anexos

- O serviço de anexos recebe a identidade autenticada em todas as operações.
- O upload exige que o usuário seja proprietário da nota ou tenha permissão `edit`.
- Permissão `view`, ausência de compartilhamento, nota removida e usuário inválido produzem recusa sem enviar bytes ao armazenamento.
- A autorização ocorre no servidor e não depende do cliente Flutter.
- O corpo HTTP tem um limite ligeiramente maior que o limite permitido para o arquivo, para acomodar o envelope multipart.
- O leitor do arquivo também tem limite estrito. O serviço não confia somente no tamanho informado pelo multipart.
- Tamanho negativo, ausente ou inconsistente é rejeitado ou medido de forma segura.
- O tipo MIME declarado pelo nome do arquivo não é tratado como prova do conteúdo.
- Se o objeto chegar ao armazenamento e a gravação de metadados falhar, o serviço tenta remover o objeto ou registra uma compensação durável.
- Consultas e remoções futuras de anexos devem aplicar a mesma regra de autorização.

### 8. Proteção da prévia de links

- O serviço aceita somente URLs absolutas com esquema HTTP ou HTTPS.
- URLs com credenciais embutidas são rejeitadas.
- O serviço resolve o host com um resolver controlado e rejeita loopback, IP privado, link-local, multicast, não especificado e faixas reservadas.
- A validação ocorre para todos os endereços retornados pelo DNS.
- A conexão usa somente um endereço aprovado. A implementação evita uma nova resolução não validada.
- Cada redirecionamento repete a validação completa e respeita um número máximo de saltos.
- O cliente mantém timeouts de conexão, cabeçalho e resposta total.
- A leitura da resposta tem limite estrito.
- Respostas que não sejam HTML não são analisadas como documento Open Graph.
- O cache usa chave normalizada, TTL, tamanho máximo e política de remoção.
- Solicitações simultâneas para a mesma chave compartilham uma única busca em andamento.
- Resultados de erro não ficam em cache por longa duração.

### 9. Observabilidade

- Logs de sessão incluem identificadores de correlação, nota, transição de estado e classe do erro.
- Logs não incluem tokens, conteúdo completo da nota ou dados sensíveis de URL.
- O estado da UI distingue falha recuperável de sincronização de falha de abertura.
- Métricas devem permitir observar sessões ativas, tamanho da outbox, falhas de autorização, destinos de prévia bloqueados e ocupação do cache.

### 10. Ordem de implementação

1. Fechar a falha de autorização de anexos e adicionar limites HTTP.
2. Fechar SSRF e limitar o cache de prévias.
3. Criar testes de caracterização da sessão atual.
4. Promover o serviço REST/OT para o escopo da sessão autenticada.
5. Introduzir o coordenador e o estado explícito da sessão de nota.
6. Migrar a tela do editor para a nova fachada de sessão.
7. Remover o registro estático e os ciclos de vida antigos.
8. Corrigir preferências, compartilhamento e metadados de tarefas.
9. Executar testes completos de reinício, offline, reabertura e múltiplos usuários.

## Testing Decisions

- Os testes validam comportamento externo. Eles não verificam se um tipo específico de provider foi usado.
- A principal costura Flutter é a sessão de nota completa: abrir, editar, observar a outbox, sincronizar, fechar e reabrir.
- Os testes usam banco Drift real em memória quando precisam validar snapshot, outbox, sessão persistida ou projeção.
- Mocks são usados somente para rede, relógio, armazenamento de objetos e notificações do sistema.
- A principal costura do backend é o handler HTTP com autenticação real de teste e banco de teste quando a autorização depende de ownership ou compartilhamento.
- Os testes de prévia usam um servidor HTTP local controlado e um resolver ou transport injetável. Eles não acessam a internet real.
- Os testes de cache usam relógio injetável para validar TTL sem esperas reais.
- Os testes existentes de caracterização REST/OT, rebase, DAO, tela do editor, metadados de tarefas, compartilhamento, autenticação e serviços Go servem como prior art.

### Testes obrigatórios de sessão e Riverpod

- Uma nota aberta duas vezes produz uma única sessão operacional.
- Uma reabertura durante o fechamento aguarda a sessão anterior.
- A sessão antiga não recebe callbacks, polling ou projeção após o fechamento.
- Uma falha em cada etapa da abertura libera todos os recursos criados anteriormente.
- O logout durante abertura, edição, sincronização e fechamento não usa a identidade antiga após a troca.
- Duas notas usam filas independentes.
- Duas chamadas concorrentes para a mesma nota são serializadas mesmo quando vierem de sessões ou consumidores diferentes.
- Uma operação criada durante um POST permanece fora do lote congelado e continua na outbox.
- Uma falha de rede durante o fechamento não remove a outbox.
- Um reinício com outbox e sessão persistida reconstrói o documento visível correto.
- Um resultado assíncrono antigo não substitui o estado de uma sessão nova.
- O provider da sessão libera a sessão quando o último consumidor sai, conforme a política definida para o editor.
- O serviço REST/OT permanece a mesma instância durante toda a sessão autenticada.

### Testes obrigatórios de preferências e UI efêmera

- Duas alternâncias rápidas não permitem que um rollback antigo substitua o resultado novo.
- A falha de um campo não restaura outros campos alterados depois.
- Operações de compartilhamento em duas notas não compartilham loading, sucesso ou erro.
- Fechar o modal de tarefa por cancelamento não salva.
- Falha ao salvar metadados mantém os valores no modal e permite nova tentativa.
- Abrir muitas tarefas e fechar seus modais não mantém famílias de estado ativas.

### Testes obrigatórios de anexos

- Proprietário pode enviar arquivo.
- Colaborador `edit` pode enviar arquivo.
- Colaborador `view` recebe recusa.
- Usuário sem acesso recebe recusa.
- Nota inexistente ou removida recebe resposta consistente e não envia dados ao armazenamento.
- Arquivo acima do limite é recusado antes do upload.
- Leitor que excede o tamanho declarado é interrompido.
- Falha na persistência após upload executa compensação.

### Testes obrigatórios de prévia de links

- HTTP e HTTPS públicos aprovados funcionam.
- Esquemas não permitidos são rejeitados.
- Loopback, IP privado, link-local e endereços reservados são rejeitados.
- Host público que redireciona para destino bloqueado é rejeitado.
- Resolução com qualquer endereço bloqueado segue a política segura definida.
- Cadeia de redirecionamentos respeita o limite.
- Resposta acima do limite é truncada ou rejeitada sem crescimento não controlado.
- Cache expira entradas, respeita capacidade e deduplica chamadas simultâneas.

### Portões de aprovação

- A análise estática Flutter termina sem erros.
- Todos os testes Flutter focados de sessão, sincronização, preferências, compartilhamento e tarefas passam.
- Todos os testes Go de anexos, prévia de links, autenticação, compartilhamento e operações de nota passam.
- O teste de integração com dois clientes offline, reinício, rebase e reabertura passa.
- Nenhum teste iniciado ou interrompido por timeout é registrado como aprovado.

## Out of Scope

- Substituir Riverpod por outro framework de gerenciamento de estado.
- Alterar o protocolo REST/OT para Yjs ou adicionar fallback Yjs.
- Redesenhar o formato do documento ou as regras de transformação OT.
- Criar novos recursos de anexos além da correção de segurança, limites e compensação.
- Criar um proxy geral de navegação web.
- Alterar o modelo de permissões `owner`, `edit` e `view` fora do necessário para aplicar as regras existentes.
- Reescrever todos os providers do aplicativo sem relação com os fluxos citados.
- Fazer mudanças visuais extensas no editor ou nas telas de configuração.
- Publicar detalhes de vulnerabilidades em um tracker público sem aprovação explícita.

## Further Notes

- A implementação deve preservar REST/OT como o único fluxo ativo de sincronização de notas.
- A fila atual por nota é uma base útil. O problema é seu ownership por instância e não a ideia da fila.
- `autoDispose` não é um padrão obrigatório nem proibido. Seu uso depende do proprietário real do recurso.
- Um provider de infraestrutura não deve usar `autoDispose` somente por convenção. Um provider de formulário não deve ser global somente por conveniência.
- O documento mutável é uma superfície de edição. O snapshot confirmado e a outbox persistida continuam a formar a base de recuperação e convergência.
- A implementação deve preservar mudanças locais existentes no worktree e evitar refactors não relacionados.
- Esta especificação contém detalhes de vulnerabilidades ainda abertas. O repositório é público. A publicação integral em uma issue exige aprovação explícita do mantenedor.
