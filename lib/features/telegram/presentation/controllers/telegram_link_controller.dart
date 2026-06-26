import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/telegram/data/telegram_repository.dart';

final telegramStatusProvider = FutureProvider.autoDispose<TelegramLinkStatus>((ref) async {
  ref.watch(sessionResetProvider);
  return ref.read(telegramRepositoryProvider).getLinkStatus();
});

class TelegramPairingResult {
  final String code;
  final int countdown;

  const TelegramPairingResult({
    required this.code,
    required this.countdown,
  });

  TelegramPairingResult copyWith({
    String? code,
    int? countdown,
  }) {
    return TelegramPairingResult(
      code: code ?? this.code,
      countdown: countdown ?? this.countdown,
    );
  }
}

class TelegramPairingController extends AsyncNotifier<TelegramPairingResult?> {
  Timer? _countdownTimer;
  Timer? _statusTimer;

  @override
  FutureOr<TelegramPairingResult?> build() {
    ref.watch(sessionResetProvider);
    ref.onDispose(() {
      _countdownTimer?.cancel();
      _statusTimer?.cancel();
    });
    return null;
  }

  Future<void> start() async {
    state = const AsyncValue.loading();
    try {
      final linkCode =
          await ref.read(telegramRepositoryProvider).generateLinkCode();
      state = AsyncValue.data(TelegramPairingResult(
        code: linkCode.code,
        countdown: linkCode.remaining.inSeconds,
      ));
      _startTimers();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  void _startTimers() {
    _countdownTimer?.cancel();
    _statusTimer?.cancel();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = state.value;
      if (current == null || current.countdown <= 0) {
        stop();
        return;
      }
      state = AsyncValue.data(current.copyWith(countdown: current.countdown - 1));
    });

    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final status =
          await ref.read(telegramRepositoryProvider).getLinkStatus();
      if (status.linked) {
        stop();
        ref.invalidate(telegramStatusProvider);
      }
    });
  }

  void stop() {
    _countdownTimer?.cancel();
    _statusTimer?.cancel();
    _countdownTimer = null;
    _statusTimer = null;
    state = const AsyncValue.data(null);
  }
}

final telegramPairingProvider = AsyncNotifierProvider.autoDispose<
  TelegramPairingController, TelegramPairingResult?>(
  TelegramPairingController.new,
);
