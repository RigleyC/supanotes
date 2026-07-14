import 'dart:io';

Future<void> main() async {
  final outputDir = Directory('.dart_tool/ycrdt_js_smoke');
  outputDir.createSync(recursive: true);
  final outputFile = File('${outputDir.path}/js_smoke.js');

  await _run(
    Platform.resolvedExecutable,
    <String>[
      'compile',
      'js',
      'tool/js_smoke.dart',
      '-O2',
      '-o',
      outputFile.path,
    ],
  );
  await _run('node', <String>[outputFile.path], forwardStdout: true);
}

Future<void> _run(
  String executable,
  List<String> arguments, {
  bool forwardStdout = false,
}) async {
  final result = await Process.run(executable, arguments);
  final stdoutOutput = result.stdout;
  if (forwardStdout && stdoutOutput is String && stdoutOutput.isNotEmpty) {
    stdout.write(stdoutOutput);
  }
  final stderrOutput = result.stderr;
  if (stderrOutput is String && stderrOutput.isNotEmpty) {
    stderr.write(stderrOutput);
  }
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      'Command failed with exit code ${result.exitCode}.',
      result.exitCode,
    );
  }
}
