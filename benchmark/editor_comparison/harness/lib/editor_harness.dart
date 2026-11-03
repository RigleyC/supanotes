// Shared benchmark harness for comparing rich-text editors under identical
// conditions. Each editor POC implements [EditorDriver]; [runEditorBenchmark]
// drives typing, caret moves and document open, and prints one RESULT line per
// metric so results can be compared across packages.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

enum BlockType { paragraph, task }

class BlockSpec {
  const BlockSpec(this.type, this.text, {this.checked = false});
  final BlockType type;
  final String text;
  final bool checked;
}

/// Document size multiplier: `--dart-define=SCALE=5` benchmarks a 1000-block
/// note instead of the default 200 blocks.
const scale = int.fromEnvironment('SCALE', defaultValue: 1);
const paragraphCount = 150 * scale;
const taskCount = 50 * scale;
const keystrokes = 80;
const caretMoves = 60;

/// 150 wrapping paragraphs followed by 50 tasks: the same shape as the
/// SupaNotes editor benchmark.
List<BlockSpec> buildDocumentSpec() => [
  for (var p = 0; p < paragraphCount; p++)
    BlockSpec(
      BlockType.paragraph,
      'Paragraph $p with enough words to wrap across the line on a '
      'phone sized viewport, like a normal note would.',
    ),
  for (var t = 0; t < taskCount; t++)
    BlockSpec(BlockType.task, 'Task number $t', checked: t % 3 == 0),
];

/// Minimal surface every editor POC implements.
abstract class EditorDriver {
  String get name;

  /// Builds the editor for [blocks]. Called once per test.
  Widget build(List<BlockSpec> blocks);

  /// Places a collapsed caret in block [blockIndex] at [offset].
  FutureOr<void> placeCaret(int blockIndex, int offset);

  /// Inserts [character] at the caret, through the same editor API the
  /// platform IME path ends up calling. If the editor applies edits
  /// asynchronously, return a Future that completes once the document
  /// reflects the edit; the time until then is measured.
  FutureOr<void> typeCharacter(String character);

  /// Selects [start, end) inside block [blockIndex].
  FutureOr<void> selectRange(int blockIndex, int start, int end);

  int get blockCount;
  int blockTextLength(int blockIndex);

  /// Plain text of block [blockIndex] (used to verify edits landed).
  String blockText(int blockIndex);

  void dispose() {}
}

class Stats {
  Stats(List<int> microseconds)
    : _sorted = [...microseconds]..sort(),
      mean = microseconds.reduce((a, b) => a + b) / microseconds.length / 1000;
  final List<int> _sorted;
  final double mean;
  double _at(double q) => _sorted[(q * (_sorted.length - 1)).round()] / 1000;
  double get p50 => _at(0.5);
  double get p90 => _at(0.9);
  double get max => _sorted.last / 1000;

  @override
  String toString() =>
      'mean=${mean.toStringAsFixed(2)}ms p50=${p50.toStringAsFixed(2)}ms '
      'p90=${p90.toStringAsFixed(2)}ms max=${max.toStringAsFixed(2)}ms';
}

/// Live binding with real time; semantics off (as on devices without a
/// screen reader). Call once from `main()` before [benchmarkEditor].
void configureBinding() {
  final binding = LiveTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
}

/// Registers the benchmark test for [createDriver].
void benchmarkEditor(EditorDriver Function() createDriver) {
  testWidgets('editor benchmark', semanticsEnabled: false, (tester) async {
    final driver = createDriver();
    await runEditorBenchmark(tester, driver);
  });
}

Future<void> runEditorBenchmark(WidgetTester tester, EditorDriver driver) async {
  // Measures only the frame's own work (build, layout, paint), not the wait
  // for the next vsync that pump() includes.
  Future<int> frame() async {
    final watch = Stopwatch();
    SchedulerBinding.instance.scheduleFrameCallback((_) => watch.start());
    SchedulerBinding.instance.addPostFrameCallback((_) => watch.stop());
    await tester.pump();
    return watch.elapsedMicroseconds;
  }

  Future<void> idle(int ms) async {
    await Future<void>.delayed(Duration(milliseconds: ms));
    await tester.pump();
  }

  final blocks = buildDocumentSpec();

  // Open: build + first layout/paint of the whole document.
  final openWatch = Stopwatch()..start();
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: SafeArea(child: driver.build(blocks)))),
  );
  openWatch.stop();
  await idle(500);
  if (driver.blockCount != blocks.length) {
    throw StateError(
      '${driver.name}: expected ${blocks.length} blocks, '
      'got ${driver.blockCount}',
    );
  }

  const target = paragraphCount ~/ 2;
  final before = driver.blockText(target);
  await driver.placeCaret(target, 0);
  await idle(300);

  final typing = <int>[];
  final typingEdit = <int>[];
  final typingFrame = <int>[];
  for (var i = 0; i < keystrokes; i++) {
    final sw = Stopwatch()..start();
    await driver.typeCharacter(i % 7 == 6 ? ' ' : 'a');
    final edit = sw.elapsedMicroseconds;
    final frameUs = await frame();
    typingEdit.add(edit);
    typingFrame.add(frameUs);
    typing.add(edit + frameUs);
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
  final after = driver.blockText(target);
  if (after.length != before.length + keystrokes) {
    throw StateError(
      '${driver.name}: typing did not land in block $target '
      '(before ${before.length} chars, after ${after.length})',
    );
  }

  final moves = <int>[];
  final movesEdit = <int>[];
  final movesFrame = <int>[];
  for (var i = 0; i < caretMoves; i++) {
    final index = (i * 7) % driver.blockCount;
    final length = driver.blockTextLength(index);
    final sw = Stopwatch()..start();
    await driver.selectRange(index, 0, length < 5 ? length : 5);
    final edit = sw.elapsedMicroseconds;
    final frameUs = await frame();
    movesEdit.add(edit);
    movesFrame.add(frameUs);
    moves.add(edit + frameUs);
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  final name = driver.name;
  // ignore: avoid_print
  print('RESULT $name blocks=${blocks.length}');
  // ignore: avoid_print
  print('RESULT $name open total=${(openWatch.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms');
  // ignore: avoid_print
  print('RESULT $name keystroke ${Stats(typing)}');
  // ignore: avoid_print
  print('RESULT $name keystroke-edit ${Stats(typingEdit)}');
  // ignore: avoid_print
  print('RESULT $name keystroke-frame ${Stats(typingFrame)}');
  // ignore: avoid_print
  print('RESULT $name selection ${Stats(moves)}');
  // ignore: avoid_print
  print('RESULT $name selection-edit ${Stats(movesEdit)}');
  // ignore: avoid_print
  print('RESULT $name selection-frame ${Stats(movesFrame)}');

  await tester.pumpWidget(const SizedBox());
  driver.dispose();
  await idle(200);
}
