import 'dart:async';

import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/data/note_operations_api.dart';

class _BlockMirror {
  String text;
  String? blockType;
  String attributionsSignature;

  _BlockMirror({
    required this.text,
    this.blockType,
    required this.attributionsSignature,
  });
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

  int _confirmedRevision = 0;
  bool _listening = false;
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

  void start() {
    _buildMirror();
    _loadConfirmedState();
    _listening = true;
    _document.addListener(_onDocumentChanged);
  }

  void _buildMirror() {
    _mirror.clear();
    for (final node in _document.toList()) {
      _mirror[node.id] = _mirrorFromNode(node);
    }
  }

  _BlockMirror _mirrorFromNode(DocumentNode node) {
    if (node is TextNode) {
      return _BlockMirror(
        text: node.text.toPlainText(),
        blockType: _blockTypeName(node),
        attributionsSignature: _attributionsSignature(node.text),
      );
    }
    return _BlockMirror(
      text: '',
      blockType: _blockTypeName(node),
      attributionsSignature: '',
    );
  }

  String? _blockTypeName(DocumentNode node) {
    if (node is ParagraphNode) {
      final blockType = node.getMetadataValue('blockType') as Attribution?;
      if (blockType == header1Attribution) return 'header1';
      if (blockType == header2Attribution) return 'header2';
      if (blockType == header3Attribution) return 'header3';
      if (blockType == blockquoteAttribution) return 'quote';
      return null;
    }
    if (node is ListItemNode) {
      return node.type == ListItemType.ordered
          ? 'orderedList'
          : 'bulletList';
    }
    if (node is TaskNode) return 'task';
    if (node is HorizontalRuleNode) return 'divider';
    return null;
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
    if (!_listening) return;

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
      'type': _blockTypeName(node) ?? 'paragraph',
      'afterBlockId': afterBlockId,
    };
    if (node is TextNode) {
      final text = node.text.toPlainText();
      payload['delta'] = text.isNotEmpty
          ? [{'insert': text}]
          : [{'insert': ''}];
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
        final delta = _computeAttributionDelta(node);
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
      }
    }

    final newType = _blockTypeName(node);
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
      final attrs = _getAttributionsInRange(node, prefix, ni + 1);
      final insertOp = <String, dynamic>{'insert': insertedText};
      if (attrs.isNotEmpty) {
        insertOp['attributes'] = attrs;
      }
      ops.add(insertOp);
    }

    return ops;
  }

  List<Map<String, dynamic>> _computeAttributionDelta(TextNode node) {
    final text = node.text.toPlainText();
    if (text.isEmpty) return [];

    final ops = <Map<String, dynamic>>[];
    int pos = 0;
    while (pos < text.length) {
      final attrs = _attributionsAtPosition(node, pos);
      int end = pos + 1;
      while (end < text.length) {
        final nextAttrs = _attributionsAtPosition(node, end);
        if (_mapsEqual(attrs, nextAttrs)) {
          end++;
        } else {
          break;
        }
      }
      final len = end - pos;
      if (attrs.isEmpty) {
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
        final spanEnd = _findSpanEnd(node.text.spans.markers, marker);
        if (spanEnd > pos) {
          if (marker.attribution.id != 'composing') {
            attrs[marker.attribution.id] = true;
          }
        }
      }
    }
    return attrs;
  }

  int _findSpanEnd(Iterable<SpanMarker> markers, SpanMarker startMarker) {
    for (final marker in markers) {
      if (marker.attribution.id == startMarker.attribution.id &&
          marker.markerType == SpanMarkerType.end &&
          marker.offset >= startMarker.offset) {
        return marker.offset;
      }
    }
    return -1;
  }

  Map<String, dynamic> _getAttributionsInRange(
    TextNode node,
    int start,
    int end,
  ) {
    final attrs = <String, dynamic>{};
    for (int i = start; i < end && i < node.text.toPlainText().length; i++) {
      for (final marker in node.text.spans.markers) {
        if (marker.markerType == SpanMarkerType.start &&
            marker.offset <= i) {
          final spanEnd = _findSpanEnd(node.text.spans.markers, marker);
          if (spanEnd > i && marker.attribution.id != 'composing') {
            attrs[marker.attribution.id] = true;
          }
        }
      }
    }
    return attrs;
  }

  bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }

  Future<void> _flushLocalOps() async {
    if (_pendingOps.isEmpty) return;
    final ops = List<OperationRequest>.from(_pendingOps);
    _pendingOps.clear();

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

  Future<void> applyRemoteOperations(List<Operation> operations) async {
    _listening = false;

    try {
      for (final op in operations) {
        _applyOperation(op);
      }
    } finally {
      _buildMirror();
      _listening = true;
    }
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

    final composed = _composeDelta(node.text.toPlainText(), ops.cast<Map<String, dynamic>>());
    if (composed == null) return;

    final newText = _buildAttributedText(composed, node.text);
    final newNode = _replaceTextNode(node, newText);
    _editor.execute([
      ReplaceNodeRequest(
        existingNodeId: blockId,
        newNode: newNode,
      ),
    ]);
  }

  String? _composeDelta(String source, List<Map<String, dynamic>> ops) {
    final buf = StringBuffer();
    int srcPos = 0;

    for (final op in ops) {
      if (op.containsKey('retain')) {
        final n = op['retain'] as int;
        if (srcPos + n > source.length) return null;
        buf.write(source.substring(srcPos, srcPos + n));
        srcPos += n;
      } else if (op.containsKey('insert')) {
        buf.write(op['insert'] as String);
      } else if (op.containsKey('delete')) {
        final n = op['delete'] as int;
        if (srcPos + n > source.length) return null;
        srcPos += n;
      } else {
        return null;
      }
    }

    buf.write(source.substring(srcPos));
    return buf.toString();
  }

  AttributedText _buildAttributedText(String plainText, AttributedText source) {
    if (plainText == source.toPlainText()) return source;

    final spans = AttributedSpans();
    final preservedSpans = <Map<String, dynamic>>[];

    for (final marker in source.spans.markers) {
      if (marker.offset < plainText.length) {
        preservedSpans.add({
          'a': marker.attribution.id,
          'o': marker.offset.clamp(0, plainText.length),
          't': marker.markerType == SpanMarkerType.start ? 's' : 'e',
        });
      }
    }

    for (final span in preservedSpans) {
      final attrs = <Attribution>[];
      if (span['a'] == 'bold') {
        attrs.add(boldAttribution);
      } else if (span['a'] == 'italics') {
        attrs.add(italicsAttribution);
      } else if (span['a'] == 'strikethrough') {
        attrs.add(strikethroughAttribution);
      } else if (span['a'] == 'underline') {
        attrs.add(underlineAttribution);
      } else if (span['a'] == 'link') {
        continue;
      } else {
        continue;
      }

      for (final attr in attrs) {
        spans.addAttribution(
          newAttribution: attr,
          start: span['o'] as int,
          end: span['o'] as int,
        );
      }
    }

    return AttributedText(plainText, spans);
  }

  DocumentNode _replaceTextNode(TextNode oldNode, AttributedText newText) {
    if (oldNode is ParagraphNode) {
      return ParagraphNode(
        id: oldNode.id,
        text: newText,
        metadata: Map<String, dynamic>.from(oldNode.metadata),
      );
    }
    if (oldNode is ListItemNode) {
      return ListItemNode(
        id: oldNode.id,
        itemType: oldNode.type,
        text: newText,
        indent: oldNode.indent,
      );
    }
    if (oldNode is TaskNode) {
      return TaskNode(
        id: oldNode.id,
        text: newText,
        isComplete: oldNode.isComplete,
        indent: oldNode.indent,
      );
    }
    return ParagraphNode(id: oldNode.id, text: newText);
  }

  void _applyCreateBlock(Operation op) {
    final payload = op.payload;
    final nodeId = payload['id'] as String? ?? op.blockId;
    if (nodeId == null) return;

    if (_document.getNodeById(nodeId) != null) return;

    final type = payload['type'] as String? ?? 'paragraph';
    final delta = payload['delta'] as List<dynamic>?;
    final text = _textFromDelta(delta);
    final afterBlockId = payload['afterBlockId'] as String?;

    DocumentNode newNode;
    if (type == 'divider') {
      newNode = HorizontalRuleNode(id: nodeId);
    } else {
      final attributedText = text.isEmpty
          ? AttributedText()
          : AttributedText(text);
      newNode = ParagraphNode(id: nodeId, text: attributedText);
    }

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
    if (node is! ParagraphNode) return;

    final attribution = _attributionFromName(blockTypeStr);
    _editor.execute([
      ChangeParagraphBlockTypeRequest(nodeId: blockId, blockType: attribution),
    ]);
  }

  String _textFromDelta(List<dynamic>? delta) {
    if (delta == null) return '';
    final buf = StringBuffer();
    for (final op in delta) {
      if (op is Map<String, dynamic> && op.containsKey('insert')) {
        buf.write(op['insert'] as String);
      }
    }
    return buf.toString();
  }

  Attribution? _attributionFromName(String? name) {
    if (name == null) return null;
    if (name == 'header1') return header1Attribution;
    if (name == 'header2') return header2Attribution;
    if (name == 'header3') return header3Attribution;
    if (name == 'quote') return blockquoteAttribution;
    return null;
  }
}
