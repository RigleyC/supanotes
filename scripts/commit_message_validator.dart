import 'dart:io';

import 'conventional_commit.dart';

class CommitValidationResult {
  const CommitValidationResult({required this.isValid, this.message = ''});

  final bool isValid;
  final String message;
}

class CommitMessageValidator {
  const CommitMessageValidator._();

  static const _allowedTypes = {
    'feat',
    'fix',
    'refactor',
    'docs',
    'test',
    'chore',
    'build',
    'ci',
    'perf',
    'revert',
    'style',
  };

  static CommitValidationResult validate(String message) {
    final lines = message
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toList();
    if (lines.isEmpty) {
      return const CommitValidationResult(
        isValid: false,
        message: 'Commit message cannot be empty.',
      );
    }

    final subject = lines.first;
    if (subject.startsWith('Merge ')) {
      return const CommitValidationResult(isValid: true);
    }

    final commit = ConventionalCommit.tryParse(subject);
    if (commit == null || !_allowedTypes.contains(commit.type)) {
      return const CommitValidationResult(
        isValid: false,
        message:
            'Use type(scope): description, for example feat(editor): add task block.',
      );
    }

    return const CommitValidationResult(isValid: true);
  }
}

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run scripts/commit_message_validator.dart <commit-message-file>',
    );
    exitCode = 2;
    return;
  }

  final result = CommitMessageValidator.validate(
    File(arguments.single).readAsStringSync(),
  );
  if (!result.isValid) {
    stderr.writeln(result.message);
    exitCode = 1;
  }
}
