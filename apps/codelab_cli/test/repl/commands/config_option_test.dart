// `/model`, `/mode` и `/config` (tasks 7.5; spec codelab-cli «Slash-меню и
// клиентские команды»; U-05; design.md change `add-codelab-cli`, D7).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:test/test.dart';

import '../../support/repl_harness.dart';

const _model = {
  'type': 'select',
  'id': 'model',
  'name': 'Model',
  'category': 'model',
  'currentValue': 'a',
  'options': [
    {'value': 'a', 'name': 'Model A'},
    {'value': 'b', 'name': 'Model B'},
  ],
};

const _mode = {
  'type': 'select',
  'id': 'mode',
  'name': 'Mode',
  'category': 'mode',
  'currentValue': 'ask',
  'options': [
    {'value': 'ask', 'name': 'Ask'},
    {'value': 'code', 'name': 'Code'},
  ],
};

void main() {
  late ReplHarness repl;

  tearDown(() => repl.dispose());

  Future<void> start(List<Map<String, Object?>> options) async {
    repl = ReplHarness();
    await repl.start(configOptions: options);
  }

  test('/model lists the values and marks the current one', () async {
    await start([_model]);

    repl.line('/model');

    await repl.waitText('Model B');
    expect(repl.lastOutput, contains('* a'));
    expect(repl.lastOutput, contains('  b'));
  });

  test('/model <value> sends set_config_option', () async {
    await start([_model]);

    repl.line('/model b');

    final set = await repl.agent.next(sessionSetConfigOptionMethod);
    expect(set.params, containsPair('configId', 'model'));
    expect(set.params, containsPair('value', 'b'));
  });

  test('/model with an unknown value says so without a request', () async {
    await start([_model]);

    repl.line('/model zzz');

    await repl.waitText('Unknown model "zzz"');
    expect(repl.sentMethods, isNot(contains(sessionSetConfigOptionMethod)));
  });

  test('/mode <value> uses the mode option', () async {
    await start([_model, _mode]);

    repl.line('/mode code');

    final set = await repl.agent.next(sessionSetConfigOptionMethod);
    expect(set.params, containsPair('configId', 'mode'));
    expect(set.params, containsPair('value', 'code'));
  });

  test('/mode without a mode option says so', () async {
    await start([_model]);

    repl.line('/mode');

    await repl.waitText('The agent does not expose a "mode" config option.');
  });

  test('/config lists every option', () async {
    await start([_model, _mode]);

    repl.line('/config');

    await repl.waitText('mode');
    expect(repl.lastOutput, contains('model = a'));
    expect(repl.lastOutput, contains('mode = ask'));
  });

  test('/config <id> <value> sets any option', () async {
    await start([_model, _mode]);

    repl.line('/config mode code');

    final set = await repl.agent.next(sessionSetConfigOptionMethod);
    expect(set.params, containsPair('configId', 'mode'));
  });

  test('/config with an unknown option says so', () async {
    await start([_model]);

    repl.line('/config effort high');

    await repl.waitText('The agent has no "effort" option.');
  });
}
