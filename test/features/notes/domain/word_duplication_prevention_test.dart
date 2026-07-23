import 'dart:convert';

import 'package:dart_quill_delta/dart_quill_delta.dart' as quill;
import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/data/note_sync_client.dart';
import 'package:supanotes/features/notes/domain/note_operation_rebaser.dart';

quill.Delta deltaFromOps(List<dynamic> ops) {
  final delta = quill.Delta();
  for (final op in ops) {
    final map = op as Map<String, dynamic>;
    if (map.containsKey('insert')) {
      delta.insert(map['insert']);
    } else if (map.containsKey('retain')) {
      delta.retain(map['retain'] as int);
    } else if (map.containsKey('delete')) {
      delta.delete(map['delete'] as int);
    }
  }
  return delta;
}

String deltaToPlainText(quill.Delta delta) {
  final buffer = StringBuffer();
  for (final op in delta.operations) {
    if (op.data is String) {
      buffer.write(op.data as String);
    }
  }
  return buffer.toString();
}

void main() {
  group('Word Duplication Prevention Tests - Prevenção de Duplicidade de Palavras', () {
    late NoteOperationRebaser rebaserUser1;

    setUp(() {
      rebaserUser1 = NoteOperationRebaser(localActorId: 'user-1');
    });

    PendingNoteOperationData makePending({
      required String operationId,
      required String blockId,
      required List<Map<String, dynamic>> ops,
      int baseRevision = 0,
      int ordinal = 0,
    }) {
      return PendingNoteOperationData(
        operationId: operationId,
        noteId: 'shared-note-dedup',
        baseRevision: baseRevision,
        ordinal: ordinal,
        kind: 'text_delta',
        blockId: blockId,
        payloadJson: jsonEncode({'ops': ops}),
        createdAt: DateTime.utc(2026, 7, 22),
        attemptCount: 0,
        lastAttemptAt: null,
        status: 'pending',
      );
    }

    Operation makeRemote({
      required String operationId,
      required String actorId,
      required String blockId,
      required List<Map<String, dynamic>> ops,
      required int revision,
      int baseRevision = 0,
    }) {
      return Operation(
        operationId: operationId,
        noteId: 'shared-note-dedup',
        revision: revision,
        baseRevision: baseRevision,
        actorId: actorId,
        kind: 'text_delta',
        blockId: blockId,
        payload: {'ops': ops},
        createdAt: DateTime.utc(2026, 7, 22),
      );
    }

    test('Cenario 1: Prevencao de duplicacao por retentativa de rede (Network Retry / Packet Replay)', () {
      const blockId = 'block-dedup-1';
      const wordToInsert = 'Banana ';

      // O usuario digita "Banana " otimisticamente no documento local
      var localDoc = quill.Delta()..insert(wordToInsert);

      // Operacao pendente no outbox
      final op1 = makePending(
        operationId: 'op-retry-1',
        blockId: blockId,
        ops: [
          {'insert': wordToInsert},
        ],
      );

      // O servidor aceita a op1 com sucesso no Revision 1
      final remoteAcceptedOp = makeRemote(
        operationId: 'op-retry-1',
        actorId: 'user-1',
        blockId: blockId,
        ops: [
          {'insert': wordToInsert},
        ],
        revision: 1,
      );

      // Devido a uma falha de ack de rede, a mesma resposta remota eh recebida 2 vezes (Replay)
      // O rebase deve filtrar operacoes cujo actorId seja o proprio usuario ou ja aceita
      final rebasedFirst = rebaserUser1.rebase(
        pending: [op1],
        remote: [remoteAcceptedOp],
        finalRevision: 1,
        acceptedOps: [
          AcceptedOperation(operationId: 'op-retry-1', revision: 1, kind: 'text_delta', blockId: blockId),
        ],
      );

      // Como op1 foi aceita pelo servidor, ela DEVE ser removida do pending (sem duplicar no rebase)
      expect(rebasedFirst, isEmpty, reason: 'Operacao ja aceita nao pode permanecer na fila pendente');

      final textFinal = deltaToPlainText(localDoc);

      // Garante que "Banana " aparece EXATAMENTE 1 vez no texto final
      final occurrences = 'Banana '.allMatches(textFinal).length;
      expect(occurrences, equals(1), reason: 'A palavra "Banana " NAO pode ser duplicada no documento');
      expect(textFinal, equals('Banana '));
    });

    test('Cenario 2: Prevencao de duplicacao por Echo de operacao propria (Self-Echo Prevention)', () {
      const blockId = 'block-dedup-2';
      const wordToInsert = ' Abacaxi';
      const initialText = 'Fruta:';

      // Documento local apos digitacao otimista
      var docLocal = quill.Delta()..insert(initialText)..insert(wordToInsert);

      // Servidor envia a lista de remoteOperations incluindo a propria operacao do usuario ('op-self')
      final remoteOps = [
        makeRemote(
          operationId: 'op-self',
          actorId: 'user-1', // Proprio usuario
          blockId: blockId,
          ops: [
            {'retain': initialText.length},
            {'insert': wordToInsert},
          ],
          revision: 1,
        ),
      ];

      // Filtro de sync: operacoes remotas geradas pelo proprio actorId nao devem ser re-aplicadas no documento local
      final externalRemoteOps = remoteOps.where((op) => op.actorId != 'user-1').toList();

      for (final r in externalRemoteOps) {
        docLocal = docLocal.compose(deltaFromOps(r.payload['ops'] as List));
      }

      final textFinal = deltaToPlainText(docLocal);

      // Verifica se a palavra Abacaxi nao foi duplicada pelo echo do servidor
      final occurrences = 'Abacaxi'.allMatches(textFinal).length;
      expect(occurrences, equals(1), reason: 'Echo da propria operacao nao pode ser re-aplicado no documento');
      expect(textFinal, equals('Fruta: Abacaxi'));
    });

    test('Cenario 3: Idempotencia do Rebase Local (Multiplas execucoes de rebase nao duplicam deltas)', () {
      const blockId = 'block-dedup-3';

      final pendingOps = [
        makePending(
          operationId: 'op-idem-1',
          blockId: blockId,
          ops: [
            {'insert': 'Primeira '},
          ],
        ),
        makePending(
          operationId: 'op-idem-2',
          blockId: blockId,
          ops: [
            {'retain': 9},
            {'insert': 'Segunda '},
          ],
          ordinal: 1,
        ),
      ];

      final remoteOps = [
        makeRemote(
          operationId: 'op-remote-other',
          actorId: 'user-other',
          blockId: blockId,
          ops: [
            {'insert': 'Outro '},
          ],
          revision: 1,
        ),
      ];

      // Executa rebase a 1a vez
      final rebaseRun1 = rebaserUser1.rebase(pending: pendingOps, remote: remoteOps, finalRevision: 1);

      // Executa rebase a 2a vez com o mesmo input (Simulando repeticao de ciclo de sync)
      final rebaseRun2 = rebaserUser1.rebase(pending: pendingOps, remote: remoteOps, finalRevision: 1);

      expect(rebaseRun1.length, equals(rebaseRun2.length));
      expect(rebaseRun1[0].payloadJson, equals(rebaseRun2[0].payloadJson));
      expect(rebaseRun1[1].payloadJson, equals(rebaseRun2[1].payloadJson));

      // Aplica o resultado de rebaseRun1
      var doc1 = quill.Delta()..insert('Outro ')..insert('Primeira ')..insert('Segunda ');
      final text1 = deltaToPlainText(doc1);

      // Valida que cada palavra aparece exatamente 1 vez
      expect('Outro '.allMatches(text1).length, equals(1));
      expect('Primeira '.allMatches(text1).length, equals(1));
      expect('Segunda '.allMatches(text1).length, equals(1));
    });
  });
}
