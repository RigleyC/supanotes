import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/telegram/data/telegram_repository.dart';

class TelegramLinkState {
  final bool linked;
  final String? code;
  final int countdown;
  final bool isLoading;
  final String? error;

  const TelegramLinkState({
    this.linked = false,
    this.code,
    this.countdown = 0,
    this.isLoading = false,
    this.error,
  });

  TelegramLinkState copyWith({
    bool? linked,
    String? code,
    int? countdown,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      TelegramLinkState(
        linked: linked ?? this.linked,
        code: code ?? this.code,
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
  Timer? _pollTimer;

  @override
  Future<TelegramLinkState> build() async {
    ref.onDispose(stopPolling);
    try {
      final status =
          await ref.read(telegramRepositoryProvider).getLinkStatus();
      return TelegramLinkState(linked: status.linked);
    } catch (e) {
      return const TelegramLinkState();
    }
  }

  Future<void> loadStatus() async {
    state = AsyncValue.data(state.value!.copyWith(isLoading: true));
    try {
      final status =
          await ref.read(telegramRepositoryProvider).getLinkStatus();
      state = AsyncValue.data(
        TelegramLinkState(linked: status.linked, isLoading: false),
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
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = state.value!;
      if (current.countdown <= 0) {
        stopPolling();
        return;
      }
      state = AsyncValue.data(current.copyWith(countdown: current.countdown - 1));
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}
