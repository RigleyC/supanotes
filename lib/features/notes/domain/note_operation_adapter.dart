import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/data/note_operations_api.dart';
import 'package:supanotes/features/notes/domain/note_document_codec.dart';

class _BlockMirror {
  String text;
  String? blockType;
  String attributionsSignature;
  Set<String> previousAttributionIds;

  _BlockMirror({
    required this.text,
    this.blockType,
    required this.attributionsSignature,
    required this.previousAttributionIds,
  });
}

class _RebuildRequest {
  final Map<String, dynamic> snapshot;
  final List<PendingNoteOperationData>? ops;
  _RebuildRequest({required this.snapshot, this.ops});
}

class NoteOperationAdapter {
  NoteOperationAdapter({
    required MutableDocument document,
    required NoteOperationsSyncService syncService,
    required String noteId,
    required Editor editor,
  })  : _document = document,
        _syncService = syncService,
        _noteId = noteId,
        _editor = editor;

  final MutableDocument _document;
  final NoteOperationsSyncService _syncService;
  final String _noteId;
  final Editor _editor;
  final _codec = NoteDocumentCodec();

  int _confirmedRevision = 0;
  bool _listening = false;
  bool _suppressOperations = false;
  final Map<String, _BlockMirror> _mirror = {};
  final List<OperationRequest> _pendingOps = [];
  Timer? _debounceTimer;

  final StreamController<List<PendingNoteOperationData>>
      _pendingOpsController =
      StreamController<List<PendingNoteOperationData>>.broadcast();

  Stream<List<PendingNoteOperationData>> get pendingOperationsStream =>
      _pendingOpsController.stream;

  int get confirmedRevision => _confirmedRevision;

  void Function(List<OperationRequest> ops)? onLocalOperations;

  bool _isComposing = false;
  _RebuildRequest? _pendingRebuild;

  void onCompositionStart() => _isComposing = true;
  void onCompositionEnd() {
    _isComposing = false;
    if (_pendingRebuild != null) {
      final req = _pendingRebuild!;
      _pendingRebuild = null;
      unawaited(rebuildFromSnapshot(snapshot: req.snapshot, rebasedOps: req.ops));
    }
  }

  Future<void> start() async {
    _suppressOperations = true;
    _buildMirror();
    await _loadConfirmedState();
    _document.addListener(_onDocumentChanged);
    await _hydrateFromServer();
    _buildMirror();
    _listening = true;
    _suppressOperations = false;
  }

  Future<void> _hydrateFromServer() async {
    try {
      final doc = await _syncService.getConfirmedDocument(_noteId);
      if (doc != null && doc.revision > 0) {
        final snapshot = jsonDecode(doc.documentJson) as Map<String, dynamic>;
        _applyFullDocument(snapshot);
        final pending = await _syncService.loadPendingProjection(_noteId);
        for (final op in pending) {
          _applyOperationRequest(op);
        }
        _confirmedRevision = doc.revision;
        return;
      }
      final serverDoc = await _syncService.fetchDocument(_noteId);
      if (serverDoc != null && serverDoc.revision > 0) {
        _applyFullDocument(serverDoc.document);
        _confirmedRevision = serverDoc.revision;
        await _syncService.storeDocument(_noteId, serverDoc);
      }
    } catch (e) {
      dev.log(
        '[NoteOperationAdapter] hydrateFromServer failed: $e',
        name: 'NoteOperationAdapter',
      );
    }
  }

  void _applyFullDocument(Map<String, dynamic> doc) {
    final blocks = doc['blocks'] as List<dynamic>? ?? [];
    for (final block in blocks) {
      if (block is! Map) continue;
      final blockMap = block as Map<String, dynamic>;
      final nodeId = blockMap['id'] as String?;
      if (nodeId == null) continue;
      if (_document.getNodeById(nodeId) != null) continue;

      final blockType = blockMap['type'] as String? ?? 'paragraph';
      final delta = blockMap['delta'] as List<dynamic>?;
      final attributedText = _codec.attributedFromDelta(delta);

      final newNode = _codec.createNodeFromBlockType(
        nodeId: nodeId,
        type: blockType,
        text: attributedText,
      );

      _editor.execute([InsertNodeAtIndexRequest(nodeIndex: _document.nodeCount, newNode: newNode)]);
    }
  }

  void _buildMirror() {
    _mirror.clear();
    for (final node in _document.toList()) {
      _mirror[node.id] = _mirrorFromNode(node);
    }
  }

  String _mirrorBlockType(DocumentNode node) => _codec.blockTypeName(node) ?? 'paragraph';

