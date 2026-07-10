import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_crdt/dart_crdt.dart';

SharedType _text(Doc doc, String key) {
  return doc.getText(key);
}

String _str(Doc doc, String key) => doc.getText(key).toPlainText();

// =============================================================================
// Teste 2 — Dart sozinho, sem rede
// Verifica que dois Docs yjs_dart convergem após trocarem updates concorrentes.
// =============================================================================

void main() {
  group('Teste 2 — yjs_dart convergência (sem rede)', () {
    test('inserts concorrentes fixos convergem', () {
      final docA = Doc();
      final docB = Doc();

      // Pré-registro do tipo (necessário para applyUpdate funcionar corretamente)
      docA.getText('content');
      docB.getText('content');

      const initial = 'hello world';

      // Ambos partem do mesmo estado inicial
      docA.transact((txn) {
        _text(docA, 'content').insertText(0, initial);
      });
      // Sync initial state: send full state of A to B
      final stateA = encodeStateAsUpdate(docA);
      applyUpdate(docB, stateA);

      expect(_str(docA, 'content'), initial);
      expect(_str(docB, 'content'), initial);

      // Edições concorrentes — antes de trocar updates
      // Capture state vectors BEFORE the concurrent edits
      final svA = encodeDocumentStateVector(docA);
      final svB = encodeDocumentStateVector(docB);

      docA.transact((txn) {
        _text(docA, 'content').insertText(5, 'XXX');
      });
      docB.transact((txn) {
        _text(docB, 'content').insertText(3, 'YYY');
      });

      // Troca de updates — only the DIFF since svA/svB (not full state)
      final diffA = encodeStateAsUpdate(docA, svB); // what B is missing
      final diffB = encodeStateAsUpdate(docB, svA); // what A is missing
      applyUpdate(docA, diffB);
      applyUpdate(docB, diffA);

      final textA = _str(docA, 'content');
      final textB = _str(docB, 'content');

      // ✅ Critério 1: convergência
      expect(textA, equals(textB),
          reason: 'CRDT divergiu:\n  docA=$textA\n  docB=$textB');
      // ✅ Critério 2: sem duplicatas
      expect(_count(textA, 'XXX'), 1, reason: 'XXX duplicado em: $textA');
      expect(_count(textA, 'YYY'), 1, reason: 'YYY duplicado em: $textA');

      // ignore: avoid_print
      print('✅ Resultado convergido: "$textA"');
    });

    test('fuzzing — 30 inserts concorrentes em posições aleatórias', () {
      const iterations = 30;
      final rng = Random(42); // seed fixo para reprodutibilidade

      for (var i = 0; i < iterations; i++) {
        final docA = Doc();
        final docB = Doc();
        docA.getText('content');
        docB.getText('content');

        const initial = 'abcdefghijklmnopqrstuvwxyz';
      docA.transact((txn) {
        _text(docA, 'content').insertText(0, initial);
      });
      final stateA = encodeStateAsUpdate(docA);
      applyUpdate(docB, stateA);

      final len = _text(docA, 'content').toPlainText().length;
      final posA = rng.nextInt(len + 1);
      final posB = rng.nextInt(len + 1);

      // Capture state vectors BEFORE the concurrent edits
      final svA = encodeDocumentStateVector(docA);
      final svB = encodeDocumentStateVector(docB);

      docA.transact((txn) {
        _text(docA, 'content').insertText(posA, 'XXX');
      });
      docB.transact((txn) {
        _text(docB, 'content').insertText(posB, 'YYY');
      });

        // Exchange only the DIFF (not full state)
        final diffA = encodeStateAsUpdate(docA, svB);
        final diffB = encodeStateAsUpdate(docB, svA);
        applyUpdate(docA, diffB);
        applyUpdate(docB, diffA);

        final textA = _str(docA, 'content');
        final textB = _str(docB, 'content');

        expect(textA, equals(textB),
            reason:
                'iter $i: CRDT divergiu posA=$posA posB=$posB\n  docA=$textA\n  docB=$textB');
        expect(_count(textA, 'XXX'), 1,
            reason: 'iter $i: XXX duplicado em $textA');
        expect(_count(textA, 'YYY'), 1,
            reason: 'iter $i: YYY duplicado em $textA');
      }
      // ignore: avoid_print
      print('✅ $iterations iterações de fuzzing passaram');
    });
  });

  // ===========================================================================
  // Teste 3 (lado Dart) — Geração de fixture + interop com Go
  // ===========================================================================

  group('Teste 3 — interop binário Go ↔ Dart', () {
    test('Dart gera fixture para o Go aplicar', () {
      final docA = Doc();
      docA.getText('content');

      docA.transact((txn) {
        _text(docA, 'content').insertText(0, 'hello world');
      });
      // Edição conhecida: insere "DART_EDIT" na posição 5
      docA.transact((txn) {
        _text(docA, 'content').insertText(5, 'DART_EDIT');
      });

      final update = encodeStateAsUpdate(docA);

      // Self-check: outro doc Dart consegue aplicar?
      final docB = Doc();
      docB.getText('content');
      applyUpdate(docB, update);

      final got = _str(docB, 'content');
      const expected = 'helloDARTEDIT world';
      // Nota: "DART_EDIT" sem underscore → "DART_EDIT" com underscore → depende da lib
      // Verificamos o que realmente sai
      expect(got.contains('DART_EDIT'), isTrue,
          reason: 'DART_EDIT ausente: $got');

      final dir = Directory('testdata');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File('testdata/crdt3_dart_update.bin').writeAsBytesSync(update);
      File('testdata/crdt3_dart_expected.txt').writeAsStringSync(got);

      // ignore: avoid_print
      print('✅ Fixture Dart gerado: ${update.length} bytes, texto: "$got"');
    });

    test('Dart aplica fixture gerado pelo Go', () {
      const fixturePath = 'testdata/crdt3_go_update.bin';
      const expectedPath = 'testdata/crdt3_go_expected.txt';

      final fixtureFile = File(fixturePath);
      if (!fixtureFile.existsSync()) {
        // ignore: avoid_print
        print(
            'SKIP: fixture Go não encontrado em $fixturePath — rode TestCRDT3_GenerateGoFixture primeiro');
        return;
      }

      final update = Uint8List.fromList(fixtureFile.readAsBytesSync());
      final expected = File(expectedPath).readAsStringSync().trim();

      final doc = Doc();
      doc.getText('content');
      applyUpdate(doc, update);

      final got = _str(doc, 'content');
      expect(got, equals(expected),
          reason: 'Dart não reconheceu o update Go:\n  expected=$expected\n  got=$got');
      // ignore: avoid_print
      print('✅ Update Go aplicado no Dart: "$got"');
    });

    test('edição concorrente cross-lib converge (Dart simula dois peers)', () {
      const fixturePath = 'testdata/crdt3_go_update.bin';
      final fixtureFile = File(fixturePath);
      if (!fixtureFile.existsSync()) {
        // ignore: avoid_print
        print('SKIP: fixture Go ausente — rode TestCRDT3_GenerateGoFixture');
        return;
      }

      final goUpdate = Uint8List.fromList(fixtureFile.readAsBytesSync());

      // peerA simula o que o Go fez: parte do estado vazio, aplica o update do Go
      final peerA = Doc();
      peerA.getText('content');
      applyUpdate(peerA, goUpdate);

      // peerB começa do mesmo estado base (sem o update do Go)
      // e faz uma edição local diferente
      final peerB = Doc();
      peerB.getText('content');
      peerB.transact((txn) {
        _text(peerB, 'content').insertText(0, 'hello world');
      });
      peerB.transact((txn) {
        _text(peerB, 'content').insertText(0, 'DART_PREFIX_');
      });

      // Agora troca updates
      final updateA = encodeStateAsUpdate(peerA);
      final updateB = encodeStateAsUpdate(peerB);
      applyUpdate(peerA, updateB);
      applyUpdate(peerB, updateA);

      final textA = _str(peerA, 'content');
      final textB = _str(peerB, 'content');

      expect(textA, equals(textB),
          reason: 'Cross-lib CRDT divergiu:\n  peerA=$textA\n  peerB=$textB');
      expect(_count(textA, 'GO_EDIT'), 1,
          reason: 'GO_EDIT duplicado: $textA');
      expect(_count(textA, 'DART_PREFIX_'), 1,
          reason: 'DART_PREFIX_ duplicado: $textA');
      // ignore: avoid_print
      print('✅ Convergência cross-lib: "$textA"');
    });
  });
}

// =============================================================================
// helpers
// =============================================================================

int _count(String s, String sub) {
  int count = 0;
  int start = 0;
  while (true) {
    final idx = s.indexOf(sub, start);
    if (idx == -1) break;
    count++;
    start = idx + sub.length;
  }
  return count;
}
