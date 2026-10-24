import 'package:test/test.dart';

import 'web_smoke/main.dart' show runWebSmoke;

void main() {
  // workspace-architecture «Web-smoke проводит ход с инструментом»: тот же
  // код, что компилируется в JS и Wasm, на Dart VM проводит ход через
  // buildAgentCore с вызовом read.
  test('the web-smoke turn reads a file and answers', () async {
    final report = await runWebSmoke();

    expect(report.toolCalls, ['read']);
    expect(report.toolOutput, '1| hello from memory');
    expect(report.answer, 'web smoke: read hello from memory');
    expect(report.reason, 'completed');
  });
}
