import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

void main() {
  test('README quick start creates a document and shared text', () {
    final doc = Doc();
    final text = doc.get('body', SharedTypeKind.text);

    text.insertText(0, 'Hello, local-first Dart.');

    expect(text.toPlainText(), 'Hello, local-first Dart.');
  });

  test('README update exchange applies encoded CRDT state', () {
    final local = _docWithRootText('sync');
    final remote = Doc(clientId: ClientId(9));

    final update = encodeStateAsUpdate(local);
    applyUpdate(remote, update);

    expect(_rootText(remote), 'sync');
    expect(remote.store.stateVector(), {ClientId(1): Clock(4)});
  });

  test('README rich text and undo examples use public APIs', () {
    final doc = Doc();
    final text = doc.get('body', SharedTypeKind.text);

    text.insertText(
      0,
      'Bold',
      attributes: DeltaAttributes.fromJson({'bold': true}),
    );

    expect(text.toDelta().toJson().toString(), contains('bold'));

    final synced = Doc(gc: false, clientId: ClientId(9));
    final undoManager = UndoManager(synced);
    applyUpdate(synced, encodeStateAsUpdate(_docWithRootText('draft')));

    expect(undoManager.canUndo(), isTrue);

    undoManager.undo();
    expect(_rootText(synced), isEmpty);

    undoManager.redo();
    expect(_rootText(synced), 'draft');

    undoManager.destroy();
  });

  test('README relative positions encode and resolve against CRDT state', () {
    final source = _docWithRootText('hello', rootName: 'body');
    final doc = Doc();
    final text = doc.get('body', SharedTypeKind.text);
    applyUpdate(doc, encodeStateAsUpdate(source));

    final position = createRelativePositionFromTypeIndex(text, 2);
    final encoded = encodeRelativePosition(position);
    final resolved = createAbsolutePositionFromRelativePosition(
      decodeRelativePosition(encoded),
      doc,
    );

    expect(resolved?.index, 2);
  });

  test('README snapshots restore a GC-disabled document version', () {
    final doc = _docWithRootText('snapshot', gc: false);
    final snap = snapshot(doc);
    final restored = createDocFromSnapshot(
      doc,
      decodeSnapshot(encodeSnapshot(snap)),
    );

    expect(_rootText(restored), 'snapshot');
  });
}

Doc _docWithRootText(String text, {String rootName = 'root', bool gc = true}) {
  final doc = Doc(clientId: ClientId(1), gc: gc);
  doc.getText(rootName).insertText(0, text);
  return doc;
}

String _rootText(Doc doc) => doc.getText('root').toPlainText();
