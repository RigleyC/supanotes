# Scope Gaps — Part 3: Frontend Fixes

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all remaining frontend gaps discovered in the scope v3 gap analysis that are NOT covered by `front.md` (FCM + tag chips).

**Architecture:** Each task is isolated and mergeable. No breaking UI changes.

**Tech Stack:** Flutter, Drift, Riverpod, Dio.

**Depends on:** `2026-06-11-scope-gaps-db.md` (task status values) and `2026-06-11-scope-gaps-backend.md` (API field rename, SSE format).

---

## File Map

| File | Role | Action |
|------|------|--------|
| `lib/core/database/tables/note_links.dart` | Drift table | Create |
| `lib/core/database/daos/note_links_dao.dart` | DAO | Create |
| `lib/core/database/database.dart` | Database | Register table + DAO |
| `lib/core/sync/sync_mapper.dart` | Sync mapper | Add note_links + note_tags |
| `lib/core/sync/sync_service.dart` | Sync service | Add note_links + note_tags push/pull |
| `lib/features/agent/data/chat_repository.dart` | Chat repo | Rename `message`→`content` |
| `lib/features/agent/data/chat_sse.dart` | SSE client | Create (new) |
| `lib/features/agent/presentation/controllers/chat_controller.dart` | Chat controller | Use SSE streaming |
| `lib/features/routines/data/routines_repository.dart` | Routines repo | Use /daily+/weekly PATCH |
| `lib/features/memories/` | Memories feature | Create (new) |

---

## Task 1: Add `note_links` Drift table + DAO

**Why:** DB has `note_links` table (migration 000002) but Flutter has no Drift representation. Bidirectional linking is non-functional.

---

- [ ] **Step 1: Create `note_links.dart` table**

`lib/core/database/tables/note_links.dart`:

```dart
import 'package:drift/drift.dart';

import 'notes.dart';

/// Bidirectional link between two notes.
///
/// Each row represents a directed edge from [sourceId] to [targetId].
/// The reverse lookup (target→source) is handled by the DAO querying
/// both columns.
@DataClassName('NoteLinkData')
class NoteLinks extends Table {
  TextColumn get id => text()();
  TextColumn get sourceId => text().references(Notes, #id)();
  TextColumn get targetId => text().references(Notes, #id)();
  TextColumn get relation => text().withDefault(const Constant('related'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}
```

---

- [ ] **Step 2: Create `note_links_dao.dart`**

`lib/core/database/daos/note_links_dao.dart`:

```dart
import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/note_links.dart';

part 'note_links_dao.g.dart';

@DriftAccessor(tables: [NoteLinks])
class NoteLinksDao extends DatabaseAccessor<AppDatabase>
    with _$NoteLinksDaoMixin {
  NoteLinksDao(super.db);

  Stream<List<NoteLinkData>> watchLinksForNote(String noteId) {
    return (select(noteLinks)
          ..where((l) =>
              l.sourceId.equals(noteId) | l.targetId.equals(noteId))
          ..orderBy([(l) => OrderingTerm(expression: l.createdAt)]))
        .watch();
  }

  Future<void> insertLink(NoteLinksCompanion link) async {
    await into(noteLinks).insert(link, mode: InsertMode.insertOrReplace);
  }

  Future<void> deleteLink(String id) async {
    await (delete(noteLinks)..where((l) => l.id.equals(id))).go();
  }

  Future<void> deleteLinksForNote(String noteId) async {
    await (delete(noteLinks)
          ..where((l) =>
              l.sourceId.equals(noteId) | l.targetId.equals(noteId)))
        .go();
  }

  Future<List<NoteLinkData>> getDirtyLinks() {
    return (select(noteLinks)..where((l) => l.isDirty.equals(true))).get();
  }

  Future<void> clearDirtyFlag(String id) async {
    await (update(noteLinks)..where((l) => l.id.equals(id)))
        .write(const NoteLinksCompanion(isDirty: Value(false)));
  }

  Future<void> upsertFromRemote(NoteLinkData link) async {
    final incoming = link.copyWith(isDirty: false);
    await into(noteLinks).insertOnConflictUpdate(incoming);
  }
}
```

