# Structured Voice Dictation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver structured voice dictation from microphone capture through semantic model selection to one atomic REST/OT editor insertion on iOS and Android.

**Architecture:** A private Cloudflare Worker transcribes temporary M4A audio with `@cf/openai/whisper-large-v3-turbo`. A standalone Go benchmark selects one text model with semantic tests and blinded review. The authenticated Go API then streams one temporary upload through STT and the selected structurer and returns the validated block plan without mutating a note. Flutter records temporary audio, sends it after stop, and converts the plan to Super Editor requests in one `Editor.execute` transaction. Existing `EditorOperationCapture`, `NoteOperationAdapter`, and `NoteSyncSession` keep `notes.document` canonical and project task nodes to Drift.

**Tech Stack:** Flutter 3.44, Dart 3.12, Super Editor, Riverpod 3, Dio, `record` 7.1.1, `permission_handler` 12.0.3, TypeScript, Cloudflare Workers AI, Vitest, Go 1.25, Echo, `testify`, `mp4ff` 0.52.0, JSONL, Markdown.

---

## Scope boundary

This single plan contains two sequential gates.

- Tasks 1–14 implement STT and select one pinned text model.
- Tasks 15–26 implement the production backend and mobile editor flow with that winner.
- Do not start Task 15 until Task 14 records one production model and the user approves it.
- Do not add database writes, direct note mutation in the backend, desktop dictation, persistent audio, offline queues, live transcription, model fallback routing, or compatibility paths.
- Do not ship a text model that fails one production gate.

## Fixed decisions

- STT model: `@cf/openai/whisper-large-v3-turbo`.
- Audio limit: five minutes. The Worker rejects bodies above 25 MiB. Task 16 adds server-side M4A duration validation before production upload processing.
- Text candidates:
  - `@cf/qwen/qwen3-30b-a3b-fp8`
  - `@cf/zai-org/glm-4.7-flash`
  - `@cf/google/gemma-4-26b-a4b-it`
  - `@cf/openai/gpt-oss-20b`
  - `@cf/openai/gpt-oss-120b`
  - `@cf/meta/llama-3.3-70b-instruct-fp8-fast`
  - `deepseek-v4-flash`
  - `gemini-3.5-flash-lite`
  - `gpt-5.6-terra`, reference candidate only
- Round 1: 20 cases, one run per candidate.
- Round 2: three finalists, 40 difficult cases, three runs per case.
- Weights: structure 35%, task metadata 25%, fidelity 20%, consistency 10%, cleanup 5%, output validity 5%.
- A model cannot ship unless it passes every production gate from the design.
- The application will use one winner. Do not implement runtime fallback routing.

## Required environment

Use environment variables. Never put values in source files, shell history examples, reports, or test fixtures.

```text
CLOUDFLARE_ACCOUNT_ID
CLOUDFLARE_API_TOKEN
CLOUDFLARE_DICTATION_EVAL_URL
CLOUDFLARE_DICTATION_EVAL_TOKEN
DEEPSEEK_API_KEY
GEMINI_API_KEY
OPENAI_API_KEY
```

The evaluation command must skip a candidate when its credential is absent and report the missing variable. A complete round is invalid while any non-reference candidate is skipped. The OpenAI reference may be skipped when the account cannot access `gpt-5.6-terra`; record that fact in the report.

## Target file map

```text
workers/dictation-stt/
  package.json
  tsconfig.json
  wrangler.jsonc
  src/index.ts
  test/index.test.ts

backend/cmd/dictation-eval/main.go
backend/internal/dictation/
  contract.go
  contract_test.go
  prompt.go
  prompt_test.go
  audio.go
  audio_test.go
  stt_client.go
  stt_client_test.go
  structurer.go
  structurer_test.go
  service.go
  service_test.go
  handler.go
  handler_test.go
backend/internal/dictationeval/
  catalog.go
  provider.go
  provider_test.go
  runner.go
  runner_test.go
  scoring.go
  scoring_test.go
  review.go
  review_test.go
  testdata/round1.json
  testdata/round2.json

docs/evaluations/dictation-models/
  README.md
  decision.md

lib/features/notes/dictation/
  domain/dictation_plan.dart
  domain/dictation_state.dart
  data/dictation_repository.dart
  application/audio_recorder_service.dart
  application/dictation_flow_controller.dart
  presentation/dictation_sheet.dart

test/features/notes/dictation/
  dictation_plan_test.dart
  dictation_repository_test.dart
  audio_recorder_service_test.dart
  dictation_flow_controller_test.dart
  dictation_editor_commands_test.dart
  dictation_sheet_test.dart
```

Runtime artifacts go under `backend/tmp/dictation-eval/`, which is already outside the committed source path. Do not commit audio, raw provider responses, blind-review mappings, credentials, or user content.

## Task 1: Add the typed block-plan contract and strict validator

**Files:**
- Create: `backend/internal/dictation/contract.go`
- Create: `backend/internal/dictation/contract_test.go`

- [ ] **Step 1: Write failing contract tests**

Cover one valid plan containing every block type, plus these invalid cases: unknown block type, blank text where text is required, text on a divider, task without metadata, task marked complete, unsupported recurrence, reminder without due data, invalid RFC 3339 date-time, and unknown JSON fields.

Use these public types so all later tasks share one contract:

```go
type BlockType string

const (
    BlockParagraph   BlockType = "paragraph"
    BlockHeader1     BlockType = "header1"
    BlockHeader2     BlockType = "header2"
    BlockHeader3     BlockType = "header3"
    BlockQuote       BlockType = "quote"
    BlockBulletList  BlockType = "bulletList"
    BlockOrderedList BlockType = "orderedList"
    BlockTask        BlockType = "task"
    BlockDivider     BlockType = "divider"
)

type BlockPlan struct {
    ContractVersion int      `json:"contractVersion"`
    Transcript      string   `json:"transcript"`
    Language        string   `json:"language"`
    Blocks          []Block  `json:"blocks"`
    Warnings        []string `json:"warnings"`
}

type Block struct {
    Type         BlockType     `json:"type"`
    Text         string        `json:"text"`
    Indent       int           `json:"indent"`
    TaskMetadata *TaskMetadata `json:"taskMetadata"`
}

type TaskMetadata struct {
    DueDate     *string `json:"dueDate"`
    HasTime     bool    `json:"hasTime"`
    Recurrence  *string `json:"recurrence"`
    Reminder    *string `json:"reminder"`
    IsCompleted bool    `json:"isCompleted"`
}

func DecodeAndValidatePlan(raw []byte) (BlockPlan, error)
```

Use `json.Decoder.DisallowUnknownFields()`. Require `contractVersion == 1`, a non-empty cleaned transcript, a non-empty BCP-47-like language string, a non-null warnings array, and at least one block. Accept only `daily`, `weekdays`, `weekly`, and `monthly` recurrence. Accept only `at_time`, `5m_before`, `1h_before`, `1d_before`, `9am`, `12pm`, `6pm`, and `1d_before_9am` reminders. Require `isCompleted == false` and `indent >= 0`. Parse `dueDate` with `time.RFC3339`. A reminder requires `dueDate`. A task requires `taskMetadata`; every other type requires `taskMetadata == null`. A divider requires empty text; every other block requires non-empty text.

- [ ] **Step 2: Prove the tests fail**

Run:

```powershell
rtk go test ./internal/dictation -run TestDecodeAndValidatePlan -count=1
```

Expected: compilation fails because `DecodeAndValidatePlan` does not exist.

- [ ] **Step 3: Implement the contract and validator**

Return errors that name the block index and failed field. Do not repair output here. The runner owns the one permitted retry.

- [ ] **Step 4: Run and commit**

```powershell
rtk go test ./internal/dictation -run TestDecodeAndValidatePlan -count=1
rtk git add backend/internal/dictation/contract.go backend/internal/dictation/contract_test.go
rtk git commit -m "test(dictation): define structured block plan contract"
```

Expected: tests pass and the commit contains only the two contract files.

## Task 2: Freeze one semantic prompt and JSON schema

**Files:**
- Create: `backend/internal/dictation/prompt.go`
- Create: `backend/internal/dictation/prompt_test.go`

- [ ] **Step 1: Write failing prompt snapshot tests**

Require `BuildPrompt` to include the transcript, `recorded_at`, timezone, contract version, all block types, all metadata enums, and these semantic rules:

- Infer structure from the complete meaning. Do not use keyword triggers.
- Keep meaning, facts, order, tone, and language.
- Remove only clear hesitation and accidental repetition.
- Do not summarize, translate, or invent content or metadata.
- A sequence of future actions can become separate pending tasks.
- Completed actions stay prose and never become checked tasks.
- Use a numbered list for ordered steps and a bullet list for unordered items.
- Use a quote only for quoted speech or a passage presented as a quotation.
- Use a divider only for a clear topic change.
- Resolve unambiguous relative dates from `recorded_at` and the IANA timezone.
- Preserve ambiguous time expressions in text and leave metadata null.
- Set a reminder only when the speaker asks for one.
- Do not approximate unsupported recurrence.
- Return JSON only.

Use this signature:

```go
type PromptInput struct {
    Transcript     string
    RecordedAt     time.Time
    Timezone       string
    ContractVersion int
}

type Prompt struct {
    System string
    User   string
    Schema json.RawMessage
    SHA256 string
}

func BuildPrompt(input PromptInput) (Prompt, error)
```

The SHA-256 must cover the exact system message, user-message template, and schema. The report uses it to prove that all models received the same instructions.

- [ ] **Step 2: Run the failing test**

```powershell
rtk go test ./internal/dictation -run TestBuildPrompt -count=1
```

Expected: compilation fails because `BuildPrompt` does not exist.

- [ ] **Step 3: Implement the fixed prompt**

Put the full contract in `const systemPrompt`. Build the JSON Schema from one raw string constant. Set `additionalProperties: false` at every object level. The schema must match Task 1 exactly. Do not put candidate-specific instructions in the prompt.

- [ ] **Step 4: Run and commit**

