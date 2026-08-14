class ConventionalCommit {
  const ConventionalCommit({required this.type, required this.isBreaking});

  final String type;
  final bool isBreaking;

  static ConventionalCommit? tryParse(String message) {
    final lines = message.trim().split(RegExp(r'\r?\n'));
    if (lines.isEmpty) return null;
    final subject = lines.first;

    final header = RegExp(
      r'^([a-z]+)(?:\([^)]*\))?(!)?: .+$',
    ).firstMatch(subject);
    if (header == null) return null;

    return ConventionalCommit(
      type: header.group(1)!,
      isBreaking: header.group(2) == '!' || hasBreakingFooter(message),
    );
  }

  static bool hasBreakingFooter(String message) => message
      .split(RegExp(r'\r?\n'))
      .any((line) => line.startsWith('BREAKING CHANGE:'));
}
