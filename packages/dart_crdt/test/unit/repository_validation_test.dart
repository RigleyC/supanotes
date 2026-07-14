import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('accepts a repository fixture that follows validation policy', () async {
    final fixture = _createFixture();
    _writeFixtureFile(fixture, 'README.md', 'Inspired by ${_blockedTerm()}.\n');
    _writeFixtureFile(
      fixture,
      'PLAN.md',
      'Reference: ${_blockedTerm()}_clone.\n',
    );
    _writeFixtureFile(fixture, 'TODO.md', 'Allowed ${_blockedTerm()} note.\n');
    _writeFixtureFile(
      fixture,
      '${_blockedTerm().toLowerCase()}_clone/file.js',
      '${_blockedTerm()} reference.\n',
    );
    _writeFixtureFile(
      fixture,
      'packages/demo/lib/demo.dart',
      'const ok = true;\n',
    );
    _writeFixtureFile(
      fixture,
      'packages/demo/test/demo_test.dart',
      'void main() {}\n',
    );

    addTearDown(() => fixture.deleteSync(recursive: true));

    final result = await _runValidator(fixture);

    expect(result.exitCode, 0, reason: result.stderr.toString());
  });

  test('rejects oversized implementation files', () async {
    final fixture = _createFixture();
    _writeFixtureFile(
      fixture,
      'packages/demo/lib/too_large.dart',
      _lines(301),
    );

    addTearDown(() => fixture.deleteSync(recursive: true));

    final result = await _runValidator(fixture);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('limit is 300'));
  });

  test('rejects oversized test files', () async {
    final fixture = _createFixture();
    _writeFixtureFile(
      fixture,
      'packages/demo/test/too_large_test.dart',
      _lines(251),
    );

    addTearDown(() => fixture.deleteSync(recursive: true));

    final result = await _runValidator(fixture);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('limit is 250'));
  });

  test('rejects forbidden package-facing references', () async {
    final fixture = _createFixture();
    _writeFixtureFile(
      fixture,
      'packages/demo/README.md',
      'Mentions ${_blockedTerm()}.\n',
    );

    addTearDown(() => fixture.deleteSync(recursive: true));

    final result = await _runValidator(fixture);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('forbidden reference'));
  });
}

Directory _createFixture() {
  return Directory.systemTemp.createTempSync('ycrdt_repository_validation_');
}

Future<ProcessResult> _runValidator(Directory fixture) {
  final script = Directory.current.parent.parent.uri
      .resolve('tool/validate_repository.dart')
      .toFilePath();
  return Process.run(
    Platform.resolvedExecutable,
    [script, '--root', fixture.path],
  );
}

void _writeFixtureFile(Directory root, String relativePath, String contents) {
  final file = File.fromUri(root.uri.resolve(relativePath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

String _lines(int count) {
  return List<String>.filled(count, 'const value = true;').join('\n');
}

String _blockedTerm() => 'Y' 'js';
