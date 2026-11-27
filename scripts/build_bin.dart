import 'dart:io';

void main(List<String> args) {
  final entry = args[0];
  final name = args[1];
  final ext = Platform.isWindows ? '.exe' : '';

  Directory('build/bin').createSync(recursive: true);

  final res = Process.runSync(
    Platform.resolvedExecutable,
    ['compile', 'exe', entry, '-o', 'build/bin/$name$ext'],
  );
  stdout.write(res.stdout);
  stderr.write(res.stderr);
  exit(res.exitCode);
}