import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/presentation/widgets/task_exit_animator.dart';

void main() {
  testWidgets('does not animate when hideCompleted=false', (tester) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskExitAnimator(
            hideCompleted: false,
            isComplete: true,
            onAnimationComplete: () => completed = true,
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(completed, isFalse);
  });

  testWidgets('forwards when hideCompleted && isComplete turns true',
      (tester) async {
    var completed = false;
    var widget = TaskExitAnimator(
      hideCompleted: true,
      isComplete: false,
      onAnimationComplete: () => completed = true,
      child: const SizedBox(width: 10, height: 10),
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
    await tester.pump();

    widget = TaskExitAnimator(
      hideCompleted: true,
      isComplete: true,
      onAnimationComplete: () => completed = true,
      child: const SizedBox(width: 10, height: 10),
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
  });
}