---

- [ ] **Step 3: Register in `database.dart`**

In `lib/core/database/database.dart`:

```dart
// Add to part directive:
part 'daos/note_links_dao.g.dart';

// Add to @DriftDatabase tables list:
tables: [Notes, Tasks, Contexts, Tags, LocalNoteTags, NoteLinks, ...],

// Add accessor:
NoteLinksDao get noteLinksDao => NoteLinksDao(this);
```

Run: `dart run build_runner build` to generate the `.g.dart` file.

---

- [ ] **Step 4: Commit**

```bash
git add lib/core/database/tables/note_links.dart lib/core/database/daos/note_links_dao.dart lib/core/database/database.dart lib/core/database/database.g.dart
git commit -m "feat(db): add note_links Drift table and DAO"
```

---

## Task 2: Add `note_links` + `note_tags` to sync

**Why:** `note_tags` junction table exists in Drift but is never pushed/pulled. `note_links` is new and also needs sync.

**Files:**
- Modify: `lib/core/sync/sync_mapper.dart`
- Modify: `lib/core/sync/sync_service.dart`

---

- [ ] **Step 1: Add `note_tags` and `note_links` mappers to `sync_mapper.dart`**

```dart
// Add to SyncMapper:

Map<String, dynamic> noteTagToJson(LocalNoteTagData nt) => {
      'note_id': nt.noteId,
      'tag_id': nt.tagId,
    };

LocalNoteTagData noteTagFromJson(Map<String, dynamic> json,
        {required String userId}) =>
    LocalNoteTagData(
      noteId: json['note_id'] as String,
      tagId: json['tag_id'] as String,
      isDirty: false,
    );

Map<String, dynamic> noteLinkToJson(NoteLinkData l) => {
      'id': l.id,
      'source_id': l.sourceId,
      'target_id': l.targetId,
      'relation': l.relation,
      'created_at': l.createdAt.toUtc().toIso8601String(),
      'updated_at': l.updatedAt.toUtc().toIso8601String(),
    };

NoteLinkData noteLinkFromJson(Map<String, dynamic> json) => NoteLinkData(
      id: json['id'] as String,
      sourceId: json['source_id'] as String,
      targetId: json['target_id'] as String,
      relation: (json['relation'] as String?) ?? 'related',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
      isDirty: false,
    );
```

---

- [ ] **Step 2: Add push for `note_tags` and `note_links` in `sync_service.dart`**

In the `push()` method:

```dart
// After existing getDirty calls:
final noteTags = await _db.noteTagsDao.getDirtyNoteTags();  // NEW
final noteLinks = await _db.noteLinksDao.getDirtyLinks();    // NEW

// Add to payload:
'note_tags': noteTags.map(_mapper.noteTagToJson).toList(),
'note_links': noteLinks.map(_mapper.noteLinkToJson).toList(),

// After existing clearDirtyFlag loops:
for (final nt in noteTags) {
  await _db.noteTagsDao.clearDirtyFlag(nt.noteId, nt.tagId);
}
for (final nl in noteLinks) {
  await _db.noteLinksDao.clearDirtyFlag(nl.id);
}
```

---

- [ ] **Step 3: Add pull for `note_tags` and `note_links` in `sync_service.dart`**

In the `pull()` method, inside the transaction:

```dart
for (final raw in (data['note_tags'] as List? ?? [])) {
  await _db.noteTagsDao.upsertFromRemote(
    _mapper.noteTagFromJson(raw as Map<String, dynamic>, userId: _userId),
  );
}
for (final raw in (data['note_links'] as List? ?? [])) {
  await _db.noteLinksDao.upsertFromRemote(
    _mapper.noteLinkFromJson(raw as Map<String, dynamic>),
  );
}
```

---

- [ ] **Step 4: Add DAO methods if missing**

