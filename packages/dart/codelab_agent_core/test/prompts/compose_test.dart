import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/prompts/compose.dart';
import 'package:test/test.dart';

import '../support/package_dir.dart';

/// Все встроенные инструменты MVP.
const allTools = {
  'read',
  'write',
  'edit',
  'update_plan',
  'exec',
  'ls',
  'search',
};

PromptInputs inputs({
  String profile = 'agent-serve',
  ModeId mode = ModeId.standard,
  Set<String> tools = allTools,
}) => PromptInputs(
  cwd: '/proj',
  platform: 'linux',
  today: DateTime.utc(2026, 1, 15, 23, 59),
  mode: mode,
  profile: HostProfile.of(profile),
  toolNames: tools,
);

void main() {
  final update = Platform.environment['UPDATE_GOLDEN'] == '1';

  // PR-3: golden системного промпта на профиль и режим. Обновить после
  // намеренной правки текстов: `UPDATE_GOLDEN=1 fvm dart test test/prompts`.
  for (final profile in ['agent-serve', 'embedded-cli']) {
    for (final mode in [ModeId.standard, ModeId.plan]) {
      final name = '$profile-${mode.value}';
      test('$name matches test/prompts/golden/$name.txt', () {
        final text = composeSystemPrompt(inputs(profile: profile, mode: mode));

        final file = File(corePath('test/prompts/golden/$name.txt'));
        if (update) {
          file
            ..createSync(recursive: true)
            ..writeAsStringSync(text);
        }
        expect(
          file.existsSync(),
          isTrue,
          reason: 'запустите с UPDATE_GOLDEN=1',
        );
        expect(text, file.readAsStringSync());
      });
    }
  }

  test('the same inputs give the same bytes', () {
    expect(composeSystemPrompt(inputs()), composeSystemPrompt(inputs()));
  });

  test('sections go in the fixed order of §11.5', () {
    expect(systemPromptSections(inputs(mode: ModeId.plan)), [
      'system.base',
      'system.untrusted',
      'modes.plan',
      'tools.read',
      'tools.edit',
      'tools.listing',
      'tools.exec',
      'tools.plan',
    ]);
  });

  test('base gets cwd, the date, the platform and the mode', () {
    final text = composeSystemPrompt(inputs());

    expect(text, contains('Workspace: /proj'));
    expect(text, contains('Today: 2026-01-15'));
    expect(text, contains('Platform: linux'));
    expect(text, contains('Mode: standard'));
    expect(text, endsWith('\n'));
    expect(text, isNot(endsWith('\n\n')));
  });

  test('capabilities that are off give no sections (HOST-4)', () {
    final profile = HostProfile.of('agent-serve').narrowed(const {
      HostCapability.shellExec: CapabilityOff('test'),
      HostCapability.fileListing: CapabilityOff('test'),
    });

    final sections = systemPromptSections(
      PromptInputs(
        cwd: '/proj',
        platform: 'linux',
        today: DateTime.utc(2026),
        mode: ModeId.standard,
        profile: profile,
        toolNames: allTools,
      ),
    );

    expect(sections, isNot(contains('tools.exec')));
    expect(sections, isNot(contains('tools.listing')));
  });
}
