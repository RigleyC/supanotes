import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/features/notes/domain/editor_document_sync_manager.dart';
import 'package:supanotes/features/notes/domain/yjs_doc_editor_bridge.dart';

class RecordingProjectionScheduler {
  final List<String> requestedNoteIds = [];

  void requestProjection(String noteId) {
    requestedNoteIds.add(noteId);
  }
}

YjsDocEditorBridge buildBridge({
  Doc? doc,
  RecordingProjectionScheduler? projectionScheduler,
}) {
  final d = doc ?? Doc();
  final mutableDoc = MutableDocument.empty();
  final composer = MutableDocumentComposer();
  final editor = createDefaultDocumentEditor(
    document: mutableDoc,
    composer: composer,
  )..reactionPipeline.clear();

  final coordinator = EditorDocumentSyncManager(
    document: mutableDoc,
    editor: editor,
  );

  return YjsDocEditorBridge(
    doc: d,
    userId: 'test-user',
    coordinator: coordinator,
  );
}

Object? readTaskField(Doc doc, String nodeId, String field) {
  final nodesMap = doc.getMap<Object>('nodes')!;
  final composite = nodesMap.get('$nodeId:$field');
  if (composite != null) return composite;
  final raw = nodesMap.get(nodeId);
  if (raw is YMap) {
    return raw.get(field);
  }
  return null;
}

void main() {
  group('YjsDocEditorBridge - task commands', () {
    test(
        'recurring completion records per-occurrence event without advancing dueDate',
        () async {
      final recorder = RecordingProjectionScheduler();
      final doc = Doc();
      final bridge = buildBridge(doc: doc, projectionScheduler: recorder);

      // Seed a recurring task node in the YDoc
      doc.transact((txn) {
        final nodeMap = YMap<Object>();
        nodeMap.set('id', 'task-1');
        nodeMap.set('type', 'task');
        nodeMap.set('position', 'a0');
        nodeMap.set('data', '{}');
        nodeMap.set('createdAt', 1000.0);
        nodeMap.set('recurrence', 'daily');
        nodeMap.set('dueDate', '2026-07-18');
        doc.getMap<Object>('nodes')!.set('task-1', nodeMap);
      });

      final result = bridge.completeTaskInYDoc('task-1',
          now: DateTime.utc(2026, 7, 18, 9));

      // Template should NOT be advanced
      expect(result.nextDue, isNull);
      expect(result.completed, false);
      expect(result.scheduledAt, DateTime(2026, 7, 18));

      // Completion event should be in taskCompletions YMap, not on template
      final nodeMap = readTaskField(doc, 'task-1', 'dueDate');
      expect(nodeMap, '2026-07-18'); // dueDate still anchor
      expect(readTaskField(doc, 'task-1', 'completed'), isNull);
      expect(readTaskField(doc, 'task-1', 'lastCompletedAt'), isNull);

      final completionsRoot = doc.getMap<Object>('taskCompletions')!;
      final key = 'task-1:2026-07-18';
      expect(completionsRoot.get(key), result.completedAt.toIso8601String());
    });
  });
}
