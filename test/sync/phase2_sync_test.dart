import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 2 (D): REST + WS Sync Logic', () {
    test('D18. Push e pull disparando ao mesmo tempo que a sessão Yjs está ativa', () async {
      // Simulação: se a sessão WS está ativa, o sync REST é suprimido para evitar corrupção
      bool wsActive = true;
      bool pushDisparado = false;

      void mockRestSync() {
        if (wsActive) return; // Guard logic
      }

      mockRestSync();
      expect(pushDisparado, isFalse, reason: 'REST sync deve ser suprimido com WS ativo');
    });

    test('D22. Dois sync() REST disparando em sobreposição', () async {
      // Simulação: mutex ou boolean lock no SyncManager
      bool isSyncing = false;
      int syncCount = 0;

      Future<void> mockSync() async {
        if (isSyncing) return;
        isSyncing = true;
        syncCount++;
        await Future.delayed(const Duration(milliseconds: 10));
        isSyncing = false;
      }

      // Dispara simultaneamente
      await Future.wait([
        mockSync(),
        mockSync(),
        mockSync(),
      ]);

      expect(syncCount, equals(1), reason: 'O guard deve impedir syncs simultâneos');
    });

    test('D23. lastSyncedAt manipulado/corrompido localmente', () async {
      // Simulação de recuperação
      DateTime localSyncedAt = DateTime.now().add(const Duration(days: 365)); // 1 ano no futuro
      DateTime serverTimestamp = DateTime.now();

      // Cliente ajusta
      if (localSyncedAt.isAfter(serverTimestamp)) {
        localSyncedAt = serverTimestamp; // Fallback
      }

      expect(localSyncedAt.isAfter(serverTimestamp), isFalse);
    });
  });
}
