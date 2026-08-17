# Spec: Compartilhar Links para Notas com Preview

Permite compartilhar uma URL a partir do share sheet nativo do iOS ou Android diretamente para uma nota do SupaNotes, sem abrir o app principal. O usuário escolhe uma nota em uma interface nativa compacta, recebe confirmação imediata de salvamento e retorna ao app de origem. O backend adiciona o link ao final da versão mais recente da nota e enriquece o bloco com metadata visual para renderização como card no Super Editor.

## User Review Required

> [!IMPORTANT]
> - A V1 suporta iOS e Android.
> - A tela de compartilhamento é nativa em cada plataforma, não Flutter.
> - A lista de notas replica o padrão atual do app: busca no topo, título + pequena prévia do conteúdo, ordenação por `updatedAt DESC`.
> - Somente notas editáveis aparecem na extensão/Activity.
> - Ao tocar numa nota, o link é salvo imediatamente e a UI mostra uma confirmação curta antes de fechar.
> - O link é sempre adicionado ao final da versão mais recente da nota.
> - URLs iguais podem ser adicionadas várias vezes; somente retries do mesmo `shareId` são deduplicados.
> - A metadata visual é enriquecida no backend. Falha de Open Graph não impede o salvamento; o node usa fallback compacto.
> - O Super Editor recebe um `LinkPreviewNode` customizado e atômico, renderizado por `ComponentBuilder` próprio.

## Goals

1. Compartilhar uma URL para uma nota sem abrir o SupaNotes.
2. Manter o fluxo rápido, offline-safe e idempotente.
3. Reutilizar o sync existente para entregar ao Flutter a revisão atualizada.
4. Não expor o banco Drift completo à Share Extension no iOS.
5. Não criar uma segunda outbox de sincronização concorrente com `pending_note_operations`.

## Non-Goals da V1

- Escolher posição arbitrária dentro da nota.
- Extrair o corpo completo de artigos.
- Deduplicar por URL.
- Editar título/descrição do preview na extensão.
- Compartilhar imagens, PDFs ou múltiplos itens; a V1 é focada em URLs.
- Renderizar o editor Flutter dentro do share sheet.

## 1. Arquitetura Geral

```text
iOS
Share Extension (SwiftUI)
        │
        ├─ lê notes_index.json no App Group
        ├─ busca + lista de notas
        ├─ grava share_inbox.json
        └─ inicia upload em background
                    │
                    ▼
                 Backend

Android
Share Activity nativa
        │
        ├─ lê notes_index.json
        ├─ busca + lista de notas
        ├─ grava share_inbox.json
        └─ envia ao backend
                    │
                    ▼
                 Backend
```

No backend:

```text
POST shared-link
   │
   ├─ autentica usuário
   ├─ valida permissão de edição
   ├─ deduplica por shareId
   ├─ carrega a revisão mais recente da nota
   ├─ busca metadata do link
   ├─ cria LinkPreviewNode
   ├─ append no final do documento
   └─ grava nova revisão
              │
              ▼
        sync já existente
              │
              ▼
           Flutter
```

## 2. Share UI

### iOS

Implementar uma Share Extension nativa em SwiftUI registrada para URLs/texto compartilhado que contenha URL.

A extensão deve:

1. Extrair a URL recebida.
2. Ler o índice local de notas do App Group.
3. Exibir campo de busca no topo.
4. Exibir notas por `updatedAt DESC`.
5. Mostrar em cada item título e pequena prévia do conteúdo.
6. Ocultar notas sem permissão de edição.
7. Ao selecionar uma nota, persistir primeiro o compartilhamento na inbox local.
8. Iniciar envio ao backend.
9. Mostrar confirmação curta, por exemplo `Salvo em Ideias`.
10. Encerrar a extensão e retornar ao app de origem.

### Android

Registrar uma Activity nativa para `ACTION_SEND` com conteúdo textual/URL.

A Activity deve oferecer a mesma experiência e protocolo do iOS:

- busca;
- lista por `updatedAt DESC`;
- título + preview;
- somente notas editáveis;
- persistência local antes do envio;
- confirmação curta;
- finalização imediata após a seleção.

A UI pode ser implementada com componentes nativos Android. Não deve inicializar a tela Flutter principal para esse fluxo.

## 3. Shared Storage

A ponte nativa usa dois arquivos JSON pequenos. Eles não substituem o banco Drift nem a outbox de sync.