Check if `NoteTagsDao` has `getDirtyNoteTags()`, `clearDirtyFlag(noteId, tagId)`, and `upsertFromRemote()`. If not, add them to `lib/core/database/daos/note_tags_dao.dart`:

```dart
Future<List<LocalNoteTagData>> getDirtyNoteTags() {
  return (select(localNoteTags)
        ..where((t) => t.isDirty.equals(true)))
      .get();
}

Future<void> clearDirtyFlag(String noteId, String tagId) async {
  await (update(localNoteTags)
        ..where((t) => t.noteId.equals(noteId) & t.tagId.equals(tagId)))
      .write(const LocalNoteTagsCompanion(isDirty: Value(false)));
}

Future<void> upsertFromRemote(LocalNoteTagData noteTag) async {
  final incoming = noteTag.copyWith(isDirty: false);
  await into(localNoteTags).insert(incoming, mode: InsertMode.insertOrReplace);
}
```

---

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/sync_mapper.dart lib/core/sync/sync_service.dart lib/core/database/daos/note_tags_dao.dart
git commit -m "feat(sync): add note_tags and note_links to push/pull"
```

---

## Task 3: Rename `message`→`content` in chat repository

**Why:** Backend now expects `content` field (per scope). Flutter sends `message`.

**Files:**
- Modify: `lib/features/agent/data/chat_repository.dart`

---

- [ ] **Step 1: Rename field in `sendMessage`**

```dart
// backend/internal/agent/handler.go now expects "content"
final response = await _api.post<Map<String, dynamic>>(
  '/agent/chat',
  data: <String, dynamic>{
    'session_id': sessionId,
    'content': message,  // was 'message'
  },
);
```

---

- [ ] **Step 2: Update `ChatController.sendMessage` parameter name**

In `lib/features/agent/presentation/controllers/chat_controller.dart`:

```dart
// Line 63-65: the call to repository
final response = await ref.read(chatRepositoryProvider).sendMessage(
      sessionId: sessionId,
      message: trimmed,  // parameter name stays the same in the method signature
    );
```

No change needed in the controller — the parameter name `message` in `sendMessage()` is internal. Only the JSON key in `chat_repository.dart` changes.

---

- [ ] **Step 3: Commit**

```bash
git add lib/features/agent/data/chat_repository.dart
git commit -m "fix(agent): rename message→content in chat request body"
```

---

## Task 4: Connect agent SSE streaming to chat UI

**Why:** Chat uses non-streaming `POST /agent/chat`. Agent sends SSE stream. User sees nothing until full response arrives.

**Files:**
- Create: `lib/features/agent/data/chat_sse.dart`
- Modify: `lib/features/agent/data/chat_repository.dart`
- Modify: `lib/features/agent/presentation/controllers/chat_controller.dart`

---

- [ ] **Step 1: Create SSE client**

`lib/features/agent/data/chat_sse.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

/// SSE event types from the agent backend.
class ChatSSEEvent {
  const ChatSSEEvent({this.delta, this.done = false});
  final String? delta;
  final bool done;
}

/// Streams agent chat responses via Server-Sent Events.
///
/// The backend sends lines like:
///   data: {"delta":"olá"}
///   data: {"delta":" mundo"}
///   data: {"done":true}
class ChatSSEClient {
  ChatSSEClient({required Dio dio}) : _dio = dio;
  final Dio _dio;

  /// Returns a stream of [ChatSSEEvent] for the given [sessionId] and
  /// [message]. The caller should listen and accumulate deltas.
  Stream<ChatSSEEvent> stream({
    required String sessionId,
    required String message,
  }) async* {
    final response = await _dio.post<ResponseBody>(
      '/agent/chat',
      data: <String, dynamic>{
        'session_id': sessionId,
        'content': message,
      },
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream'},
      ),
    );

    final stream = response.data!.stream;
    String buffer = '';