```powershell
rtk go test ./internal/dictation -run "Test(BuildPrompt|PromptSchemaMatchesContract)" -count=1
rtk git add backend/internal/dictation/prompt.go backend/internal/dictation/prompt_test.go
rtk git commit -m "feat(dictation): freeze semantic structuring prompt"
```

## Task 3: Add the fixed candidate catalog and cost snapshot

**Files:**
- Create: `backend/internal/dictationeval/catalog.go`
- Create: `backend/internal/dictationeval/catalog_test.go`

- [ ] **Step 1: Add a failing catalog test**

Require exactly nine unique candidate IDs and these values:

```go
type ProviderKind string

const (
    ProviderCloudflare ProviderKind = "cloudflare"
    ProviderDeepSeek   ProviderKind = "deepseek"
    ProviderGemini     ProviderKind = "gemini"
    ProviderOpenAI     ProviderKind = "openai"
)

type Candidate struct {
    ID                   string
    Provider             ProviderKind
    Model                string
    InputUSDPerMTokens   float64
    OutputUSDPerMTokens  float64
    APIKeyEnv            string
    ReferenceOnly        bool
}
```

Use this price snapshot, captured on 2026-08-11:

| Candidate | Input USD/M | Output USD/M | Reference only |
|---|---:|---:|---|
| Qwen3 30B A3B | 0.051 | 0.335 | no |
| GLM 4.7 Flash | 0.060 | 0.400 | no |
| Gemma 4 26B | 0.100 | 0.300 | no |
| GPT-OSS 20B | 0.200 | 0.300 | no |
| GPT-OSS 120B | 0.350 | 0.750 | no |
| Llama 3.3 70B | 0.293 | 2.253 | no |
| DeepSeek V4 Flash | 0.140 | 0.280 | no |
| Gemini 3.5 Flash-Lite | 0.300 | 2.500 | no |
| GPT-5.6 Terra | use account usage data | use account usage data | yes |

For the OpenAI reference, store zero catalog prices and mark cost as unavailable when the response does not expose billed cost. Do not treat zero as free.

- [ ] **Step 2: Implement `Candidates()` and validate it**

```go
func Candidates() []Candidate
func ValidateCatalog(candidates []Candidate) error
```

Cloudflare candidates use `CLOUDFLARE_API_TOKEN`; DeepSeek uses `DEEPSEEK_API_KEY`; Gemini uses `GEMINI_API_KEY`; OpenAI uses `OPENAI_API_KEY`.

- [ ] **Step 3: Run and commit**

```powershell
rtk go test ./internal/dictationeval -run TestCandidateCatalog -count=1
rtk git add backend/internal/dictationeval/catalog.go backend/internal/dictationeval/catalog_test.go
rtk git commit -m "feat(dictation): add evaluation candidate catalog"
```

## Task 4: Build the provider clients behind one interface

**Files:**
- Create: `backend/internal/dictationeval/provider.go`
- Create: `backend/internal/dictationeval/provider_test.go`

- [ ] **Step 1: Write HTTP contract tests with `httptest.Server`**

Test the Cloudflare/OpenAI-compatible, DeepSeek, Gemini, and OpenAI request and response shapes. Also test 401, 429 with `Retry-After`, 500, malformed JSON, missing content, and request cancellation.

Use these interfaces and result types:

```go
type ModelRequest struct {
    Prompt dictation.Prompt
}

type ModelResponse struct {
    Model        string
    Content      []byte
    InputTokens  int
    OutputTokens int
    RequestID    string
}

type ModelClient interface {
    Generate(context.Context, Candidate, ModelRequest) (ModelResponse, error)
}

type HTTPModelClient struct {
    Client             *http.Client
    CloudflareAccountID string
    Env                func(string) string
}
```

For Cloudflare use:

```text
POST https://api.cloudflare.com/client/v4/accounts/{account}/ai/v1/chat/completions
Authorization: Bearer {CLOUDFLARE_API_TOKEN}
```

For DeepSeek use `POST https://api.deepseek.com/chat/completions`. For OpenAI use `POST https://api.openai.com/v1/chat/completions`. Both use bearer authentication. For these three transports, send the same system and user messages, `temperature: 0`, and `response_format: {"type":"json_object"}`. The schema stays in the shared prompt; do not use provider-specific strict schemas.

For Gemini use:

```text
POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent
x-goog-api-key: {GEMINI_API_KEY}
```

Send the shared system instruction and user content, `temperature: 0`, and `responseMimeType: application/json`. Do not pass `responseJsonSchema`, because all candidates must solve the same prompt-level contract.

- [ ] **Step 2: Prove the tests fail**

```powershell
rtk go test ./internal/dictationeval -run TestHTTPModelClient -count=1
```

- [ ] **Step 3: Implement the client**

Use one `http.Client` with a 45-second timeout. Limit response bodies to 2 MiB with `http.MaxBytesReader` equivalent logic. Return a typed error with HTTP status, provider request ID, and whether the failure is retryable. Never include prompts, transcripts, or response bodies in errors.

- [ ] **Step 4: Run and commit**

```powershell
rtk go test ./internal/dictationeval -run TestHTTPModelClient -count=1
rtk git add backend/internal/dictationeval/provider.go backend/internal/dictationeval/provider_test.go
rtk git commit -m "feat(dictation): add model evaluation clients"
```

## Task 5: Create the 20-case Round 1 corpus

**Files:**
- Create: `backend/internal/dictationeval/testdata/round1.json`
- Create: `backend/internal/dictationeval/runner_test.go`

- [ ] **Step 1: Define the corpus schema in the runner test**

```go
type EvalCase struct {
    ID                 string              `json:"id"`
    Language           string              `json:"language"`
    Transcript         string              `json:"transcript"`
    RecordedAt         string              `json:"recorded_at"`
    Timezone           string              `json:"timezone"`
    RequiredBlockTypes []dictation.BlockType `json:"required_block_types"`
    ForbiddenBlockTypes []dictation.BlockType `json:"forbidden_block_types"`
    MetadataChecks     []MetadataCheck     `json:"metadata_checks"`
    RequiredFacts      []string            `json:"required_facts"`
    ForbiddenClaims    []string            `json:"forbidden_claims"`
    Source             string              `json:"source"`
}

type MetadataCheck struct {
    TaskContains string  `json:"task_contains"`
    DueDate      *string `json:"due_date"`
    HasTime      *bool   `json:"has_time"`
    Recurrence   *string `json:"recurrence"`
    Reminder     *string `json:"reminder"`
}
```

The loader rejects duplicate IDs, invalid timestamps, invalid timezones, empty transcripts, and unknown source values. Allowed sources are `clean`, `synthetic_noise`, and `whisper`.

- [ ] **Step 2: Add these exact cases**

All cases use `recorded_at=2026-08-11T10:00:00-03:00` and `timezone=America/Sao_Paulo`, unless the row states another value.

| ID | Transcript | Required result |
|---|---|---|
| r1-01 | `A ideia central é reduzir o tempo de abertura da nota sem remover a sincronização.` | one paragraph; keep both facts |
| r1-02 | `Plano de lançamento. Primeiro validar o build, depois publicar no TestFlight e por fim avisar a equipe.` | header plus ordered list; no tasks |
| r1-03 | `Comprar café, leite e pão.` | one bullet list; no task |
| r1-04 | `Preciso ligar para a Ana, enviar o contrato e pagar a fatura.` | three pending tasks |
| r1-05 | `Contexto do cliente: ele usa Android. Ações: revisar o crash e mandar uma resposta até amanhã às três da tarde.` | paragraph plus two tasks; response due `2026-08-12T15:00:00-03:00` |
| r1-06 | `O Pedro disse abre aspas não publique isso hoje fecha aspas.` | one quote containing the quoted sentence; do not invent speaker text |
| r1-07 | `Projeto Atlas. O backend está pronto. Mudando de assunto, ideias para férias: conhecer Cusco e Lima.` | clear topic sections with divider; preserve both places |
| r1-08 | `Me lembra de renovar o certificado sexta-feira às nove da manhã, um dia antes às nove.` | one task; due `2026-08-14T09:00:00-03:00`; reminder `1d_before_9am` |
| r1-09 | `Todo dia útil revisar os alertas às oito.` | one task; recurrence `weekdays`; due time 08:00 |
| r1-10 | `Eu já enviei o relatório e fechei o chamado.` | prose, not tasks, and no checked task |
| r1-11 | `Talvez falar com a Maria mais tarde.` | preserve ambiguity; no due date or reminder |
| r1-12 | `É, então, eu eu acho que a gente deve, deve simplificar o cadastro sem tirar a confirmação por e-mail.` | cleaned paragraph; preserve email confirmation |
| r1-13 | `Shopping list: apples, rice, and soap.` | English bullet list; language `en` |
| r1-14 | `Revisar el contrato mañana y send the final PDF to John.` | two pending tasks; keep mixed language; no translation |
| r1-15 | `Checklist da viagem: passaporte, carregador, remédios. Depois reservar o táxi para sábado.` | bullet list plus one task; Saturday date resolved |
| r1-16 | `Na primeira semana de cada trimestre revisar os números.` | no supported recurrence metadata; preserve temporal phrase in task text |
| r1-17 | `Título: Retrospectiva. Funcionou bem a comunicação. Não funcionou o tempo de resposta.` | header and two paragraphs; no tasks |
| r1-18 | `A senha é azul. Não, corrigindo, a cor do protótipo é azul.` | keep only corrected fact; never claim password is blue |
| r1-19 | `Fazer backup mensal no dia quinze às seis da tarde e me lembrar uma hora antes.` | task; monthly; due day 15 at 18:00; reminder `1h_before` |
| r1-20 | `Um dois testando. A tarefa é conferir o microfone amanhã. Um dois.` | remove test chatter; one task due tomorrow; do not lose microphone action |

Encode the expectations with `required_block_types`, `forbidden_block_types`, metadata checks, required facts, and forbidden claims. Do not store a single exact “gold answer”; several block arrangements can be semantically correct.

- [ ] **Step 3: Test and commit the corpus**

```powershell
rtk go test ./internal/dictationeval -run TestLoadRound1Corpus -count=1
rtk git add backend/internal/dictationeval/testdata/round1.json backend/internal/dictationeval/runner_test.go
rtk git commit -m "test(dictation): add round one evaluation corpus"
```

