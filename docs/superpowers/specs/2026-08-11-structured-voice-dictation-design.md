# Ditado por voz com estrutura semântica

**Data:** 2026-08-11

**Status:** Aprovado para planejamento

**Plataformas iniciais:** iOS e Android

## Objetivo

Permitir que o usuário grave uma fala dentro de uma nota. Depois que ele parar
a gravação, o SupaNotes deve transcrever a fala, interpretar sua estrutura e
inserir blocos semânticos na posição escolhida no editor.

O resultado pode combinar parágrafos, títulos, listas, tasks, quotes e
divisores. A IA também pode preencher metadados de tasks quando o significado
da fala permitir essa interpretação.

## Princípios

- A IA escolhe a estrutura pelo significado completo da fala. Não há gatilhos
  fixos, como converter toda frase no futuro em task.
- A IA faz limpeza leve. Ela não resume, não muda a intenção e não inventa
  conteúdo.
- `notes.document` continua sendo a fonte canônica.
- A UI aplica o resultado pelo `Editor`. O fluxo REST/OT captura e sincroniza
  as mudanças.
- O backend de ditado não altera notas e não grava diretamente em `tasks`.
- O áudio é temporário e não vira anexo.
- O produto cresce em camadas. A primeira versão atende gravações de até cinco
  minutos. Ditados longos e reuniões ficam fora deste escopo.

## Escopo da primeira versão

### Incluído

- iOS e Android.
- Gravação de até cinco minutos.
- Processamento somente depois que o usuário parar a gravação.
- Detecção automática do idioma, sem tradução.
- Limpeza leve de hesitações, repetições e pontuação.
- Inserção de parágrafo, `header1`, `header2`, `header3`, lista com marcadores,
  lista numerada, task, quote e divisor.
- Interpretação de data, hora, recorrência e lembrete de tasks.
- Tasks novas sempre pendentes.
- Inserção direta com uma ação para desfazer toda a mudança.
- Nova tentativa manual após falha recuperável.
- Operação somente com conexão.

### Excluído

- Transcrição ao vivo.
- Inserção durante a fala.
- Gravação persistente ou áudio como anexo.
- Fila offline persistente.
- Ditados acima de cinco minutos.
- Reuniões, aulas e identificação de falantes.
- Resumo automático.
- Prompt configurável pelo usuário.
- Revisão manual antes da inserção.
- Desktop.

## Arquitetura

```text
Flutter
  -> POST /api/v1/dictation/process
Backend Go
  -> Cloudflare Worker privado
Cloudflare Workers AI
  -> @cf/openai/whisper-large-v3-turbo
Backend Go
  -> modelo de estruturação vencedor da avaliação
Backend Go
  -> plano de blocos validado
Flutter
  -> comando atômico do Editor
EditorOperationCapture
  -> operações REST/OT
notes.document
  -> projeções de tasks
```

### Flutter

Um módulo em `lib/features/notes/dictation/` possui três responsabilidades:

1. Gravar e remover o arquivo temporário.
2. Enviar o áudio ao repositório da feature.
3. Converter o plano validado em uma única mudança do editor.

O estado do fluxo é local à UI e usa um tipo de estágio explícito, por exemplo:

- `recording`
- `processing`
- `recoverableError`
- `applying`

O fluxo não cria um provider global nem usa booleanos paralelos de requisição.
O repositório usa o `ApiClient`; widgets não chamam Dio diretamente.

### Backend Go

Um módulo em `backend/internal/dictation/` segue o fluxo handler, service e
clientes externos.

O endpoint autenticado é:

```text
POST /api/v1/dictation/process
Content-Type: multipart/form-data
```

Campos:

- `audio`: arquivo obrigatório.
- `recorded_at`: instante ISO 8601 no qual a gravação começou.
- `timezone`: identificador IANA do fuso do dispositivo.
- `contract_version`: inteiro com valor `1`.

O endpoint não recebe `note_id` nem o conteúdo atual da nota. Ele não precisa
desses dados para produzir o plano e não possui autoridade para alterar uma
nota.

### Cloudflare Worker

O Worker em `workers/dictation-stt/` recebe áudio somente do backend. Ele:

- Exige um token de serviço.
- Rejeita métodos e formatos não permitidos.
- Executa `@cf/openai/whisper-large-v3-turbo` com `task: transcribe` e
  `vad_filter: true`.
- Permite que o modelo detecte o idioma.
- Retorna somente a transcrição e os dados mínimos de diagnóstico.
- Não usa R2, KV, Durable Objects ou outro storage.

O app nunca chama o Worker diretamente. O backend guarda a URL e o token do
Worker em variáveis de ambiente.

### Modelo de estruturação

O modelo recebe somente:

- A transcrição.
- O instante de início.
- O fuso horário.
- As instruções de interpretação.
- O contrato de saída.

O modelo de produção não é escolhido por preferência antecipada. A seção
"Avaliação de modelos" define um gate obrigatório. Depois da escolha, somente
o cliente do vencedor permanece no caminho de produção. Não há roteamento,
fallback automático ou camada de compatibilidade para candidatos descartados.

## Contrato de saída

Resposta de sucesso:

```json
{
  "contractVersion": 1,
  "transcript": "Texto transcrito e limpo.",
  "language": "pt",
  "blocks": [
    {
      "type": "paragraph",
      "text": "Conteúdo do bloco",
      "indent": 0,
      "taskMetadata": null
    },
    {
      "type": "task",
      "text": "Pagar a conta",
      "indent": 0,
      "taskMetadata": {
        "dueDate": "2026-08-12T00:00:00-03:00",
        "hasTime": false,
        "recurrence": null,
        "reminder": null,
        "isCompleted": false
      }
    }
  ],
  "warnings": []
}
```

Tipos aceitos:

- `paragraph`
- `header1`
- `header2`
- `header3`
- `quote`
- `bulletList`
- `orderedList`
- `task`
- `divider`

`divider` possui texto vazio. Os outros tipos, exceto quando rejeitados pela
validação de conteúdo, possuem texto não vazio.

Recorrências aceitas:

- `daily`
- `weekdays`
- `weekly`
- `monthly`

Lembretes aceitos:

- `at_time`
- `5m_before`
- `1h_before`
- `1d_before`
- `9am`
- `12pm`
- `6pm`
- `1d_before_9am`

Metadados opcionais usam `null`. Todos os objetos recusam propriedades não
declaradas. O backend valida o JSON e as regras de negócio mesmo quando o
fornecedor oferece saída estruturada.

## Interpretação semântica

A IA escolhe a combinação de blocos que melhor representa a fala completa.
Exemplos:

- Uma sequência de ações pode virar várias tasks.
- Uma explicação seguida de ações pode virar um parágrafo e várias tasks.
- Etapas de um processo podem virar uma lista numerada.
- Uma mudança clara de assunto pode receber um divisor.
- Uma frase citada pode virar quote.
- Um tema seguido de detalhes pode virar título e parágrafos.

Os exemplos não são gatilhos. O modelo deve considerar intenção, relação entre
frases e organização geral.

Restrições:

- Não inventar fatos, ações ou metadados.
- Não resumir nem mudar o tom.
- Remover somente hesitações e repetições óbvias.
- Não traduzir.
- Criar tasks pendentes. Relatos concluídos não viram tasks concluídas.
- Definir lembrete somente quando a fala pedir um lembrete.
- Interpretar datas relativas com `recorded_at` e `timezone`.
- Não aproximar uma recorrência não suportada. A expressão permanece no texto
  e gera um aviso.
- Preservar expressões temporais ambíguas no texto em vez de inventar valores.

## Experiência no editor

O toolbar móvel recebe uma ação de microfone.

1. O usuário posiciona o cursor e toca no microfone.
2. O app pede permissão, se necessário.
3. Um bottom sheet dedicado mostra gravação, duração, limite, cancelar e parar.
4. Depois de parar, o sheet mostra `Transcrevendo e organizando`.
5. O editor não recebe texto provisório.
6. No sucesso, o sheet fecha e o plano inteiro é aplicado.
7. Uma mensagem confirma a inserção e oferece `Desfazer`.

Enquanto o sheet estiver aberto, o usuário não edita a nota nem inicia outra
gravação.

### Regra de inserção

