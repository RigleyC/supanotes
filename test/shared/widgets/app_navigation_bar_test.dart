import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/shared/widgets/app_navigation_bar.dart';

Widget _bar({
  required int currentIndex,
  required ValueChanged<int> onSelected,
  VoidCallback? onPrimaryAction,
}) {
  void noop(BuildContext _) {}
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: AppNavigationBar(
          currentIndex: currentIndex,
          onDestinationSelected: onSelected,
          onPrimaryAction: onPrimaryAction,
          destinations: [
            AppNavigationDestination(
              label: 'Tarefas',
              primaryActionLabel: 'Nova tarefa',
              onPrimaryAction: noop,
            ),
            AppNavigationDestination(
              label: 'Notas',
              primaryActionLabel: 'Nova nota',
              onPrimaryAction: noop,
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders text tabs with the selected state', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_bar(currentIndex: 1, onSelected: (_) {}));

    expect(find.text('Tarefas'), findsOneWidget);
    expect(find.text('Notas'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('app-navigation-tab-1'))),
      matchesSemantics(
        label: 'Notas',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('app-navigation-tab-0'))).height,
      greaterThanOrEqualTo(44),
    );
    // The first label is aligned with list content.
    expect(
      tester.getTopLeft(find.text('Tarefas')).dx,
      AppNavigationBar.contentInset,
    );
    handle.dispose();
  });

  testWidgets('selects tabs and runs the primary action', (tester) async {
    int? selected;
    var created = 0;
    await tester.pumpWidget(
      _bar(
        currentIndex: 0,
        onSelected: (index) => selected = index,
        onPrimaryAction: () => created++,
      ),
    );

    await tester.tap(find.text('Notas'));
    expect(selected, 1);

    expect(find.bySemanticsLabel('Nova tarefa'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('app-navigation-primary-action')),
    );
    expect(created, 1);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('app-navigation-primary-action')),
      ),
      const Size.square(48),
    );
  });
}