## Task 6: Implement repeatable runs, one validation retry, and sanitized JSONL

**Files:**
- Create: `backend/internal/dictationeval/runner.go`
- Modify: `backend/internal/dictationeval/runner_test.go`

- [ ] **Step 1: Write failing runner tests**

Test one successful response, invalid JSON followed by one successful retry, two invalid responses, retryable 429 followed by success, permanent 400 without retry, stable run IDs, cost calculation, and output-directory permissions.

Use these types:

```go
type RunOptions struct {
    Round       int
    Repetitions int
    OutputDir   string
    Candidates []Candidate
}

type RunRecord struct {
    RunID           string    `json:"run_id"`
    Round           int       `json:"round"`
    CaseID          string    `json:"case_id"`
    CandidateID     string    `json:"candidate_id"`
    Repetition      int       `json:"repetition"`
    PromptSHA256    string    `json:"prompt_sha256"`
    Model           string    `json:"model"`
    Plan            *dictation.BlockPlan `json:"plan,omitempty"`
    Valid           bool      `json:"valid"`
    Attempts        int       `json:"attempts"`
    LatencyMS       int64     `json:"latency_ms"`
    InputTokens     int       `json:"input_tokens"`
    OutputTokens    int       `json:"output_tokens"`
    EstimatedUSD    *float64  `json:"estimated_usd,omitempty"`
    ErrorCode       string    `json:"error_code,omitempty"`
}

type Runner struct {
    Client ModelClient
    Now    func() time.Time
}

func (r Runner) Run(ctx context.Context, cases []EvalCase, options RunOptions) ([]RunRecord, error)
```

- [ ] **Step 2: Implement the runner**

Retry at most once. Retry only 429, 5xx, network timeout, malformed JSON, or contract validation failure. On a validation retry, append only this fixed user message: `Your previous response did not match the contract. Return one valid JSON object only. Do not change the transcript meaning.`

Use a deterministic loop order: case, candidate, repetition. Write one JSONL record after each request with `os.OpenFile(..., 0600)`. Never write the transcript, prompt, raw response, API key, or authorization header to the run file. The case ID links results to the committed synthetic corpus.

Compute text cost from response token counts and catalog rates. Add a fixed STT estimate of US$0.0025 only in final five-minute cost projections, not per text request.

- [ ] **Step 3: Run and commit**

```powershell
rtk go test ./internal/dictationeval -run TestRunner -count=1
rtk git add backend/internal/dictationeval/runner.go backend/internal/dictationeval/runner_test.go
rtk git commit -m "feat(dictation): add repeatable model evaluation runner"
```

## Task 7: Implement hard scoring and the production gates

**Files:**
- Create: `backend/internal/dictationeval/scoring.go`
- Create: `backend/internal/dictationeval/scoring_test.go`

- [ ] **Step 1: Write failing scoring tests**

Test exact metadata matching, case-insensitive fact matching, forbidden claims, block constraints, validity after one retry, p50/p95 latency, median review score, weighted total, and every production gate.

```go
type ManualScore struct {
    RunID             string `json:"run_id"`
    Structure         int    `json:"structure"`
    Fidelity          int    `json:"fidelity"`
    Cleanup           int    `json:"cleanup"`
    CriticalInvention bool   `json:"critical_invention"`
    Notes             string `json:"notes"`
}

type CandidateScore struct {
    CandidateID          string
    StructureScore       float64
    MetadataAccuracy     float64
    FidelityScore        float64
    ConsistencyScore     float64
    CleanupScore         float64
    ValidityRate         float64
    WeightedScore        float64
    CriticalInventions   int
    FiveMinuteCostUSD    *float64
    PortugueseAccepted   bool
    WhisperNoiseAccepted bool
    GatesPassed          bool
    FailedGates          []string
}

func Score(cases []EvalCase, runs []RunRecord, reviews []ManualScore) ([]CandidateScore, error)
```

Scoring rules:

- Convert each 1–5 manual score to a 0–1 value with `(score-1)/4`.
- Metadata accuracy is exact correct fields divided by all unambiguous expected fields.
- Output validity is valid results after at most two attempts divided by all requested runs.
- Consistency is 1 minus the mean normalized pairwise disagreement across the three Round 2 plans. Compare block-type sequence, task count, and exact metadata. Clamp to 0–1.
- Weighted total is `0.35*structure + 0.25*metadata + 0.20*fidelity + 0.10*consistency + 0.05*cleanup + 0.05*validity`.
- Round 1 has no consistency score and does not decide the winner. Rank it with weights renormalized across the other five dimensions.
- Portuguese is accepted when Portuguese cases have median structure and fidelity at least 4/5 and zero critical inventions.
- Whisper noise is accepted by the same rule on `source=whisper` cases.
- Five-minute cost is the observed p95 text request cost plus US$0.0025 STT.

Production gates:

- median structure score at least 4/5;
- metadata accuracy at least 0.95;
- zero critical inventions in Round 2;
- validity at least 0.99 after no more than one retry;
- five-minute p95 cost at most US$0.01;
- Portuguese accepted;
- Whisper noise accepted.

- [ ] **Step 2: Implement, test, and commit**

```powershell
rtk go test ./internal/dictationeval -run "Test(Score|ProductionGates)" -count=1
rtk git add backend/internal/dictationeval/scoring.go backend/internal/dictationeval/scoring_test.go
rtk git commit -m "feat(dictation): score semantic quality and production gates"
```

## Task 8: Implement blinded review artifacts

**Files:**
- Create: `backend/internal/dictationeval/review.go`
- Create: `backend/internal/dictationeval/review_test.go`

- [ ] **Step 1: Write failing blinding tests**

The public review file must contain transcript, temporal context, anonymous output label, parsed plan, and empty numeric score fields. It must not contain provider, candidate, model, price, request ID, or token counts. A separate mapping file stays in the temporary directory.

```go
type ReviewBundle struct {
    PublicPath  string
    MappingPath string
}

func PrepareBlindReview(cases []EvalCase, runs []RunRecord, outputDir string, seed int64) (ReviewBundle, error)
func LoadManualScores(publicPath, mappingPath string) ([]ManualScore, error)
```

Use a seeded Fisher–Yates shuffle per case. Assign anonymous labels in sequence from `A` through the last executed candidate (`I` when the reference is available) for Round 1 and from `A` through `C` for Round 2; repetitions are also shuffled. The editable public artifact is JSON so the loader can validate scores. Score values start at zero and the loader rejects zero; reviewers must enter 1–5 before aggregation.

- [ ] **Step 2: Implement, test, and commit**

```powershell
rtk go test ./internal/dictationeval -run TestBlindReview -count=1
rtk git add backend/internal/dictationeval/review.go backend/internal/dictationeval/review_test.go
rtk git commit -m "feat(dictation): add blinded semantic review workflow"
```

## Task 9: Implement and test the private Cloudflare STT Worker

**Files:**
- Create: `workers/dictation-stt/package.json`
- Create: `workers/dictation-stt/tsconfig.json`
- Create: `workers/dictation-stt/wrangler.jsonc`
- Create: `workers/dictation-stt/src/index.ts`
- Create: `workers/dictation-stt/test/index.test.ts`

- [ ] **Step 1: Add the Worker package and failing tests**

Use these scripts:

```json
{
  "name": "supanotes-dictation-stt",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "vitest run",
    "typecheck": "tsc --noEmit",
    "deploy": "wrangler deploy"
  },
  "devDependencies": {
    "@cloudflare/workers-types": "latest",
    "typescript": "latest",
    "vitest": "latest",
    "wrangler": "latest"
  }
}
```

Tests must cover: `GET /health`, `POST /transcribe`, bearer token match, supported audio content types, empty body, 25 MiB limit, AI binding failure, missing transcription, and successful output. Inject the AI call into `handleRequest` so unit tests do not call Cloudflare.

- [ ] **Step 2: Implement the exact Worker contract**

```ts
export interface Env {
  AI: Ai;
  DICTATION_SERVICE_TOKEN: string;
}

export type Transcribe = (audio: number[]) => Promise<{ text?: string }>;

export async function handleRequest(
  request: Request,
  env: Env,
  transcribe: Transcribe = async (audio) =>
    env.AI.run('@cf/openai/whisper-large-v3-turbo', {
      audio,
      task: 'transcribe',
    }) as Promise<{ text?: string }>,
): Promise<Response>
```

Return `{ "status": "ok", "model": "@cf/openai/whisper-large-v3-turbo" }` from unauthenticated `GET /health` without calling AI. For `/transcribe`, only accept `audio/mpeg`, `audio/mp4`, `audio/x-m4a`, `audio/wav`, `audio/webm`, and `audio/ogg`. Return JSON errors without request content. Return `401` for a missing or wrong token, `404` for another path, `405` for another method, `413` above 25 MiB, `415` for another content type, `422` for an empty body or blank transcription, and `502` when Workers AI fails. Return `{ "text": "..." }` on success. Do not log audio or transcription.

Use this Worker configuration:

```jsonc
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "supanotes-dictation-stt",
  "main": "src/index.ts",
  "compatibility_date": "2026-08-11",
  "ai": { "binding": "AI" }
}
```

- [ ] **Step 3: Test and commit**

```powershell
rtk npm install
rtk npm test
rtk npm run typecheck
rtk git add workers/dictation-stt
rtk git commit -m "feat(dictation): add private Cloudflare STT worker"
```

Run the npm commands from `workers/dictation-stt`. Expected: all tests pass and TypeScript reports no errors.

## Task 10: Add STT fixture ingestion and create real Whisper-noise cases

**Files:**
- Create: `backend/internal/dictation/stt_client.go`
- Create: `backend/internal/dictation/stt_client_test.go`
- Create: `backend/cmd/dictation-eval/main.go`
- Modify: `backend/internal/dictationeval/testdata/round2.json`

- [ ] **Step 1: Write failing STT client tests**

```go
type WorkerTranscriber struct {
    Client *http.Client
    URL    string
    Token  string
}

type Transcript struct {
    Text      string
    Model     string
    Duration  time.Duration
    RequestID string
    Attempts  int
}

func (c WorkerTranscriber) Transcribe(ctx context.Context, audioPath, contentType string) (Transcript, error)
```

