import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/presentation/widgets/notes_grid_view.dart';
import 'package:supanotes/features/notes/presentation/widgets/notes_list_view.dart';
import 'package:supanotes/features/notes/presentation/widgets/pull_down_brief_panel.dart';

const contentKey = Key('notes-content');

class _TestApp extends StatelessWidget {
  const _TestApp({this.onProgressChanged, this.childBuilder});

  final ValueChanged<double>? onProgressChanged;
  final Widget Function(ScrollController controller)? childBuilder;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: PullDownBriefPanel(
            background: const ColoredBox(color: Colors.black),
            onProgressChanged: onProgressChanged,
            builder: (context, controller) {
              final childBuilder = this.childBuilder;
              if (childBuilder != null) return childBuilder(controller);
              return CustomScrollView(
                key: contentKey,
                controller: controller,
                physics: const ClampingScrollPhysics(),
                slivers: [
                  SliverList.builder(
                    itemCount: 40,
                    itemBuilder: (context, index) {
                      return SizedBox(height: 56, child: Text('Note $index'));
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

NoteModel _note() {
  final now = DateTime(2026);
  return NoteModel(
    id: 'note-1',
    userId: 'user-1',
    title: 'One note',
    excerpt: null,
    content: 'Only one note',
    isInbox: false,
    favorite: false,
    archived: false,
    contextId: null,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  testWidgets(
    'starts as a square full-height sheet over the brief background',
    (tester) async {
      final progressValues = <double>[];
      await tester.pumpWidget(_TestApp(onProgressChanged: progressValues.add));
      await tester.pump();

      final material = tester.widget<Material>(find.byType(Material).last);

      expect(progressValues, contains(0));
      expect(material.borderRadius, BorderRadius.zero);
    },
  );

  testWidgets(
    'reports progress while dragging sheet down to reveal the brief',
    (tester) async {
      final progressValues = <double>[];
      await tester.pumpWidget(_TestApp(onProgressChanged: progressValues.add));
      await tester.pump();

      await tester.drag(find.byKey(contentKey), const Offset(0, 180));
      await tester.pumpAndSettle();

      expect(progressValues, isNotEmpty);
      expect(progressValues.last, greaterThan(0));
    },
  );

  testWidgets('reports hidden and revealed progress in the right direction', (
    tester,
  ) async {
    final progressValues = <double>[];
    await tester.pumpWidget(_TestApp(onProgressChanged: progressValues.add));
    await tester.pump();

    expect(progressValues, contains(0));

    await tester.drag(find.byKey(contentKey), const Offset(0, 300));
    await tester.pumpAndSettle();

    expect(progressValues.last, 1);
  });

  testWidgets('reveals the brief with the real list view and one note', (
    tester,
  ) async {
    final progressValues = <double>[];
    await tester.pumpWidget(
      _TestApp(
        onProgressChanged: progressValues.add,
        childBuilder: (controller) {
          return NotesListView(
            key: contentKey,
            controller: controller,
            notes: [_note()],
            headerSlivers: const [],
            onTap: (_) {},
            onDelete: (_) {},
            onToggleFavorite: (_) {},
          );
        },
      ),
    );
    await tester.pump();

    await tester.drag(find.byKey(contentKey), const Offset(0, 300));
    await tester.pumpAndSettle();

    final scrollView = tester.widget<CustomScrollView>(
      find.descendant(
        of: find.byKey(contentKey),
        matching: find.byType(CustomScrollView),
      ),
    );
    expect(scrollView.physics, isA<AlwaysScrollableScrollPhysics>());
    expect(progressValues.last, 1);
  });

  testWidgets(
    'reveals the brief when dragging directly on the only list note',
    (tester) async {
      final progressValues = <double>[];
      await tester.pumpWidget(
        _TestApp(
          onProgressChanged: progressValues.add,
          childBuilder: (controller) {
            return NotesListView(
              controller: controller,
              notes: [_note()],
              headerSlivers: const [],
              onTap: (_) {},
              onDelete: (_) {},
              onToggleFavorite: (_) {},
            );
          },
        ),
      );
      await tester.pump();

      await tester.drag(find.text('One note'), const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(progressValues.last, 1);
    },
  );

  testWidgets('hides the brief again with the real list view and one note', (
    tester,
  ) async {
    final progressValues = <double>[];
    await tester.pumpWidget(
      _TestApp(
        onProgressChanged: progressValues.add,
        childBuilder: (controller) {
          return NotesListView(
            key: contentKey,
            controller: controller,
            notes: [_note()],
            headerSlivers: const [],
            onTap: (_) {},
            onDelete: (_) {},
            onToggleFavorite: (_) {},
          );
        },
      ),
    );
    await tester.pump();

    await tester.drag(find.byKey(contentKey), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(progressValues.last, 1);

    await tester.drag(find.byKey(contentKey), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(progressValues.last, 0);
  });

  testWidgets('reveals the brief with the real grid view and one note', (
    tester,
  ) async {
    final progressValues = <double>[];
    await tester.pumpWidget(
      _TestApp(
        onProgressChanged: progressValues.add,
        childBuilder: (controller) {
          return NotesGridView(
            key: contentKey,
            controller: controller,
            notes: [_note()],
            headerSlivers: const [],
            onTap: (_) {},
            onDelete: (_) {},
            onToggleFavorite: (_) {},
          );
        },
      ),
    );
    await tester.pump();

    await tester.drag(find.byKey(contentKey), const Offset(0, 300));
    await tester.pumpAndSettle();

    expect(progressValues.last, 1);
  });

  testWidgets('rounds the top edge only while revealing the brief', (
    tester,
  ) async {
    await tester.pumpWidget(const _TestApp());

    await tester.drag(find.byKey(contentKey), const Offset(0, 300));
    await tester.pumpAndSettle();

    final material = tester.widget<Material>(find.byType(Material).last);

    expect(
      material.borderRadius,
      const BorderRadius.vertical(top: Radius.circular(30)),
    );
  });

  testWidgets('uses sheet controller for inner scrolling while hidden', (
    tester,
  ) async {
    final progressValues = <double>[];
    await tester.pumpWidget(_TestApp(onProgressChanged: progressValues.add));
    await tester.pump();
    final progressBeforeScroll = progressValues.last;

    await tester.drag(find.byKey(contentKey), const Offset(0, -240));
    await tester.pumpAndSettle();

    expect(progressValues.last, closeTo(progressBeforeScroll, 0.01));
  });
}
