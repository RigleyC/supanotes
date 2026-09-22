import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/features/tasks/application/task_controller.dart';
import 'package:supanotes/features/tasks/application/task_list_providers.dart';
import 'package:supanotes/features/tasks/domain/task.dart';
import 'package:supanotes/features/tasks/domain/task_list_item.dart';
import 'package:supanotes/features/tasks/presentation/task_editor_screen.dart';
import 'package:supanotes/features/tasks/presentation/tasks_screen.dart';

class _MockTaskController extends Mock implements TaskController {}

Task _task({String id = 'plain', String title = 'plain', DateTime? updatedAt}) {
  final now = DateTime.utc(2026, 9, 15, 10);
  return Task(
    id: id,
    ownerUserId: 'user-1',
    title: title,
    createdAt: now,
    updatedAt: updatedAt ?? now,
  );
}

/// The editor sheet mounts the root page twice (visible + Offstage height
/// measurer of family_bottom_sheet). Both share the same session controller,
/// so reading either one is equivalent.
TextEditingController _titleController(WidgetTester tester) => tester
    .widgetList<TextFormField>(find.byType(TextFormField))
    .first
    .controller!;

/// Simulates a real keyboard insertion at the current cursor position, the
/// way IME deltas land while the user keeps typing. If a snapshot re-apply
/// reset the selection mid-typing, the suffix lands at the wrong offset —
/// reproducing the user-reported interleaved text.
Future<void> _typeAtCursor(WidgetTester tester, String suffix) async {
  final controller = _titleController(tester);
  final selection = controller.selection;
  final start = selection.isValid ? selection.baseOffset : 0;
  final text = controller.value.text;
  tester.testTextInput.updateEditingValue(
    controller.value.copyWith(
      text: text.replaceRange(start, start, suffix),
      selection: TextSelection.collapsed(offset: start + suffix.length),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
    registerFallbackValue(_task());
  });

  testWidgets(
    'title keeps text and cursor across metadata page round-trips mid-typing',
    (tester) async {
      final controller = _MockTaskController();
      when(() => controller.update(any())).thenAnswer((_) async {});
      final router = GoRouter(
        initialLocation: '/tasks',
        routes: [
          GoRoute(path: '/tasks', builder: (_, _) => const TasksScreen()),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWithValue('user-1'),
            taskListProvider(includeNoteTasks: false).overrideWith(
              (ref) => Stream.value([TaskListItem.task(_task())]),
            ),
            taskControllerProvider.overrideWithValue(controller),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      await tester.tap(find.text('plain'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField),
        'isso aqui vai dar prob',
      );
      await tester.pump();

      // First metadata round-trip mid-typing (the user's reported workflow:
      // opening the metadata sheet multiple times while editing the title).
      await tester.tap(find.text('Adicionar data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hoje'));
      await tester.pumpAndSettle();

      final afterFirst = _titleController(tester);
      expect(afterFirst.text, 'isso aqui vai dar prob');
      expect(
        afterFirst.selection.baseOffset,
        'isso aqui vai dar prob'.length,
        reason: 'the cursor must stay at the end of the typed text',
      );

      // Second round-trip before finishing the sentence.
      await tester.tap(find.byIcon(Icons.calendar_today_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hoje'));
      await tester.pumpAndSettle();

      final afterSecond = _titleController(tester);
      expect(afterSecond.text, 'isso aqui vai dar prob');
      expect(afterSecond.selection.baseOffset, 'isso aqui vai dar prob'.length);

      // Continue typing at the cursor, as the keyboard would.
      await _typeAtCursor(tester, 'lema demais');
      expect(
        _titleController(tester).text,
        'isso aqui vai dar problema demais',
      );

      // Saving flushes the full in-flight title plus the picked metadata.
      await tester.tap(find.byTooltip('Salvar'));
      await tester.pumpAndSettle();
      final saved =
          verify(() => controller.update(captureAny())).captured.single as Task;
      expect(saved.title, 'isso aqui vai dar problema demais');
      expect(saved.dueDate, isNotNull);
    },
  );

  testWidgets(
    'a remote task update never clobbers the title while typing',
    (tester) async {
      final updates = StreamController<Task?>();
      addTearDown(updates.close);
      updates.add(_task(id: 't1', title: 'Titulo'));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            standaloneTaskProvider(
              't1',
            ).overrideWith((ref) => updates.stream),
          ],
          child: const MaterialApp(home: TaskEditorScreen(taskId: 't1')),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Titulo'), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField),
        'isso aqui vai dar prob',
      );
      await tester.pump();

      // A background sync/outbox confirmation updates the row (e.g. a
      // schedule change from another device) while the user is typing.
      updates.add(
        _task(
          id: 't1',
          title: 'Titulo',
          updatedAt: DateTime.utc(2026, 9, 15, 11),
        ).copyWith(dueDate: DateTime.utc(2026, 9, 16)),
      );
      await tester.pump();
      await tester.pump();

      final controller = _titleController(tester);
      expect(
        controller.text,
        'isso aqui vai dar prob',
        reason: 'a snapshot re-apply must never overwrite in-flight typing',
      );
      expect(
        controller.selection.baseOffset,
        'isso aqui vai dar prob'.length,
        reason: 'the cursor must not be reset by the update',
      );

      await _typeAtCursor(tester, 'lema demais');
      expect(
        _titleController(tester).text,
        'isso aqui vai dar problema demais',
      );
    },
  );
}
