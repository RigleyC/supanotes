// Measures the cost of each keystroke and caret move in the real note editor.
//
// The editor screen is pumped with the production session stack (Drift
// database, NoteSyncSession, operation capture/outbox) and only the HTTP
// client replaced. Each keystroke is applied through the editor pipeline and
// followed by one frame, so the measured time covers capture, outbox writes
// scheduled on that turn, widget rebuilds and layout.
//
// Run with:
//   flutter test benchmark/editor_typing_benchmark.dart
import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supanotes/core/auth/current_user.dart';

import 'cpu_profile.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_provider.dart';
import 'package:supanotes/features/notes/editor/presentation/note_editor_screen.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';
import 'package:super_editor/super_editor.dart';

const _paragraphs = 150;
const _tasks = 50;
const _keystrokes = 80;
const _caretMoves = 60;

class _QuietServer implements NoteSyncClient {
  @override
  Future<OperationsListResponse> getOperationsSince(
    String noteId,
    int sinceRevision, {
    int? limit,
  }) async => OperationsListResponse(
    revision: sinceRevision,
    operations: const [],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('network disabled in benchmark');
}

void main() {
  final binding = LiveTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  // Semantics are off on devices unless a screen reader is active.
  testWidgets('editor typing and caret movement', semanticsEnabled: false, (
    tester,
  ) async {
    await initializeDateFormatting('pt_BR');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final database = AppDatabase.test();
    await _seed(database);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentUserIdProvider.overrideWithValue('user-1'),
        noteSyncClientProvider.overrideWithValue(_QuietServer()),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: NoteEditorScreen(noteId: 'note-1')),
      ),
    );
    // Measures only the frame's own work (animations, build, layout, paint),
    // not the wait for the next vsync that pump() includes.
    Future<int> frame() async {
      final watch = Stopwatch();
      SchedulerBinding.instance.scheduleFrameCallback((_) => watch.start());
      SchedulerBinding.instance.addPostFrameCallback((_) => watch.stop());
      await tester.pump();
      return watch.elapsedMicroseconds;
    }

    Future<void> idle(int ms) async {
      await Future<void>.delayed(Duration(milliseconds: ms));
      await tester.pump();
    }

    await idle(1500);
    final session = container.read(noteEditorSessionProvider('note-1')).value!;
    final controller = session.controller;
    final editor = controller.editor;
    final document = controller.document;
    final target = document.getNodeAt(_paragraphs ~/ 2)!;