### `notes_index.json`

Snapshot somente-leitura para a UI de share:

```json
[
  {
    "noteId": "note-uuid",
    "title": "Ideias",
    "preview": "Texto inicial da nota...",
    "updatedAt": "2026-08-17T18:00:00Z",
    "canEdit": true
  }
]
```

O app principal atualiza esse arquivo sempre que houver mudança relevante em:

- criação/exclusão de nota;
- título;
- preview usado na lista;
- `updatedAt`;
- permissão de edição.

No iOS, o arquivo fica no container do App Group compartilhado entre o app e a Share Extension.

No Android, o mesmo contrato JSON fica em armazenamento interno acessível pelo fluxo nativo do aplicativo.

### `share_inbox.json`

Contém apenas compartilhamentos que ainda não tiveram entrega confirmada pelo backend:

```json
[
  {
    "shareId": "uuid",
    "noteId": "note-uuid",
    "url": "https://example.com/post",
    "createdAt": "2026-08-17T18:10:00Z",
    "state": "pending"
  }
]
```

A escrita deve ser atômica: escrever um arquivo temporário completo e fazer rename/substituição somente após flush bem-sucedido.

### Lifecycle

```text
seleciona nota
→ cria shareId
→ grava item na inbox
→ inicia envio
→ backend confirma shareId
→ remove item da inbox
```

Se houver timeout, falta de internet ou encerramento do processo, o item permanece disponível para retry com o mesmo `shareId`.

A inbox não possui `baseRevision`, conflito, `in_flight` de sync, merge ou resolução de revisão. Ela é somente a ponte durável entre UI nativa e backend.

## 4. Relação com `pending_note_operations`

O projeto já possui `pending_note_operations` como outbox de edições produzidas pelo app Flutter, com `baseRevision`, `ordinal`, `kind`, `payloadJson`, ownership, status e retry.

Essa infraestrutura permanece como a única outbox do fluxo normal de edição Flutter.

O compartilhamento externo não escreve diretamente nessa tabela porque, no iOS, a Share Extension vive em outro sandbox e o banco atual `supanotes.sqlite` fica no Application Documents Directory do app principal.

Portanto:

```text
Flutter edit
   ↓
pending_note_operations
   ↓
sync
   ↓
Backend

Share Extension / Share Activity
   ↓
share_inbox.json
   ↓
HTTP idempotente
   ↓
Backend
```

Os dois fluxos convergem no backend e depois retornam ao cliente pelo sync normal.

## 5. Endpoint de Compartilhamento

Adicionar um endpoint autenticado equivalente a:

```http
POST /api/v1/notes/:noteId/shared-links
```

Payload:

```json
{
  "shareId": "uuid",
  "url": "https://example.com/post",
  "createdAt": "2026-08-17T18:10:00Z"
}
```

Regras:

1. Validar autenticação.
2. Validar que o usuário é dono da nota ou possui permissão `edit`.
3. Deduplicar por `(userId, shareId)` ou outro escopo equivalente que impeça colisões entre usuários.
4. Não deduplicar por URL.
5. Validar esquema da URL e aceitar apenas `http`/`https` na V1.
6. Carregar a versão canônica mais recente da nota.
7. Gerar metadata do link.
8. Construir `LinkPreviewNode`.
9. Inserir o node ao final da versão mais recente do documento.
10. Persistir nova revisão usando o mecanismo canônico de mutação de documento do backend.
11. Retornar sucesso idempotente para retries de um `shareId` já aceito.

O endpoint não recebe uma cópia do documento nem uma `baseRevision` fornecida pela extensão.

## 6. Concorrência

O comando do share é semântico:

> Adicione esta URL ao final da versão mais recente desta nota.

O backend nunca substitui a nota por um snapshot construído pela extensão.

Exemplo:

```text
rev 20
→ edição remota cria rev 21
→ compartilhamento chega
→ backend lê rev 21
→ append LinkPreviewNode
→ rev 22
```

Se outro dispositivo possuir operações offline baseadas em uma revisão anterior, o pipeline de sync já existente deve reconciliar essas operações contra a nova revisão remota. O cliente não terá lógica especial de conflito para links compartilhados.

## 7. Enriquecimento de Link

O backend resolve metadata após receber o comando e antes de persistir o node final.

Prioridade de fontes:

