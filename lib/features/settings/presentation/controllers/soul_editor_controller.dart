import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/settings/data/settings_models.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';

class SoulEditorState {
  final Soul? soul;
  final bool isEditing;
  final bool isSaving;
  final String? loadError;

  const SoulEditorState({
    this.soul,
    this.isEditing = false,
    this.isSaving = false,
    this.loadError,
  });

  SoulEditorState copyWith({
    Soul? soul,
    bool? isEditing,
    bool? isSaving,
    String? loadError,
    bool clearError = false,
  }) =>
      SoulEditorState(
        soul: soul ?? this.soul,
        isEditing: isEditing ?? this.isEditing,
        isSaving: isSaving ?? this.isSaving,
        loadError: clearError ? null : (loadError ?? this.loadError),
      );
}

final soulEditorControllerProvider =
    AsyncNotifierProvider<SoulEditorController, SoulEditorState>(
  SoulEditorController.new,
);

class SoulEditorController extends AsyncNotifier<SoulEditorState> {
  @override
  Future<SoulEditorState> build() async {
    try {
      final soul = await ref.read(settingsRepositoryProvider).getSoul();
      return SoulEditorState(soul: soul);
    } catch (e) {
      return SoulEditorState(loadError: e.toString());
    }
  }

  Future<void> load() async {
    try {
      final soul = await ref.read(settingsRepositoryProvider).getSoul();
      state = AsyncValue.data(SoulEditorState(soul: soul));
    } catch (e) {
      state = AsyncValue.data(SoulEditorState(loadError: e.toString()));
    }
  }

  Future<void> save(String content) async {
    state = AsyncValue.data(state.value!.copyWith(isSaving: true));
    try {
      final updated =
          await ref.read(settingsRepositoryProvider).updateSoul(content);
      state = AsyncValue.data(
        SoulEditorState(soul: updated, isSaving: false),
      );
    } catch (e) {
      state = AsyncValue.data(
        state.value!.copyWith(isSaving: false, loadError: e.toString()),
      );
    }
  }

  Future<void> restoreDefault() async {
    // Will be implemented when soul_editor_screen is refactored
  }
}