Test bearer authentication, streamed file body, content type, success, 401, 413, 502, invalid JSON, blank text, response body limit, timeout, and safe errors without transcript content or file paths.

- [ ] **Step 2: Implement and test the client**

Use a 90-second client timeout and a 1 MiB response limit. Open the file inside `Transcribe` and close it on every path.

```powershell
rtk go test ./internal/dictation -run TestWorkerTranscriber -count=1
```

- [ ] **Step 3: Deploy the evaluation Worker**

From `workers/dictation-stt`:

```powershell
rtk npx wrangler secret put DICTATION_SERVICE_TOKEN
rtk npm run deploy
```

Store the returned URL in `CLOUDFLARE_DICTATION_EVAL_URL`. Store the same secret in `CLOUDFLARE_DICTATION_EVAL_TOKEN`. Do not write either value to the repository.

- [ ] **Step 4: Record five scripted, non-sensitive fixtures on a real phone**

Record each script naturally. Include normal pauses, one correction, and ordinary room noise. Save them outside Git under `backend/tmp/dictation-eval/audio/`:

1. `pt_tasks.m4a`: “Preciso enviar o orçamento para a Carla amanhã às três, revisar o contrato e me lembrar do orçamento uma hora antes.”
2. `pt_mixed.m4a`: “Notas do projeto. O login ficou mais rápido. Mudando de assunto, próximos passos: medir no Android, falar com suporte e publicar o resultado sexta-feira.”
3. `pt_correction.m4a`: “A reunião é terça às duas, não, corrigindo, quarta às duas da tarde. Me lembra um dia antes.”
4. `en_steps.m4a`: “Release steps. First run the tests, then build iOS, and finally notify the team.”
5. `mixed_language.m4a`: “Comprar café e pão, then send the invoice to Mark tomorrow morning.”

- [ ] **Step 5: Add the first CLI command and transcribe each fixture once**

Add `transcribe-fixtures --audio-dir <path>` to `backend/cmd/dictation-eval/main.go`. It reads the five named files, calls the Worker, and prints JSON cases to standard output. Run:

```powershell
rtk go run ./cmd/dictation-eval transcribe-fixtures --audio-dir ./tmp/dictation-eval/audio
```

Review the output for accidental personal information. Then copy only the transcript strings into the five `source: "whisper"` Round 2 entries. Delete the audio after the corpus commit.

- [ ] **Step 6: Commit code and sanitized corpus only**

```powershell
rtk git add backend/internal/dictation/stt_client.go backend/internal/dictation/stt_client_test.go backend/internal/dictationeval/testdata/round2.json backend/cmd/dictation-eval/main.go
rtk git commit -m "test(dictation): add real Whisper-noise evaluation cases"
```

Expected: `rtk git status --short` shows no audio file.

## Task 11: Create the 40-case Round 2 corpus

**Files:**
- Complete: `backend/internal/dictationeval/testdata/round2.json`
- Modify: `backend/internal/dictationeval/runner_test.go`

- [ ] **Step 1: Add 35 difficult text cases plus the five Whisper cases**

Use the same fixed time as Round 1 unless stated. The five `w` rows receive the actual transcript from Task 10. All other transcript text is exact.

| ID | Source | Transcript and required distinction |
|---|---|---|
| r2-01 | clean | `Ideias, comprar pão talvez, mas a ação de hoje é revisar o pull request.` Only review is a task. |
| r2-02 | clean | `Para configurar: abra Ajustes, toque em Conta, escolha Segurança.` Ordered steps, not tasks. |
| r2-03 | clean | `A equipe precisa abrir Ajustes, tocar em Conta e ativar MFA em todos os aparelhos.` Three tasks are acceptable; ordered instructions are not. Human review decides semantic fit. |
| r2-04 | clean | `Ele falou: não apague a fila pendente.` Quote; no task assigned to the user. |
| r2-05 | clean | `Não esquecer: a fila pendente é canônica. Depois, verificar a fila amanhã.` Paragraph plus one task. |
| r2-06 | clean | `Já revisei a tela. Falta testar no iPhone e corrigir o espaçamento.` Two pending tasks; completed review stays prose. |
| r2-07 | clean | `Toda segunda revisar métricas.` Weekly task anchored to Monday. |
| r2-08 | clean | `A cada duas semanas revisar métricas.` Unsupported recurrence stays in text; recurrence null. |
| r2-09 | clean | `Dia primeiro de cada mês pagar aluguel às oito.` Monthly task; due time 08:00. |
| r2-10 | clean | `Me avisa sobre o deploy.` Task text preserved; reminder null because time is absent. |
| r2-11 | clean | `Me lembra às nove de ligar para a Ana amanhã.` Due tomorrow 09:00; reminder `at_time`. |
| r2-12 | clean | `Ligar para Ana amanhã, talvez de manhã.` Date may resolve; exact time stays null. |
| r2-13 | clean | `Amanhã ou quinta eu ligo para Ana.` Ambiguous date stays in task text and metadata null. |
| r2-14 | clean | `Na próxima sexta às 14h revisar o contrato.` Resolve using the fixed São Paulo context. |
| r2-15 | clean | `At 3 PM tomorrow, enviar o relatório.` Mixed language, one task, no translation. |
| r2-16 | clean | `Compras. Café. Leite. Trabalho. Revisar logs. Atualizar alerta.` Two sections with divider; shopping list and work tasks. |
| r2-17 | clean | `Retrospectiva: bom, entrega rápida; ruim, crash no login; ação, adicionar teste.` Header, prose, one task. |
| r2-18 | clean | `Um título talvez fosse Melhorias, mas escreva apenas que o cache reduziu a latência.` One paragraph, not a header invented from the suggestion. |
| r2-19 | clean | `Citação para guardar: simplicidade é remover o desnecessário.` Quote is acceptable; do not attribute an author. |
| r2-20 | clean | `Não é uma citação. O botão mostra o texto “Salvar agora”.` Paragraph; quoted UI label stays inline, not a quote block. |
| r2-21 | synthetic_noise | `é revisar revisar o build amanhã e e publicar depois quer dizer publicar só se passar` One conditional sequence; no unconditional publish task. |
| r2-22 | synthetic_noise | `teste microfone hum tarefas pagar conta sexta lembrar um dia antes nove horas` Recover one task and temporal metadata without inventing amount. |
| r2-23 | synthetic_noise | `projeto atlas backend pronto assunto férias cusco lima` Recover two topics; divider and places preserved. |
| r2-24 | synthetic_noise | `já fiz backup não fazer de novo mas conferir se abriu` Only check result is pending. |
| r2-25 | synthetic_noise | `todo todo dia não dias úteis olhar alertas oito` Apply correction: weekdays, not daily. |
| r2-26 | clean | `Criar as tarefas “revisar contrato” e “enviar proposta”, mas não criar tarefa para esta própria instrução.` Exactly two tasks. |
| r2-27 | clean | `Lista de ações concluídas: liguei, enviei e paguei.` Not pending tasks. |
| r2-28 | clean | `Possíveis ações: ligar, enviar ou esperar.` Bullet list of options, not three committed tasks. |
| r2-29 | clean | `Decidimos ligar e enviar hoje.` Two tasks due on recorded date; no reminder. |
| r2-30 | clean | `Antes de enviar, revisar; depois de enviar, arquivar.` Ordered process; task interpretation must preserve dependencies. |
| r2-31 | clean | `Cabeçalho um: Segurança. Cabeçalho dois: Autenticação. Texto: MFA é obrigatório.` Header hierarchy and paragraph. |
| r2-32 | clean | `Primeiro assunto sem título: latência caiu. Segundo assunto sem título: custo subiu.` Two prose sections with divider; do not invent headings. |
| r2-33 | clean | `The task is revisar o contrato on Friday at noon.` Mixed language, one task, date and 12:00. |
| r2-34 | clean | `Revisar contrato sexta ao meio-dia, sem lembrete.` Due set; reminder null. |
| r2-35 | clean | `Revisar contrato todo mês e lembrar às seis da tarde.` Monthly; reminder is ambiguous without a due occurrence and must stay null. |
| r2-w1 | whisper | Task 10 writes the transcript returned for `pt_tasks.m4a`; preserve two actions and reminder relation. |
| r2-w2 | whisper | Task 10 writes the transcript returned for `pt_mixed.m4a`; preserve topic shift, facts, and future actions. |
| r2-w3 | whisper | Task 10 writes the transcript returned for `pt_correction.m4a`; Wednesday replaces Tuesday. |
| r2-w4 | whisper | Task 10 writes the transcript returned for `en_steps.m4a`; ordered list, not tasks. |
| r2-w5 | whisper | Task 10 writes the transcript returned for `mixed_language.m4a`; bullet item context plus one future task, no translation. |

The corpus test must reject any `r2-w*` transcript that equals its fixture script, is blank, or starts with `Task 10 writes`.

- [ ] **Step 2: Test corpus completeness**

Require exactly 40 unique cases, five `source=whisper` cases, at least ten metadata checks, all supported block types across expectations, Portuguese, English, and mixed-language coverage.

```powershell
rtk go test ./internal/dictationeval -run TestLoadRound2Corpus -count=1
rtk git add backend/internal/dictationeval/testdata/round2.json backend/internal/dictationeval/runner_test.go
rtk git commit -m "test(dictation): complete difficult evaluation corpus"
```

## Task 12: Add the evaluation CLI and operator guide

**Files:**
- Modify: `backend/cmd/dictation-eval/main.go`
- Create: `docs/evaluations/dictation-models/README.md`

- [ ] **Step 1: Add CLI integration tests through an extracted `run` function**

```go
func run(ctx context.Context, args []string, stdout, stderr io.Writer, getenv func(string) string) int
```

Commands:

```text
dictation-eval validate-corpus
dictation-eval transcribe-fixtures --audio-dir <path>
dictation-eval run --round 1 --output <path>
dictation-eval run --round 2 --finalists-from <round1-score-path> --repetitions 3 --output <path>
dictation-eval prepare-review --runs <path> --output <path> --seed <integer>
dictation-eval score --runs <path> --reviews <path> --mapping <path> --output <path>
```