    editor.execute([
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: target.id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);
    await idle(300);

    const experiment = String.fromEnvironment('EXPERIMENT');
    if (experiment == 'no_capture') session.setCaptureLocalOperations(false);
    if (experiment == 'no_reactions') {
      // ignore: avoid_print
      print(
        'REACTIONS ${editor.reactionPipeline.map((r) => r.runtimeType).join(',')}',
      );
      editor.reactionPipeline.clear();
    }

    final rebuilds = <String, int>{};
    var counting = false;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (!counting) return;
      final key = element.widget.runtimeType.toString();
      rebuilds[key] = (rebuilds[key] ?? 0) + 1;
    };
    final typing = <int>[];
    final typingEdit = <int>[];
    await profile('typing', () async {
      for (var i = 0; i < _keystrokes; i++) {
        final sw = Stopwatch()..start();
        editor.execute([
          InsertCharacterAtCaretRequest(character: i % 7 == 6 ? ' ' : 'a'),
        ]);
        typingEdit.add(sw.elapsedMicroseconds);
        counting = i == 40;
        final frameUs = await frame();
        counting = false;
        typing.add(typingEdit.last + frameUs);
        // Typing cadence of ~12 characters per second lets debounces fire.
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    });

    final typingRebuilds = Map.of(rebuilds);
    rebuilds.clear();
    final moves = <int>[];
    final movesEdit = <int>[];
    for (var i = 0; i < _caretMoves; i++) {
      final node = document.getNodeAt((i * 7) % document.nodeCount)!;
      if (node is! TextNode) continue;
      final sw = Stopwatch()..start();
      editor.execute([
        ChangeSelectionRequest(
          DocumentSelection(
            base: DocumentPosition(
              nodeId: node.id,
              nodePosition: const TextNodePosition(offset: 0),
            ),
            extent: DocumentPosition(
              nodeId: node.id,
              nodePosition: TextNodePosition(
                offset: node.text.length < 5 ? node.text.length : 5,
              ),
            ),
          ),
          SelectionChangeType.expandSelection,
          SelectionReason.userInteraction,
        ),
      ]);
      movesEdit.add(sw.elapsedMicroseconds);
      counting = i == 30;
      final frameUs = await frame();
      counting = false;
      moves.add(movesEdit.last + frameUs);
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }

    String summary(List<int> samples) {
      final sorted = [...samples]..sort();
      double ms(int us) => us / 1000;
      final mean = samples.reduce((a, b) => a + b) / samples.length;
      return 'mean=${(mean / 1000).toStringAsFixed(2)}ms '
          'p50=${ms(sorted[sorted.length ~/ 2]).toStringAsFixed(2)}ms '
          'p90=${ms(sorted[(sorted.length * 0.9).floor()]).toStringAsFixed(2)}ms '
          'max=${ms(sorted.last).toStringAsFixed(2)}ms';
    }

    // A benchmark reports its result on stdout.
    // ignore: avoid_print
    print('BENCHMARK editor_typing keystroke ${summary(typing)}');
    // ignore: avoid_print
    print('BENCHMARK editor_selection move ${summary(moves)}');
    String top(Map<String, int> m) {
      final e = m.entries.toList()..sort((a, b) => b.value - a.value);
      final total = m.values.fold<int>(0, (a, b) => a + b);
      return 'total=$total ' +
          e.take(25).map((x) => '${x.key}:${x.value}').join(' ');
    }

    // ignore: avoid_print
    print('REBUILDS typing ${top(typingRebuilds)}');
    // ignore: avoid_print
    print('REBUILDS selection ${top(rebuilds)}');
    // ignore: avoid_print
    print('BENCHMARK editor_typing edit-only ${summary(typingEdit)}');
    // ignore: avoid_print
    print('BENCHMARK editor_selection edit-only ${summary(movesEdit)}');

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await idle(300);
    await database.close();
  });
}

Future<void> _seed(AppDatabase database) async {
  final now = DateTime.utc(2026, 9, 15, 10);
  final blocks = <Map<String, dynamic>>[
    for (var p = 0; p < _paragraphs; p++)
      {
        'id': 'p$p',
        'type': 'paragraph',
        'delta': [
          {
            'insert':
                'Paragraph $p with enough words to wrap across the line on a '
                'phone sized viewport, like a normal note would.',
          },
        ],
      },
    for (var t = 0; t < _tasks; t++)
      {
        'id': 't$t',
        'type': 'task',
        'delta': [
          {'insert': 'Task number $t'},
        ],
        'metadata': {
          'dueDate': '2026-0${(t % 9) + 1}-10T09:00:00.000',
          'hasTime': true,
          'recurrenceRule': t.isEven ? 'daily' : null,
          'isCompleted': false,
        }..removeWhere((_, value) => value == null),
      },
  ];
  final json = jsonEncode({'schemaVersion': 1, 'blocks': blocks});
  await database.notesDao.createNote(
    NotesCompanion.insert(
      id: 'note-1',
      userId: 'user-1',
      content: 'Paragraph 0',
      createdAt: now,
      updatedAt: now,
      hasRemoteCopy: const Value(true),
    ),
  );
  await database.noteOperationsDao.upsertNoteDocument(
    LocalNoteDocumentsCompanion.insert(
      noteId: 'note-1',
      revision: 1,
      documentJson: json,
      updatedAt: now,
      materializedDocumentJson: Value(json),
      materializedUpdatedAt: Value(now),
    ),
  );
}
