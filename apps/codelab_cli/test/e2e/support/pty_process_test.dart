// Обвязка псевдотерминала для PTY-e2e (tasks 6.1; spec testing-quality
// «PTY-e2e терминального клиента»; §9.11 «Обвязка PTY для e2e»; design.md
// change `add-codelab-cli`, D11).

import 'dart:io';

import 'package:test/test.dart';

import 'pty_process.dart';

Future<void> main() async {
  final skip = await PtyProcess.unavailableReason();

  test('the child gets a terminal on stdin and stdout and its exit '
      'code', () async {
    final pty = await PtyProcess.start('sh', [
      '-c',
      'test -t 0 && test -t 1; exit 3',
    ]);

    expect(await pty.exitCode, 3);
  }, skip: skip);

  test('the terminal has the requested size', () async {
    final pty = await PtyProcess.start(
      'sh',
      ['-c', 'tput cols; stty size'],
      columns: 100,
      rows: 30,
    );

    expect(await pty.exitCode, 0);
    expect(pty.text, contains('100\n'));
    expect(pty.text, contains('30 100\n'));
  }, skip: skip);

  test('arguments with spaces and quotes reach the child as is', () async {
    final pty = await PtyProcess.start('sh', [
      '-c',
      r'printf "<%s>" "$@"',
      'sh',
      'a b',
      "it's",
    ]);

    expect(await pty.exitCode, 0);
    expect(pty.text, contains("<a b><it's>"));
  }, skip: skip);

  test('bytes written to the harness reach the child stdin', () async {
    final pty = await PtyProcess.start('sh', [
      '-c',
      'read line; echo "got:\$line"',
    ]);

    pty.write('hello\r');

    expect(await pty.exitCode, 0);
    expect(pty.text, contains('got:hello\n'));
    expect(pty.text, isNot(contains('\r')));
  }, skip: skip);

  test('waitFor completes when the text appears', () async {
    final pty = await PtyProcess.start('sh', ['-c', 'sleep 0.2; echo ready']);

    await pty.waitFor('ready');
    expect(await pty.exitCode, 0);
  }, skip: skip);

  // Изоляция e2e (change `share-recent-projects-store`, D7, задача 3.5).
  test('without CODELAB_HOME the harness sets a temporary one', () async {
    final pty = await PtyProcess.start('sh', [
      '-c',
      r'echo "home=$CODELAB_HOME"',
    ]);

    expect(await pty.exitCode, 0);
    final home = RegExp(r'home=(\S+)').firstMatch(pty.text)!.group(1)!;
    expect(home, startsWith(Directory.systemTemp.path.replaceAll('//', '/')));
    expect(home, contains('codelab_pty_home_'));
  }, skip: skip);

  test('an explicit CODELAB_HOME is kept', () async {
    final pty = await PtyProcess.start(
      'sh',
      ['-c', r'echo "home=$CODELAB_HOME"'],
      environment: {'CODELAB_HOME': '/explicit/home'},
    );

    expect(await pty.exitCode, 0);
    expect(pty.text, contains('home=/explicit/home\n'));
  }, skip: skip);
}
