import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/telegram/data/telegram_repository.dart';

final telegramStatusProvider = FutureProvider.autoDispose<TelegramLinkStatus>((ref) async {
  return ref.read(telegramRepositoryProvider).getLinkStatus();
});

typedef TelegramPairingState = ({String? code, int countdown});

class TelegramPairingController extends Notifier<TelegramPairingState> {
  Timer? _countdownTimer;
  Timer? _statusTimer;

  @override
  TelegramPairingState build() {
    ref.onDispose(() {
      _countdownTimer?.cancel();
      _statusTimer?.cancel();
    });
    return (code: null, countdown: 0);
  }

  Future<void> start() async {
    final linkCode =
        await ref.read(telegramRepositoryProvider).generateLinkCode();
    state = (code: linkCode.code, countdown: linkCode.remaining.inSeconds);
    _startTimers();
  }

  void _startTimers() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.countdown <= 0) {
        stop();
        return;
      }
      state = (code: state.code, countdown: state.countdown - 1);
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
  }
}

final telegramPairingProvider = NotifierProvider.autoDispose<
  TelegramPairingController, TelegramPairingState>(
  TelegramPairingController.new,
);
