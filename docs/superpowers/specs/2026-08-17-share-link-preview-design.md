# Spec: Compartilhar Links para Notas com Preview

Permite compartilhar uma URL a partir do share sheet nativo do iOS ou Android diretamente para uma nota do SupaNotes, sem abrir o app principal. O usuário escolhe uma nota em uma interface nativa compacta, recebe confirmação imediata de salvamento local e retorna ao app de origem. O backend adiciona o link ao final da versão mais recente da nota e enriquece o bloco com metadata visual para renderização como card no Super Editor.

## User Review Required

> [!IMPORTANT]
> - A V1 suporta iOS e Android.
> - A tela de compartilhamento é nativa em cada plataforma, não Flutter.
> - A lista de notas replica o padrão atual do app: busca no topo, título + pequena prévia do conteúdo, ordenação por `updatedAt DESC`.
> - Somente notas editáveis aparecem na extensão/Activity.
> - Ao tocar numa nota, o compartilhamento é persistido localmente antes do envio e a UI mostra uma confirmação curta antes de fechar.
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
        ├─ lê credencial da sessão em storage seguro compartilhado
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
        ├─ lê credencial da sessão em storage seguro nativo
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

A Activity deve oferecer a mesma experiência e protocolo do iOS: busca, lista por `updatedAt DESC`, título + preview, somente notas editáveis, persistência local antes do envio, confirmação curta e finalização imediata após a seleção.

A UI não deve inicializar a tela Flutter principal para esse fluxo.

## 3. Shared Storage

A ponte nativa usa dois arquivos JSON pequenos. Eles não substituem o banco Drift nem a outbox de sync.

### `notes_index.json`

Usar um envelope com ownership explícito:

```json
{
  "ownerUserId": "user-uuid",
  "notes": [
    {
      "noteId": "note-uuid",
      "title": "Ideias",
      "preview": "Texto inicial da nota...",
      "updatedAt": "2026-08-17T18:00:00Z",
      "canEdit": true
    }
  ]
}
```

O app principal atualiza o arquivo quando houver mudança relevante em criação/exclusão, título, preview, `updatedAt` ou permissão.

No iOS, o arquivo fica no container do App Group. No Android, o mesmo contrato JSON fica em armazenamento interno acessível pelo fluxo nativo do aplicativo.

### `share_inbox.json`

Contém somente compartilhamentos ainda não confirmados pelo backend:

```json
[
  {
    "shareId": "uuid",
    "ownerUserId": "user-uuid",
    "noteId": "note-uuid",
    "url": "https://example.com/post",
    "createdAt": "2026-08-17T18:10:00Z",
    "state": "pending"
  }
]
```

A escrita deve ser atômica: escrever o conteúdo completo em arquivo temporário, fazer flush e só então substituir o arquivo anterior.

### Lifecycle

```text
seleciona nota
→ cria shareId
→ grava item na inbox
→ mostra confirmação de salvamento local
→ inicia envio
→ backend confirma shareId
→ remove item da inbox
```

Se houver timeout, falta de internet ou encerramento do processo, o item permanece para retry com o mesmo `shareId`.

A inbox não possui `baseRevision`, conflito, merge ou resolução de revisão. Ela é apenas a ponte durável entre UI nativa e backend.

## 4. Autenticação do Fluxo Nativo

Hoje a sessão Flutter persiste access token e refresh token em `FlutterSecureStorage`, que usa Keychain no iOS e armazenamento seguro no Android. O código nativo do share não deve depender de inicializar Flutter para recuperar essas credenciais.

Criar uma abstração `ShareAuthStore` de plataforma, sincronizada pelo app principal sempre que a sessão for instalada, renovada ou removida.

### iOS

Usar Keychain Access Group compartilhado entre app e Share Extension. O App Group continua sendo usado para arquivos; credenciais não devem ser gravadas em JSON ou `UserDefaults`.

### Android

Usar armazenamento seguro nativo acessível à Share Activity dentro do mesmo aplicativo. A implementação deve evitar depender de detalhes internos do formato usado por `flutter_secure_storage`; o app Flutter deve escrever/limpar explicitamente os valores necessários através da ponte de plataforma.

### Conteúdo

O `ShareAuthStore` pode manter o par JWT da sessão atual para permitir o mesmo protocolo de refresh já usado pelo app. O `ownerUserId` deve acompanhar o estado da sessão para impedir que um item pendente seja entregue usando outra conta.

Regras:

