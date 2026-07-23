import 'dart:convert';

import 'package:dart_quill_delta/dart_quill_delta.dart' as quill;
import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/data/note_sync_client.dart';
import 'package:supanotes/features/notes/domain/note_operation_rebaser.dart';

void main() {
  group('Collaborative Typing Test - 2 Pessoas Digitando ao Mesmo Tempo', () {
    late NoteOperationRebaser rebaserUser1;
    late NoteOperationRebaser rebaserUser2;

    setUp(() {
      rebaserUser1 = NoteOperationRebaser(localActorId: 'user-1');
      rebaserUser2 = NoteOperationRebaser(localActorId: 'user-2');
    });

    PendingNoteOperationData makePending({
      required String operationId,
      required String blockId,
      required List<Map<String, dynamic>> ops,
      int baseRevision = 0,
    }) {
      return PendingNoteOperationData(
        operationId: operationId,
        noteId: 'shared-note-1',
        baseRevision: baseRevision,
        ordinal: 0,
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
      int revision = 1,
      int baseRevision = 0,
    }) {
      return Operation(
        operationId: operationId,
        noteId: 'shared-note-1',
        revision: revision,
        baseRevision: baseRevision,
        actorId: actorId,
        kind: 'text_delta',
        blockId: blockId,
        payload: {'ops': ops},
        createdAt: DateTime.utc(2026, 7, 22),
      );
    }

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

    test(
      'Duas pessoas digitando simultaneamente no mesmo ponto da nota preservam todas as palavras',
      () {
        // Texto inicial da nota compartilhada: "Nota compartilhada:"
        const initialText = 'Nota compartilhada:';
        const blockId = 'block-header';

        // Pessoa 1 digita " ABACAXI" no final (índice 19)
        final opPessoa1 = makePending(
          operationId: 'op-p1',
          blockId: blockId,
          ops: [
            {'retain': 19},
            {'insert': ' ABACAXI'},
          ],
        );

        // A operacao da Pessoa 2 chega ao servidor primeiro (Revision 1)
        final remoteOpPessoa2 = makeRemote(
          operationId: 'op-p2',
          actorId: 'user-2',
          blockId: blockId,
          ops: [
            {'retain': 19},
            {'insert': ' BANANA'},
          ],
          revision: 1,
        );

        // Pessoa 1 recebe a operacao remota da Pessoa 2 e faz o rebase da sua operacao pendente
        final rebasedPessoa1 = rebaserUser1.rebase(
          pending: [opPessoa1],
          remote: [remoteOpPessoa2],
          finalRevision: 1,
        );

        expect(rebasedPessoa1.length, 1);
        final opsRebasedPessoa1 =
            (jsonDecode(rebasedPessoa1[0].payloadJson)['ops'] as List);

        // Aplica as edicoes ao documento inicial:
        var docDelta = quill.Delta()..insert(initialText);

        // 1. Aplica alteracao da Pessoa 2
        final deltaP2 = deltaFromOps(remoteOpPessoa2.payload['ops'] as List);
        docDelta = docDelta.compose(deltaP2);

        // 2. Aplica alteracao rebaseada da Pessoa 1
        final deltaP1Rebased = deltaFromOps(opsRebasedPessoa1);
        docDelta = docDelta.compose(deltaP1Rebased);

        final finalText = deltaToPlainText(docDelta);

        // Verifica se AMBAS as palavras "ABACAXI" e "BANANA" estao presentes e inteiras sem corrupcao
        expect(
          finalText.contains('ABACAXI'),
          isTrue,
          reason: 'Palavra da Pessoa 1 deve ser preservada na integra',
        );
        expect(
          finalText.contains('BANANA'),
          isTrue,
          reason: 'Palavra da Pessoa 2 deve ser preservada na integra',
        );
        expect(finalText, equals('Nota compartilhada: BANANA ABACAXI'));
      },
    );

    test(
      'Duas pessoas digitando simultaneamente em posicoes diferentes da nota',
      () {
        // Texto inicial: "O rato roeu a roupa do rei de Roma"
        const initialText = 'O rato roeu a roupa do rei de Roma';
        const blockId = 'block-body';

        final posRato =
            initialText.indexOf('rato') +
            'rato'.length; // Posicao logo apos "rato" (index 6)
        final posRoma = initialText.indexOf(
          'Roma',
        ); // Posicao antes de "Roma" (index 30)

        // Pessoa 2 insere "muito " antes de "Roma"
        final opPessoa2 = makePending(
          operationId: 'op-p2-diff',
          blockId: blockId,
          ops: [
            {'retain': posRoma},
            {'insert': 'muito '},
          ],
        );

        final remoteOpPessoa1 = makeRemote(
          operationId: 'op-p1-diff',
          actorId: 'user-1',
          blockId: blockId,
          ops: [
            {'retain': posRato},
            {'insert': ' grande'},
          ],
          revision: 1,
        );

        // Pessoa 2 rebaseia sua edicao em relacao a Pessoa 1
        final rebasedPessoa2 = rebaserUser2.rebase(
          pending: [opPessoa2],
          remote: [remoteOpPessoa1],
          finalRevision: 1,
        );

        final opsRebasedPessoa2 =
            (jsonDecode(rebasedPessoa2[0].payloadJson)['ops'] as List);

        // O retain da Pessoa 2 deve ter sido deslocado de 30 para 30 + length(" grande") = 37
        expect(
          opsRebasedPessoa2[0]['retain'],
          equals(posRoma + ' grande'.length),
        );

        // Aplica as edicoes na ordem de resolucao
        var docDelta = quill.Delta()..insert(initialText);
        docDelta = docDelta.compose(
          deltaFromOps(remoteOpPessoa1.payload['ops'] as List),
        );
        docDelta = docDelta.compose(deltaFromOps(opsRebasedPessoa2));

        final finalText = deltaToPlainText(docDelta);

        expect(finalText.contains('rato grande'), isTrue);
        expect(finalText.contains('muito Roma'), isTrue);
        expect(
          finalText,
          equals('O rato grande roeu a roupa do rei de muito Roma'),
        );
      },
    );

    test(
      'Uma pessoa substituindo texto enquanto outra digita simultaneamente',
      () {
        // Texto inicial: "Texto antigo na nota"
        const initialText = 'Texto antigo na nota';
        const blockId = 'block-replace';

        final posAntigo = initialText.indexOf('antigo'); // index 6

        final posFinal = initialText.length; // index 20 (final da nota)

        // Pessoa 2 digita " incrível" no final simultaneamente
        final opPessoa2 = makePending(
          operationId: 'op-p2-replace',
          blockId: blockId,
          ops: [
            {'retain': posFinal},
            {'insert': ' incrível'},
          ],
        );

        final remoteOpPessoa1 = makeRemote(
          operationId: 'op-p1-replace',
          actorId: 'user-1',
          blockId: blockId,
          ops: [
            {'retain': posAntigo},
            {'delete': 6},
            {'insert': 'novo'},
          ],
          revision: 1,
        );

        // Pessoa 2 rebaseia sua operacao remota da Pessoa 1
        final rebasedPessoa2 = rebaserUser2.rebase(
          pending: [opPessoa2],
          remote: [remoteOpPessoa1],
          finalRevision: 1,
        );

        final opsRebasedPessoa2 =
            (jsonDecode(rebasedPessoa2[0].payloadJson)['ops'] as List);

        // O retain da Pessoa 2 desloca: -6 (delete) + 4 (insert "novo") = -2
        // retain inicial era 20 -> passa a ser 18
        expect(opsRebasedPessoa2[0]['retain'], equals(posFinal - 2));

        // Aplica as edicoes na ordem de resolucao
        var docDelta = quill.Delta()..insert(initialText);
        docDelta = docDelta.compose(
          deltaFromOps(remoteOpPessoa1.payload['ops'] as List),
        );
        docDelta = docDelta.compose(deltaFromOps(opsRebasedPessoa2));

        final finalText = deltaToPlainText(docDelta);

        expect(finalText, equals('Texto novo na nota incrível'));
      },
    );
  });
}