  _BlockMirror _mirrorFromNode(DocumentNode node) {
    if (node is TextNode) {
      return _BlockMirror(
        text: node.text.toPlainText(),
        blockType: _mirrorBlockType(node),
        attributionsSignature: _attributionsSignature(node.text),
        previousAttributionIds: _collectAttributionIds(node),
      );
    }
    return _BlockMirror(
      text: '',
      blockType: _mirrorBlockType(node),
      attributionsSignature: '',
      previousAttributionIds: {},
    );
  }

  Map<String, dynamic> _deltaSegmentWithAttributes(
    String text,
    Map<String, dynamic> attrs,
  ) {
    final op = <String, dynamic>{'insert': text};
    if (attrs.isNotEmpty) {
      op['attributes'] = Map<String, dynamic>.from(attrs);
    }
    return op;
  }

  List<MapEntry<String, Map<String, dynamic>>> _textSegmentsWithAttributes(
    TextNode node,
  ) {
    final text = node.text.toPlainText();
    if (text.isEmpty) return [];
    final segments = <MapEntry<String, Map<String, dynamic>>>[];
    int pos = 0;
    while (pos < text.length) {
      final attrs = _attributionsAtPosition(node, pos);
      int end = pos + 1;
      while (end < text.length) {
        if (_codec.mapsEqual(attrs, _attributionsAtPosition(node, end))) {
          end++;
        } else {
          break;
        }
      }
      segments.add(MapEntry(text.substring(pos, end), attrs));
      pos = end;
    }
    return segments;
  }

  Set<String> _collectAttributionIds(TextNode node) {
    final ids = <String>{};
    for (final marker in node.text.spans.markers) {
      if (marker.markerType == SpanMarkerType.start &&
          marker.attribution.id != 'composing') {
        ids.add(marker.attribution.id);
      }
    }
    return ids;
  }

  String _attributionsSignature(AttributedText text) {
    final parts = <String>[];
    for (final marker in text.spans.markers) {
      parts.add(
        '${marker.attribution.id}:${marker.offset}:${marker.markerType.index}',
      );
    }
    parts.sort();
    return parts.join(',');
  }

  Future<void> _loadConfirmedState() async {
    final doc = await _syncService.getConfirmedDocument(_noteId);
    if (doc != null) {
      _confirmedRevision = doc.revision;
    }
  }