- login/registro: instalar credenciais no storage Flutter e no `ShareAuthStore`;
- refresh: substituir o par nos dois storages de forma coerente;
- logout: limpar ambos antes de permitir nova sessão;
- uploader nativo: se access token estiver expirado, usar o endpoint de refresh existente e substituir o par de forma atômica;
- item da inbox só pode ser enviado se `ownerUserId` coincidir com a sessão nativa atual.

Se não houver sessão válida, a UI de share deve informar que o usuário precisa abrir o SupaNotes e autenticar-se; ela não deve descartar silenciosamente o link já persistido quando existir ownership válido.

## 5. Relação com `pending_note_operations`

O projeto já possui `pending_note_operations` como outbox de edições produzidas pelo app Flutter, com `baseRevision`, `ordinal`, `kind`, `payloadJson`, ownership, status e retry.

Essa infraestrutura permanece como a única outbox do fluxo normal de edição Flutter.

O compartilhamento externo não escreve diretamente nessa tabela porque, no iOS, a Share Extension vive em outro sandbox e o banco atual `supanotes.sqlite` fica no Application Documents Directory do app principal.

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

Os dois fluxos convergem no backend e retornam ao cliente pelo sync normal.

## 6. Endpoint de Compartilhamento

Adicionar endpoint autenticado equivalente a:

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
3. Deduplicar por `(userId, shareId)`.
4. Não deduplicar por URL.
5. Aceitar somente URLs `http`/`https` na V1.
6. Carregar a versão canônica mais recente da nota.
7. Gerar metadata do link.
8. Construir `LinkPreviewNode`.
9. Inserir o node ao final da versão mais recente do documento.
10. Persistir nova revisão usando o mecanismo canônico de mutação do backend.
11. Retornar sucesso idempotente para retries de `shareId` já aceito.

O endpoint não recebe snapshot do documento nem `baseRevision` da extensão.

## 7. Concorrência

O comando é semântico: **adicione esta URL ao final da versão mais recente desta nota**.

O backend nunca substitui a nota por snapshot produzido pela extensão.

```text
rev 20
→ edição remota cria rev 21
→ compartilhamento chega
→ backend lê rev 21
→ append LinkPreviewNode
→ rev 22
```

Se outro dispositivo tiver operações offline baseadas em revisão anterior, o pipeline de sync existente deve reconciliá-las contra a nova revisão. Não haverá lógica especial de conflito para links no cliente.

## 8. Enriquecimento de Link

Prioridade de metadata:

1. Open Graph (`og:title`, `og:description`, `og:image`, `og:site_name`).
2. HTML title/description quando úteis.
3. favicon e hostname como fallback.

O serviço deve seguir redirects com limite, aplicar timeout curto, limitar HTML recebido, aceitar apenas HTTP(S), normalizar campos e bloquear SSRF, inclusive destinos locais/privados, metadata services de cloud e redirects para redes bloqueadas.

Falha de metadata cria node válido em `failed`; não falha o compartilhamento.

## 9. `LinkPreviewNode` no Super Editor

Criar um tipo próprio de `DocumentNode`, renderizado por `ComponentBuilder` próprio:

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

Estados da V1:

- `ready`: metadata resolvida;
- `failed`: fallback por domínio/URL.

Não é necessário `pending` no documento Flutter porque a revisão só é publicada depois de o backend construir o node final.

O node é atômico: seleção, exclusão e movimentação do bloco inteiro, sem cursor textual interno. A serialização canônica do documento inclui o snapshot da metadata para cards antigos não mudarem silenciosamente.

## 10. Layout do Card

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
- descrição abaixo, até 2 linhas;
- site/domínio abaixo da descrição;
- card inteiro clicável e abre a URL;
- sem imagem: texto ocupa toda a largura;
- `failed`: card compacto com domínio + URL.

## 11. Atualização no Flutter

Nenhum novo canal realtime é necessário.

App fechado:

```text
backend grava nova revisão
→ usuário abre SupaNotes
→ sync atual
→ revisão atualizada chega ao armazenamento local
→ card aparece
```

App aberto:

```text
nova revisão remota
→ projeção local atualizada
→ stream do documento emite
→ editor recebe documento efetivo atualizado
→ card aparece
```

A feature reutiliza o mecanismo atual de atualização; não cria polling específico.

## 12. Retry e Background

### iOS

Usar background `URLSession` da Share Extension associado ao App Group/shared container. Não assumir que o app Flutter será executado depois que a extensão fechar.

Itens ainda na inbox devem ser reenviados quando houver nova oportunidade segura de execução, sempre com o mesmo `shareId`.

### Android

