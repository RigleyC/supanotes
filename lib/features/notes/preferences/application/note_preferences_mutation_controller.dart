import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/features/notes/catalog/data/notes_repository.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/preferences/data/user_note_preferences_repository.dart';

enum NotePreferenceMutationStatus { idle, saving, error }

extension NotePreferenceMutationAsyncValueX on AsyncValue<void> {
  NotePreferenceMutationStatus get status {
    return when(
      data: (_) => NotePreferenceMutationStatus.idle,
      loading: () => NotePreferenceMutationStatus.saving,
      error: (_, _) => NotePreferenceMutationStatus.error,
    );
  }
}

final class NotePreferenceMutationException implements Exception {
  const NotePreferenceMutationException({
    required this.field,
    required this.cause,
    this.rollbackError,
  });

  final String field;
  final Object cause;
  final Object? rollbackError;

  @override
  String toString() {
    final rollback = rollbackError == null
        ? ''
        : '; rollback failed: $rollbackError';
    return 'Failed to update note preference "$field": $cause$rollback';
  }
}

class NotePreferenceMutationController extends Notifier<AsyncValue<void>> {
  NotePreferenceMutationController();

  late String _userId;
  late INotesRepository _notesRepository;
  late UserNotePreferencesRepository _preferencesRepository;
  final Map<_PreferenceField, int> _versions = {};
  int _nextVersion = 0;
  int _inFlightCount = 0;
  int? _errorVersion;

  @override
  AsyncValue<void> build() {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null || userId.isEmpty) {
      throw StateError(
        'NotePreferenceMutationController requires an authenticated user',
      );
    }

    _userId = userId;
    _notesRepository = ref.watch(notesRepositoryProvider);
    _preferencesRepository = ref.watch(userNotePreferencesRepositoryProvider);
    return const AsyncValue.data(null);
  }

  Future<void> setHideCompleted({
    required NoteModel current,
    required bool value,
  }) {
    return _runBooleanMutation(
      field: _PreferenceField.hideCompleted,
      current: current,
      previousValue: current.hideCompleted,
      targetValue: value,
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
    );
  }

  Future<void> _runBooleanMutation({
    required _PreferenceField field,
    required NoteModel current,
    required bool previousValue,
    required bool targetValue,
  }) async {
    final version = ++_nextVersion;
    _versions[field] = version;
    _inFlightCount++;
    state = const AsyncValue.loading();

    try {
      await _write(field, current.id, targetValue);
    } on Object catch (error, stackTrace) {
      Object failure = NotePreferenceMutationException(
        field: field.name,
        cause: error,
      );
      var failureStackTrace = stackTrace;
      try {
        await _rollbackIfStillCurrent(
          field: field,
          noteId: current.id,
          version: version,
          targetValue: targetValue,
          previousValue: previousValue,
        );
      } on Object catch (rollbackError, rollbackStackTrace) {
        failure = NotePreferenceMutationException(
          field: field.name,
          cause: error,
          rollbackError: rollbackError,
        );
        failureStackTrace = rollbackStackTrace;
      } finally {
        _finish(
          version: version,
          error: _versions[field] == version ? failure : null,
          stackTrace: failureStackTrace,
        );
      }
      Error.throwWithStackTrace(failure, failureStackTrace);
    }
    _finish(version: version);
  }

  Future<void> _rollbackIfStillCurrent({
    required _PreferenceField field,
    required String noteId,
    required int version,
    required bool targetValue,
    required bool previousValue,
  }) async {
    if (_versions[field] != version) return;

    final latest = await _notesRepository.getNoteById(noteId);
    if (latest == null) return;
    if (_readValue(field, latest) != targetValue) return;

    await _write(field, noteId, previousValue);
  }

  Future<void> _write(_PreferenceField field, String noteId, bool value) {
    return switch (field) {
      _PreferenceField.hideCompleted => _preferencesRepository.setHideCompleted(
        _userId,
        noteId,
        value,
      ),
      _PreferenceField.collapseImages =>
        _preferencesRepository.setCollapseImages(_userId, noteId, value),
    };
  }

  bool _readValue(_PreferenceField field, NoteModel note) {
    return switch (field) {
      _PreferenceField.hideCompleted => note.hideCompleted,
      _PreferenceField.collapseImages => note.collapseImages,
    };
  }

  void _finish({required int version, Object? error, StackTrace? stackTrace}) {
    if (_inFlightCount > 0) _inFlightCount--;
    if (error != null) {
      _errorVersion = version;
      state = AsyncValue.error(error, stackTrace ?? StackTrace.current);
      return;
    }
    if (_errorVersion != null && version >= _errorVersion!) {
      _errorVersion = null;
    }
    if (_errorVersion != null) return;
    state = _inFlightCount == 0
        ? const AsyncValue.data(null)
        : const AsyncValue.loading();
  }
}

enum _PreferenceField { hideCompleted, collapseImages }

final notePreferenceMutationControllerProvider = NotifierProvider.autoDispose
    .family<NotePreferenceMutationController, AsyncValue<void>, String>(
      (_) => NotePreferenceMutationController(),
    );
