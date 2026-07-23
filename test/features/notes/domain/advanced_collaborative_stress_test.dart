import 'dart:convert';
import 'dart:math';

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
  group('Advanced Stress & Edge Cases - Sincronizacao Colaborativa', () {
    PendingNoteOperationData makePending({
      required String actorId,
      required String operationId,
      required String blockId,
      required String kind,
      required List<Map<String, dynamic>> ops,
      int baseRevision = 0,
      int ordinal = 0,
    }) {
      return PendingNoteOperationData(
        operationId: operationId,
        noteId: 'shared-note-adv',
        baseRevision: baseRevision,
        ordinal: ordinal,
        kind: kind,
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
      required String kind,
      required List<Map<String, dynamic>> ops,
      required int revision,
      int baseRevision = 0,
    }) {
      return Operation(
        operationId: operationId,
        noteId: 'shared-note-adv',
        revision: revision,
        baseRevision: baseRevision,
        actorId: actorId,
        kind: kind,
        blockId: blockId,
        payload: {'ops': ops},
        createdAt: DateTime.utc(2026, 7, 22),
      );
    }

    test('Cenario 1: Delecao em massa (Backspace/Selecao) vs Digitacao Simultanea', () {
      final rebaserA = NoteOperationRebaser(localActorId: 'user-A');
      final rebaserB = NoteOperationRebaser(localActorId: 'user-B');
      const blockId = 'block-del';

      // Texto inicial: "O texto original contem palavras importantes que nao devem sumir"
      const initialText = 'O texto original contem palavras importantes que nao devem sumir';
      final posOriginal = initialText.indexOf('original'); // index 8

      // User A seleciona e apaga "original " (8 caracteres)
      final pendingA = [
        makePending(
          actorId: 'user-A',
          operationId: 'op-del-A',
          blockId: blockId,
          kind: 'text_delta',
          ops: [
            {'retain': posOriginal},
            {'delete': 9}, // Apaga "original "
          ],
        ),
      ];

      // User B simultaneamente digita "MUITO " logo antes de "palavras" (index 27)
      final posPalavras = initialText.indexOf('palavras'); // index 27
      final pendingB = [
        makePending(
          actorId: 'user-B',
          operationId: 'op-ins-B',
          blockId: blockId,
          kind: 'text_delta',
          ops: [
            {'retain': posPalavras},
            {'insert': 'MUITO '},
          ],
        ),
      ];

      final remoteA = [
        makeRemote(
          operationId: 'op-del-A',
          actorId: 'user-A',
          blockId: blockId,
          kind: 'text_delta',
          ops: [
            {'retain': posOriginal},
            {'delete': 9},
          ],
          revision: 1,
        ),
      ];

      // User B recebe a delecao do User A e faz rebase da sua insercao
      final rebasedB = rebaserB.rebase(pending: pendingB, remote: remoteA, finalRevision: 1);

      // O retain do User B deve ter encolhido em 9 caracteres (de 27 para 18)
      final opsRebasedB = jsonDecode(rebasedB[0].payloadJson)['ops'] as List;
      expect(opsRebasedB[0]['retain'], equals(posPalavras - 9));

      // Aplica edicoes no documento
      var doc = quill.Delta()..insert(initialText);
      doc = doc.compose(deltaFromOps(remoteA[0].payload['ops'] as List));
      doc = doc.compose(deltaFromOps(opsRebasedB));

      final finalText = deltaToPlainText(doc);

      // Verifica se "original " foi apagado, mas a palavra "MUITO " foi inserida com precisao sem corromper "palavras"
      expect(finalText.contains('original'), isFalse);
      expect(finalText.contains('MUITO palavras'), isTrue);
      expect(finalText, equals('O texto contem MUITO palavras importantes que nao devem sumir'));
    });

    test('Cenario 2: Rebase de Fila Offline de Alta Carga (50 operacoes acumuladas)', () {
      final rebaserOffline = NoteOperationRebaser(localActorId: 'offline-user');
      const blockId = 'block-heavy';

      // Servidor possui 25 operacoes ja comitadas pelo outro usuario
      final remoteOps = <Operation>[];
      var docRemote = quill.Delta()..insert('Inicio ');
      for (int i = 0; i < 25; i++) {
        final toInsert = 'R$i ';
        remoteOps.add(
          makeRemote(
            operationId: 'rem-$i',
            actorId: 'online-user',
            blockId: blockId,
            kind: 'text_delta',
            ops: [
              {'retain': deltaToPlainText(docRemote).length},
              {'insert': toInsert},
            ],
            revision: i + 1,
            baseRevision: i,
          ),
        );
        docRemote = docRemote.compose(quill.Delta()..retain(deltaToPlainText(docRemote).length)..insert(toInsert));
      }

      // Usuario offline acumulou 25 operacoes pendentes locais na fila de sync
      final pendingOps = <PendingNoteOperationData>[];
      var docPending = quill.Delta()..insert('Inicio ');
      for (int i = 0; i < 25; i++) {
        final toInsert = 'L$i ';
        final currentLen = deltaToPlainText(docPending).length;
        pendingOps.add(
          makePending(
            actorId: 'offline-user',
            operationId: 'loc-$i',
            blockId: blockId,
            kind: 'text_delta',
            baseRevision: 0, // Todas criadas localmente quando estava offline no rev 0
            ordinal: i,
            ops: [
              {'retain': currentLen},
              {'insert': toInsert},
            ],
          ),
        );
        docPending = docPending.compose(quill.Delta()..retain(currentLen)..insert(toInsert));
      }

      // Usuario offline reconecta e executa o rebase em massa de 25 pendentes contra 25 remotas
      final rebasedList = rebaserOffline.rebase(
        pending: pendingOps,
        remote: remoteOps,
        finalRevision: 25,
      );

      expect(rebasedList.length, equals(25));

      // Aplica tudo ao documento final
      var finalDoc = quill.Delta()..insert('Inicio ');
      for (final r in remoteOps) {
        finalDoc = finalDoc.compose(deltaFromOps(r.payload['ops'] as List));
      }
      for (final p in rebasedList) {
        finalDoc = finalDoc.compose(deltaFromOps(jsonDecode(p.payloadJson)['ops'] as List));
      }

      final text = deltaToPlainText(finalDoc);

      // Garante que todas as 25 edicoes locais e 25 edicoes remotas estao presentes
      for (int i = 0; i < 25; i++) {
        expect(text.contains('R$i'), isTrue, reason: 'Operacao remota R$i deve estar presente');
        expect(text.contains('L$i'), isTrue, reason: 'Operacao local L$i rebaseada deve estar presente');
      }
    });

    test('Cenario 3: Monte Carlo Fuzzer de 3 Clientes Simultaneos (Invariante de Convergencia Total)', () {
      final random = Random(12345);
      const blockId = 'block-fuzz-3';

      final clientIds = ['client-Alpha', 'client-Beta', 'client-Gamma'];
      final clientRebasers = {
        for (final id in clientIds) id: NoteOperationRebaser(localActorId: id),
      };

      final clientWords = {
        'client-Alpha': ['ALPHA_1', 'ALPHA_2', 'ALPHA_3'],
        'client-Beta': ['BETA_1', 'BETA_2', 'BETA_3'],
        'client-Gamma': ['GAMMA_1', 'GAMMA_2', 'GAMMA_3'],
      };

      // Cada cliente gera suas operacoes no baseRevision 0
      final clientPendingOps = <String, List<PendingNoteOperationData>>{};

      for (final clientId in clientIds) {
        final words = clientWords[clientId]!;
        final ops = <PendingNoteOperationData>[];
        var len = 0;
        for (int i = 0; i < words.length; i++) {
          final textToInsert = '${words[i]} ';
          ops.add(
            makePending(
              actorId: clientId,
              operationId: 'op-$clientId-$i',
              blockId: blockId,
              kind: 'text_delta',
              baseRevision: 0,
              ordinal: i,
              ops: [
                if (len > 0) {'retain': len},
                {'insert': textToInsert},
              ],
            ),
          );
          len += textToInsert.length;
        }
        clientPendingOps[clientId] = ops;
      }

      // O servidor recebe operacoes dos clientes e transforma cada operacao recebida contra as operacoes ja comitadas no servidor
      final clientQueues = {
        for (final id in clientIds) id: List<PendingNoteOperationData>.from(clientPendingOps[id]!),
      };

      final serverCommittedOps = <Operation>[];
      var currentRev = 0;

      final serverTransformer = NoteOperationRebaser(localActorId: 'server');

      while (clientQueues.values.any((q) => q.isNotEmpty)) {
        final availableClients = clientIds.where((id) => clientQueues[id]!.isNotEmpty).toList();
        final selectedClientId = availableClients[random.nextInt(availableClients.length)];
        final nextPending = clientQueues[selectedClientId]!.removeAt(0);

        // Rebaseia/transforma a operacao do cliente contra as operacoes ja salvas no servidor
        final rebasedByServer = serverTransformer.rebase(
          pending: [nextPending],
          remote: serverCommittedOps,
          finalRevision: currentRev,
        );

        if (rebasedByServer.isNotEmpty) {
          final p = rebasedByServer.first;
          final payload = jsonDecode(p.payloadJson) as Map<String, dynamic>;
          currentRev += 1;
          serverCommittedOps.add(
            makeRemote(
              operationId: p.operationId,
              actorId: selectedClientId,
              blockId: blockId,
              kind: 'text_delta',
              ops: (payload['ops'] as List).cast<Map<String, dynamic>>(),
              revision: currentRev,
              baseRevision: currentRev - 1,
            ),
          );
        }
      }

      // Cada cliente rebaseia suas 3 operacoes pendentes locais contra as operacoes remotas dos outros clientes
      for (final clientId in clientIds) {
        final rebaser = clientRebasers[clientId]!;
        final pending = clientPendingOps[clientId]!;
        final remoteForClient = serverCommittedOps.where((op) => op.actorId != clientId).toList();

        final rebased = rebaser.rebase(
          pending: pending,
          remote: remoteForClient,
          finalRevision: remoteForClient.length,
        );

        // Recompoe o documento do cliente
        var clientDoc = quill.Delta();
        for (final r in remoteForClient) {
          clientDoc = clientDoc.compose(deltaFromOps(r.payload['ops'] as List));
        }
        for (final p in rebased) {
          clientDoc = clientDoc.compose(deltaFromOps(jsonDecode(p.payloadJson)['ops'] as List));
        }

        final clientText = deltaToPlainText(clientDoc);

        // Valida que TODAS as palavras dos 3 clientes estao presentes sem corrupcao
        for (final id in clientIds) {
          for (final word in clientWords[id]!) {
            expect(
              clientText.contains(word),
              isTrue,
              reason: 'Palavra $word do $id deve existir sem corrupcao no documento do $clientId',
            );
          }
        }
      }
    });
  });
}
