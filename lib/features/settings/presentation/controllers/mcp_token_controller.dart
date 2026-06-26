import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_repository.dart';

final mcpTokenProvider =
    AsyncNotifierProvider.autoDispose<McpTokenController, String?>(
  McpTokenController.new,
);

class McpTokenController extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async => null;

  Future<void> generate() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(settingsRepositoryProvider).generateMcpToken(),
    );
  }
}