1. Open Graph (`og:title`, `og:description`, `og:image`, `og:site_name`).
2. HTML title/description quando úteis.
3. favicon e hostname como fallback.

O serviço deve:

- seguir redirects com limite;
- aplicar timeout curto;
- limitar tamanho de resposta HTML;
- rejeitar esquemas não HTTP(S);
- proteger contra SSRF, incluindo destinos locais/privados e redirects para redes bloqueadas;
- normalizar campos excessivamente longos;
- tratar metadata inválida sem falhar o compartilhamento.

Falha de metadata gera um node válido em estado `failed`, não erro de compartilhamento.

## 8. `LinkPreviewNode` no Super Editor

O link é um tipo próprio de `DocumentNode`, renderizado por um `ComponentBuilder` próprio.

Modelo conceitual:

```text
LinkPreviewNode
├─ id
├─ url
├─ title?
├─ description?
├─ imageUrl?
├─ faviconUrl?
├─ siteName?
└─ previewStatus
```

`previewStatus` na V1:

- `ready`: metadata suficiente foi resolvida;
- `failed`: metadata não pôde ser resolvida; mostrar fallback.

Não é necessário estado `pending` no documento Flutter porque o backend só publica a nova revisão depois de construir o node final.

O node deve ser atômico:

- seleção do bloco inteiro;
- exclusão como bloco;
- movimentação como bloco;
- sem cursor textual interno.

A serialização canônica do documento deve incluir todos os campos necessários para o snapshot do preview, para que cards existentes não mudem silenciosamente quando o site de origem alterar metadata.

## 9. Layout do Card

Layout aprovado:

```text
┌─────────────────────────────────────────────┐
│ ┌──────────┐  Título da página              │
│ │          │  Descrição curta do conteúdo   │
│ │  imagem  │  exemplo.com                   │
│ │          │                                │
│ └──────────┘                                │
└─────────────────────────────────────────────┘
```

Regras:

- imagem à esquerda;
- título à direita, até 2 linhas;
- descrição abaixo do título, até 2 linhas;
- site/domínio abaixo da descrição;
- card inteiro clicável e abre a URL;
- sem imagem: conteúdo textual ocupa toda a largura;
- `failed`: mostrar card compacto com domínio e URL, sem estado visual de erro agressivo.

## 10. Atualização no Flutter

Nenhum novo canal de realtime é necessário para a V1.

### App fechado

```text
backend grava nova revisão
→ usuário abre SupaNotes
→ sync atual executa
→ revisão atualizada chega ao armazenamento local
→ LinkPreviewNode aparece
```

### App aberto

Se o mecanismo atual de stream/sync receber atualização remota enquanto a nota estiver aberta:

```text
nova revisão remota
→ projeção local atualizada
→ stream do documento emite
→ editor recebe documento efetivo atualizado
→ card aparece
```

A feature deve reutilizar o mecanismo existente de atualização do documento; não criar polling específico para previews.

## 11. Retry e Background

### iOS

Usar background `URLSession` configurada para a Share Extension e associada ao App Group/shared container. A entrega pode continuar após o fechamento da interface da extensão conforme as capacidades permitidas pelo sistema.

Não assumir execução imediata do app Flutter depois que a extensão fecha.

Itens ainda presentes em `share_inbox.json` devem ser reenviados quando houver nova oportunidade segura de execução, sempre usando o mesmo `shareId`.

### Android

O envio inicial pode começar pela Share Activity. A persistência na inbox garante que um envio incompleto possa ser retomado posteriormente pelo app/processamento apropriado, sem exigir que a UI de share permaneça aberta.

O design de implementação deve usar mecanismo de background compatível com as restrições modernas do Android, sem depender de processo indefinidamente residente.

## 12. Logout e Troca de Conta

`notes_index.json` e `share_inbox.json` pertencem à sessão autenticada atual.

Ao logout:

- remover o índice de notas;
- não entregar itens pendentes usando credenciais de outro usuário;
- itens pendentes devem manter ownership explícito ou ser descartados conforme a política de logout escolhida na implementação.

Para a V1, a política recomendada é armazenar `ownerUserId` em cada item da inbox e só reenviá-lo quando a sessão autenticada corresponder ao mesmo usuário. O índice também deve incluir um identificador de owner da sessão no envelope do arquivo para evitar exibir notas de uma conta anterior.

## 13. Error Handling

