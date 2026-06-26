import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/telegram/data/telegram_repository.dart';

final telegramStatusProvider = FutureProvider.autoDispose<TelegramLinkStatus>((ref) async {
  return ref.read(telegramRepositoryProvider).getLinkStatus();
});

class TelegramPairingState {
  final String? code;
  final int countdown;
  final bool isPairing;
  final String? errorMessage;

  const TelegramPairingState({
    this.code,
    this.countdown = 0,
    this.isPairing = false,
    this.errorMessage,
  });

  TelegramPairingState copyWith({
    String? code,
    int? countdown,
    bool? isPairing,
    String? errorMessage,
  }) {
    return TelegramPairingState(
      code: code ?? this.code,
      countdown: countdown ?? this.countdown,
      isPairing: isPairing ?? this.isPairing,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class TelegramPairingController extends Notifier<TelegramPairingState> {
  Timer? _countdownTimer;
  Timer? _statusTimer;

  @override
  TelegramPairingState build() {
    ref.onDispose(() {
      _countdownTimer?.cancel();
      _statusTimer?.cancel();
    });
    return const TelegramPairingState();
  }

  Future<void> start() async {
    state = state.copyWith(isPairing: true, errorMessage: null);
    try {
      final linkCode =
          await ref.read(telegramRepositoryProvider).generateLinkCode();
      state = state.copyWith(
        isPairing: true,
        code: linkCode.code,
        countdown: linkCode.remaining.inSeconds,
      );
      _startTimers();
    } catch (e) {
      state = state.copyWith(isPairing: false, errorMessage: e.toString());
      rethrow;
    }
  }

  void _startTimers() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.countdown <= 0) {
        stop();
        return;
      }
      state = state.copyWith(countdown: state.countdown - 1);
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
    state = state.copyWith(isPairing: false);
    _countdownTimer?.cancel();
    _statusTimer?.cancel();
    _countdownTimer = null;
    _statusTimer = null;
  }
}

final telegramPairingProvider = NotifierProvider.autoDispose<
  TelegramPairingController, TelegramPairingState>(
  TelegramPairingController.new,
);