    await for (final chunk in stream) {
      buffer += utf8.decode(chunk);
      // Process complete lines
      while (buffer.contains('\n')) {
        final newlineIndex = buffer.indexOf('\n');
        final line = buffer.substring(0, newlineIndex).trim();
        buffer = buffer.substring(newlineIndex + 1);

        if (line.startsWith('data: ')) {
          final payload = line.substring(6);
          try {
            final json = jsonDecode(payload) as Map<String, dynamic>;
            if (json['done'] == true) {
              yield const ChatSSEEvent(done: true);
              return;
            }
            if (json['delta'] is String) {
              yield ChatSSEEvent(delta: json['delta'] as String);
            }
          } catch (_) {
            // Skip malformed lines
          }
        }
      }
    }
  }
}
```

---

- [ ] **Step 2: Add `sendMessageStream` to `ChatRepository`**

In `lib/features/agent/data/chat_repository.dart`:

```dart
import 'chat_sse.dart';

// Add to IChatRepository:
Stream<ChatSSEEvent> sendMessageStream({
  required String sessionId,
  required String message,
});

// Add to ChatRepository:
@override
Stream<ChatSSEEvent> sendMessageStream({
  required String sessionId,
  required String message,
}) {
  final sseClient = ChatSSEClient(dio: _api.dio);
  return sseClient.stream(sessionId: sessionId, message: message);
}
```

Note: `_api.dio` exposes the underlying `Dio` instance. If `ApiClient` doesn't expose it, add a getter.

---

- [ ] **Step 3: Update `ChatController.sendMessage` to use SSE**

```dart
Future<void> sendMessage(String content) async {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return;

  final sessionId = ref.read(sessionManagerProvider);
  final pending = MessageModel(
    id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
    sessionId: sessionId,
    role: MessageRole.user,
    content: trimmed,
    createdAt: DateTime.now(),
  );

  // Add user message immediately
  state = (
    messages: [...state.messages, pending],
    isLoading: true,
    error: null,
  );

  // Create placeholder for assistant response
  final assistantId = 'response-${DateTime.now().microsecondsSinceEpoch}';
  final assistantPlaceholder = MessageModel(
    id: assistantId,
    sessionId: sessionId,
    role: MessageRole.assistant,
    content: '',
    createdAt: DateTime.now(),
  );
  state = (
    messages: [...state.messages, assistantPlaceholder],
    isLoading: true,
    error: null,
  );

  try {
    final stream = ref.read(chatRepositoryProvider).sendMessageStream(
          sessionId: sessionId,
          message: trimmed,
        );

    String accumulated = '';
    await for (final event in stream) {
      if (event.done) break;
      if (event.delta != null) {
        accumulated += event.delta!;
        // Update the assistant message in-place
        final updatedMessages = state.messages.map((m) {
          if (m.id == assistantId) {
            return m.copyWith(content: accumulated);
          }
          return m;
        }).toList(growable: false);
        state = (
          messages: updatedMessages,
          isLoading: true,  // still streaming
          error: null,
        );
      }
    }

    // Finalize
    final finalizedMessages = state.messages.map((m) {
      if (m.id == assistantId) {
        return m.copyWith(content: accumulated);
      }
      return m;
    }).toList(growable: false);
    state = (
      messages: finalizedMessages,
      isLoading: false,
      error: null,
    );
  } on ApiException catch (e) {
    if (ref.read(sessionManagerProvider) != sessionId) return;
    state = (
      messages: state.messages
          .where((m) => m.id != pending.id && m.id != assistantId)
          .toList(growable: false),
      isLoading: false,
      error: e.message,
    );
  }
}
```

---

- [ ] **Step 4: Ensure `MessageModel` has `copyWith`**

Check `lib/features/agent/domain/message_model.dart`. If `copyWith` is missing, add it:

```dart
MessageModel copyWith({String? content}) {
  return MessageModel(
    id: id,
    sessionId: sessionId,
    role: role,
    content: content ?? this.content,
    createdAt: createdAt,
  );
}
```

---

- [ ] **Step 5: Expose `Dio` from `ApiClient`**

If `ApiClient` doesn't expose its `Dio` instance, add a getter:

```dart
// lib/core/api/api_client.dart
class ApiClient {
  // ... existing code ...
  Dio get dio => _dio;  // ADD
}
```

---

- [ ] **Step 6: Commit**

```bash
git add lib/features/agent/data/chat_sse.dart lib/features/agent/data/chat_repository.dart lib/features/agent/presentation/controllers/chat_controller.dart lib/features/agent/domain/message_model.dart lib/core/api/api_client.dart
git commit -m "feat(agent): connect SSE streaming to chat UI"
```

---

## Task 5: Use `/daily` + `/weekly` PATCH endpoints for routines

**Why:** Flutter sends `PATCH /routines/:id` (generic). Backend now has `PATCH /routines/daily` and `PATCH /routines/weekly`.

**Files:**
- Modify: `lib/features/routines/data/routines_repository.dart`

---

- [ ] **Step 1: Update `updateRoutine` to use type-specific endpoints**

In `lib/features/routines/data/routines_repository.dart`:

```dart
Future<void> updateRoutine({
  required String type,  // 'daily' or 'weekly'
  String? timeOfDay,
  List<int>? daysOfWeek,
  bool? enabled,
  String? timezone,
}) async {
  try {
    await _api.patch<dynamic>(
      '/routines/$type',  // was '/routines/$id'
      data: <String, dynamic>{
        if (timeOfDay != null) 'time_of_day': timeOfDay,
        if (daysOfWeek != null) 'days_of_week': daysOfWeek,
        if (enabled != null) 'enabled': enabled,
        if (timezone != null) 'timezone': timezone,
      },
    );
  } on DioException catch (e) {
    throw fromDioError(e);
  }
}
```

---

- [ ] **Step 2: Update any callers**

Search for `updateRoutine` calls and ensure they pass `type` instead of `id`.

---

- [ ] **Step 3: Commit**

```bash
git add lib/features/routines/data/routines_repository.dart
git commit -m "fix(routines): use /daily and /weekly PATCH endpoints"
```

---

## Task 6: Create Memories feature (UI)

**Why:** Scope §6.1.6 defines a full Memories feature. Backend exists but Flutter has zero UI.

**Files:**
- Create: `lib/features/memories/data/memories_repository.dart`
- Create: `lib/features/memories/presentation/memories_screen.dart`
- Create: `lib/features/memories/presentation/controllers/memories_controller.dart`
- Modify: `lib/core/router/app_router.dart` (add route)

---

- [ ] **Step 1: Create `MemoriesRepository`**

`lib/features/memories/data/memories_repository.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/di/providers.dart';