Reject Round 1 repetitions other than 1. Reject Round 2 finalist counts other than 3 and repetitions other than 3. Print progress as case IDs and candidate IDs only. Never print transcript or response content.

- [ ] **Step 2: Implement the CLI and guide**

The guide must give the exact commands below, explain every score, explain the gates, identify temporary sensitive files, and require deletion of phone audio after corpus creation.

- [ ] **Step 3: Run all local tests and commit**

```powershell
rtk go test ./internal/dictationeval ./cmd/dictation-eval -count=1
rtk git add backend/cmd/dictation-eval/main.go docs/evaluations/dictation-models/README.md
rtk git commit -m "feat(dictation): add model evaluation command"
```

## Task 13: Execute Round 1 and select three finalists

**Files:**
- Runtime only: `backend/tmp/dictation-eval/round1.jsonl`
- Runtime only: `backend/tmp/dictation-eval/round1-review/`
- Modify: `docs/evaluations/dictation-models/decision.md`

- [ ] **Step 1: Validate credentials and corpus**

```powershell
rtk go run ./cmd/dictation-eval validate-corpus
rtk go run ./cmd/dictation-eval run --round 1 --output ./tmp/dictation-eval/round1.jsonl
```

Expected: 180 requested model runs when the reference is available, or 160 production-candidate runs plus one recorded reference skip. Every production candidate must run all 20 cases.

- [ ] **Step 2: Prepare and complete a blind review**

```powershell
rtk go run ./cmd/dictation-eval prepare-review --runs ./tmp/dictation-eval/round1.jsonl --output ./tmp/dictation-eval/round1-review --seed 8112026
```

One reviewer scores structure, fidelity, cleanup, and critical invention for all outputs without opening `mapping.json`. Round 1 can eliminate a candidate for any critical invention, Portuguese median below 3/5, metadata accuracy below 80%, validity below 95% after retry, or projected cost above US$0.01.

- [ ] **Step 3: Score and select the top three eligible candidates**

```powershell
rtk go run ./cmd/dictation-eval score --runs ./tmp/dictation-eval/round1.jsonl --reviews ./tmp/dictation-eval/round1-review/review.json --mapping ./tmp/dictation-eval/round1-review/mapping.json --output ./tmp/dictation-eval/round1-score.json
```

Select the three highest weighted eligible production candidates. The OpenAI reference cannot be a finalist. If fewer than three production candidates remain, stop and revise the prompt or candidate pool through a new design decision; do not lower gates silently.

- [ ] **Step 4: Start the decision record**

Create `decision.md` with the date, prompt SHA, corpus Git commit, candidate/model identifiers, price snapshot links, run counts, exclusions with evidence, and the three finalists. Include aggregate results only. Do not include raw model content.

- [ ] **Step 5: Commit the Round 1 decision record**

```powershell
rtk git add docs/evaluations/dictation-models/decision.md
rtk git commit -m "docs(dictation): record round one model shortlist"
```

## Task 14: Execute Round 2, choose the winner, and close the gate

**Files:**
- Runtime only: `backend/tmp/dictation-eval/round2.jsonl`
- Runtime only: `backend/tmp/dictation-eval/round2-review/`
- Modify: `docs/evaluations/dictation-models/decision.md`

- [ ] **Step 1: Run exactly 360 finalist requests**

```powershell
rtk go run ./cmd/dictation-eval run --round 2 --finalists-from ./tmp/dictation-eval/round1-score.json --repetitions 3 --output ./tmp/dictation-eval/round2.jsonl
```

Expected: 40 cases × 3 candidates × 3 repetitions = 360 run records. A failed record remains in the denominator.

- [ ] **Step 2: Prepare the blind review**

```powershell
rtk go run ./cmd/dictation-eval prepare-review --runs ./tmp/dictation-eval/round2.jsonl --output ./tmp/dictation-eval/round2-review --seed 11082026
```

Two reviewers independently score every result. They must not open `mapping.json` until both review files are complete. Resolve any difference of two or more points with a third blind review. Merge the resolved values into `review.json`.

- [ ] **Step 3: Calculate final scores**

```powershell
rtk go run ./cmd/dictation-eval score --runs ./tmp/dictation-eval/round2.jsonl --reviews ./tmp/dictation-eval/round2-review/review.json --mapping ./tmp/dictation-eval/round2-review/mapping.json --output ./tmp/dictation-eval/round2-score.json
```

The winner is the highest weighted candidate that passes every gate. Do not select a candidate that fails one gate. If no candidate passes, record “no production model selected” and open a new research cycle. Do not add a fallback chain.

- [ ] **Step 4: Complete the decision record**

Add:

- exact winner provider and pinned model ID;
- aggregate score in each weighted dimension;
- median and inter-reviewer disagreement;
- metadata numerator and denominator;
- validity numerator and denominator before and after retry;
- critical-invention count;
- Portuguese and Whisper subset results;
- observed p50 and p95 latency;
- p95 estimated five-minute cost including US$0.0025 STT;
- prompt SHA and corpus commit;
- reasons the other finalists lost;
- approval line with reviewer names and date;
- statement that production integration must use this one model without fallback.

- [ ] **Step 5: Run final verification and commit**

```powershell
rtk go test ./internal/dictationeval ./cmd/dictation-eval -count=1
rtk npm test
rtk npm run typecheck
rtk git status --short
```

Run npm commands from `workers/dictation-stt`. Confirm that Git does not show audio, JSONL, mappings, raw outputs, or credentials.

```powershell
rtk git add docs/evaluations/dictation-models/decision.md
rtk git commit -m "docs(dictation): select production structuring model"
```

## Task 15: Promote the shared contract and implement only the selected structurer

**Gate:** Start only after the user approves the Task 14 winner.

**Files:**
- Create: `backend/internal/dictation/structurer.go`
- Create: `backend/internal/dictation/structurer_test.go`
- Modify: `backend/.env.example`

- [ ] **Step 1: Write the selected-model interface test**

Use the contract and prompt from Tasks 1–2. Production must not import `internal/dictationeval`.

```go
type Structurer interface {
    Structure(ctx context.Context, input PromptInput) (BlockPlan, StructureUsage, error)
}

type StructureUsage struct {
    Model        string
    InputTokens  int
    OutputTokens int
    Attempts     int
    Duration     time.Duration
}

type SelectedModelConfig struct {
    URL    string
    APIKey string
    Model  string
}

func NewSelectedStructurer(client *http.Client, config SelectedModelConfig) (Structurer, error)
```

Test blank configuration, one valid response, provider 401, 429, 500, timeout, invalid JSON followed by one valid response, two invalid responses, unknown fields, and cancellation. Require the model ID returned in `StructureUsage` to equal the pinned Task 14 model.

- [ ] **Step 2: Choose one transport from the decision record**

Implement only the winning transport in `structurer.go`:

- For a Cloudflare or DeepSeek winner, send OpenAI-compatible chat completions with the shared system and user messages, `temperature: 0`, and JSON-object mode.
- For a Gemini winner, send `generateContent` with the shared system instruction, user content, `temperature: 0`, and `responseMimeType: application/json`.

Do not keep both production transports. Do not route to another model after an error. Evaluation adapters stay in `internal/dictationeval` for reproducibility.

- [ ] **Step 3: Implement one validation retry**

Call `DecodeAndValidatePlan` on every response. Retry once for a timeout, 429, 5xx, invalid JSON, or invalid contract. Use the same correction sentence as the benchmark. Do not retry 400, 401, 403, cancellation, or a second invalid response. Errors contain only error class, status, request ID, model ID, attempt count, and duration.

- [ ] **Step 4: Pin production configuration names**

Add these empty example values:

```dotenv
DICTATION_MODEL_URL=
DICTATION_MODEL_API_KEY=
DICTATION_MODEL_ID=
```

The deployed value of `DICTATION_MODEL_ID` must match `decision.md`. There is no provider selector and no fallback-model variable.

- [ ] **Step 5: Test and commit**

```powershell
rtk go test ./internal/dictation -run TestSelectedStructurer -count=1
rtk git add backend/internal/dictation/structurer.go backend/internal/dictation/structurer_test.go backend/.env.example
rtk git commit -m "feat(dictation): add selected semantic structurer"
```

## Task 16: Validate M4A uploads and add the production STT client

**Files:**
- Create: `backend/internal/dictation/audio.go`
- Create: `backend/internal/dictation/audio_test.go`
- Modify: `backend/internal/dictation/stt_client.go`
- Modify: `backend/internal/dictation/stt_client_test.go`
- Modify: `backend/go.mod`
- Modify: `backend/go.sum`
- Modify: `backend/.env.example`

- [ ] **Step 1: Add the maintained MP4 parser**

From `backend` run:

```powershell
rtk go get github.com/Eyevinn/mp4ff@v0.52.0
```

The mobile app will upload only AAC-LC in an M4A container. Do not add decoders for other formats.

- [ ] **Step 2: Write failing audio validation tests**

```go
const MaxAudioBytes int64 = 25 << 20
const MaxAudioDuration = 5 * time.Minute

type AudioInfo struct {
    Size     int64
    Duration time.Duration
    MIMEType string
}

func ValidateM4A(path string, declaredMIME string) (AudioInfo, error)
```

Test a valid short fixture, exactly five minutes, over five minutes, empty file, over 25 MiB, wrong declared MIME, corrupt MP4, MP4 without an audio track, zero timescale, and a path that cannot be opened. Keep generated tiny MP4 boxes under `testdata`; do not commit recorded speech.

- [ ] **Step 3: Implement strict validation**

Accept only `audio/mp4` and `audio/x-m4a`. Check file size before decode. Use `mp4.DecodeFile` and the movie header timescale and duration. Require at least one audio track. Return typed errors; never include the file name or path in client-facing errors.

- [ ] **Step 4: Write failing STT client tests**

Add the production `Transcriber` interface above the Task 10 `WorkerTranscriber`: `Transcribe(ctx context.Context, audioPath, mimeType string) (Transcript, error)`.