- Em parágrafo, título ou quote com texto, a inserção ocorre no cursor. O bloco
  atual é dividido e os novos blocos entram entre as partes.
- Um bloco vazio é substituído.
- Dentro de lista ou task existente, a inserção ocorre depois do bloco inteiro.
  O fluxo não divide uma task nem duplica metadados.
- Uma seleção expandida é substituída por todo o resultado.
- Desfazer restaura o documento e a seleção anteriores em uma única ação.

A âncora guarda o ID imutável do bloco e a posição necessária. Se uma mudança
remota remover a âncora, o app mantém o plano em memória e pede uma nova
posição. Ele não escolhe outra posição silenciosamente.

## Ciclo de vida e falhas

### Dispositivo

- O áudio fica no diretório temporário.
- O arquivo permanece disponível após erro recuperável.
- O arquivo é apagado após inserção, cancelamento, fechamento da nota ou fim da
  sessão.
- Não existe recuperação do áudio após reiniciar o app.

### Backend e Worker

- O backend limita tipo, tamanho e duração.
- O backend remove arquivos temporários em sucesso, erro e cancelamento.
- O Worker não persiste áudio nem transcrição.
- Áudio, transcrição e plano não entram em logs.
- Chamadas externas têm timeout e poucas tentativas automáticas.
- Erros inválidos ou permanentes não são repetidos.

Falhas são classificadas por etapa:

- Permissão ou captura.
- Upload.
- Transcrição.
- Estruturação.
- Validação.
- Aplicação no editor.

O app mantém o áudio para uma nova tentativa quando a falha ocorre antes de um
plano válido. Depois que existe um plano válido, o app pode apagar o áudio e
manter somente o plano em memória.

Nenhuma falha pode causar inserção parcial.

## Avaliação de modelos

A capacidade semântica é o principal fator de escolha. Suporte a JSON Schema é
um critério operacional secundário.

### Candidatos iniciais

- `@cf/qwen/qwen3-30b-a3b-fp8`
- `@cf/zai-org/glm-4.7-flash`
- `@cf/google/gemma-4-26b-a4b-it`
- `@cf/openai/gpt-oss-20b`
- `@cf/openai/gpt-oss-120b`
- `@cf/meta/llama-3.3-70b-instruct-fp8-fast`
- `deepseek-v4-flash`
- `gemini-3.5-flash-lite`
- `gpt-5.6-terra`, somente como referência de qualidade e custo

O conjunto inclui modelos chineses, modelos de pesos abertos e modelos
proprietários. A lista pode remover um modelo que deixe de estar disponível
antes da execução. Um substituto só entra quando pertence à mesma faixa de
custo e está documentado pelo fornecedor.

O Gemini gratuito recebe somente dados sintéticos porque o nível gratuito pode
usar conteúdo para melhorar produtos. Um candidato que não satisfaça o
tratamento de dados exigido para notas privadas não pode vencer o gate de
produção, mesmo que tenha a maior nota semântica.

### Rodada 1

- 20 transcrições fixas.
- Uma execução por modelo.
- Mesmo prompt, contrato e contexto temporal.
- Elimina erros graves, baixa qualidade em português e custo inadequado.

### Rodada 2

- Três finalistas.
- 40 casos difíceis.
- Três execuções por caso.
- Nomes dos modelos ocultos durante a revisão.
- Inclui transcrições reais do Whisper com ruído e erros.

Casos obrigatórios:

- Parágrafos livres.
- Títulos e mudanças de assunto.
- Listas simples e numeradas.
- Sequências de ações convertidas em várias tasks.
- Conteúdo misto.
- Quotes e divisores.
- Datas relativas e absolutas.
- Horas, recorrências e lembretes.
- Ações já concluídas.
- Frases ambíguas.
- Hesitações e repetições.
- Português, inglês e idiomas misturados.

### Pesos

- 35%: escolha e organização dos blocos.
- 25%: interpretação de tasks e metadados.
- 20%: fidelidade, sem invenções ou perdas.
- 10%: consistência.
- 5%: limpeza textual.
- 5%: validade do formato.

Custo e latência são limites e critérios de desempate, não substitutos da
qualidade.

