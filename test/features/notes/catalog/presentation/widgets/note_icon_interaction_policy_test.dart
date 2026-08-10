import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/note_icon_interaction_policy.dart';

void main() {
  final editableNote = NoteModel(
    id: 'note-1',
    userId: 'user-1',
    title: 'Nota',
    favorite: false,
    archived: false,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final readOnlyNote = NoteModel(
    id: 'note-2',
    userId: 'user-1',
    title: 'Somente leitura',
    permission: 'view',
    favorite: false,
    archived: false,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  Widget host({required double width, required Widget child}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 600)),
        child: Scaffold(body: child),
      ),
    );
  }

  testWidgets(
    'allows icon editing by long press only on editable mobile notes',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        host(
          width: 360,
          child: Builder(
            builder: (builderContext) {
              context = builderContext;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(
        NoteIconInteractionPolicy.canUseMobileLongPress(
          context: context,
          note: editableNote,
          onEditIcon: () {},
        ),
        isTrue,
      );
      expect(
        NoteIconInteractionPolicy.canUseMobileLongPress(
          context: context,
          note: readOnlyNote,
          onEditIcon: () {},
        ),
        isFalse,
      );
      expect(
        NoteIconInteractionPolicy.canUseMobileLongPress(
          context: context,
          note: editableNote,
          onEditIcon: null,
        ),
        isFalse,
      );
    },
  );

  testWidgets('allows icon editing from the context menu only on desktop', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      host(
        width: 1200,
        child: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(
      NoteIconInteractionPolicy.canUseDesktopContextMenu(
        context: context,
        note: editableNote,
        onEditIcon: () {},
      ),
      isTrue,
    );
    expect(
      NoteIconInteractionPolicy.canUseDesktopContextMenu(
        context: context,
        note: readOnlyNote,
        onEditIcon: () {},
      ),
      isFalse,
    );
    expect(
      NoteIconInteractionPolicy.canUseDesktopContextMenu(
        context: context,
        note: editableNote,
        onEditIcon: null,
      ),
      isFalse,
    );
  });
}