Test bearer authentication, streamed request body, content type, success, 401, 413, 422, 429, 502, timeout, blank transcript, cancellation, and safe errors. The client must reopen the file for its one retry; it must not read the whole file into memory.

- [ ] **Step 5: Implement one bounded STT retry**

Use a 90-second HTTP timeout. Retry once for timeout, 429, or 5xx. Do not retry authentication, invalid audio, cancellation, or a second failure. Set `X-Request-ID` from the Go request context. Never log the token, path, audio, or transcript.

- [ ] **Step 6: Add STT configuration and commit**

```dotenv
DICTATION_STT_URL=
DICTATION_STT_TOKEN=
```

```powershell
rtk go test ./internal/dictation -run "Test(ValidateM4A|WorkerTranscriber)" -count=1
rtk git add backend/internal/dictation/audio.go backend/internal/dictation/audio_test.go backend/internal/dictation/stt_client.go backend/internal/dictation/stt_client_test.go backend/go.mod backend/go.sum backend/.env.example
rtk git commit -m "feat(dictation): validate audio and call private STT worker"
```

## Task 17: Compose the production dictation service without note mutation

**Files:**
- Create: `backend/internal/dictation/service.go`
- Create: `backend/internal/dictation/service_test.go`

- [ ] **Step 1: Write service orchestration tests**

```go
type ProcessInput struct {
    AudioPath       string
    MIMEType        string
    RecordedAt      time.Time
    Timezone        string
    ContractVersion int
}

type ProcessUsage struct {
    AudioBytes       int64
    AudioDuration    time.Duration
    STTDuration      time.Duration
    StructureDuration time.Duration
    STTAttempts      int
    StructureAttempts int
    InputTokens      int
    OutputTokens     int
    STTModel         string
    StructureModel   string
}

type Service interface {
    Process(context.Context, ProcessInput) (BlockPlan, ProcessUsage, error)
}
```

Test the exact call order: validate audio, transcribe, structure. Test invalid contract version, invalid IANA timezone, `recorded_at` more than five minutes in the future, empty transcript, STT failure, structurer failure, cancellation between phases, and success. The service must never accept a note ID or repository.

- [ ] **Step 2: Resolve dates with the supplied context**

Load the timezone with `time.LoadLocation`. Pass the original RFC 3339 instant and IANA timezone into `BuildPrompt`. Do not replace `recorded_at` with server time. Require `contract_version == 1`.

- [ ] **Step 3: Return usage without content**

`ProcessUsage` contains timing, size, attempt, token, and model data only. It must not contain transcript, cleaned transcript, blocks, warnings, or file paths.

- [ ] **Step 4: Test and commit**

```powershell
rtk go test ./internal/dictation -run TestServiceProcess -count=1
rtk git add backend/internal/dictation/service.go backend/internal/dictation/service_test.go
rtk git commit -m "feat(dictation): compose transcription and structuring service"
```

## Task 18: Expose the authenticated multipart API and wire production configuration

**Files:**
- Create: `backend/internal/dictation/handler.go`
- Create: `backend/internal/dictation/handler_test.go`
- Modify: `backend/pkg/config/config.go`
- Modify: `backend/pkg/config/config_test.go`
- Modify: `backend/cmd/server/main.go`
- Create: `backend/cmd/server/main_test.go`

- [ ] **Step 1: Write multipart handler tests**

Register `POST /api/v1/dictation/structure` under the existing protected group. Require parts named `audio`, `recorded_at`, `timezone`, and `contract_version`. Test missing authentication through the server route, missing and duplicate fields, invalid RFC 3339, invalid timezone, wrong version, wrong MIME, oversized body, service errors, cancellation, and success.

- [ ] **Step 2: Stream the upload to one temporary file**

Set the request limit to `MaxAudioBytes + 64 KiB`. Use `multipart.Reader` and `io.Copy` through a limiting reader. Permit one audio part and three small text parts. Create the file with `os.CreateTemp("", "supanotes-dictation-*.m4a")`, mode `0600`, and `defer os.Remove(path)` immediately after creation. Close and remove it on every parse, service, timeout, and cancellation path.

- [ ] **Step 3: Define exact HTTP errors**

- `400`: malformed multipart, fields, timestamp, timezone, or contract version.
- `401`: existing JWT middleware.
- `413`: body, audio size, or duration above the limit.
- `415`: media type other than M4A.
- `422`: corrupt audio, blank STT result, or model output that still fails validation after retry.
- `502`: STT or model provider permanent failure.
- `504`: exhausted external timeout.

Use the project JSON error shape. Return the validated `BlockPlan` directly on `200`.

- [ ] **Step 4: Add required production config**

Add `DictationSTTURL`, `DictationSTTToken`, `DictationModelURL`, `DictationModelAPIKey`, and `DictationModelID` to `config.Config`. Outside dev, fail startup if one is blank. In dev, do not register the dictation route when configuration is incomplete; log only `dictation route disabled: missing configuration`.

- [ ] **Step 5: Wire clients and structured metrics**

Create dedicated 90-second STT and 45-second model clients. Register the handler in `registerRoutes`. Log one structured completion event with Echo request ID, audio bytes, audio duration, both phase durations, attempts, token counts, fixed model IDs, total latency, success, and error class. Do not log multipart fields except version/timezone, transcript, plan, note content, audio path, or response content.

- [ ] **Step 6: Test and commit**

```powershell
rtk go test ./internal/dictation ./pkg/config ./cmd/server -count=1
rtk git add backend/internal/dictation/handler.go backend/internal/dictation/handler_test.go backend/pkg/config/config.go backend/pkg/config/config_test.go backend/cmd/server/main.go backend/cmd/server/main_test.go
rtk git commit -m "feat(dictation): expose authenticated structure endpoint"
```

## Task 19: Add strict Flutter response models and the multipart repository

**Files:**
- Create: `lib/features/notes/dictation/domain/dictation_plan.dart`
- Create: `lib/features/notes/dictation/data/dictation_repository.dart`
- Modify: `lib/core/di/providers.dart`
- Create: `test/features/notes/dictation/dictation_plan_test.dart`
- Create: `test/features/notes/dictation/dictation_repository_test.dart`
- Modify: `lib/core/api/api_client.dart`

- [ ] **Step 1: Write strict Dart contract tests**

Mirror the backend JSON exactly with immutable Dart classes: `DictationPlan`, `DictationBlock`, and `DictationTaskMetadata`. Parse `contractVersion`, `transcript`, `language`, `blocks`, and `warnings`; parse block `type`, `text`, `indent`, and `taskMetadata`; parse task `dueDate`, `hasTime`, `recurrence`, `reminder`, and `isCompleted`.

Reject unknown keys, wrong types, `contractVersion != 1`, invalid block types, invalid RFC 3339, completed tasks, missing task metadata, metadata on non-task blocks, non-empty divider text, empty text on other blocks, unsupported recurrence/reminder, and negative indent.

- [ ] **Step 2: Add a per-request receive timeout seam**

Extend `ApiClient.post` with an optional `Duration? receiveTimeout` and apply it through copied Dio options. Keep existing callers unchanged. Test that the dictation repository requests a 150-second receive timeout.

- [ ] **Step 3: Write repository transport tests**

```dart
abstract interface class DictationRepository {
  Future<DictationPlan> structure({
    required File audio,
    required DateTime recordedAt,
    required String timezone,
    required CancelToken cancelToken,
  });
}
```

The implementation posts `FormData` to `/dictation/structure` with one `audio` file and the three exact scalar fields. Use `audio/mp4`, `contract_version=1`, and `recordedAt.toIso8601String()`. Convert Dio failures through `fromDioError`; do not catch and replace parse errors.

- [ ] **Step 4: Add one manual provider**

```dart
final dictationRepositoryProvider = Provider.autoDispose<DictationRepository>(
  (ref) => ApiDictationRepository(ref.watch(apiClientProvider)),
);
```

Keep this provider in the central DI file. Do not create a Riverpod state controller for screen-local recording state.

- [ ] **Step 5: Test and commit**

```powershell
rtk flutter test test/features/notes/dictation/dictation_plan_test.dart
rtk flutter test test/features/notes/dictation/dictation_repository_test.dart
rtk git add lib/features/notes/dictation lib/core/api/api_client.dart lib/core/di/providers.dart test/features/notes/dictation
rtk git commit -m "feat(dictation): add mobile dictation API contract"
```

## Task 20: Add mobile recording and permission services

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `ios/Runner/Info.plist`
- Modify: `ios/Podfile`
- Create: `lib/features/notes/dictation/application/audio_recorder_service.dart`
- Create: `test/features/notes/dictation/audio_recorder_service_test.dart`

- [ ] **Step 1: Add supported packages**

```powershell
rtk flutter pub add record:^7.1.1 permission_handler:^12.0.3
```

Raise the Dart lower bound in `pubspec.yaml` to `>=3.12.0 <4.0.0`, matching Flutter 3.44 and `record` 7. Do not add another recording or permission package.

- [ ] **Step 2: Add platform permissions**

Add `android.permission.RECORD_AUDIO`. Add `NSMicrophoneUsageDescription` with `O SupaNotes usa o microfone para transcrever sua fala na nota.` Enable only `PERMISSION_MICROPHONE=1` in the existing Podfile post-install definitions.

- [ ] **Step 3: Write the service tests against an adapter**

```dart
enum MicrophoneAccess { granted, denied, permanentlyDenied, restricted }

abstract interface class DictationAudioRecorder {
  Future<MicrophoneAccess> requestAccess();
  Future<String> start();
  Future<String?> stop();
  Future<void> cancel();
  Stream<RecordState> get stateChanges;
  Future<void> dispose();
}
```

Test every permission state, a unique file under `getTemporaryDirectory()`, start, stop, cancel, native interruption, and disposal. The service must delete a partial file after failed start or cancel.

- [ ] **Step 4: Implement one M4A recording profile**

Use `AudioEncoder.aacLc`, 16 kHz, mono, and 64 kbit/s. File names use `supanotes-dictation-<uuid>.m4a`. Use `Permission.microphone` for status and request, and `AudioRecorder` only for capture. Do not record in the background and do not write to documents or app storage.

