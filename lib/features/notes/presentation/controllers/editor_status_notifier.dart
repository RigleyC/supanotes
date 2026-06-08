import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/features/notes/domain/editor_status.dart';

class EditorStatusNotifier extends Notifier<EditorStatus> {
  @override
  EditorStatus build() => EditorStatus.idle;

  void saving() => state = EditorStatus.saving;
  void saved() => state = EditorStatus.saved;
  void errored() => state = EditorStatus.error;
  void reset() => state = EditorStatus.idle;
}

final editorStatusProvider =
    NotifierProvider.autoDispose<EditorStatusNotifier, EditorStatus>(
  EditorStatusNotifier.new,
);