class MemoryModel {
  const MemoryModel({
    required this.id,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String content;
  final DateTime createdAt;

  factory MemoryModel.fromJson(Map<String, dynamic> json) => MemoryModel(
        id: json['id'] as String,
        content: json['content'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

abstract class IMemoriesRepository {
  Future<List<MemoryModel>> getMemories({int limit = 50});
  Future<void> createMemory(String content);
  Future<void> deleteMemory(String id);
}

class MemoriesRepository implements IMemoriesRepository {
  MemoriesRepository({required ApiClient apiClient}) : _api = apiClient;
  final ApiClient _api;

  @override
  Future<List<MemoryModel>> getMemories({int limit = 50}) async {
    try {
      final response = await _api.get<List<dynamic>>(
        '/memories',
        queryParameters: {'limit': limit},
      );
      return (response.data ?? [])
          .whereType<Map<String, dynamic>>()
          .map(MemoryModel.fromJson)
          .toList();
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  @override
  Future<void> createMemory(String content) async {
    try {
      await _api.post<dynamic>('/memories', data: {'content': content});
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }

  @override
  Future<void> deleteMemory(String id) async {
    try {
      await _api.delete<dynamic>('/memories/$id');
    } on DioException catch (e) {
      throw fromDioError(e);
    }
  }
}

final memoriesRepositoryProvider = Provider<IMemoriesRepository>((ref) {
  return MemoriesRepository(apiClient: ref.watch(apiClientProvider));
});
```

---

- [ ] **Step 2: Create `MemoriesController`**

`lib/features/memories/presentation/controllers/memories_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/memories/data/memories_repository.dart';

typedef MemoriesState = ({
  List<MemoryModel> memories,
  bool isLoading,
  String? error,
});

final memoriesControllerProvider =
    NotifierProvider<MemoriesController, MemoriesState>(MemoriesController.new);

class MemoriesController extends Notifier<MemoriesState> {
  @override
  MemoriesState build() {
    Future.microtask(() => loadMemories());
    return (memories: [], isLoading: true, error: null);
  }

  Future<void> loadMemories() async {
    state = (memories: state.memories, isLoading: true, error: null);
    try {
      final memories =
          await ref.read(memoriesRepositoryProvider).getMemories();
      state = (memories: memories, isLoading: false, error: null);
    } on ApiException catch (e) {
      state = (memories: state.memories, isLoading: false, error: e.message);
    }
  }

  Future<void> createMemory(String content) async {
    try {
      await ref.read(memoriesRepositoryProvider).createMemory(content);
      await loadMemories();
    } on ApiException catch (e) {
      state = (memories: state.memories, isLoading: false, error: e.message);
    }
  }

  Future<void> deleteMemory(String id) async {
    try {
      await ref.read(memoriesRepositoryProvider).deleteMemory(id);
      state = (
        memories: state.memories.where((m) => m.id != id).toList(),
        isLoading: false,
        error: null,
      );
    } on ApiException catch (e) {
      state = (memories: state.memories, isLoading: false, error: e.message);
    }
  }
}
```

---

- [ ] **Step 3: Create `MemoriesScreen`**

`lib/features/memories/presentation/memories_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'controllers/memories_controller.dart';

class MemoriesScreen extends ConsumerStatefulWidget {
  const MemoriesScreen({super.key});

  @override
  ConsumerState<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends ConsumerState<MemoriesScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(memoriesControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Memórias')),
      body: Column(
        children: [
          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : state.memories.isEmpty
                    ? const Center(child: Text('Nenhuma memória salva.'))
                    : ListView.builder(
                        itemCount: state.memories.length,
                        itemBuilder: (context, index) {
                          final memory = state.memories[index];
                          return ListTile(
                            title: Text(memory.content),
                            subtitle: Text(
                              '${memory.createdAt.day}/${memory.createdAt.month}/${memory.createdAt.year}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => ref
                                  .read(memoriesControllerProvider.notifier)
                                  .deleteMemory(memory.id),
                            ),
                          );
                        },
                      ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Salvar uma memória...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    final text = _controller.text.trim();
                    if (text.isNotEmpty) {
                      ref
                          .read(memoriesControllerProvider.notifier)
                          .createMemory(text);
                      _controller.clear();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

---

- [ ] **Step 4: Add route**

In `lib/core/router/app_router.dart`, add:

```dart
GoRoute(
  path: '/memories',
  name: 'memories',
  builder: (context, state) => const MemoriesScreen(),
),
```

---

- [ ] **Step 5: Commit**

```bash
git add lib/features/memories/ lib/core/router/app_router.dart
git commit -m "feat(memories): add Memories UI with list, create, delete"
```

---

## Self-Review

| Gap | Task | Covered? |
|-----|------|----------|
| note_links table/DAO | Task 1 | ✅ |
| note_links sync | Task 2 | ✅ |
| note_tags sync | Task 2 | ✅ |
| `message`→`content` rename | Task 3 | ✅ |
| Agent SSE to chat UI | Task 4 | ✅ |
| Routines PATCH /daily+/weekly | Task 5 | ✅ |
| Memories feature | Task 6 | ✅ |
| Task status mismatch (pending→open) | DB plan Task 2 | ✅ |
| completed_at not written | DB plan Task 3 | ✅ |

**Not addressed:** `isVault` column doesn't exist in Drift `Notes` table — scope says notes can be vault-protected but the local schema has no such column. Add as follow-up if needed.

---

## Execution Handoff

Plan complete. Ready to execute via subagent-driven or inline approach.