- [ ] **Step 5: Test and commit**

```powershell
rtk flutter test test/features/notes/dictation/audio_recorder_service_test.dart
rtk flutter analyze
rtk git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist ios/Podfile lib/features/notes/dictation/application/audio_recorder_service.dart test/features/notes/dictation/audio_recorder_service_test.dart
rtk git commit -m "feat(dictation): record temporary mobile audio"
```

## Task 21: Implement the local dictation lifecycle controller

**Files:**
- Create: `lib/features/notes/dictation/domain/dictation_state.dart`
- Create: `lib/features/notes/dictation/application/dictation_flow_controller.dart`
- Create: `test/features/notes/dictation/dictation_flow_controller_test.dart`

- [ ] **Step 1: Define one sealed state model**

```dart
sealed class DictationState {
  const DictationState();
}

final class DictationIdle extends DictationState {}
final class DictationRecording extends DictationState {
  final Duration elapsed;
}
final class DictationProcessing extends DictationState {}
final class DictationRecoverableError extends DictationState {
  final DictationFailure failure;
}
final class DictationApplying extends DictationState {}
final class DictationAwaitingAnchor extends DictationState {}
```

Keep the audio path, recorded time, cancel token, timer, and optional processed plan private inside the controller. Do not put paths or response content in the public state.

- [ ] **Step 2: Write transition tests**

Test idle → recording; manual stop → processing → applying → idle; automatic stop at exactly five minutes; cancel during recording; cancel during request; denied, permanently denied, and restricted permissions; upload/STT/model/validation failure; retry from retained audio; missing insertion anchor → awaiting anchor → applying without another HTTP request; native recorder interruption; app pause/resume; dispose in each phase; and duplicate taps.

- [ ] **Step 3: Implement lifecycle and cleanup**

```dart
final class DictationFlowController extends ChangeNotifier {
  DictationState get state;
  Future<void> start();
  Future<void> stopAndProcess();
  Future<void> retry();
  Future<void> applyAtNewAnchor();
  Future<void> cancel();
  Future<void> onAppLifecycleStateChanged(AppLifecycleState state);
  Future<void> disposeAsync();
}
```

Constructor dependencies are recorder, repository, timezone loader, clock, `Future<void> Function(DictationPlan) applyPlan`, and `Future<void> Function(DictationPlan) applyPlanAtNewAnchor`. Capture `recordedAt` when recording starts. After stop, resolve the IANA timezone with the existing `flutter_timezone` package and process automatically. Convert `DictationAnchorMissingException` into `DictationAwaitingAnchor` and retain the validated plan.

- [ ] **Step 4: Enforce temporary-file rules**

Retain audio only in `DictationRecoverableError`. Delete it after successful insertion, explicit cancel, note close, or controller disposal. On app pause while recording, stop capture and retain the file; process after resume. Do not recover a file after process restart. Delete any stale `supanotes-dictation-*` files older than one hour when a controller starts.

- [ ] **Step 5: Test and commit**

```powershell
rtk flutter test test/features/notes/dictation/dictation_flow_controller_test.dart
rtk git add lib/features/notes/dictation/domain/dictation_state.dart lib/features/notes/dictation/application/dictation_flow_controller.dart test/features/notes/dictation/dictation_flow_controller_test.dart
rtk git commit -m "feat(dictation): manage recording and retry lifecycle"
```

## Task 22: Convert a block plan into one atomic Super Editor transaction

**Files:**
- Modify: `lib/features/notes/editor/document/note_editor_commands.dart`
- Modify: `lib/features/notes/editor/application/note_editor_controller.dart`
- Create: `test/features/notes/dictation/dictation_editor_commands_test.dart`

- [ ] **Step 1: Write node mapping tests**

Map paragraph to `ParagraphNode`; headers to `ParagraphNode` with `header1Attribution`, `header2Attribution`, or `header3Attribution`; quote to `blockquoteAttribution`; lists to ordered or unordered `ListItemNode`; task to pending `TaskNode`; and divider to `HorizontalRuleNode`. Preserve `indent`. New task metadata uses only the canonical `dueDate`, `hasTime`, `recurrence`, and `reminder` keys. Do not add the obsolete duplicate `recurrenceRule` key. Never set `isCompleted` or `checked` true.

- [ ] **Step 2: Write every insertion-position test**

Cover caret at start, middle, and end of a non-empty paragraph, header, and quote; empty text block replacement; caret inside ordered list, bullet list, and task; expanded selection inside one block; expanded selection across blocks; entire-document selection; document with one empty block; and a plan that starts or ends with a divider.

Expected rules:

- Text blocks split exactly at the caret and keep their original type and inline attributions on both remaining fragments.
- An empty block is replaced.
- Inside a list or task, the complete plan is inserted after that whole block.
- An expanded selection is replaced by the complete plan.
- The final caret is at the end of the last inserted text node, or in a new empty paragraph after a final divider.

- [ ] **Step 3: Implement one command entry point**

```dart
final class DictationUndoHandle {
  bool get canUndo;
  void undo();
  void invalidate();
}

static DictationInsertionAnchor captureDictationAnchor(
  MutableDocumentComposer composer,
);

static DictationUndoHandle insertDictationPlan(
  Editor editor,
  MutableDocumentComposer composer,
  DictationPlan plan,
  DictationInsertionAnchor anchor,
)
```

`DictationInsertionAnchor` stores the immutable start/end block IDs and the required text positions. While the modal is open, update its positions only from composer rebasing caused by document changes; user interaction is blocked. If either required block no longer exists, throw `DictationAnchorMissingException`. Build all `DeleteContentRequest`, `ReplaceNodeRequest`, `InsertNodeAtIndexRequest`, and `ChangeSelectionRequest` values first. Execute the complete list with one `editor.execute(requests)` call. Do not mutate `MutableDocument` directly. Add only a small helper for plan-to-node conversion.

- [ ] **Step 4: Prove atomic history and REST/OT capture**

For every position class, assert that insertion adds one editor history transaction. Call `editor.undo()` once and assert that document nodes, text, metadata, order, and selection equal the pre-insertion snapshot. Add an `EditorOperationCapture` harness and assert that inserted tasks and metadata become canonical block operations.

Invalidate `DictationUndoHandle` on the next document change after insertion so the snackbar cannot undo unrelated later edits.

- [ ] **Step 5: Expose through the existing controller and commit**

```dart
DictationInsertionAnchor captureDictationAnchor()
DictationUndoHandle insertDictationPlan(
  DictationPlan plan,
  DictationInsertionAnchor anchor,
)
```

Call `_assertCanMutate` first and delegate to `NoteEditorCommands`. Do not call task repositories or Drift.

```powershell
rtk flutter test test/features/notes/dictation/dictation_editor_commands_test.dart
rtk flutter test test/features/notes/domain/editor_operation_capture_test.dart
rtk git add lib/features/notes/editor/document/note_editor_commands.dart lib/features/notes/editor/application/note_editor_controller.dart test/features/notes/dictation/dictation_editor_commands_test.dart
rtk git commit -m "feat(dictation): insert structured plans atomically"
```

## Task 23: Add the microphone action and dedicated mobile dictation sheet

**Files:**
- Create: `lib/features/notes/dictation/presentation/dictation_sheet.dart`
- Create: `test/features/notes/dictation/dictation_sheet_test.dart`
- Modify: `lib/features/notes/editor/presentation/widgets/note_toolbar.dart`
- Modify: `lib/features/notes/editor/presentation/widgets/note_editor.dart`
- Modify: `lib/features/notes/editor/presentation/note_editor_screen.dart`
- Modify: `test/features/notes/presentation/widgets/note_toolbar_test.dart`
- Modify: `test/features/notes/presentation/note_editor_screen_test.dart`

- [ ] **Step 1: Write bottom-sheet widget tests**

Test these exact presentations:

- Recording: red recording indicator, elapsed `mm:ss`, the `Limite de 05:00` label, `Parar`, and `Cancelar`.
- Processing: progress indicator and `Transcrevendo e organizando`.
- Recoverable error: concise error, `Tentar novamente`, and `Cancelar`.
- Awaiting anchor: `A posição original não existe mais`, `Escolher nova posição`, and `Cancelar`.
- Applying: progress indicator and `Inserindo na nota`.

Test narrow widths, large text scale, dark theme, safe-area padding, semantics, disabled animation, drag dismissal disabled during processing, and taps. Use `showAppBottomSheet`, `AppButton`, and the shared sheet conventions; do not create raw Material action buttons.

- [ ] **Step 2: Add one toolbar microphone action**

Add `onStartDictation` and `dictationAwaitingAnchor` to `NoteToolbar`. Show one microphone `ToolbarButton` only on iOS and Android and only when the note is editable and has a valid selection. Its normal semantic label is `Iniciar ditado`. When a processed plan needs a new anchor, change the icon and semantic label to `Inserir ditado nesta posição`; tapping applies the cached plan and never starts another recording. Close formatting mode before either action.

- [ ] **Step 3: Own the flow in `NoteEditorScreen`**

Create one `DictationFlowController` in `initState` with `ref.read(dictationRepositoryProvider)`, `MobileDictationAudioRecorder`, and apply callbacks. On microphone tap, capture `session.controller.captureDictationAnchor()`, open `DictationSheet` with `showAppBottomSheet`, and start capture only after the sheet is mounted. The first apply callback uses the captured anchor. The new-anchor callback captures the current selection and applies the cached plan. Both callbacks check `captureLocalOperations` and store the returned undo handle. Register one controller listener that updates the sheet and screen; remove it and call `disposeAsync` on screen disposal.

- [ ] **Step 4: Block editing while the sheet is open**

Close the software keyboard but do not clear `composer.selection`. The modal route blocks user editing and prevents a second recording while recording, processing, or applying. Keep `NoteSyncSession` active behind the sheet so remote operations still reconcile and rebase the stored anchor. If a required anchor block is removed, keep the plan and audio in memory and show the awaiting-anchor state.

- [ ] **Step 5: Request a new anchor without silent relocation**

