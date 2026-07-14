import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('release validation script passes for repository docs', () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'tool/validate_release.dart'],
      workingDirectory: _repoRoot.path,
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout, contains('Release validation passed.'));
  });

  test('release checklist and changelog cover required release evidence', () {
    final release = _repoFile('RELEASE.md').readAsStringSync();
    final changelog =
        _repoFile('packages/dart_crdt/CHANGELOG.md').readAsStringSync();
    final ci = _repoFile('.github/workflows/ci.yaml').readAsStringSync();

    for (final expected in [
      'Semantic Versioning',
      'Release Checklist',
      'API changes',
      'Compatibility summary',
      'Benchmark summary',
      'Known limitations',
      'melos run test:long-random',
      'melos run release:validate',
      'melos run publish:dry-run',
    ]) {
      expect(release, contains(expected));
    }

    for (final heading in [
      '### API Changes',
      '### Compatibility Summary',
      '### Benchmark Summary',
      '### Known Limitations',
      '### Verification',
    ]) {
      expect(changelog, contains(heading));
    }

    expect(ci, contains('melos run release:validate'));
    final nightly =
        _repoFile('.github/workflows/nightly.yaml').readAsStringSync();
    expect(nightly, contains('melos run test:long-random'));
  });
}

Directory get _repoRoot {
  return Directory.fromUri(Directory.current.uri.resolve('../../'));
}

File _repoFile(String relativePath) {
  return File.fromUri(_repoRoot.uri.resolve(relativePath));
}
