// Samples the Dart VM CPU profiler around a block of work and prints the
// hottest functions by inclusive and exclusive time. Requires running the
// test with `--enable-vmservice`.
import 'dart:developer';
import 'dart:isolate' as iso;

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> profile(String label, Future<void> Function() work) async {
  final info = await Service.getInfo();
  final uri = info.serverWebSocketUri;
  if (uri == null) {
    // ignore: avoid_print
    print('PROFILE $label skipped: run with --enable-vmservice');
    await work();
    return;
  }
  final service = await vmServiceConnectUri(uri.toString());
  final isolateId = Service.getIsolateId(iso.Isolate.current)!;
  await service.setFlag('profile_period', '100');
  await service.clearCpuSamples(isolateId);
  final start = (await service.getVMTimelineMicros()).timestamp!;
  await work();
  final end = (await service.getVMTimelineMicros()).timestamp!;
  final samples = await service.getCpuSamples(isolateId, start, end - start);
  final functions = samples.functions!;
  final inclusive = <int, int>{};
  final exclusive = <int, int>{};
  for (final sample in samples.samples!) {
    final stack = sample.stack!;
    if (stack.isEmpty) continue;
    exclusive[stack.first] = (exclusive[stack.first] ?? 0) + 1;
    for (final index in stack.toSet()) {
      inclusive[index] = (inclusive[index] ?? 0) + 1;
    }
  }
  // Samples spent waiting on the event loop are not work.
  final busy = samples.samples!.where((sample) {
    final stack = sample.stack!;
    return stack.isNotEmpty && stack.length > 3;
  }).length;
  final total = busy == 0 ? 1 : busy;
  String name(int index) {
    final function = functions[index].function;
    if (function is FuncRef) {
      final owner = function.owner;
      final ownerName = owner is ClassRef
          ? owner.name
          : owner is FuncRef
          ? owner.name
          : '';
      final lib = (function.location?.script?.uri ?? '').toString();
      final short = lib.startsWith('package:')
          ? lib.substring(8).split('/').first
          : lib.split('/').first;
      return '$ownerName.${function.name} [$short]';
    }
    if (function is NativeFunction) return 'native ${function.name}';
    return function.toString();
  }

  String top(Map<int, int> counts, bool Function(String) keep) {
    final ranked = counts.entries.toList()..sort((a, b) => b.value - a.value);
    return ranked
        .where((e) => keep(name(e.key)))
        .take(45)
        .map(
          (e) =>
              '  ${(100 * e.value / total).toStringAsFixed(1)}% ${name(e.key)}',
        )
        .join('\n');
  }

  bool appOrEditor(String n) =>
      n.contains('[supanotes]') ||
      n.contains('[super_editor]') ||
      n.contains('[super_text_layout]') ||
      n.contains('[attributed_text]') ||
      n.contains('[drift]');
  // ignore: avoid_print
  print(
    'PROFILE $label samples=$total\nINCLUSIVE (app/editor)\n'
    '${top(inclusive, appOrEditor)}\nEXCLUSIVE\n${top(exclusive, (_) => true)}',
  );
  await service.dispose();
}
