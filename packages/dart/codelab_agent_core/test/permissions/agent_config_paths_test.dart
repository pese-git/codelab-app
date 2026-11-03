import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/edit.dart';
import 'package:codelab_agent_core/src/tools/builtin/exec.dart';
import 'package:codelab_agent_core/src/tools/builtin/read.dart';
import 'package:codelab_agent_core/src/tools/builtin/write.dart';
import 'package:test/test.dart';

import '../env/resolving_env.dart';
import '../tools/executor_harness.dart';
import '../tools/fake_shell.dart';
import 'fake_gate.dart';
import 'policy_harness.dart';

const _paths = [
  '.codelab/config.yaml',
  '.codelab/config.local.yaml',
  '.codelab/cli.yaml',
  '.codelab/agents/x.md',
  '.codelab/skills/s/SKILL.md',
  '.codelab/prompts/p.md',
  '.codelab/hooks/pre.sh',
];

Future<(PolicyHarness, MemoryExecutionEnv)> _harness({
  ModeId mode = ModeId.bypass,
  PermissionMode? modeOverride,
  PermissionGate? gate,
}) async {
  final memory = MemoryExecutionEnv(cwd: '/proj');
  for (final path in _paths) {
    await memory.writeText('/proj/$path', 'old\n');
  }
  final h = await ExecutorHarness.create([
    ReadTool(),
    WriteTool(),
    EditTool(),
    ExecTool(),
  ], base: FakeShellEnv(memory, answering('')));
  final p = await PolicyHarness.wrap(
    h,
    mode: mode,
    modeOverride: modeOverride,
    gate: gate,
  );
  return (p, memory);
}

String _requiresHuman(String tool, String path) =>
    deniedText(tool, 'Editing agent configuration requires a human: $path');

void main() {
  // Критические пути правок конфигурации агента (§7.6.1, PERM-11).
  for (final mode in [ModeId.bypass, ModeId.acceptEdits]) {
    test('write and edit ask in ${mode.value} without allow_always', () async {
      final gate = FakeGate((_) => PermissionDecision.allowAlways);
      final (p, _) = await _harness(mode: mode, gate: gate);

      for (final (i, path) in _paths.indexed) {
        await p.run('write', {'path': path, 'content': 'x'}, id: 'w$i');
        await p.run('edit', {
          'path': './$path',
          'oldText': 'x',
          'newText': 'y',
        }, id: 'e$i');
      }

      expect(gate.requests, hasLength(_paths.length * 2));
      expect(
        gate.requests.map((r) => r.allowAlwaysOffered),
        everyElement(isFalse),
      );
    });
  }

  test('allow-always granted earlier does not apply to the path', () async {
    final gate = FakeGate();
    final (p, _) = await _harness(gate: gate);
    p.policy.decisions.allowAlways.add(
      const PermissionKey('write', '.codelab/config.yaml'),
    );

    await p.run('write', {'path': '.codelab/config.yaml', 'content': 'x'});

    expect(gate.requests, hasLength(1));
  });

  test('without a gate and in autopilot the edit is denied', () async {
    final (headless, _) = await _harness();
    final (autopilot, _) = await _harness(
      modeOverride: PermissionMode.autopilot,
      gate: FakeGate(),
    );

    final a = await headless.run('write', {
      'path': '.codelab/agents/x.md',
      'content': 'x',
    });
    final b = await autopilot.run('edit', {
      'path': '.codelab/config.yaml',
      'oldText': 'old',
      'newText': 'new',
    });

    expect(textOf(a), _requiresHuman('write', '.codelab/agents/x.md'));
    expect(textOf(b), _requiresHuman('edit', '.codelab/config.yaml'));
  });

  test('read of agent configuration is not restricted', () async {
    final gate = FakeGate();
    final (p, _) = await _harness(gate: gate);

    final outcome = await p.run('read', {'path': '.codelab/config.yaml'});

    expect(gate.requests, isEmpty);
    expect(outcome.outcome, ToolOutcome.completed);
  });

  test('other .codelab files and look-alikes are ordinary', () async {
    final gate = FakeGate();
    final (p, _) = await _harness(gate: gate);

    for (final (i, path) in [
      '.codelab/notes.md',
      'codelab/config.yaml',
      'lib/.codelab/config.yaml',
    ].indexed) {
      await p.run('write', {'path': path, 'content': 'x'}, id: 'o$i');
    }

    expect(gate.requests, isEmpty);
  });

  test('exec writing into agent configuration is critical', () async {
    final gate = FakeGate();
    final (p, _) = await _harness(gate: gate);

    for (final (i, command) in [
      'echo x >> .codelab/config.yaml',
      'tee .codelab/cli.yaml',
      'cp evil.md .codelab/agents/',
      'ln -s /tmp/x .codelab/hooks/pre.sh',
      "sed -i 's/a/b/' .codelab/config.yaml",
    ].indexed) {
      await p.run('exec', {'command': command}, id: 'x$i');
    }

    expect(
      gate.requests.map((r) => r.reason),
      everyElement('critical command: write to agent configuration'),
    );
    expect(gate.requests, hasLength(5));
  });

  group('paths from the host (agentConfigPaths, D8)', _hostPathsTests);
}

