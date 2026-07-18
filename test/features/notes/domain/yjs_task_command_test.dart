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
        'recurring completion produces one Yjs transaction and one projection request',
        () async {
      final recorder = RecordingProjectionScheduler();
      final doc = Doc();
      final bridge = buildBridge(doc: doc, projectionScheduler: recorder);

      final result = bridge.completeTaskInYDoc('task-1',
          now: DateTime(2026, 7, 18, 9));

      expect(result.nextDue, DateTime(2026, 7, 19, 9));
      expect(recorder.requestedNoteIds, ['note-1']);
      expect(readTaskField(doc, 'task-1', 'lastCompletedAt'), isNotNull);
    });
  });
}
