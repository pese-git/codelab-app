import 'package:test/test.dart';

import 'web_smoke/main.dart';

/// Тот же код, что компилирует `melos run web-compile`, на Dart VM: основной
/// барель моста работает без файлов и сети (design.md change
/// `add-provider-setup-ui`, D20).
void main() {
  test('основной барель работает без dart:io', () async {
    final report = await runSetupWebSmoke();

    expect(report.access, 'EditableSettings');
    expect(report.models, ['m']);
    expect(report.entries, ['a:Key: env SMOKE_KEY (not set)', 'b:No key']);
    expect(report.removal, 'ProviderRemoved');
    expect(report.wizard, [
      'SetValue(providers.openrouter.kind)',
      'SetValue(providers.openrouter.base_url)',
      'SetValue(providers.openrouter.models.m.context_window)',
      'SetValue(agent.default_model)',
    ]);
    expect(report.settings, [
      'providers.a.kind:user',
      'providers.b.kind:user',
      'providers.a.api_key_env:user',
      'type:true',
      'scope:true',
      'bad:true',
      'refusal:true',
      'rows:true',
    ]);
    expect(report.mcp, [
      'upsert:docs',
      'secret:codelab/mcp/docs/authorization',
      'entry:docs:user:true',
      'valid:true',
    ]);
    expect(report.extensions, [
      'context:AGENTS.md',
      'skill:smoke:.codelab/skills',
      'trusted:true',
    ]);
    expect(report.codes, [
      'address:addressInvalid',
      'key:secretStoreReadOnly',
      'literal:false',
      'notVerified:null',
    ]);
    // Типизированные проблемы черновика MCP и поля вида навыков (задача 5.1a).
    expect(report.draftCodes, [
      'nameInvalid:null:Use a name without spaces, [, ] or ".',
      'urlHasUserinfo:null:Remove the user name and password from the URL.',
      'secretValueEmpty:TOKEN:Enter the secret value for TOKEN.',
      'keyDuplicate:Authorization:Two values are named Authorization.',
    ]);
    expect(report.skillFields, [
      'delta:null:~/.claude/skills',
      'review:user:null',
    ]);
  });
}
