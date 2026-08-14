import 'dart:io';

enum VersionBump { none, patch, minor, major }

class AppVersion {
  const AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  factory AppVersion.parse(String value) {
    final match = RegExp(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')
        .firstMatch(value);
    if (match == null) {
      throw FormatException('Invalid app version: $value');
    }
    return AppVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  AppVersion bump(VersionBump bump) => switch (bump) {
    VersionBump.none => this,
    VersionBump.patch => AppVersion(major, minor, patch + 1),
    VersionBump.minor => AppVersion(major, minor + 1, 0),
    VersionBump.major => AppVersion(major + 1, 0, 0),
  };

  String toBuildName() => '$major.$minor.$patch';

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => toBuildName();
}

class VersionCalculator {
  const VersionCalculator._();

  static AppVersion fromCommitMessages({
    required AppVersion baseVersion,
    required Iterable<String> messages,
  }) {
    var highestBump = VersionBump.none;
    for (final message in messages) {
      final bump = _bumpForCommit(message);
      if (bump.index > highestBump.index) highestBump = bump;
    }
    return baseVersion.bump(highestBump);
  }

  static VersionBump _bumpForCommit(String message) {
    final lines = message.trim().split(RegExp(r'\r?\n'));
    if (lines.isEmpty || lines.first.startsWith('Merge ')) {
      return VersionBump.none;
    }

    final subject = lines.first;
    if (lines.any((line) => line.startsWith('BREAKING CHANGE:'))) {
      return VersionBump.major;
    }

    final header = RegExp(
      r'^([a-z]+)(?:\([^)]*\))?(!)?: .+$',
    ).firstMatch(subject);
    if (header?.group(2) == '!') return VersionBump.major;

    return switch (header?.group(1)) {
      'feat' => VersionBump.minor,
      'fix' => VersionBump.patch,
      _ => VersionBump.none,
    };
  }
}

void main(List<String> arguments) {
  final buildNumber = _readBuildNumber(arguments);
  final tags = _git(['tag', '--list', 'v[0-9]*', '--sort=-version:refname']);
  final latestTag = tags
      .split(RegExp(r'\r?\n'))
      .map((tag) => tag.trim())
      .firstWhere((tag) => tag.isNotEmpty, orElse: () => '');
  final baseVersion = latestTag.isEmpty
      ? const AppVersion(1, 0, 0)
      : AppVersion.parse(latestTag.substring(1));
  final logRange = latestTag.isEmpty ? 'HEAD' : '$latestTag..HEAD';
  final log = _git(['log', logRange, '--format=%B%x1e']);
  final messages = log
      .split('\u001e')
      .map((message) => message.trim())
      .where((message) => message.isNotEmpty);
  final version = VersionCalculator.fromCommitMessages(
    baseVersion: baseVersion,
    messages: messages,
  );

  stdout.writeln('APP_VERSION=${version.toBuildName()}');
  stdout.writeln('APP_BUILD_NUMBER=$buildNumber');
}

int _readBuildNumber(List<String> arguments) {
  if (arguments.length != 2 || arguments.first != '--build-number') {
    throw ArgumentError('Usage: dart run scripts/app_version.dart --build-number <number>');
  }
  final value = int.tryParse(arguments[1]);
  if (value == null || value <= 0) {
    throw ArgumentError('Build number must be a positive integer.');
  }
  return value;
}

String _git(List<String> arguments) {
  final result = Process.runSync('git', arguments);
  if (result.exitCode != 0) {
    throw ProcessException('git', arguments, result.stderr.toString(), result.exitCode);
  }
  return result.stdout.toString();
}
