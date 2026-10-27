// `/queue`, `/queue drop <n>`, `/queue clear` (tasks 7.5; spec codelab-cli
// «Очередь промптов в REPL»; U-15; design.md change `add-codelab-cli`, D7).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:test/test.dart';

import '../../support/repl_harness.dart';

void main() {
  late ReplHarness repl;
  late JsonRpcRequest running;

  setUp(() async {
    repl = ReplHarness();
    await repl.start();
    repl.line('first');
    running = await repl.agent.next(sessionPromptMethod);
    repl.line('second');
    await repl.waitText('queued: 1');
    repl.line('third');
    await repl.waitText('queued: 2');
  });
  tearDown(() => repl.dispose());

  test('/queue lists the queued prompts with numbers', () async {
    repl.line('/queue');

    await repl.waitText('2. third');
    expect(repl.lastOutput, contains('1. second'));
  });

  test('/queue drop <n> removes the n-th prompt', () async {
    repl.line('/queue drop 1');
    await repl.waitText('Dropped');

    repl.agent.respond(running, {'stopReason': 'end_turn'});
    final next = await repl.agent.next(sessionPromptMethod);
    expect(promptTextOf(next), 'third');
  });

  test('/queue drop with a wrong number says so', () async {
    repl.line('/queue drop 5');

    await repl.waitText('No queued prompt 5.');
  });

  test('/queue clear empties the queue', () async {
    repl.line('/queue clear');
    await repl.waitText('Cleared');

    repl.line('/queue');
    await repl.waitText('The queue is empty.');
  });
}
