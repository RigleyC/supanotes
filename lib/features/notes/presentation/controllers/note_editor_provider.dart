import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'note_editor_controller.dart';

final noteEditorControllerProvider = Provider.autoDispose.family<NoteEditorController, String>((ref, noteId) {
  final userId = ref.watch(currentUserIdProvider)!;
  final controller = NoteEditorController(
    userId: userId,
    database: ref.watch(appDatabaseProvider),
  );
  controller.bind(noteId);
  ref.onDispose(() {
    controller.dispose();
  });
  return controller;
});