// Пути конфигурации агента от хоста (PERM-11, §7.6.1, design.md change
// `add-config-writer-and-reload`, D8). Сессия открыта в `/proj`, корень
// запуска агента — `/launch`, `$CODELAB_HOME` — `/home/me/.codelab`.
const _home = '/home/me';
const _codelabHome = '/home/me/.codelab';

AgentConfigPaths _hostConfig({
  bool caseInsensitive = false,
  List<String> extra = const [],
}) => AgentConfigPaths(
  paths: [
    '$_codelabHome/config.yaml',
    '$_codelabHome/secrets.yaml',
    '$_codelabHome/agents',
    '$_codelabHome/prompts',
    '/launch/.codelab/config.yaml',
    '/launch/.codelab/config.local.yaml',
    '/etc/codelab/agent.yaml',
    ...extra,
  ],
  expansions: {'HOME': _home, 'CODELAB_HOME': _codelabHome},
  caseInsensitive: caseInsensitive,
);

Future<(PolicyHarness, ResolvingEnv)> _hostHarness({
  ModeId mode = ModeId.bypass,
  PermissionMode? modeOverride,
  PermissionGate? gate,
  AgentConfigPaths? config,
  bool withConfig = true,
  Map<String, String>? links,
  String cwd = '/proj',
}) async {
  final memory = MemoryExecutionEnv(cwd: cwd);
  final env = ResolvingEnv(memory, links: links ?? {});
  final h = await ExecutorHarness.create([
    ReadTool(),
    WriteTool(),
    EditTool(),
    ExecTool(),
  ], base: env);
  final p = await PolicyHarness.wrap(
    h,
    mode: mode,
    modeOverride: modeOverride,
    gate: gate,
    agentConfigPaths: withConfig ? config ?? _hostConfig() : null,
    pathResolver: env,
  );
  return (p, env);
}

const _writeLabel = 'critical command: write to agent configuration';

