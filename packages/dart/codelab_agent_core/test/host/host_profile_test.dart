import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'every capability of a profile has an explicit state with a reason (HOST-1)',
    () {
      for (final name in ['agent-serve', 'embedded-cli']) {
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
    for (final name in ['agent-serve', 'embedded-cli']) {
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
    for (final name in ['agent-serve', 'embedded-cli']) {
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
}
