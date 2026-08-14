import 'package:flutter_test/flutter_test.dart';

import '../../scripts/app_version.dart';

void main() {
  group('AppVersion', () {
    test('parses and formats a semantic version', () {
      final version = AppVersion.parse('1.2.3');

      expect(version.major, 1);
      expect(version.minor, 2);
      expect(version.patch, 3);
      expect(version.toBuildName(), '1.2.3');
    });

    test('rejects malformed semantic versions', () {
      expect(() => AppVersion.parse('1.2'), throwsFormatException);
      expect(() => AppVersion.parse('v1.2.3'), throwsFormatException);
      expect(() => AppVersion.parse('1.2.3+4'), throwsFormatException);
      expect(() => AppVersion.parse('01.2.3'), throwsFormatException);
    });

    test('bumps each semantic version component', () {
      const version = AppVersion(1, 2, 3);

      expect(version.bump(VersionBump.none), const AppVersion(1, 2, 3));
      expect(version.bump(VersionBump.patch), const AppVersion(1, 2, 4));
      expect(version.bump(VersionBump.minor), const AppVersion(1, 3, 0));
      expect(version.bump(VersionBump.major), const AppVersion(2, 0, 0));
    });
  });

  group('VersionCalculator', () {
    test('classifies conventional commit types', () {
      expect(
        VersionCalculator.fromCommitMessages(
          baseVersion: const AppVersion(1, 0, 0),
          messages: ['fix(editor): preserve selection'],
        ),
        const AppVersion(1, 0, 1),
      );
      expect(
        VersionCalculator.fromCommitMessages(
          baseVersion: const AppVersion(1, 0, 0),
          messages: ['feat(editor): add task block'],
        ),
        const AppVersion(1, 1, 0),
      );
      expect(
        VersionCalculator.fromCommitMessages(
          baseVersion: const AppVersion(1, 0, 0),
          messages: ['feat(editor)!: replace task protocol'],
        ),
        const AppVersion(2, 0, 0),
      );
      expect(
        VersionCalculator.fromCommitMessages(
          baseVersion: const AppVersion(1, 0, 0),
          messages: ['fix(editor): preserve selection!'],
        ),
        const AppVersion(1, 0, 1),
      );
      expect(
        VersionCalculator.fromCommitMessages(
          baseVersion: const AppVersion(1, 0, 0),
          messages: [
            'refactor(editor): simplify command routing',
            'docs: explain setup',
            'test: cover parser',
            'chore: update tooling',
          ],
        ),
        const AppVersion(1, 0, 0),
      );
    });

    test('uses the highest bump and recognizes a breaking footer', () {
      expect(
        VersionCalculator.fromCommitMessages(
          baseVersion: const AppVersion(1, 2, 3),
          messages: [
            'fix: close stale session',
            'feat: add sharing',
            'refactor: simplify sync\n\nBREAKING CHANGE: remove old route',
          ],
        ),
        const AppVersion(2, 0, 0),
      );
    });
  });
}
