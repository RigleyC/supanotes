import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/features/notes/catalog/model/note_icon.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/note_icon_picker.dart';
import 'package:supanotes/shared/widgets/global_sheet.dart';

import '../../../../../helpers/haptic_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('catalog picker exposes 48px color and icon hit targets', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteCatalogIconPickerPage(
            current: null,
            onSelected: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();

    final colorTarget = find.bySemanticsLabel('Cor red');
    final iconTarget = find.bySemanticsLabel('Carteira');

    expect(colorTarget, findsOneWidget);
    expect(iconTarget, findsOneWidget);
    expect(tester.getSize(colorTarget), const Size(48, 48));
    expect(tester.getSize(iconTarget).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(iconTarget).height, greaterThanOrEqualTo(48));
  });

  testWidgets('emoji picker keeps title and search fixed while grid scrolls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NoteEmojiPickerPage(onSelected: (_) async {})),
      ),
    );
    await tester.pump();

    expect(find.text('Escolher emoji'), findsOneWidget);
    expect(find.text('Buscar emojis'), findsOneWidget);

    final titleDy = tester.getTopLeft(find.text('Escolher emoji')).dy;
    final searchDy = tester.getTopLeft(find.text('Buscar emojis')).dy;

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('Escolher emoji')).dy, titleDy);
    expect(tester.getTopLeft(find.text('Buscar emojis')).dy, searchDy);
  });

  testWidgets(
    'catalog picker keeps search and color controls fixed while grid scrolls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteCatalogIconPickerPage(
              current: null,
              onSelected: (_) async {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Escolher ícone'), findsOneWidget);
      expect(find.text('Buscar ícones'), findsOneWidget);
      expect(find.bySemanticsLabel('Cor red'), findsOneWidget);

      final searchDy = tester.getTopLeft(find.text('Buscar ícones')).dy;
      final colorDy = tester.getTopLeft(find.bySemanticsLabel('Cor red')).dy;

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.text('Buscar ícones')).dy, searchDy);
      expect(tester.getTopLeft(find.bySemanticsLabel('Cor red')).dy, colorDy);
    },
  );

  testWidgets(
    'tapping Usar emoji emits one control haptic and opens emoji page',
    (tester) async {
      final recorder = HapticTestRecorder()..install();
      addTearDown(recorder.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showGlobalSheet<void>(
                  context: context,
                  builder: (_) => NoteIconPickerRootPage(
                    note: _buildNote(),
                    onSelected: (_) async {},
                  ),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      recorder.calls.clear();
      await tester.tap(find.text('Usar emoji'));
      await tester.pumpAndSettle();

      expect(find.text('Escolher emoji'), findsOneWidget);
      expect(
        recorder.calls.where(
          (call) => call.arguments == 'HapticFeedbackType.lightImpact',
        ),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'tapping an emoji semantics target emits one selection haptic and returns an emoji icon',
    (tester) async {
      final recorder = HapticTestRecorder()..install();
      addTearDown(recorder.dispose);
      NoteIcon? selectedIcon;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteEmojiPickerPage(
              onSelected: (icon) async {
                selectedIcon = icon;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      recorder.calls.clear();
      final emojiTarget = find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.button == true,
            ),
          )
          .first;
      await tester.tap(emojiTarget);
      await tester.pumpAndSettle();

      expect(selectedIcon, isNotNull);
      expect(selectedIcon!.isEmoji, isTrue);
      expect(selectedIcon!.value, isNotEmpty);
      expect(
        recorder.calls.where(
          (call) => call.arguments == 'HapticFeedbackType.selectionClick',
        ),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'tapping a different color emits one selection haptic and updates the selected color',
    (tester) async {
      final recorder = HapticTestRecorder()..install();
      addTearDown(recorder.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteCatalogIconPickerPage(
              current: NoteIcon.catalog(id: 'wallet', colorKey: 'red'),
              onSelected: (_) async {},
            ),
          ),
        ),
      );
      await tester.pump();

      recorder.calls.clear();
      await tester.tap(find.bySemanticsLabel('Cor blue'));
      await tester.pumpAndSettle();

      final blueSemantics = tester.getSemantics(
        find.bySemanticsLabel('Cor blue'),
      );
      expect(blueSemantics.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(blueSemantics.hasFlag(SemanticsFlag.isSelected), isTrue);
      expect(
        recorder.calls.where(
          (call) => call.arguments == 'HapticFeedbackType.selectionClick',
        ),
        hasLength(1),
      );
    },
  );

  testWidgets('tapping the selected color emits no extra selection haptic', (
    tester,
  ) async {
    final recorder = HapticTestRecorder()..install();
    addTearDown(recorder.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteCatalogIconPickerPage(
            current: NoteIcon.catalog(id: 'wallet', colorKey: 'red'),
            onSelected: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();

    recorder.calls.clear();
    await tester.tap(find.bySemanticsLabel('Cor red'));
    await tester.pumpAndSettle();

    expect(
      recorder.calls.where(
        (call) => call.arguments == 'HapticFeedbackType.selectionClick',
      ),
      isEmpty,
    );
  });

  testWidgets(
    'tapping a catalog icon emits one selection haptic and returns the selected icon',
    (tester) async {
      final recorder = HapticTestRecorder()..install();
      addTearDown(recorder.dispose);
      NoteIcon? selectedIcon;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteCatalogIconPickerPage(
              current: null,
              onSelected: (icon) async {
                selectedIcon = icon;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Cor blue'));
      await tester.pumpAndSettle();
      recorder.calls.clear();
      await tester.tap(find.bySemanticsLabel('Carteira'));
      await tester.pumpAndSettle();

      expect(selectedIcon, isNotNull);
      expect(selectedIcon!.isEmoji, isFalse);
      expect(selectedIcon!.value, 'wallet');
      expect(selectedIcon!.colorKey, 'blue');
      expect(
        recorder.calls.where(
          (call) => call.arguments == 'HapticFeedbackType.selectionClick',
        ),
        hasLength(1),
      );
    },
  );

  testWidgets('tapping the current catalog icon emits no selection haptic', (
    tester,
  ) async {
    final recorder = HapticTestRecorder()..install();
    addTearDown(recorder.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteCatalogIconPickerPage(
            current: NoteIcon.catalog(id: 'wallet', colorKey: 'blue'),
            onSelected: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();

    recorder.calls.clear();
    await tester.tap(find.bySemanticsLabel('Carteira'));
    await tester.pumpAndSettle();

    expect(
      recorder.calls.where(
        (call) => call.arguments == 'HapticFeedbackType.selectionClick',
      ),
      isEmpty,
    );
  });
}

NoteModel _buildNote() {
  final now = DateTime(2026, 8, 13);
  return NoteModel(
    id: 'note-1',
    userId: 'user-1',
    content: '',
    title: 'Teste',
    favorite: false,
    archived: false,
    createdAt: now,
    updatedAt: now,
    hasRemoteCopy: true,
    isEmptyDraft: false,
  );
}