### Gate de produção

O vencedor precisa cumprir todos os limites:

- Mediana humana de pelo menos 4 em 5 para organização semântica.
- Pelo menos 95% de acerto em metadados não ambíguos.
- Nenhuma invenção crítica no conjunto final.
- Pelo menos 99% de respostas válidas após no máximo uma repetição.
- Custo estimado de até US$ 0,01 por gravação de cinco minutos, incluindo STT.
- Resultado aceitável em português e com erros reais do Whisper.

Se nenhum candidato passar, a equipe ajusta prompt, contrato ou candidatos e
repete a avaliação. A aplicação não escolhe automaticamente o modelo com a
maior nota relativa.

O resultado da avaliação registra modelo, versão, prompt, corpus, custo,
latência e pontuação. O usuário aprova a comparação cega dos finalistas antes
da integração de produção.

## Testes

### Backend e Worker

- Autenticação e limites do upload.
- Formatos inválidos e duração acima do limite.
- Remoção do temporário em todos os caminhos.
- Timeout e falhas do Cloudflare.
- Validação de todos os tipos de bloco.
- Datas, horas, recorrências e lembretes.
- Respostas inválidas, recusas e repetição limitada.
- Ausência de mutação de notas e projeções.
- Ausência de conteúdo sensível em logs.

### Flutter

- Permissão aceita, negada e permanentemente negada.
- Início, cancelamento, parada e limite de cinco minutos.
- Ciclo de vida do arquivo temporário.
- Nova tentativa após falha.
- Inserção em todos os tipos e posições aprovados.
- Substituição de seleção.
- Desfazer atômico.
- Captura REST/OT.
- Projeção das tasks criadas.

### Dispositivos reais

- Um iPhone e um Android.
- Interrupções de microfone.
- App em segundo plano e tela bloqueada.
- Rede lenta, perda de conexão e retorno ao app.
- Sincronização concorrente durante o processamento.

## Observabilidade

Métricas e logs técnicos podem registrar:

- ID da requisição.
- Duração e tamanho do áudio.
- Modelo usado.
- Tempo de transcrição e estruturação.
- Tokens ou neurons.
- Sucesso, repetição e código de erro.
- Latência p50 e p95.

Não podem registrar áudio, transcrição, prompt com conteúdo do usuário ou plano
de blocos.

## Configuração

O backend adiciona somente as variáveis necessárias ao caminho escolhido:

- URL e token do Worker de STT.
- Credencial do fornecedor vencedor.
- Nome fixado do modelo vencedor.

O Worker adiciona o binding do Workers AI e o token esperado do backend. As
variáveis entram em `.env.example`; segredos reais nunca entram no repositório.

## Evolução futura

### Camada 2: ditados longos

- Até 30 minutos.
- Divisão do áudio.
- Progresso e processamento em segundo plano.
- Retomada segura.

### Camada 3: reuniões e aulas

- Gravações extensas.
- Identificação de falantes.
- Revisão antes da inserção.
- Resumo opcional e explicitamente solicitado.

Essas camadas exigem novas especificações. Elas não alteram o escopo desta
primeira entrega.

## Fontes consultadas

- [Cloudflare Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/)
- [Cloudflare Whisper Large V3 Turbo](https://developers.cloudflare.com/workers-ai/models/whisper-large-v3-turbo/)
- [Cloudflare Workers AI data usage](https://developers.cloudflare.com/workers-ai/platform/data-usage/)
- [Cloudflare Workers AI JSON Mode](https://developers.cloudflare.com/workers-ai/features/json-mode/)
- [Groq models and pricing](https://console.groq.com/docs/models)
- [Groq Structured Outputs](https://console.groq.com/docs/structured-outputs)
- [Groq data controls](https://console.groq.com/docs/your-data)
- [DeepSeek models and pricing](https://api-docs.deepseek.com/quick_start/pricing/)
- [DeepSeek JSON Output](https://api-docs.deepseek.com/guides/json_mode/)
- [Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing)
- [Gemini Structured Outputs](https://ai.google.dev/gemini-api/docs/structured-output)
- [OpenAI file transcription](https://developers.openai.com/api/docs/guides/speech-to-text)
- [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
