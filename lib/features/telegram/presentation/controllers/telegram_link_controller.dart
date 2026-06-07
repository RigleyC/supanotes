import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/telegram/data/telegram_repository.dart';

class TelegramLinkState {
  final bool linked;
  final String? username;
  final int? chatId;
  final String? code;
  final int countdown;
  final bool isLoading;
  final String? error;

  const TelegramLinkState({
    this.linked = false,
    this.username,
    this.chatId,
    this.code,
    this.countdown = 0,
    this.isLoading = false,
    this.error,
  });

  TelegramLinkState copyWith({
    bool? linked,
    String? username,
    int? chatId,
    String? code,
    int? countdown,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool clearCode = false,
    bool clearChatInfo = false,
  }) =>
      TelegramLinkState(
        linked: linked ?? this.linked,
        username: clearChatInfo ? null : (username ?? this.username),
        chatId: clearChatInfo ? null : (chatId ?? this.chatId),
        code: clearCode ? null : (code ?? this.code),
        countdown: countdown ?? this.countdown,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

final telegramLinkControllerProvider =
    AsyncNotifierProvider<TelegramLinkController, TelegramLinkState>(
  TelegramLinkController.new,
);

class TelegramLinkController extends AsyncNotifier<TelegramLinkState> {
  Timer? _countdownTimer;
  Timer? _statusTimer;

  @override
  Future<TelegramLinkState> build() async {
    ref.onDispose(stopPolling);
    try {
      final status =
          await ref.read(telegramRepositoryProvider).getLinkStatus();
      return TelegramLinkState(
        linked: status.linked,
        username: status.username,
        chatId: status.chatId,
      );
    } catch (e) {
      return const TelegramLinkState();
    }
  }

  Future<void> loadStatus() async {
    state = AsyncValue.data(state.value!.copyWith(isLoading: true));
    try {
      final status =
          await ref.read(telegramRepositoryProvider).getLinkStatus();
      if (status.linked) stopPolling();
      state = AsyncValue.data(
        state.value!.copyWith(
          linked: status.linked,
          username: status.username,
          chatId: status.chatId,
          isLoading: false,
        ),
      );
    } catch (e) {
      state = AsyncValue.data(
        state.value!.copyWith(isLoading: false, error: e.toString()),
      );
    }
  }

  Future<void> generateCode() async {
    state = AsyncValue.data(state.value!.copyWith(isLoading: true));
    try {
      final linkCode =
          await ref.read(telegramRepositoryProvider).generateLinkCode();
      final remaining = linkCode.remaining.inSeconds;
      state = AsyncValue.data(
        state.value!.copyWith(
          code: linkCode.code,
          countdown: remaining,
          isLoading: false,
        ),
      );
      startPolling();
    } catch (e) {
      state = AsyncValue.data(
        state.value!.copyWith(isLoading: false, error: e.toString()),
      );
    }
  }

  Future<void> deleteLink() async {
    await ref.read(telegramRepositoryProvider).deleteLink();
    stopPolling();
    state = AsyncValue.data(const TelegramLinkState());
  }

  void startPolling() {
    _countdownTimer?.cancel();
    _statusTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = state.value!;
      if (current.countdown <= 0) {
        stopPolling();
        return;
      }
      state = AsyncValue.data(current.copyWith(countdown: current.countdown - 1));
    });
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await loadStatus();
    });
  }

  void stopPolling() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _statusTimer?.cancel();
    _statusTimer = null;
  }
}
