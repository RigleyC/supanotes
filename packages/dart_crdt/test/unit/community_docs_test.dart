import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('contributing guide covers project workflow requirements', () {
    final contributing = _repoFile('CONTRIBUTING.md').readAsStringSync();

    for (final expected in [
      'melos bootstrap',
      'melos run validate',
      'melos run docs',
      'melos run test:long-random',
      'melos run examples',
      'melos run benchmark:smoke',
      'packages/dart_crdt/test/fixtures/compat/',
      'neutral',
      'conventional commit',
      'GitHub Security Advisories',
    ]) {
      expect(contributing, contains(expected));
    }
  });

  test('security and conduct docs describe private reporting', () {
    final security = _repoFile('SECURITY.md').readAsStringSync();
    final conduct = _repoFile('CODE_OF_CONDUCT.md').readAsStringSync();

    expect(security, contains('Reporting A Vulnerability'));
    expect(security, contains('/security/advisories/new'));
    expect(security, contains('Coordinated Disclosure'));
    expect(conduct, contains('Expected Behavior'));
    expect(conduct, contains('Unacceptable Behavior'));
    expect(conduct, contains('/security/advisories/new'));
  });

  test('GitHub templates cover compatibility and review gates', () {
    final issueTemplates = _repoDirectory('.github/ISSUE_TEMPLATE');
    final compatibility =
        File.fromUri(issueTemplates.uri.resolve('compatibility_report.yml'));
    final pullRequest =
        _repoFile('.github/pull_request_template.md').readAsStringSync();

    expect(compatibility.existsSync(), isTrue);
    final template = compatibility.readAsStringSync();
    expect(template, contains('Compatibility report'));
    expect(template, contains('Fixture or payload'));
    expect(template, contains('update encoding or decoding'));
    expect(template, contains('relative positions'));

    for (final check in [
      'melos run validate',
      'melos run docs',
      'melos run examples',
      'melos run benchmark:smoke',
      'Compatibility',
      'Security-sensitive behavior',
    ]) {
      expect(pullRequest, contains(check));
    }
  });
}

File _repoFile(String relativePath) {
  return File.fromUri(_repoDirectory('').uri.resolve(relativePath));
}

Directory _repoDirectory(String relativePath) {
  final root = Directory.current.uri.resolve('../../');
  return Directory.fromUri(root.resolve(relativePath));
}
