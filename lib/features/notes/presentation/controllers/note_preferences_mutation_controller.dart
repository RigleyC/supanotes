import 'package:flutter_riverpod/legacy.dart';

import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/data/user_note_preferences_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';

enum NotePreferenceMutationStatus { idle, saving, error }

class NotePreferenceMutationState {
  const NotePreferenceMutationState({
    this.status = NotePreferenceMutationStatus.idle,
    this.error,
    this.inFlightCount = 0,
  });

  final NotePreferenceMutationStatus status;
  final Object? error;
  final int inFlightCount;

  NotePreferenceMutationState copyWith({
    NotePreferenceMutationStatus? status,
    Object? error,
    bool clearError = false,
    int? inFlightCount,
  }) {
    return NotePreferenceMutationState(
      status: status ?? this.status,
      error: clearError ? null : error ?? this.error,
      inFlightCount: inFlightCount ?? this.inFlightCount,
    );
  }
}

class NotePreferenceMutationController
    extends StateNotifier<NotePreferenceMutationState> {
  NotePreferenceMutationController({
    required String userId,
    required INotesRepository notesRepository,
    required UserNotePreferencesRepository preferencesRepository,
  }) : _userId = userId,
       _notesRepository = notesRepository,
       _preferencesRepository = preferencesRepository,
       super(const NotePreferenceMutationState());

  final String _userId;
  final INotesRepository _notesRepository;
  final UserNotePreferencesRepository _preferencesRepository;
  final Map<_PreferenceField, int> _versions = {};
  int _nextVersion = 0;

  Future<void> setHideCompleted({
    required NoteModel current,
    required bool value,
  }) {
    return _runBooleanMutation(
      field: _PreferenceField.hideCompleted,
      current: current,
      previousValue: current.hideCompleted,
      targetValue: value,
      write: (next) =>
          _preferencesRepository.setHideCompleted(_userId, current.id, next),
      readCurrentValue: (note) => note.hideCompleted,
      rollback: (previous) => _preferencesRepository.setHideCompleted(
        _userId,
        current.id,
        previous,
      ),
    );
  }

  Future<void> setCollapseImages({
    required NoteModel current,
    required bool value,
  }) {
    return _runBooleanMutation(
      field: _PreferenceField.collapseImages,
      current: current,
      previousValue: current.collapseImages,
      targetValue: value,
      write: (next) =>
          _notesRepository.updateNote(current.id, collapseImages: next),
      readCurrentValue: (note) => note.collapseImages,
      rollback: (previous) =>
          _notesRepository.updateNote(current.id, collapseImages: previous),
    );
  }

  Future<void> _runBooleanMutation({
    required _PreferenceField field,
    required NoteModel current,
    required bool previousValue,
    required bool targetValue,
    required Future<void> Function(bool value) write,
    required bool Function(NoteModel note) readCurrentValue,
    required Future<void> Function(bool value) rollback,
  }) async {
    final version = ++_nextVersion;
    _versions[field] = version;
    _markSaving();

    try {
      await write(targetValue);
      _markComplete();
    } catch (error) {
      await _rollbackIfStillCurrent(
        field: field,
        noteId: current.id,
        version: version,
        targetValue: targetValue,
        previousValue: previousValue,
        readCurrentValue: readCurrentValue,
        rollback: rollback,
      );
      _markError(error);
    }
  }

  Future<void> _rollbackIfStillCurrent({
    required _PreferenceField field,
    required String noteId,
    required int version,
    required bool targetValue,
    required bool previousValue,
    required bool Function(NoteModel note) readCurrentValue,
    required Future<void> Function(bool value) rollback,
  }) async {
    if (_versions[field] != version) return;

    final latest = await _notesRepository.getNoteById(noteId);
    if (latest == null) return;
    if (readCurrentValue(latest) != targetValue) return;

    await rollback(previousValue);
  }

  void _markSaving() {
    state = state.copyWith(
      status: NotePreferenceMutationStatus.saving,
      clearError: true,
      inFlightCount: state.inFlightCount + 1,
    );
  }

  void _markComplete() {
    final nextCount = state.inFlightCount - 1;
    state = state.copyWith(
      status: nextCount <= 0
          ? NotePreferenceMutationStatus.idle
          : NotePreferenceMutationStatus.saving,
      inFlightCount: nextCount < 0 ? 0 : nextCount,
    );
  }

  void _markError(Object error) {
    final nextCount = state.inFlightCount - 1;
    state = state.copyWith(
      status: NotePreferenceMutationStatus.error,
      error: error,
      inFlightCount: nextCount < 0 ? 0 : nextCount,
    );
  }
}

enum _PreferenceField { hideCompleted, collapseImages }

final notePreferenceMutationControllerProvider = StateNotifierProvider.family
    .autoDispose<
      NotePreferenceMutationController,
      NotePreferenceMutationState,
      String
    >((ref, noteId) {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null || userId.isEmpty) {
        throw StateError(
          'NotePreferenceMutationController requires an authenticated user',
        );
      }
      return NotePreferenceMutationController(
        userId: userId,
        notesRepository: ref.watch(notesRepositoryProvider),
        preferencesRepository: ref.watch(userNotePreferencesRepositoryProvider),
      );
    });
