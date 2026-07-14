import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('compiled JavaScript smoke entrypoint stays web-compatible', () {
    final sources = <File>[
      File('tool/js_smoke.dart'),
      ...Directory('tool/src')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    ];
    final source = sources.map((file) => file.readAsStringSync()).join('\n');

    expect(source, isNot(contains('dart:io')));
    expect(source, isNot(contains('package:test')));
    expect(source, contains('_binaryPrimitiveSmoke'));
    expect(source, contains('_updateAlgebraSmoke'));
    expect(source, contains('_randomConvergenceSmoke'));
  });

  test('compiled JavaScript runner keeps generated artifacts hidden', () {
    final source = File('tool/run_js_smoke.dart').readAsStringSync();
    final docs = File('tool/JS_SMOKE.md').readAsStringSync();

    expect(source, contains('.dart_tool/ycrdt_js_smoke'));
    expect(docs, contains('.dart_tool/ycrdt_js_smoke/'));
    expect(docs, contains('RSS and VM allocation metrics'));
  });
}