  void _onDocumentChanged(DocumentChangeLog changeLog) {
    if (!_listening || _suppressOperations) return;

    for (final change in changeLog.changes) {
      if (change is NodeInsertedEvent) {
        _handleNodeInserted(change.nodeId);
      } else if (change is NodeRemovedEvent) {
        _handleNodeRemoved(change.nodeId);
      } else if (change is NodeMovedEvent) {
        _handleNodeMoved(change.nodeId);
      } else if (change is NodeChangeEvent) {
        _handleNodeChanged(change.nodeId);
      }
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      _flushLocalOps();
    });
  }

  void _handleNodeInserted(String nodeId) {
    final node = _document.getNodeById(nodeId);
    if (node == null) return;

    final index = _document.getNodeIndexById(nodeId);
    final afterBlockId =
        index > 0 ? _document.getNodeAt(index - 1)?.id : null;

    final payload = <String, dynamic>{
      'id': nodeId,
      'type': _codec.blockTypeName(node) ?? 'paragraph',
      'afterBlockId': afterBlockId,
    };
    if (node is TextNode) {
      final text = node.text.toPlainText();
      if (text.isNotEmpty) {
        final segments = _textSegmentsWithAttributes(node);
        payload['delta'] = segments
            .map((seg) => _deltaSegmentWithAttributes(seg.key, seg.value))
            .toList();
      } else {
        payload['delta'] = [{'insert': ''}];
      }
    } else {
      payload['delta'] = [];
    }

    _pendingOps.add(OperationRequest(
      operationId: _syncService.generateOperationId(),
      baseRevision: _confirmedRevision,
      kind: 'create_block',
      blockId: nodeId,
      payload: payload,
    ));

    _mirror[nodeId] = _mirrorFromNode(node);
  }

  void _handleNodeRemoved(String nodeId) {
    _pendingOps.add(OperationRequest(
      operationId: _syncService.generateOperationId(),
      baseRevision: _confirmedRevision,
      kind: 'delete_block',
      blockId: nodeId,
      payload: {'blockId': nodeId},
    ));

    _mirror.remove(nodeId);
  }

  void _handleNodeMoved(String nodeId) {
    final index = _document.getNodeIndexById(nodeId);
    final afterBlockId =
        index > 0 ? _document.getNodeAt(index - 1)?.id : null;

    _pendingOps.add(OperationRequest(
      operationId: _syncService.generateOperationId(),
      baseRevision: _confirmedRevision,
      kind: 'move_block',
      blockId: nodeId,
      payload: {
        'blockId': nodeId,
        'afterBlockId': afterBlockId,
      },
    ));
  }

  void _handleNodeChanged(String nodeId) {
    final node = _document.getNodeById(nodeId);
    if (node == null) return;

    final mirror = _mirror[nodeId];
    if (mirror == null) {
      _mirror[nodeId] = _mirrorFromNode(node);
      return;
    }

    if (node is TextNode) {
      final newText = node.text.toPlainText();
      if (newText != mirror.text) {
        final delta = _computeTextDelta(mirror.text, newText, node);
        if (delta.isNotEmpty) {
          _pendingOps.add(OperationRequest(
            operationId: _syncService.generateOperationId(),
            baseRevision: _confirmedRevision,
            kind: 'text_delta',
            blockId: nodeId,
            payload: {'ops': delta},
          ));
        }
        mirror.text = newText;
      }

      final newSig = _attributionsSignature(node.text);
      if (newText == mirror.text && newSig != mirror.attributionsSignature) {
        final delta = _computeAttributionDelta(
          node,
          mirror.previousAttributionIds,
        );
        if (delta.isNotEmpty) {
          _pendingOps.add(OperationRequest(
            operationId: _syncService.generateOperationId(),
            baseRevision: _confirmedRevision,
            kind: 'text_delta',
            blockId: nodeId,
            payload: {'ops': delta},
          ));
        }
        mirror.attributionsSignature = newSig;
        mirror.previousAttributionIds = _collectAttributionIds(node);
      }
    }

    final newType = _mirrorBlockType(node);
    if (newType != mirror.blockType) {
      _pendingOps.add(OperationRequest(
        operationId: _syncService.generateOperationId(),
        baseRevision: _confirmedRevision,
        kind: 'set_block_type',
        blockId: nodeId,
        payload: {'type': newType},
      ));
      mirror.blockType = newType;
    }
  }

  List<Map<String, dynamic>> _computeTextDelta(
    String oldText,
    String newText,
    TextNode node,
  ) {
    if (oldText == newText) return [];

    int prefix = 0;
    while (prefix < oldText.length &&
        prefix < newText.length &&
        oldText[prefix] == newText[prefix]) {
      prefix++;
    }

    int oi = oldText.length - 1;
    int ni = newText.length - 1;
    while (oi >= prefix &&
        ni >= prefix &&
        oldText[oi] == newText[ni]) {
      oi--;
      ni--;
    }

    final ops = <Map<String, dynamic>>[];
    if (prefix > 0) {
      ops.add({'retain': prefix});
    }

    final deletedLen = oi - prefix + 1;
    if (deletedLen > 0) {
      ops.add({'delete': deletedLen});
    }

    if (ni >= prefix) {
      final insertedText = newText.substring(prefix, ni + 1);
      final segments = <MapEntry<String, Map<String, dynamic>>>[];
      int insertPos = 0;
      while (insertPos < insertedText.length) {
        final globalPos = prefix + insertPos;
        final attrs = _attributionsAtPosition(node, globalPos);
        int segEnd = insertPos + 1;
        while (segEnd < insertedText.length) {
          if (_codec.mapsEqual(attrs, _attributionsAtPosition(node, prefix + segEnd))) {
            segEnd++;
          } else {
            break;
          }
        }
        segments.add(MapEntry(insertedText.substring(insertPos, segEnd), attrs));
        insertPos = segEnd;
      }
      for (final seg in segments) {
        ops.add(_deltaSegmentWithAttributes(seg.key, seg.value));
      }
    }

    return ops;
  }

  List<Map<String, dynamic>> _computeAttributionDelta(
    TextNode node,
    Set<String> previousIds,
  ) {
    final text = node.text.toPlainText();
    if (text.isEmpty) return [];

    final ops = <Map<String, dynamic>>[];
    int pos = 0;
    while (pos < text.length) {
      final attrs = _attributionsAtPosition(node, pos);
      for (final id in previousIds) {
        if (!attrs.containsKey(id)) {
          attrs[id] = null;
        }
      }
      int end = pos + 1;
      while (end < text.length) {
        final nextAttrs = _attributionsAtPosition(node, end);
        for (final id in previousIds) {
          if (!nextAttrs.containsKey(id)) {
            nextAttrs[id] = null;
          }
        }
        if (_codec.mapsEqual(attrs, nextAttrs)) {
          end++;
        } else {
          break;
        }
      }
      final len = end - pos;
      final hasNonNull = attrs.values.any((v) => v != null);
      if (!hasNonNull) {
        if (ops.isNotEmpty &&
            ops.last.length == 1 &&
            ops.last.containsKey('retain')) {
          ops.last['retain'] = (ops.last['retain'] as int) + len;
        } else {
          ops.add({'retain': len});
        }
      } else {
        ops.add({'retain': len, 'attributes': attrs});
      }
      pos = end;
    }
    return ops;
  }

  Map<String, dynamic> _attributionsAtPosition(TextNode node, int pos) {
    final attrs = <String, dynamic>{};
    for (final marker in node.text.spans.markers) {
      if (marker.markerType == SpanMarkerType.start &&
          marker.offset <= pos) {
        final spanEnd = _codec.findSpanEnd(node.text.spans.markers, marker);
        if (spanEnd > pos) {
          if (marker.attribution.id != 'composing') {
            attrs[marker.attribution.id] = true;
          }
        }
      }
    }
    return attrs;
  }

  Future<void> _flushLocalOps() async {
    if (_pendingOps.isEmpty) return;
    final projectedCount =
        await _syncService.getProjectedOutboxOperationCount(_noteId);
    final ops = List<OperationRequest>.from(_pendingOps);
    _pendingOps.clear();

    for (int i = 0; i < ops.length; i++) {
      final old = ops[i];
      ops[i] = OperationRequest(
        operationId: old.operationId,
        baseRevision: _confirmedRevision + projectedCount + i,
        kind: old.kind,
        blockId: old.blockId,
        payload: old.payload,
      );
    }

    for (final op in ops) {
      await _syncService.enqueueOperation(_noteId, op);
    }

    onLocalOperations?.call(ops);
    final pending = await _syncService.getPendingOperations(_noteId);
    _pendingOpsController.add(pending);
  }

  Future<void> flushNow() async {
    _debounceTimer?.cancel();
    if (_pendingOps.isNotEmpty) {
      await _flushLocalOps();
    }
  }

  void dispose() {
    _debounceTimer?.cancel();
    _document.removeListener(_onDocumentChanged);
    _listening = false;
    _pendingOpsController.close();
  }

  Future<void> reconcile(SyncResult result) async {
    final canonical = result.canonicalDocument;
    if (canonical == null) return;
    _confirmedRevision = result.finalRevision;
    final rebasedOps = await _syncService.loadPendingProjection(_noteId);
    await rebuildFromSnapshot(
      snapshot: canonical.document,
      rebasedOps: rebasedOps,
    );
  }

  Future<void> rebuildFromSnapshot({
    required Map<String, dynamic> snapshot,
    required List<PendingNoteOperationData>? rebasedOps,
  }) async {
    if (_isComposing) {
      _pendingRebuild = _RebuildRequest(snapshot: snapshot, ops: rebasedOps);
      return;
    }

    _suppressOperations = true;
    try {
      final existingNodes = _document.toList();
      for (final node in existingNodes.reversed) {
        _editor.execute([DeleteNodeRequest(nodeId: node.id)]);
      }
      _applyFullDocument(snapshot);
      if (rebasedOps != null) {
        for (final op in rebasedOps) {
          _applyOperationRequest(op);
        }
      }
      _buildMirror();
    } finally {
      _suppressOperations = false;
    }
  }

  void _applyOperationRequest(PendingNoteOperationData op) {
    _applyOperation(Operation(
      operationId: op.operationId,
      noteId: op.noteId,
      revision: op.baseRevision,
      baseRevision: op.baseRevision,
      actorId: '',
      kind: op.kind,
      blockId: op.blockId,
      payload: NoteOperationsSyncService.parsePayload(op.payloadJson),
      createdAt: op.createdAt,
    ));
  }

  void _applyOperation(Operation op) {
    switch (op.kind) {
      case 'text_delta':
        _applyTextDelta(op);
      case 'create_block':
        _applyCreateBlock(op);
      case 'delete_block':
        _applyDeleteBlock(op);
      case 'move_block':
        _applyMoveBlock(op);
      case 'set_block_type':
        _applySetBlockType(op);
    }
  }

  void _applyTextDelta(Operation op) {
    final blockId = op.blockId;
    if (blockId == null) return;

    final node = _document.getNodeById(blockId);
    if (node is! TextNode) return;

    final ops = op.payload['ops'] as List<dynamic>?;
    if (ops == null || ops.isEmpty) return;

    final result = _codec.applyDeltaToText(
      node.text,
      ops.cast<Map<String, dynamic>>(),
    );
    if (result == null) return;

    final newNode = _codec.replaceTextNode(node, result);
    _editor.execute([
      ReplaceNodeRequest(
        existingNodeId: blockId,
        newNode: newNode,
      ),
    ]);
  }

  void _applyCreateBlock(Operation op) {
    final payload = op.payload;
    final nodeId = payload['id'] as String? ?? op.blockId;
    if (nodeId == null) return;

    if (_document.getNodeById(nodeId) != null) return;

    final type = payload['type'] as String? ?? 'paragraph';
    final delta = payload['delta'] as List<dynamic>?;
    final afterBlockId = payload['afterBlockId'] as String?;

    final attributedText = _codec.attributedFromDelta(delta);
    final newNode = _codec.createNodeFromBlockType(
      nodeId: nodeId,
      type: type,
      text: attributedText,
    );

    int targetIndex;
    if (afterBlockId == null) {
      targetIndex = 0;
    } else {
      final afterIndex = _document.getNodeIndexById(afterBlockId);
      if (afterIndex == -1) {
        targetIndex = _document.nodeCount;
      } else {
        targetIndex = afterIndex + 1;
      }
    }

    _editor.execute([
      InsertNodeAtIndexRequest(nodeIndex: targetIndex, newNode: newNode),
    ]);
  }

  void _applyDeleteBlock(Operation op) {
    final blockId = op.blockId ?? op.payload['blockId'] as String?;
    if (blockId == null) return;
    if (_document.getNodeById(blockId) == null) return;

    _editor.execute([DeleteNodeRequest(nodeId: blockId)]);
  }

  void _applyMoveBlock(Operation op) {
    final blockId = op.blockId ?? op.payload['blockId'] as String?;
    final afterBlockId = op.payload['afterBlockId'] as String?;
    if (blockId == null) return;
    if (_document.getNodeById(blockId) == null) return;

    int targetIndex;
    if (afterBlockId == null) {
      targetIndex = 0;
    } else {
      final afterIndex = _document.getNodeIndexById(afterBlockId);
      if (afterIndex == -1) {
        targetIndex = _document.nodeCount - 1;
      } else {
        targetIndex = afterIndex + 1;
      }
    }

    _editor.execute([MoveNodeRequest(nodeId: blockId, newIndex: targetIndex)]);
  }

  void _applySetBlockType(Operation op) {
    final blockId = op.blockId;
    final blockTypeStr = op.payload['type'] as String?;
    if (blockId == null) return;

    final node = _document.getNodeById(blockId);
    if (node == null) return;

    if (blockTypeStr == null || blockTypeStr == 'paragraph') {
      _replaceWithParagraph(node);
      return;
    }

    if (blockTypeStr == 'bulletList') {
      _replaceWithListItem(node, ListItemType.unordered);
      return;
    }
    if (blockTypeStr == 'orderedList') {
      _replaceWithListItem(node, ListItemType.ordered);
      return;
    }
    if (blockTypeStr == 'task') {
      _replaceWithTask(node);
      return;
    }

    final attribution = _attributionFromName(blockTypeStr);
    if (node is ParagraphNode) {
      _editor.execute([
        ChangeParagraphBlockTypeRequest(nodeId: blockId, blockType: attribution),
      ]);
    } else {
      _replaceWithParagraph(node);
      if (attribution != null) {
        final newNode = _document.getNodeById(blockId);
        if (newNode is ParagraphNode) {
          _editor.execute([
            ChangeParagraphBlockTypeRequest(nodeId: blockId, blockType: attribution),
          ]);
        }
      }
    }
  }

  void _replaceWithParagraph(DocumentNode node) {
    final text = node is TextNode ? node.text : AttributedText();
    _editor.execute([
      ReplaceNodeRequest(
        existingNodeId: node.id,
        newNode: ParagraphNode(id: node.id, text: text),
      ),
    ]);
  }

  void _replaceWithListItem(DocumentNode node, ListItemType itemType) {
    final text = node is TextNode ? node.text : AttributedText();
    _editor.execute([
      ReplaceNodeRequest(
        existingNodeId: node.id,
        newNode: ListItemNode(id: node.id, itemType: itemType, text: text),
      ),
    ]);
  }

  void _replaceWithTask(DocumentNode node) {
    final text = node is TextNode ? node.text : AttributedText();
    _editor.execute([
      ReplaceNodeRequest(
        existingNodeId: node.id,
        newNode: TaskNode(id: node.id, text: text, isComplete: false),
      ),
    ]);
  }

  Attribution? _attributionFromName(String? name) {
    return _codec.attributionFromName(name);
  }
}
