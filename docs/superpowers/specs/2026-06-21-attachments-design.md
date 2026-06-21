# Design Spec: Sistema de Anexos e Links Ricos

**Data:** 2026-06-21  
**Status:** Aprovado  
**Autor:** Antigravity AI

---

## 1. Objetivos

Permitir que os usuarios anexem arquivos locais (fotos, videos, documentos) e links web interativos diretamente no editor de notas rico do SupaNotes. O sistema sincronizara os arquivos via backend Go em um Cloud Storage publico/privado compativel com S3 (AWS, MinIO, Supabase Storage, Google Cloud Storage, etc.) e renderizara os elementos de maneira inline no editor usando a sintaxe padrao Markdown para portabilidade.

---

## 2. Modelagem de Dados

### Local Database (Drift/SQLite)
Criaremos uma nova tabela `attachments` para gerenciar o cache local e uploads:

```dart
class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get localPath => text().nullable()();
  TextColumn get remoteUrl => text().nullable()();
  TextColumn get fileName => text()();
  TextColumn get mimeType => text()();
  IntColumn get fileSize => integer()();
  TextColumn get status => text()(); // local, uploading, synced, failed
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

### Backend API (Go)
1. **Upload de Arquivo**
   * `POST /api/v1/attachments/upload`
   * Entrada: `multipart/form-data` com o arquivo físico e `note_id`.
   * Saida: JSON com o ID gerado, URL publica do Storage compativel, tipo mime e tamanho.
2. **Metadados de Link**
   * `GET /api/v1/links/preview?url=...`
   * Saida: `{ "title": "...", "description": "...", "image_url": "..." }`

---

## 3. UI & Fluxo de Interacao (Flutter)

1. **Toolbar Button**: Um icone de clipe `+` na `NoteToolbar` abre o picker de arquivos nativo do Flutter.
2. **Paste & Drag/Drop**: Interceptadores no `SuperEditor` para arquivos colados e arrastados no canvas do editor.
3. **Componentes Customizados no Super Editor**:
   * `ImageAttachmentNode` / `VideoAttachmentNode`: Renderiza imagens e reprodutores de video.
   * `FileAttachmentNode`: Card com metadados do arquivo (icone de tipo de doc, tamanho, nome, acao de download/abrir).
   * `RichLinkCardNode`: Card visual elegante renderizando metadados Open Graph de links isolados.

---

## 4. Serializacao Markdown

* **Salvar nota**:
  * Imagens: `![fileName](remoteUrl)`
  * Videos e Outros Arquivos: `[fileName](remoteUrl)`
  * Links Ricos: `https://url.com` isolado na linha.
* **Carregar nota**:
  * O parser do markdown identificara o tipo de arquivo pela extensao da url ou tag standard e instanciara o nó correspondente do SuperEditor.
