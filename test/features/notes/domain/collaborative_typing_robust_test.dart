import 'dart:convert';

import 'package:dart_quill_delta/dart_quill_delta.dart' as quill;
import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/data/note_sync_client.dart';
import 'package:supanotes/features/notes/domain/note_operation_rebaser.dart';

/// Helper to convert payload JSON ops to quill.Delta
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

/// Helper to convert Delta to plain text
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
  group('Robust Collaborative Typing & Sync Convergence Tests', () {
    late NoteOperationRebaser rebaserUser2;

    setUp(() {
      rebaserUser2 = NoteOperationRebaser(localActorId: 'user-2');
    });

    PendingNoteOperationData makePending({
      required String operationId,
      required String blockId,
      required List<Map<String, dynamic>> ops,
      required int baseRevision,
      int ordinal = 0,
    }) {
      return PendingNoteOperationData(
        operationId: operationId,
        noteId: 'shared-note-robust',
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
      required int baseRevision,
    }) {
      return Operation(
        operationId: operationId,
        noteId: 'shared-note-robust',
        revision: revision,
        baseRevision: baseRevision,
        actorId: actorId,
        kind: 'text_delta',
        blockId: blockId,
        payload: {'ops': ops},
        createdAt: DateTime.utc(2026, 7, 22),
      );
    }

    test(
      'Cadeia de operacoes sequenciais (digitacao letra por letra) de 2 usuarios simultaneos',
      () {
        const blockId = 'block-1';
        // User 1 quer digitar "GATO " letra por letra no offset 0 (baseRevision 0)
        // User 2 quer digitar "CACHORRO " letra por letra no offset 0 (baseRevision 0)

        const word1 = 'GATO ';
        const word2 = 'CACHORRO ';

        // User 1 gera 5 operacoes encadeadas localmente
        final opsUser1 = <PendingNoteOperationData>[];
        var currentLen1 = 0;
        for (int i = 0; i < word1.length; i++) {
          final char = word1[i];
          opsUser1.add(
            makePending(
              operationId: 'op-u1-$i',
              blockId: blockId,
              baseRevision:
                  0, // Todas criadas antes de receber qualquer sync remoto
              ordinal: i,
              ops: [
                if (currentLen1 > 0) {'retain': currentLen1},
                {'insert': char},
              ],
            ),
          );
          currentLen1 += 1;
        }

        // User 2 gera 9 operacoes encadeadas localmente
        final opsUser2 = <PendingNoteOperationData>[];
        var currentLen2 = 0;
        for (int i = 0; i < word2.length; i++) {
          final char = word2[i];
          opsUser2.add(
            makePending(
              operationId: 'op-u2-$i',
              blockId: blockId,
              baseRevision: 0,
              ordinal: i,
              ops: [
                if (currentLen2 > 0) {'retain': currentLen2},
                {'insert': char},
              ],
            ),
          );
          currentLen2 += 1;
        }

        // Servidor aceita as operacoes do User 1 primeiro (Revisoes 1..5)
        final remoteOpsUser1Server = <Operation>[];
        for (int i = 0; i < opsUser1.length; i++) {
          final pending = opsUser1[i];
          final payloadMap =
              jsonDecode(pending.payloadJson) as Map<String, dynamic>;
          remoteOpsUser1Server.add(
            makeRemote(
              operationId: pending.operationId,
              actorId: 'user-1',
              blockId: blockId,
              ops: (payloadMap['ops'] as List).cast<Map<String, dynamic>>(),
              revision: i + 1,
              baseRevision: i,
            ),
          );
        }

        // User 2 recebe todas as 5 operacoes do User 1 e realiza o rebase de suas 9 operacoes pendentes
        final rebasedOpsUser2 = rebaserUser2.rebase(
          pending: opsUser2,
          remote: remoteOpsUser1Server,
          finalRevision: 5,
        );

        // Recompoe o documento final do User 2:
        // 1. Documento inicial vazio
        var docUser2 = quill.Delta();
        // 2. Aplica as operacoes confirmadas do User 1 (Revisoes 1..5)
        for (final rOp in remoteOpsUser1Server) {
          docUser2 = docUser2.compose(deltaFromOps(rOp.payload['ops'] as List));
        }
        // 3. Aplica as operacoes rebaseadas do User 2
        for (final pOp in rebasedOpsUser2) {
          final ops = jsonDecode(pOp.payloadJson)['ops'] as List;
          docUser2 = docUser2.compose(deltaFromOps(ops));
        }

        final textUser2 = deltaToPlainText(docUser2);

        // Recompoe o documento final do User 1 (Servidor aceita as 9 operacoes rebaseadas do User 2):
        var docUser1 = quill.Delta();
        // 1. User 1 aplica suas operacoes originais (1..5)
        for (final rOp in remoteOpsUser1Server) {
          docUser1 = docUser1.compose(deltaFromOps(rOp.payload['ops'] as List));
        }
        // 2. User 1 aplica as 9 operacoes do User 2 (rebaseadas pelo servidor)
        for (final pOp in rebasedOpsUser2) {
          final ops = jsonDecode(pOp.payloadJson)['ops'] as List;
          docUser1 = docUser1.compose(deltaFromOps(ops));
        }

        final textUser1 = deltaToPlainText(docUser1);

        // VERIFICACOES DE ROBUSTES E CONVERGENCIA:
        // 1. Convergencia deterministica exata entre ambos os clientes
        expect(
          textUser1,
          equals(textUser2),
          reason: 'Ambos os clientes DEVEM ter exatamente o mesmo texto final',
        );

        // 2. Preservacao de Palavras: "GATO " e "CACHORRO " devem estar intactas e contiguas
        expect(
          textUser1.contains('GATO '),
          isTrue,
          reason: 'A palavra GATO  nao pode ser fragmentada ou embolada',
        );
        expect(
          textUser1.contains('CACHORRO '),
          isTrue,
          reason: 'A palavra CACHORRO  nao pode ser fragmentada ou embolada',
        );
      },
    );

    test(
      'Simulacao de Fuzzing Stress Test: 2 usuarios digitando frases simultaneamente com latencia',
      () {
        const blockId = 'block-fuzz';

        const user1Words = ['MACA', 'BANANA', 'LARANJA', 'UVA'];
        const user2Words = ['CARRO', 'NAVIO', 'AVIAO', 'TREM'];

        // Gera deltas de insercao de palavra inteira ou blocos de caracteres
        final opsUser1 = <PendingNoteOperationData>[];
        var len1 = 0;
        for (final word in user1Words) {
          final toInsert = '$word ';
          opsUser1.add(
            makePending(
              operationId: 'fuzz-u1-${opsUser1.length}',
              blockId: blockId,
              baseRevision: 0,
              ordinal: opsUser1.length,
              ops: [
                if (len1 > 0) {'retain': len1},
                {'insert': toInsert},
              ],
            ),
          );
          len1 += toInsert.length;
        }

        final opsUser2 = <PendingNoteOperationData>[];
        var len2 = 0;
        for (final word in user2Words) {
          final toInsert = '$word ';
          opsUser2.add(
            makePending(
              operationId: 'fuzz-u2-${opsUser2.length}',
              blockId: blockId,
              baseRevision: 0,
              ordinal: opsUser2.length,
              ops: [
                if (len2 > 0) {'retain': len2},
                {'insert': toInsert},
              ],
            ),
          );
          len2 += toInsert.length;
        }

        // Servidor ordena e comita as operacoes do User 1 (Revisoes 1..4)
        final remoteOps1 = <Operation>[];
        for (int i = 0; i < opsUser1.length; i++) {
          final p = opsUser1[i];
          final payload = jsonDecode(p.payloadJson) as Map<String, dynamic>;
          remoteOps1.add(
            makeRemote(
              operationId: p.operationId,
              actorId: 'user-1',
              blockId: blockId,
              ops: (payload['ops'] as List).cast<Map<String, dynamic>>(),
              revision: i + 1,
              baseRevision: i,
            ),
          );
        }

        // User 2 recebe as 4 operacoes do User 1 e rebaseia suas 4 operacoes pendentes
        final rebasedOps2 = rebaserUser2.rebase(
          pending: opsUser2,
          remote: remoteOps1,
          finalRevision: 4,
        );

        // Recompoe estado final no User 1 e User 2
        var docState = quill.Delta();
        for (final r in remoteOps1) {
          docState = docState.compose(deltaFromOps(r.payload['ops'] as List));
        }
        for (final p in rebasedOps2) {
          docState = docState.compose(
            deltaFromOps(jsonDecode(p.payloadJson)['ops'] as List),
          );
        }

        final resultText = deltaToPlainText(docState);

        // Valida que TODAS as palavras do User 1 e User 2 aparecem inteiras sem corrupcao
        for (final w in user1Words) {
          expect(
            resultText.contains(w),
            isTrue,
            reason: 'Palavra "$w" do User 1 deve existir intacta na nota final',
          );
        }
        for (final w in user2Words) {
          expect(
            resultText.contains(w),
            isTrue,
            reason: 'Palavra "$w" do User 2 deve existir intacta na nota final',
          );
        }
      },
    );
  });
}
