import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('runs dartdoc link validation in Melos and CI', () {
    final melos = _repoFile('melos.yaml').readAsStringSync();
    final ci = _repoFile('.github/workflows/ci.yaml').readAsStringSync();

    expect(melos, contains('docs:'));
    expect(melos, contains('dart doc --validate-links'));
    expect(ci, contains('melos run docs'));
  });

  test('package entrypoint has examples and advanced API guidance', () {
    final entrypoint = File('lib/dart_crdt.dart').readAsStringSync();

    expect(entrypoint, contains('```dart'));
    expect(entrypoint, contains('Advanced APIs'));
    expect(entrypoint, contains('Prefer `Doc`, `SharedType`'));
  });

  test('package README uses a dartdoc-safe examples link', () {
    final readme = File('README.md').readAsStringSync();

    expect(readme, contains('https://github.com/salakar/ycrdt'));
    expect(readme, isNot(contains('](example/)')));
  });
}

File _repoFile(String relativePath) {
  return File.fromUri(Directory.current.uri.resolve('../../$relativePath'));
}
