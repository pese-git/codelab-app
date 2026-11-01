import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../permissions/fake_gate.dart';
import '../support/package_dir.dart';
import '../tools/fake_shell.dart';
import 'core_harness.dart';

void main() {
  test(
    'every capability of a profile has an explicit state with a reason (HOST-1)',
    () {
      for (final name in [
        'agent-serve',
        'embedded-app-desktop',
        'embedded-cli',
      ]) {
        final profile = HostProfile.of(name);

        expect(profile.name, name);
        expect(profile.states.keys.toSet(), HostCapability.values.toSet());
        for (final state in profile.states.values) {
          switch (state) {
            case CapabilityOn():
              break;
            case CapabilityOff(:final reason) ||
                CapabilityTransport(:final reason):
              expect(reason, isNotEmpty);
          }
        }
        expect(profile.defaultMode, ModeId.standard);
      }
    },
  );

  test('the transports of §10.4', () {
    final serve = HostProfile.of('agent-serve');
    final cli = HostProfile.of('embedded-cli');

    expect(
      (serve.states[HostCapability.shellExec]! as CapabilityTransport)
          .transports,
      {'acp-terminal', 'local'},
    );
    expect(
      (cli.states[HostCapability.shellExec]! as CapabilityTransport).transports,
      {'local'},
    );
    expect(
      (cli.states[HostCapability.interactiveApproval]! as CapabilityTransport)
          .transports,
      {'acp'},
    );
  });

  test('the journal and compaction of stage 3 (§10.4)', () {
    for (final name in [
      'agent-serve',
      'embedded-app-desktop',
      'embedded-cli',
    ]) {
      final profile = HostProfile.of(name);

      expect(
        (profile.states[HostCapability.sessionPersistence]!
                as CapabilityTransport)
            .transports,
        {'jsonl-file'},
        reason: name,
      );
      expect(
        profile.states[HostCapability.compaction],
        isA<CapabilityOn>(),
        reason: name,
      );
    }
  });

  test('an unknown profile is an ArgumentError', () {
    expect(() => HostProfile.of('mainframe'), throwsArgumentError);
  });

  test('narrowed only narrows (HOST-2)', () {
    final profile = HostProfile.of('agent-serve');

    final off = profile.narrowed({
      HostCapability.shellExec: const CapabilityOff('флаг --no-exec'),
    });
    final local = profile.narrowed({
      HostCapability.shellExec: const CapabilityTransport({
        'local',
      }, 'флаг --local-exec'),
    });

    expect(off.states[HostCapability.shellExec], isA<CapabilityOff>());
    expect(
      (local.states[HostCapability.shellExec]! as CapabilityTransport)
          .transports,
      {'local'},
    );
    expect(
      () => off.narrowed({HostCapability.shellExec: const CapabilityOn()}),
      throwsA(
        isA<HostWiringException>().having(
          (e) => e.message,
          'message',
          contains('shellExec'),
        ),
      ),
    );
    expect(
      () => local.narrowed({
        HostCapability.shellExec: const CapabilityTransport({
          'local',
          'ssh',
        }, 'x'),
      }),
      throwsA(isA<HostWiringException>()),
    );
  });

  test('mcp: {stdio, http} in both profiles (design.md change '
      'add-agent-mcp-client, D3)', () {
    for (final name in [
      'agent-serve',
      'embedded-app-desktop',
      'embedded-cli',
    ]) {
      final state = HostProfile.of(name).states[HostCapability.mcp];

      expect(state, isA<CapabilityTransport>(), reason: name);
      expect((state! as CapabilityTransport).transports, {'stdio', 'http'});
      expect((state as CapabilityTransport).reason, isNotEmpty);
    }
  });

  test('the MCP transports narrow to a subset but never widen back', () {
    final http = HostProfile.of('agent-serve').narrowed({
      HostCapability.mcp: const CapabilityTransport({'http'}, 'только http'),
    });

    expect(
      (http.states[HostCapability.mcp]! as CapabilityTransport).transports,
      {'http'},
    );
    expect(
      () => http.narrowed({
        HostCapability.mcp: const CapabilityTransport({
          'http',
          'stdio',
        }, 'назад'),
      }),
      throwsA(
        isA<HostWiringException>().having(
          (e) => e.message,
          'message',
          contains('mcp'),
        ),
      ),
    );
  });

  group('embedded-app-desktop (§10.4; design.md change '
      'add-embedded-agent-mode, D4)', () {
    /// Описание состояния capability для сравнения и golden-файла.
    Map<String, Object?> describeState(CapabilityState state) =>
        switch (state) {
          CapabilityOn() => {'state': 'on'},
          CapabilityOff(:final reason) => {'state': 'off', 'reason': reason},
          CapabilityTransport(:final transports, :final reason) => {
            'state': 'transport',
            'transports': (transports.toList()..sort()),
            'reason': reason,
          },
        };

    /// Матрица профиля: состояния capability и режим по умолчанию, а по
    /// собранному ядру — инструменты со схемами, секции промпта и slash-команды.
    /// Имя профиля в матрицу не входит: паритет — это равенство остального.
    Future<Map<String, Object?>> matrixOf(String name) async {
      final profile = HostProfile.of(name);
      final h = CoreHarness.build(
        profile: name,
        baseEnv: FakeShellEnv(MemoryExecutionEnv(cwd: '/proj'), answering('')),
        narrow: inMemoryJournal,
        gate: FakeGate(),
        steps: [textStep('ok')],
      );
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      await session.prompt([const TextContent('hi')]);
      return {
        'defaultMode': profile.defaultMode.value,
        'capabilities': {
          for (final c in HostCapability.values)
            c.name: describeState(profile.states[c]!),
        },
        'toolNames': h.core.plan.toolNames,
        'promptSections': h.core.plan.promptSections,
        'tools': [
          for (final t in h.requestedContexts.single.tools)
            {
              'name': t.name,
              'description': t.description,
              'parameters': t.parameters,
            },
        ],
        'commands': [
          for (final c in session.commands)
            {'name': c.name, 'description': c.description},
        ],
      };
    }

    test('states and the default mode match embedded-cli', () {
      final app = HostProfile.of('embedded-app-desktop');
      final cli = HostProfile.of('embedded-cli');

      expect(app.name, 'embedded-app-desktop');
      expect(app.defaultMode, cli.defaultMode);
      expect(app.states.keys.toSet(), cli.states.keys.toSet());
      for (final capability in HostCapability.values) {
        expect(
          describeState(app.states[capability]!),
          describeState(cli.states[capability]!),
          reason: capability.name,
        );
      }
    });

    test(
      'the golden matrix matches test/host/profiles/ and embedded-cli',
      () async {
        final app = await matrixOf('embedded-app-desktop');
        final cli = await matrixOf('embedded-cli');
        final text = '${const JsonEncoder.withIndent('  ').convert(app)}\n';
        final file = File(
          corePath('test/host/profiles/embedded-app-desktop.golden.json'),
        );
        if (Platform.environment['UPDATE_GOLDEN'] == '1') {
          file.createSync(recursive: true);
          file.writeAsStringSync(text);
        }

        expect(
          file.existsSync(),
          isTrue,
          reason: 'UPDATE_GOLDEN=1 создаёт файл',
        );
        expect(text, file.readAsStringSync());
        expect(app, cli);
      },
    );
  });
}
