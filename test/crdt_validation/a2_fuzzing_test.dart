import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:yjs_dart/yjs_dart.dart';
import 'package:supanotes/features/notes/domain/yjs_node_codec.dart';

void main() {
  test('P0: A2 - Fuzzing colisão de tipos YMap vs YText', () {
    // Client A (ex: Dart bugado ou malicioso) cria um Paragrafo, e por algum motivo ele é um YText.
    final docA = Doc(DocOpts(clientID: 1));
    docA.getText('content/node-123')!.insert(0, "Texto");
    
    // Client B (ex: Go via REST) cria o mesmo node como uma Task (YMap) por colisão
    final docB = Doc(DocOpts(clientID: 2));
    docB.getMap('content/node-123')!.set('foo', 'bar');
    
    // Cruza os updates (Simula rede offline sync)
    final updateA = encodeStateAsUpdate(docA);
    final updateB = encodeStateAsUpdate(docB);
    
    applyUpdate(docA, updateB);
    applyUpdate(docB, updateA);
    
    // Ambos devem convergir para o mesmo tipo! O Yjs YATA decide deterministicamente.
    final typeA = docA.get('content/node-123');
    final typeB = docB.get('content/node-123');
    
    expect(typeA.runtimeType, typeB.runtimeType, reason: "Devem convergir para o mesmo tipo de CRDT");
    
    // Agora o codec não deve crashar!
    final nodeMap = YMap<Object>();
    nodeMap.set('id', 'node-123');
    nodeMap.set('type', 'task'); // Diz que é task
    docA.getMap<Object>('nodes')!.set('node-123', nodeMap);
    
    final node = noteNodeFromYDoc(docA, 'node-123');
    expect(node, isNotNull);
    
    // O tipo derivado no NoteNode deve corresponder à realidade do shared type que venceu
    if (typeA is YText) {
      expect(node!.type, 'paragraph');
    } else if (typeA is YMap) {
      expect(node!.type, 'task');
    }
  });
}