O envio inicial começa pela Share Activity. A inbox garante retomada posterior. A implementação deve usar mecanismo de background compatível com as restrições modernas do Android e não depender de processo residente indefinidamente.

## 13. Logout e Troca de Conta

Ao logout:

- remover `notes_index.json`;
- limpar `ShareAuthStore`;
- nunca enviar item pendente com credenciais de outro usuário.

Itens pendentes mantêm `ownerUserId` e só são enviados quando a sessão atual corresponde ao mesmo usuário.

## 14. Error Handling

- URL inválida: UI mostra erro e permanece aberta.
- Falha ao persistir inbox: não mostrar sucesso.
- Falha de rede após persistência: mostrar sucesso local e manter item para retry.
- Sessão ausente/inválida: manter item, não enviar com outra conta.
- Nota removida antes do processamento: backend retorna erro terminal; não repetir para sempre.
- Permissão removida: erro terminal equivalente.
- Metadata indisponível: criar fallback e concluir.
- Retry do mesmo `shareId`: sucesso sem duplicação.

## 15. Segurança

O backend é autoridade final para permissões; `canEdit` serve somente à UX.

Credenciais não podem aparecer em `notes_index.json`, `share_inbox.json` ou logs. O enriquecimento de URL deve bloquear loopback, link-local, redes privadas, metadata services, esquemas locais e redirects para destinos bloqueados.

A extensão armazena somente índice mínimo de notas, inbox de compartilhamentos e credenciais no storage seguro da plataforma.

## 16. Testes

### Flutter / Documento

1. Serializar/desserializar `LinkPreviewNode` `ready` e `failed`.
2. Renderizar com e sem imagem.
3. Selecionar/excluir/mover como bloco atômico.
4. Receber revisão atualizada pela stream existente e exibir o node.

### Backend

1. Dono e usuário `edit` conseguem adicionar; `view` não.
2. `shareId` repetido não duplica.
3. Mesma URL com outro `shareId` duplica intencionalmente.
4. Concorrência sempre faz append na revisão mais recente.
5. Metadata válida produz `ready`; metadata ausente produz `failed` sem falhar.
6. Timeout/redirects são limitados e SSRF é bloqueado.
7. Nota excluída ou permissão removida gera erro terminal.

### Auth nativo

1. Login instala sessão no `ShareAuthStore`.
2. Refresh substitui o par sem janela de conta cruzada.
3. Logout limpa o storage nativo.
4. Share com access token expirado consegue refresh.
5. `ownerUserId` divergente impede envio.

### iOS / Android

1. Share sheet/`ACTION_SEND` reconhece URL.
2. Lista ordena por `updatedAt DESC`, busca corretamente e oculta read-only.
3. Seleção persiste inbox antes do envio e mostra confirmação.
4. Falha de rede mantém item.
5. Retry mantém `shareId`.
6. Escrita interrompida não corrompe JSON anterior.
7. Troca de conta não expõe notas ou credenciais antigas.

### End-to-End

1. Compartilhar online e abrir SupaNotes depois: card já sincronizado ou sincroniza na abertura.
2. Compartilhar offline, recuperar internet e confirmar entrega posterior sem abrir a tela principal para concluir o envio quando o SO permitir o job/background pendente.
3. Compartilhar enquanto a mesma nota recebe outra edição remota; ambas permanecem.
4. Compartilhar enquanto outro dispositivo possui operações locais pendentes; sync converge sem perda.
5. Manter app aberto na nota e confirmar que o card aparece pelo mecanismo atual.
6. Centenas de notas no índice continuam abrindo e buscando rapidamente.

## 17. Critérios de Aceite

A feature está concluída quando:

- SupaNotes aparece no share sheet de iOS e Android para URLs.
- É possível buscar e selecionar uma nota sem abrir o app principal.
- A lista usa título + preview + `updatedAt DESC` e contém somente notas editáveis.
- A seleção persiste localmente antes da rede.
- O usuário recebe confirmação curta e retorna ao app de origem.
- O uploader nativo autentica com storage seguro próprio, incluindo refresh, sem depender de inicializar Flutter.
- O compartilhamento pode ser entregue ao backend sem exigir abertura manual do SupaNotes, sujeito às garantias de execução em background do sistema operacional.
- O backend é idempotente por `shareId`, valida permissão e adiciona ao final da revisão mais recente.
- O preview é enriquecido no backend com fallback seguro.
- O Super Editor renderiza `LinkPreviewNode` no layout aprovado.
- O link chega ao Flutter através do documento/sync já existente.
- Nenhuma alteração concorrente é perdida nos testes de integração.