void _hostPathsTests() {
  const targets = [
    '~/.codelab/config.yaml',
    '$_codelabHome/secrets.yaml',
    '$_codelabHome/agents/x.md',
    '$_codelabHome/prompts/sub/p.md',
    '/etc/codelab/agent.yaml',
    '/launch/.codelab/config.local.yaml',
    '../launch/.codelab/config.yaml',
  ];

  for (final mode in [ModeId.bypass, ModeId.acceptEdits]) {
    test('write and edit of host paths ask in ${mode.value}', () async {
      final gate = FakeGate((_) => PermissionDecision.allowAlways);
      final (p, _) = await _hostHarness(mode: mode, gate: gate);

      for (final (i, path) in targets.indexed) {
        await p.run('write', {'path': path, 'content': 'x'}, id: 'w$i');
        await p.run('edit', {
          'path': path,
          'oldText': 'x',
          'newText': 'y',
        }, id: 'e$i');
      }

      expect(gate.requests, hasLength(targets.length * 2));
      expect(
        gate.requests.map((r) => r.allowAlwaysOffered),
        everyElement(isFalse),
      );
    });
  }

  test('allow-always earlier does not apply to a host path', () async {
    final gate = FakeGate();
    final (p, _) = await _hostHarness(gate: gate);
    p.policy.decisions.allowAlways.add(
      const PermissionKey('write', '$_codelabHome/config.yaml'),
    );

    await p.run('write', {'path': '~/.codelab/config.yaml', 'content': 'x'});

    expect(gate.requests, hasLength(1));
  });

  test('autopilot and no gate deny the edit of a host path', () async {
    final (headless, _) = await _hostHarness();
    final (autopilot, _) = await _hostHarness(
      modeOverride: PermissionMode.autopilot,
      gate: FakeGate(),
    );

    final a = await headless.run('write', {
      'path': '~/.codelab/config.yaml',
      'content': 'x',
    });
    final b = await autopilot.run('edit', {
      'path': '/etc/codelab/agent.yaml',
      'oldText': 'old',
      'newText': 'new',
    });

    expect(textOf(a), _requiresHuman('write', '$_codelabHome/config.yaml'));
    expect(textOf(b), _requiresHuman('edit', '/etc/codelab/agent.yaml'));
  });

  test(
    'reading and ordinary paths outside the root are not restricted',
    () async {
      final gate = FakeGate();
      final (p, _) = await _hostHarness(gate: gate);

      await p.run('read', {'path': '$_codelabHome/config.yaml'}, id: 'r1');
      await p.run('write', {'path': '/home/me/notes.md', 'content': 'x'});
      await p.run('exec', {'command': 'cat ~/.codelab/config.yaml'}, id: 'x1');
      await p.run('exec', {'command': 'ls ~/.codelab'}, id: 'x2');

      expect(gate.requests, isEmpty);
    },
  );

  test('without agentConfigPaths host paths stay ordinary', () async {
    final gate = FakeGate();
    final (p, _) = await _hostHarness(gate: gate, withConfig: false);

    await p.run('write', {'path': '$_codelabHome/config.yaml', 'content': 'x'});
    await p.run('exec', {
      'command': 'echo x > ~/.codelab/config.yaml',
    }, id: 'x');

    expect(gate.requests, isEmpty);
  });

  test('case differs: asks only with caseInsensitive', () async {
    final sensitive = FakeGate();
    final insensitive = FakeGate();
    final (a, _) = await _hostHarness(gate: sensitive);
    final (b, _) = await _hostHarness(
      gate: insensitive,
      config: _hostConfig(caseInsensitive: true),
    );
    const path = '/Home/ME/.CodeLab/Config.YAML';

    await a.run('write', {'path': path, 'content': 'x'});
    await b.run('write', {'path': path, 'content': 'x'});
    await b.run('exec', {'command': 'echo x > /HOME/me/.codelab/CONFIG.yaml'});

    expect(sensitive.requests, isEmpty);
    expect(insensitive.requests, hasLength(2));
  });

  test('symlink dotfiles: the target of the link is protected', () async {
    final gate = FakeGate();
    final dotfiles = '$_home/dotfiles/codelab.yaml';
    // Хост передал канонический путь цели ссылки.
    final (canonical, _) = await _hostHarness(
      gate: gate,
      config: _hostConfig(extra: [dotfiles]),
    );
    await canonical.run('edit', {
      'path': '~/dotfiles/codelab.yaml',
      'oldText': 'a',
      'newText': 'b',
    });
    expect(gate.requests, hasLength(1));

    // Ссылка появилась после старта: путь, как его знал хост, сам
    // раскрывается при проверке.
    final late = FakeGate();
    final (p, env) = await _hostHarness(
      gate: late,
      links: {'$_codelabHome/config.yaml': dotfiles},
    );
    await env.inner.writeText(dotfiles, 'old');
    await p.run('edit', {'path': dotfiles, 'oldText': 'old', 'newText': 'new'});
    expect(late.requests, hasLength(1));
  });

  test(
    'the launch config is protected from a session with another cwd',
    () async {
      final gate = FakeGate();
      final (p, _) = await _hostHarness(gate: gate, cwd: '/other/deep');

      await p.run('write', {
        'path': '/launch/.codelab/config.local.yaml',
        'content': 'x',
      });
      await p.run('write', {
        'path': '../../launch/.codelab/config.yaml',
        'content': 'x',
      }, id: 'w2');
      await p.run('write', {
        'path': '/etc/codelab/agent.yaml',
        'content': 'x',
      }, id: 'w3');

      expect(gate.requests, hasLength(3));
    },
  );

  test('a ".codelab" replaced by a link after start does not escape', () async {
    final gate = FakeGate();
    final (p, env) = await _hostHarness(
      gate: gate,
      config: _hostConfig(extra: ['/proj/.codelab/config.yaml']),
    );
    await env.inner.writeText('/proj/sub/keep.txt', 'k');

    await p.run('write', {'path': 'sub/config.yaml', 'content': 'x'}, id: 'a');
    expect(gate.requests, isEmpty, reason: 'sub is an ordinary directory');

    // Человек одобрил `ln -s sub .codelab`: каталог подменён ссылкой.
    env.links['/proj/.codelab'] = '/proj/sub';
    await p.run('write', {'path': 'sub/config.yaml', 'content': 'x'}, id: 'b');
    await p.run('edit', {
      'path': 'sub/config.yaml',
      'oldText': 'x',
      'newText': 'y',
    }, id: 'c');

    expect(gate.requests, hasLength(2));
    expect(
      gate.requests.map((r) => r.allowAlwaysOffered),
      everyElement(isFalse),
    );
  });

  test('exec writing into host paths is critical', () async {
    final gate = FakeGate();
    final (p, _) = await _hostHarness(gate: gate);
    final commands = [
      'echo x > ~/.codelab/config.yaml',
      r'echo x >> $HOME/.codelab/config.yaml',
      r'echo x > ${HOME}/.codelab/secrets.yaml',
      r'echo x | tee $CODELAB_HOME/secrets.yaml',
      r'echo x | tee ${CODELAB_HOME}/secrets.yaml',
      'cp /tmp/c.yaml ~/.codelab/config.yaml',
      'cp evil.md ~/.codelab/agents/',
      'mv /tmp/c.yaml ~/.codelab/config.yaml',
      'mv ~/.codelab/config.yaml /tmp/saved.yaml',
      'rename s/a/b/ /home/me/.codelab/config.yaml',
      r'ln -sf /tmp/c.yaml ${HOME}/.codelab/config.yaml',
      'install -m 600 /tmp/c.yaml ~/.codelab/config.yaml',
      'dd if=/tmp/c.yaml of=~/.codelab/config.yaml',
      r"sed -i 's/a/b/' $CODELAB_HOME/config.yaml",
      'cd ~/.codelab && echo x > config.yaml',
      'cd ~/.codelab/agents; tee x.md',
      'echo x > ../launch/.codelab/config.yaml',
      'echo x > /etc/codelab/agent.yaml',
      "sh -c 'echo x > ~/.codelab/config.yaml'",
      'echo x > ../home/me/.codelab/config.yaml',
    ];

    for (final (i, command) in commands.indexed) {
      await p.run('exec', {'command': command}, id: 'x$i');
    }

    expect(gate.requests.map((r) => r.reason), everyElement(_writeLabel));
    expect(gate.requests.map((r) => r.rawInput['command']), commands);
    expect(
      gate.requests.map((r) => r.allowAlwaysOffered),
      everyElement(isFalse),
    );
  });

  test('exec uses the cwd argument of the command', () async {
    final gate = FakeGate();
    final (p, _) = await _hostHarness(gate: gate);

    await p.run('exec', {
      'command': 'echo x > config.yaml',
      'cwd': '../home/me/.codelab',
    });

    expect(gate.requests, hasLength(1));
  });

  test('exec that only reads or writes elsewhere is ordinary', () async {
    final gate = FakeGate();
    final (p, _) = await _hostHarness(gate: gate);
    final commands = [
      'cat ~/.codelab/config.yaml',
      'cd ~/.codelab && cat config.yaml',
      'echo x > /tmp/ok.yaml',
      'echo x > ~/.codelab-other/config.yaml',
      r'echo x > $OTHER/.codelab/config.yaml',
      'ln /tmp/a /tmp/b',
      'mkdir -p /tmp/work',
    ];

    for (final (i, command) in commands.indexed) {
      await p.run('exec', {'command': command}, id: 'x$i');
    }

    expect(gate.requests, isEmpty);
  });

  test('exec in autopilot and without a gate is refused', () async {
    final (autopilot, _) = await _hostHarness(
      modeOverride: PermissionMode.autopilot,
      gate: FakeGate(),
    );
    final (headless, _) = await _hostHarness();

    final a = await autopilot.run('exec', {
      'command': 'echo x > ~/.codelab/config.yaml',
    });
    final b = await headless.run('exec', {
      'command': 'echo x > ~/.codelab/config.yaml',
    });

    expect(
      textOf(a),
      deniedText(
        'exec',
        'critical command blocked in autopilot: write to agent configuration',
      ),
    );
    expect(textOf(b), deniedText('exec', 'no approval interface is available'));
  });

  test('hard links to a protected path are critical in any position', () async {
    final gate = FakeGate();
    final (p, _) = await _hostHarness(gate: gate);
    final commands = [
      'ln ~/.codelab/config.yaml /tmp/c.yaml',
      'ln /tmp/c.yaml ~/.codelab/config.yaml',
      'ln -f ~/.codelab/secrets.yaml /tmp/s.yaml',
      'cp -l ~/.codelab/config.yaml /tmp/c.yaml',
      'cp --link ~/.codelab/config.yaml /tmp/c.yaml',
      'cp -al /tmp/c.yaml ~/.codelab/config.yaml',
      'cp -l /launch/.codelab/config.yaml /tmp/c.yaml',
    ];

    for (final (i, command) in commands.indexed) {
      await p.run('exec', {'command': command}, id: 'x$i');
    }

    expect(gate.requests.map((r) => r.reason), everyElement(_writeLabel));
    expect(gate.requests, hasLength(commands.length));
  });

  test('ancestor directories are protected from replacement', () async {
    final gate = FakeGate();
    final (p, _) = await _hostHarness(gate: gate);
    final commands = [
      'ln -s sub /launch/.codelab',
      'mv /launch/.codelab /launch/old',
      'mv /tmp/evil /launch/.codelab',
      'rm -rf ~/.codelab',
      r'rm -rf $CODELAB_HOME',
      'rmdir ~/.codelab',
      'mkdir ~/.codelab',
      'mkdir -p /launch/.codelab',
      'ln -s sub .codelab',
      'mv .codelab x',
      'mkdir .codelab',
    ];

    for (final (i, command) in commands.indexed) {
      await p.run('exec', {'command': command}, id: 'x$i');
    }

    expect(gate.requests.map((r) => r.reason), everyElement(_writeLabel));
    expect(gate.requests, hasLength(commands.length));
  });

  test('look-alike directories are not ancestors', () async {
    final gate = FakeGate();
    final (p, _) = await _hostHarness(gate: gate);

    for (final (i, command) in [
      'mkdir ~/.codelab-other',
      'rm -rf /launch/.codelab-old',
      'mkdir /launch-other',
    ].indexed) {
      await p.run('exec', {'command': command}, id: 'x$i');
    }

    expect(gate.requests, isEmpty);
  });

  test('a link to the protected place does not hide the target', () async {
    final gate = FakeGate();
    final (p, env) = await _hostHarness(
      gate: gate,
      links: {'/tmp/c': _codelabHome, '/var/home': _home},
    );
    await env.inner.writeText('$_codelabHome/config.yaml', 'old');

    await p.run('exec', {'command': 'echo x > /tmp/c/config.yaml'}, id: 'a');
    await p.run('write', {
      'path': '/tmp/c/config.yaml',
      'content': 'x',
    }, id: 'b');

    expect(gate.requests, hasLength(2));
  });

  test('deleting or corrupting a protected file is critical', () async {
    final gate = FakeGate();
    final (p, _) = await _hostHarness(gate: gate);
    final commands = [
      'rm ~/.codelab/config.yaml',
      r'rm -f $HOME/.codelab/secrets.yaml',
      r'rm ${CODELAB_HOME}/config.yaml',
      r'rm -rf $CODELAB_HOME/agents',
      'rm /launch/.codelab/config.local.yaml',
      'rm ../launch/.codelab/config.yaml',
      'unlink ~/.codelab/config.yaml',
      'truncate -s 0 ~/.codelab/config.yaml',
      r'truncate --size=0 $CODELAB_HOME/secrets.yaml',
      ': > ~/.codelab/config.yaml',
      '> /etc/codelab/agent.yaml',
      'mv ~/.codelab/config.yaml /tmp/gone.yaml',
      'cd ~/.codelab && rm config.yaml',
      'cd ~/.codelab/agents && rm x.md',
      'cd /launch/.codelab && unlink config.yaml',
      'cd ~/.codelab && truncate -s 0 secrets.yaml',
      'cd ~ && rm .codelab/config.yaml',
    ];

    for (final (i, command) in commands.indexed) {
      await p.run('exec', {'command': command}, id: 'x$i');
    }

    expect(gate.requests.map((r) => r.reason), everyElement(_writeLabel));
    expect(gate.requests.map((r) => r.rawInput['command']), commands);
  });

  test('removing ordinary files is not critical', () async {
    final gate = FakeGate();
    final (p, _) = await _hostHarness(gate: gate);

    for (final (i, command) in [
      'rm /tmp/x.yaml',
      'unlink notes.md',
      'truncate -s 0 /tmp/log',
      'cd /tmp && rm config.yaml',
    ].indexed) {
      await p.run('exec', {'command': command}, id: 'x$i');
    }

    expect(gate.requests, isEmpty);
  });

  test('exec through a link to a protected file is critical', () async {
    final gate = FakeGate();
    final (p, env) = await _hostHarness(
      gate: gate,
      config: _hostConfig(extra: ['/proj/.codelab/config.yaml']),
      links: {
        '/proj/c.yaml': '/proj/.codelab/config.yaml',
        '/tmp/x': '$_codelabHome/config.yaml',
      },
    );
    await env.inner.writeText('/proj/.codelab/config.yaml', 'old');
    await env.inner.writeText('$_codelabHome/config.yaml', 'old');
    final commands = [
      for (final link in ['c.yaml', '/tmp/x']) ...[
        'echo x > $link',
        'echo x | tee $link',
        "sed -i 's/a/b/' $link",
        'rm $link',
        'truncate -s0 $link',
      ],
    ];

    for (final (i, command) in commands.indexed) {
      await p.run('exec', {'command': command}, id: 'x$i');
    }

    expect(gate.requests.map((r) => r.reason), everyElement(_writeLabel));
    expect(gate.requests.map((r) => r.rawInput['command']), commands);
  });

  test(
    'every ancestor of a protected path is protected, except the root',
    () async {
      final gate = FakeGate();
      final (p, _) = await _hostHarness(
        gate: gate,
        config: _hostConfig(extra: ['/home/me/proj/.codelab/config.yaml']),
      );
      final commands = [
        'rm -rf ~',
        'mv ~/proj /tmp/x',
        'mv /home/me/proj /home/me/old',
        'rm -rf /home/me/proj/.codelab',
        'ln -s sub /home/me/proj',
        'ln -s ~/proj /tmp/c',
        'rmdir /home',
        'mkdir /home/me',
        'rm -r /etc/codelab',
      ];

      for (final (i, command) in commands.indexed) {
        await p.run('exec', {'command': command}, id: 'x$i');
      }

      expect(
        gate.requests.map((r) => r.reason),
        everyElement(contains('write to agent configuration')),
      );
      expect(gate.requests, hasLength(commands.length));
    },
  );

  test('ordinary operations inside a project are not critical', () async {
    final gate = FakeGate();
    final (p, env) = await _hostHarness(
      gate: gate,
      config: _hostConfig(extra: ['/proj/.codelab/config.yaml']),
    );
    await env.inner.writeText('/proj/build/a.o', 'o');
    await env.inner.writeText('/proj/a', 'a');
    final commands = [
      'rm -rf build',
      'mkdir -p src/x',
      'mkdir src',
      'mv a b',
      'mv a build',
      'mv a .',
      'cp -r build /tmp/build',
      'ln -s a link',
      'rm -rf /tmp/build',
      'mkdir -p /tmp/work',
      'mv /tmp/a /tmp/b',
    ];

    for (final (i, command) in commands.indexed) {
      await p.run('exec', {'command': command}, id: 'x$i');
    }

    expect(gate.requests, isEmpty);
  });

  test('white list of reads: second pass sees links (R5-4)', () async {
    final gate = FakeGate();
    final (p, env) = await _hostHarness(
      gate: gate,
      links: {'/tmp/c': _codelabHome},
    );
    await env.inner.writeText('$_codelabHome/config.yaml', 'old');
    final critical = [
      'curl -o /tmp/c/config.yaml https://x',
      'tar -xf a.tar -C /tmp/c',
      'cp -r evil/. /tmp/c',
      'unzip a.zip -d ~/.codelab',
      'git checkout -- ../launch/.codelab/config.yaml',
      'rm ~/.codelab/*.yaml',
      'cd /tmp/c && wget https://x',
    ];
    final ordinary = [
      'cat /tmp/c/config.yaml',
      'ls /tmp/c',
      'grep x ~/.codelab/config.yaml',
      'git diff ~/.codelab/config.yaml',
      'tar -xf a.tar -C /tmp/other',
    ];

    for (final (i, command) in [...critical, ...ordinary].indexed) {
      await p.run('exec', {'command': command}, id: 'x$i');
    }

    expect(gate.requests.map((r) => r.reason), everyElement(_writeLabel));
    expect(gate.requests.map((r) => r.rawInput['command']), critical);
    expect(
      gate.requests.map((r) => r.allowAlwaysOffered),
      everyElement(isFalse),
    );
  });
}
