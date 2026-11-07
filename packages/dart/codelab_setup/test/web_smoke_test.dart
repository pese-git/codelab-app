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
    ]);
    expect(report.mcp, [
      'upsert:docs',
      'secret:codelab/mcp/docs/authorization',
      'entry:docs:user:true',
      'valid:true',
    ]);
  });
}