- URL inválida: extensão mostra erro e permanece aberta.
- Falha ao persistir `share_inbox.json`: não mostrar sucesso; permanecer aberta para retry.
- Falha de rede após persistência: mostrar sucesso de salvamento local e manter item para retry.
- Nota removida antes do processamento: backend rejeita como não encontrada; item deixa de ser retry infinito e o app pode registrar falha local para diagnóstico.
- Permissão removida: backend rejeita; mesmo tratamento de erro terminal.
- Metadata indisponível: criar `LinkPreviewNode` fallback e considerar operação concluída.
- Retry do mesmo `shareId`: retornar sucesso sem criar outro node.

## 14. Segurança

O backend deve ser a autoridade final para permissão. O filtro `canEdit` do índice serve somente para UX.

O enriquecimento de URLs deve implementar proteção SSRF e nunca permitir que URLs fornecidas pelo usuário façam o servidor acessar:

- loopback;
- link-local;
- redes privadas;
- metadata services de cloud;
- esquemas locais como `file:`;
- redirects para destinos bloqueados.

A extensão não recebe nem armazena dados sensíveis do documento completo; somente índice mínimo de notas e itens de share pendentes.

## 15. Testes

### Flutter / Documento

1. Serializar e desserializar `LinkPreviewNode` `ready`.
2. Serializar e desserializar fallback `failed`.
3. Renderizar card com imagem.
4. Renderizar card sem imagem.
5. Selecionar/excluir/mover o node como bloco atômico.
6. Atualizar documento efetivo via stream e verificar aparecimento do node sem recriar lógica especial de polling.

### Backend

1. Usuário dono consegue adicionar link.
2. Usuário com `edit` consegue adicionar link.
3. Usuário `view` recebe rejeição.
4. `shareId` repetido não duplica node.
5. Mesma URL com `shareId` diferente cria outro node.
6. Concorrência: sempre append na revisão mais recente.
7. Metadata válida produz node `ready`.
8. Metadata ausente produz fallback `failed` e operação bem-sucedida.
9. Redirects e timeout são limitados.
10. SSRF para IP privado/loopback é bloqueado.
11. Nota excluída entre seleção e processamento retorna erro terminal.

### iOS

1. Share sheet reconhece URL.
2. Lista usa `notes_index.json` e ordena por `updatedAt DESC`.
3. Busca filtra corretamente.
4. Notas não editáveis não aparecem.
5. Seleção persiste inbox antes do envio.
6. Confirmação aparece após persistência local.
7. Falha de rede mantém item pendente.
8. Retry usa o mesmo `shareId`.
9. Escrita interrompida não corrompe JSON anterior.
10. Troca de conta não expõe índice antigo.

### Android

Executar os mesmos casos funcionais do iOS para `ACTION_SEND`, lista, busca, persistência, retry, confirmação e isolamento de sessão.

### End-to-End

1. Compartilhar online, fechar imediatamente e abrir SupaNotes depois: card já sincronizado ou sincroniza na abertura.
2. Compartilhar offline, recuperar internet e confirmar entrega posterior.
3. Compartilhar enquanto a mesma nota recebe outra edição remota; ambas permanecem.
4. Compartilhar enquanto outro dispositivo possui operações locais pendentes; sync converge sem perda.
5. Manter app aberto na nota e confirmar que o card aparece pelo mecanismo atual de atualização.
6. Centenas de notas no índice continuam abrindo e buscando rapidamente.

## 16. Critérios de Aceite

A feature está concluída quando:

- SupaNotes aparece no share sheet de iOS e Android para URLs.
- É possível buscar e selecionar uma nota sem abrir o app principal.
- A lista corresponde ao padrão atual de título + preview + `updatedAt DESC` e contém somente notas editáveis.
- A seleção persiste localmente antes de qualquer dependência de rede.
- O usuário recebe confirmação curta e volta ao app de origem.
- O compartilhamento pode ser entregue ao backend sem exigir abertura manual do SupaNotes.
- O backend é idempotente por `shareId`, valida permissão e adiciona o bloco ao final da revisão mais recente.
- O preview é enriquecido no backend com fallback seguro.
- O Super Editor renderiza `LinkPreviewNode` no layout aprovado.
- O link chega ao Flutter exclusivamente através do documento/sync já existente.
- Nenhuma alteração concorrente é perdida em testes de integração.