When the user taps `Escolher nova posição`, close the sheet, retain the plan/audio, and show `Posicione o cursor e toque em Inserir ditado`. Re-enable editor interaction. The toolbar action now says `Inserir ditado nesta posição`. Applying there uses no new STT or model request. `Cancelar` deletes the audio and cached plan.

- [ ] **Step 6: Add the one-action undo feedback**

After success, show `Ditado inserido` with `SnackBarAction(label: 'Desfazer')`. The action calls the valid `DictationUndoHandle`. Dismiss or disable the action when the handle is invalidated by a later document edit.

- [ ] **Step 7: Test and commit**

```powershell
rtk flutter test test/features/notes/dictation/dictation_sheet_test.dart
rtk flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart
rtk flutter test test/features/notes/presentation/note_editor_screen_test.dart
rtk git add lib/features/notes/dictation/presentation/dictation_sheet.dart lib/features/notes/editor/presentation/widgets/note_toolbar.dart lib/features/notes/editor/presentation/widgets/note_editor.dart lib/features/notes/editor/presentation/note_editor_screen.dart test/features/notes/dictation/dictation_sheet_test.dart test/features/notes/presentation/widgets/note_toolbar_test.dart test/features/notes/presentation/note_editor_screen_test.dart
rtk git commit -m "feat(dictation): add mobile voice control to editor"
```

## Task 24: Complete permission, error, interruption, and note-close behavior

**Files:**
- Modify: `lib/features/notes/editor/presentation/note_editor_screen.dart`
- Modify: `lib/features/notes/dictation/application/dictation_flow_controller.dart`
- Modify: `test/features/notes/dictation/dictation_flow_controller_test.dart`
- Modify: `test/features/notes/presentation/note_editor_screen_test.dart`

- [ ] **Step 1: Add explicit permission feedback**

For denied permission, show `Permita o acesso ao microfone para usar o ditado.` For permanently denied, show the same message with `Abrir ajustes`, which calls `openAppSettings`. For restricted permission, show `O microfone está indisponível neste dispositivo.` Do not open settings automatically.

- [ ] **Step 2: Map recoverable processing failures**

Map no connection, timeout, 429, 502, 504, and invalid provider output to recoverable error. Map a removed insertion anchor to `DictationAwaitingAnchor`. Keep audio and any already validated plan in both states. Map invalid local audio or permission to a permanent failure, delete the file, and return to idle after feedback.

- [ ] **Step 3: Handle navigation and app lifecycle**

On back navigation or note replacement, cancel the request, stop/cancel the recorder, delete audio, and then close the editor. On app pause, stop recording; on resume, process the retained file. On screen lock or native interruption, use the same stopped-file path. Do not upload while the app is paused.

- [ ] **Step 4: Test no hidden persistence**

Assert that no dictation state enters Riverpod persistence, Drift, SharedPreferences, secure storage, attachment storage, or `notes.document` before the final editor transaction. Assert that retry does not create an attachment.

- [ ] **Step 5: Test and commit**

```powershell
rtk flutter test test/features/notes/dictation/dictation_flow_controller_test.dart
rtk flutter test test/features/notes/presentation/note_editor_screen_test.dart
rtk git add lib/features/notes/editor/presentation/note_editor_screen.dart lib/features/notes/dictation/application/dictation_flow_controller.dart test/features/notes/dictation/dictation_flow_controller_test.dart test/features/notes/presentation/note_editor_screen_test.dart
rtk git commit -m "fix(dictation): harden failures and lifecycle cleanup"
```

## Task 25: Prove canonical sync, task projection, concurrency, and server cleanup

**Files:**
- Create: `test/features/notes/dictation/dictation_sync_integration_test.dart`
- Modify: `test/features/tasks/domain/task_projection_engine_test.dart`
- Modify: `backend/internal/dictation/handler_test.go`
- Modify: `backend/internal/dictation/service_test.go`

- [ ] **Step 1: Add an end-to-end local editor test**

Insert a plan containing paragraph, divider, bullet list, and two tasks with distinct metadata. Assert captured REST/OT operations, serialized `notes.document`, replay into a second document, and equal nodes after replay. Run `TaskProjectionEngine` and assert both task rows match the canonical task nodes.

- [ ] **Step 2: Test atomic undo through synchronization**

Insert, flush captured operations, undo once, and flush again. Replay the full operation sequence into a clean document. Assert the original document and selection are restored and projected tasks are removed.

- [ ] **Step 3: Test concurrent reconciliation during processing**

Start with a live caret, apply a remote insertion through `NoteSyncSession` while the fake dictation request is pending, then complete the response. Assert the plan inserts at the rebased live selection, both edits survive, and both clients converge. Add a second case where the anchor block is remotely deleted; expect `DictationAwaitingAnchor` and no plan insertion.

- [ ] **Step 4: Prove backend temporary-file deletion**

Inject a temp-file factory into the handler tests. Assert zero remaining files after success, multipart error, validation error, STT error, model error, timeout, cancellation, and panic-safe handler recovery. Assert captured logs contain no transcript, block text, temp path, or audio bytes.

- [ ] **Step 5: Run focused suites and commit**

```powershell
rtk go test ./internal/dictation -count=1
rtk flutter test test/features/notes/dictation/dictation_sync_integration_test.dart
rtk flutter test test/features/tasks/domain/task_projection_engine_test.dart
rtk git add backend/internal/dictation test/features/notes/dictation/dictation_sync_integration_test.dart test/features/tasks/domain/task_projection_engine_test.dart
rtk git commit -m "test(dictation): prove canonical sync and cleanup"
```

## Task 26: Deploy, validate real devices, and write the walkthrough

**Files:**
- Modify: `workers/dictation-stt/wrangler.jsonc`
- Modify: `backend/fly.toml` only if a non-secret setting is required
- Create: `docs/superpowers/walkthroughs/2026-08-11-structured-voice-dictation.md`

- [ ] **Step 1: Run all static and automated checks sequentially**

```powershell
rtk go test ./... -count=1
rtk flutter analyze
rtk flutter test
```

From `workers/dictation-stt`:

```powershell
rtk npm test
rtk npm run typecheck
```

Report a timeout as a timeout. Do not call it a pass. Run Flutter commands sequentially.

- [ ] **Step 2: Deploy and set secrets**

Deploy the Worker. Set `DICTATION_SERVICE_TOKEN` there. Set the matching backend STT URL/token and the approved model URL/key/ID with the deployment secret mechanism. Deploy the Go backend and verify the existing health endpoint before testing dictation. Never put secrets in `fly.toml`, `.env.example`, a command transcript, or the walkthrough.

- [ ] **Step 3: Validate on one iPhone and one Android device**

Run this matrix on both devices:

- permission accepted, denied, and permanently denied;
- 10-second paragraph, mixed paragraph/tasks, ordered steps, quote, and topic divider;
- date, time, recurrence, and requested reminder;
- stop, cancel, automatic five-minute stop, and retry after network loss;
- app background, screen lock, microphone interruption, and return to app;
- insertion at paragraph/header/quote start, middle, and end;
- insertion from a list/task and expanded selection;
- one-action undo;
- remote edit from a second client while processing;
- successful sync and task projection after insertion.

Record device model, OS version, app commit, backend release, Worker release, model ID, latency, outcome, and defect link. Do not record spoken content.

- [ ] **Step 4: Confirm cost and observability in production-like traffic**

Run at least 20 synthetic recordings across both devices. Confirm p50/p95 total, STT, and structuring latency; retry counts; valid response rate; and estimated five-minute cost. Confirm logs contain request IDs and metrics but no audio, transcript, plan, or note content.

- [ ] **Step 5: Write the walkthrough**

Document architecture, selected model evidence, API contract, state machine, insertion rules, temporary-file lifecycle, test commands and exact results, device matrix, deployment identifiers, known limits, and rollback steps. The rollback disables the route and hides the microphone control; it must not add a fallback model or alter stored note documents.

- [ ] **Step 6: Final repository check and commit**

```powershell
rtk git status --short
rtk git diff --check
rtk git add docs/superpowers/walkthroughs/2026-08-11-structured-voice-dictation.md
rtk git commit -m "docs(dictation): add implementation walkthrough"
```

Confirm that no `.env`, audio, raw evaluation response, blind mapping, or temporary upload is tracked.

## Completion criteria

This plan is complete only when:

- the private STT Worker is deployed and its tests pass;
- Round 1 contains all production candidates and 20 fixed cases;
- Round 2 contains three finalists, 40 cases, three repetitions, and five real Whisper transcripts;
- the review stayed blind until scoring was complete;
- the selected model passes every production gate;
- `decision.md` pins the exact model and contains reproducible aggregate evidence;
- the authenticated Go endpoint streams and deletes temporary uploads and never mutates notes or tasks;
- iOS and Android record at most five minutes and process only after stop;
- the model plan inserts at the approved cursor or selection rule through one editor transaction;
- one undo restores document and selection;
- REST/OT replay converges and task projection matches the canonical document;
- permission, retry, interruption, cancellation, and note-close paths delete or retain audio exactly as specified;
- real-device validation passes on one iPhone and one Android device;
- temporary phone audio is deleted;
- no sensitive or raw evaluation artifact is tracked by Git;
- the walkthrough records exact automated and device validation results.

## Source snapshot

- [Cloudflare Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/)
- [Cloudflare Whisper Large V3 Turbo](https://developers.cloudflare.com/workers-ai/models/whisper-large-v3-turbo/)
- [Cloudflare Workers AI REST API](https://developers.cloudflare.com/workers-ai/get-started/rest-api/)
- [Cloudflare Workers AI data use](https://developers.cloudflare.com/workers-ai/platform/data-usage/)
- [DeepSeek pricing](https://api-docs.deepseek.com/quick_start/pricing/)
- [DeepSeek JSON output](https://api-docs.deepseek.com/guides/json_mode/)
- [Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing)
- [Gemini structured output](https://ai.google.dev/gemini-api/docs/structured-output)
- [record package](https://pub.dev/packages/record)
- [permission_handler package](https://pub.dev/packages/permission_handler)
- [Eyevinn mp4ff](https://pkg.go.dev/github.com/Eyevinn/mp4ff@v0.52.0/mp4)
