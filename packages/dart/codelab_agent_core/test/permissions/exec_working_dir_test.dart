// Рабочий каталог команды `exec` при проверке PERM-11 (спецификация
// `agent-permissions`, требование «Рабочий каталог команды exec при проверке
// PERM-11»; change `harden-exec-cwd-tracking`, D1–D11;
// `agent-core/07-permissions.md` §7.6.2).
//
// Тесты — чистый Dart через `findCritical`; политика целиком (`bypass`,
// `autopilot`, вторая фаза канонизации ссылок) — через `PolicyHarness`.
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/permissions/agent_config_paths.dart';
import 'package:codelab_agent_core/src/permissions/critical_patterns.dart';
import 'package:codelab_agent_core/src/tools/builtin/exec.dart';
import 'package:test/test.dart';

import '../env/resolving_env.dart';
import '../tools/executor_harness.dart';
import '../tools/fake_shell.dart';
import 'fake_gate.dart';
import 'policy_harness.dart';

const _root = '/work/demo';

/// Каталог навыка проекта: защищён без хостовых путей (`.codelab/skills`).
const _skill = '$_root/.codelab/skills/pdf';
const _config = 'write to agent configuration';

/// Один предел времени разбора для всех проверок размера, глубины и работы.
const _parseLimit = Duration(seconds: 1);

/// Метки команды; проверяет, что разбор уложился в [_parseLimit].
Future<List<String>?> timed(String command, {bool host = false}) async {
  final watch = Stopwatch()..start();
  final labels = await _labels(command, host: host);
  expect(watch.elapsed, lessThan(_parseLimit), reason: 'slow command');
  return labels;
}

const _unknown = 'write in unknown working directory';

final _hostPaths = AgentConfigPaths(
  paths: ['/home/u/.codelab/config.yaml', '/home/u/.codelab/agents'],
  expansions: {'HOME': '/home/u', 'CODELAB_HOME': '/home/u/.codelab'},
);

/// Метки команды в сессии с корнем [_root]; [host] добавляет пути хоста.
Future<List<String>?> _labels(
  String command, {
  bool host = false,
  String? cwd,
}) async {
  final scope = host ? await AgentConfigScope.resolve(_hostPaths, null) : null;
  return findCritical(
    command,
    cwd: _root,
    commandCwd: cwd,
    agentConfig: scope,
  )?.labels;
}

Future<void> _expectLabels(
  Iterable<String> commands,
  List<String> labels, {
  bool host = false,
}) async {
  for (final command in commands) {
    expect(await _labels(command, host: host), labels, reason: command);
  }
}

Future<void> _expectOrdinary(
  Iterable<String> commands, {
  bool host = false,
}) async {
  for (final command in commands) {
    expect(await _labels(command, host: host), isNull, reason: command);
  }
}

/// Политика над `exec` с корнем [_root] и пользовательским gate.
Future<PolicyHarness> _policy({
  ModeId mode = ModeId.bypass,
  PermissionMode? modeOverride,
  PermissionGate? gate,
}) async {
  final shell = FakeShellEnv(MemoryExecutionEnv(cwd: _root), answering(''));
  final h = await ExecutorHarness.create([ExecTool()], base: shell);
  return PolicyHarness.wrap(
    h,
    mode: mode,
    modeOverride: modeOverride,
    gate: gate,
  );
}

void main() {
  group('cd -, popd, CDPATH (примеры 1–4)', () {
    test('cd - после смены каталога возвращает в каталог навыка', () async {
      await _expectLabels(
        [
          'cd $_skill; cd /tmp; cd -; touch SKILL.md',
          'cd $_skill && cd /tmp && cd - && touch SKILL.md',
        ],
        [_config],
      );
    });

    test('сценарий «cd - после смены каталога» в bypass и autopilot', () async {
      const command = 'cd $_skill; cd /tmp; cd -; touch SKILL.md';
      final gate = FakeGate();
      final bypass = await _policy(gate: gate);
      await bypass.run('exec', {'command': command});
      expect(gate.requests, hasLength(1));
      expect(gate.requests.single.allowAlwaysOffered, isFalse);
      expect(
        gate.requests.single.reason,
        'critical command: write to agent configuration',
      );

      final autopilotGate = FakeGate();
      final autopilot = await _policy(
        modeOverride: PermissionMode.autopilot,
        gate: autopilotGate,
      );
      final outcome = await autopilot.run('exec', {'command': command});
      expect(autopilotGate.requests, isEmpty);
      expect(outcome.outcome, ToolOutcome.rejected);
      expect(
        textOf(outcome),
        deniedText(
          'exec',
          'critical command blocked in autopilot: '
              'write to agent configuration',
        ),
      );
    });

    test('popd возвращает в каталог навыка', () async {
      await _expectLabels(
        [
          'pushd $_skill; pushd /tmp; popd; touch SKILL.md',
          'pushd $_skill && pushd /tmp && popd && touch SKILL.md',
        ],
        [_config],
      );
    });

    test(
      'CDPATH в строке команды делает относительную цель неизвестной',
      () async {
        await _expectLabels(
          [
            'CDPATH=$_root/.codelab/skills cd pdf; touch SKILL.md',
            'export CDPATH="\$ROOT"; cd pdf && touch SKILL.md',
            'CD""PATH=/x; cd sub && touch f',
            'CDPATH=/x; eval "cd sub"; touch f',
          ],
          [_unknown],
        );
        // `./`, `../`, `.` и абсолютные цели от CDPATH не зависят (POSIX).
        await _expectOrdinary([
          'CDPATH=/x cd ./build && make',
          'CDPATH=/x cd ../up && make',
          'CDPATH=/x cd /tmp && make',
        ]);
      },
    );

    test('OLDPWD в строке делает cd - неизвестным', () async {
      await _expectLabels(['OLDPWD=$_skill; cd -; touch SKILL.md'], [_unknown]);
    });

    test('путь конфигурации хоста через cd - и popd', () async {
      await _expectLabels(
        [
          'cd ~/.codelab; cd /tmp; cd -; echo x > config.yaml',
          'pushd ~/.codelab/agents; pushd /tmp; popd; tee x.md',
          r'cd $HOME/.codelab; cd /tmp; cd -; echo x > config.yaml',
        ],
        [_config],
        host: true,
      );
    });
  });

  group('неизвестная цель cd и неудачный cd (примеры 5–6)', () {
    test('переменная, подстановка, ~user, env -C, sudo -D', () async {
      await _expectLabels(
        [
          r'cd $X && touch SKILL.md',
          r'cd "$(dirname "$F")" && sed -i s/a/b/ SKILL.md',
          'cd ~bob && make',
          r'env -C "$X" touch SKILL.md',
          'cd `pwd`/x && make',
          'cd * && make',
        ],
        [_unknown],
      );
      expect(await _labels(r'sudo -D "$X" make'), [
        'privileged command',
        _unknown,
      ]);
    });

    test('cd без аргумента и cd - без известного OLDPWD', () async {
      // HOME известен только хосту; без него — неизвестно.
      expect(await _labels('cd && make'), [_unknown]);
      expect(await _labels('cd - && make'), [_unknown]);
      // С хостом HOME известен и каталог точный.
      expect(await _labels('cd && make', host: true), isNull);
      expect(await _labels('cd; touch ~/.codelab/config.yaml', host: true), [
        _config,
      ]);
    });

    test('неудачный cd оставляет прежний каталог', () async {
      await _expectLabels(
        [
          'cd $_skill; cd /nonexistent; touch SKILL.md',
          'cd $_skill || cd /nonexistent; touch SKILL.md',
        ],
        [_config],
      );
      await _expectOrdinary([
        'cd $_skill && cd /nonexistent && touch SKILL.md',
        'cd /nonexistent && touch SKILL.md',
      ]);
    });

    test(
      'опции cd: -L, -P, -e, -@ и -- пропускаются, прочие — неизвестно',
      () async {
        await _expectLabels(
          [
            'cd -L $_skill && touch SKILL.md',
            'cd -P -- $_skill && touch SKILL.md',
            'cd -- $_skill && touch SKILL.md',
          ],
          [_config],
        );
        await _expectLabels(
          [
            'cd -Z /tmp && touch f',
            // Физический `..` идёт от цели ссылки, нормализация лексическая.
            'cd -P $_root/a/../b && touch f',
            'set -P; cd $_root/a/../b && touch f',
            'set -o physical; cd $_root/a/../b && touch f',
            'cd /a /b && touch f',
          ],
          [_unknown],
        );
        // `..` после обычной компоненты: цель может оказаться ссылкой, а bash
        // вне POSIX-режима откатывается к физическому `cd` (D17, A5).
        expect(await _labels('cd $_root/a/../b && touch f'), [_unknown]);
        // Ведущие `..` и `.` лексически точны.
        await _expectOrdinary(['cd ../x && touch f', 'cd ./a/./b && touch f']);
      },
    );

    test('pushd и popd с +N/-N, dirs с опциями — неизвестно', () async {
      await _expectLabels(
        [
          'pushd +1 && touch f',
          'popd -1 && touch f',
          'pushd /a; pushd /b; dirs -c; popd && touch f',
        ],
        [_unknown],
      );
    });

    test('pushd без аргумента меняет каталог и вершину стека', () async {
      await _expectLabels(
        ['pushd $_skill && pushd /tmp && pushd && touch SKILL.md'],
        [_config],
      );
      // Пустой стек — неуспех: `&&`-хвост недостижим, но ярлыки остаются.
      await _expectOrdinary(['pushd && touch SKILL.md']);
    });
  });

  group('блоки, лаунчеры и вложенные тексты (D6–D8)', () {
    test(
      'подоболочка, конвейер, фон и внешний лаунчер не меняют каталог',
      () async {
        await _expectLabels(
          [
            'cd $_skill; (cd /tmp); touch SKILL.md',
            'cd $_skill; cd /tmp | cat; touch SKILL.md',
            'cd $_skill; cd /tmp & touch SKILL.md',
            'cd $_skill; { cd /tmp; } | cat; touch SKILL.md',
            'cd $_skill && env cd /tmp && touch SKILL.md',
            'cd $_skill && nohup cd /tmp && touch SKILL.md',
            'cd $_skill && /usr/bin/cd /tmp && touch SKILL.md',
          ],
          [_config],
        );
        // `sudo cd` — внешняя программа: каталог тоже прежний; к метке каталога
        // добавляется привилегированная команда.
        expect(await _labels('cd $_skill && sudo cd /tmp && touch SKILL.md'), [
          'privileged command',
          _config,
        ]);
      },
    );

    test('группа вне конвейера меняет каталог текущей оболочки', () async {
      await _expectLabels(
        ['cd /tmp; { cd $_skill; }; touch SKILL.md'],
        [_config],
      );
      // Конец блока объединяет успех и неуспех: `cd /tmp` в группе мог не
      // удаться, и тогда оболочка осталась в каталоге навыка (D2).
      await _expectLabels(
        ['cd $_skill && { cd /tmp; } && touch SKILL.md'],
        [_config],
      );
    });

    test('command и builtin — встроенный cd; time объединяет', () async {
      await _expectOrdinary([
        'cd $_skill && command cd /tmp && touch SKILL.md',
        'cd $_skill && builtin cd /tmp && touch SKILL.md',
      ]);
      await _expectLabels(
        [
          'cd $_skill; time cd /tmp && touch SKILL.md',
          'cd $_skill && time cd /tmp && touch SKILL.md',
        ],
        [_config],
      );
    });

    test('eval меняет каталог текущей оболочки', () async {
      await _expectLabels(
        [
          "eval 'cd $_skill'; touch SKILL.md",
          'eval cd $_skill && touch SKILL.md',
        ],
        [_config],
      );
    });

    test(
      'подстановка не выходит наружу; sh -c начинает с чистого OLDPWD',
      () async {
        await _expectLabels(
          [
            'cd $_skill; echo "\$(cd /tmp)"; touch SKILL.md',
            'cd $_skill; echo `cd /tmp`; touch SKILL.md',
            'cd $_skill; cat <(cd /tmp); touch SKILL.md',
          ],
          [_config],
        );
        expect(
          await _labels(
            "cd $_skill && cd /tmp && sh -c 'cd -; touch SKILL.md'",
          ),
          [_unknown],
        );
        // Новый процесс не оставляет следов в родителе.
        await _expectLabels(
          [
            "cd $_skill; sh -c 'cd /tmp'; touch SKILL.md",
            "cd $_skill; env -S 'cd /tmp'; touch SKILL.md",
          ],
          [_config],
        );
      },
    );

    test('if, цикл, функция и alias', () async {
      await _expectLabels(
        [
          'if true; then cd $_skill; fi; touch SKILL.md',
          'cd $_skill; while false; do cd /tmp; done; touch SKILL.md',
          'cd $_skill; for d in a; do cd /tmp; done; touch SKILL.md',
          'cd $_skill; f(){ cd /tmp; }; touch SKILL.md',
          'cd $_skill; function f { cd /tmp; }; touch SKILL.md',
        ],
        [_config],
      );
      // Цикл со сменой каталога добавляет неизвестный; без смены — как обычно.
      expect(await _labels('cd /tmp; while c; do cd "\$d"; done; touch f'), [
        _unknown,
      ]);
      await _expectOrdinary([
        'for f in a b; do echo "\$f"; done',
        'cd sub; while read l; do echo "\$l"; done < in.txt',
      ]);
      // После определения функции или alias любая команда может быть вызовом.
      await _expectLabels(
        ['f(){ echo x; }; touch f', 'alias cd=true; cd /tmp; touch f'],
        [_unknown],
      );
    });

    test('тело функции проверяется в неизвестном каталоге', () async {
      expect(await _labels('f(){ touch SKILL.md; }'), [_unknown]);
      expect(await _labels('f(){ echo hi; }'), isNull);
    });

    test('чужой каталог вложенной команды: find -execdir и git', () async {
      await _expectLabels(
        [
          r'find . -execdir touch SKILL.md \;',
          "git -c alias.x='!touch SKILL.md' x",
          'GIT_PAGER="touch SKILL.md" git log',
        ],
        [_unknown],
      );
      // `-exec` идёт из каталога find.
      await _expectOrdinary([r'find . -exec echo {} \;']);
      expect(await _labels(r'find . -exec touch SKILL.md \;'), isNull);
      expect(await _labels('cd $_skill && find . -exec touch SKILL.md \\;'), [
        _config,
      ]);
    });

    // Цена D8 (design.md): git, пейджер и редактор запускаются в корне
    // рабочего дерева, а не в каталоге оболочки. Команды белого списка чтения
    // (`less`, `cat`) остаются обычными.
    test('переменные-команды: команда не из белого списка критична', () async {
      await _expectLabels(
        [
          'EDITOR=vim git commit',
          r'LESSOPEN="|lesspipe %s" less x',
          'git -c core.pager=delta log',
          // Потребитель идёт после объявления: переменную проверяем там.
          'export EDITOR=vim; git commit',
          'export EDITOR=vim && git commit',
          'declare -x GIT_EDITOR=vim; git rebase --continue',
        ],
        [_unknown],
      );
      await _expectOrdinary([
        'PAGER=less git log',
        'GIT_PAGER=cat git log',
        'git -c core.pager=less log',
        // `true`, `false`, `:` — только чтение.
        'GIT_EDITOR=true git rebase --continue',
        'EDITOR=: git commit',
        'GIT_EDITOR=false git commit',
        'true',
        // Объявление само ничего не исполняет.
        'export EDITOR=vim',
        'export EDITOR=vim GIT_PAGER=less',
        'readonly EDITOR=vim',
        'local EDITOR=vim',
        'export EDITOR=true; git commit',
      ]);
    });

    test('отрицание и || выбирают ветки успеха и неуспеха', () async {
      // `!` меняет успех и неуспех местами: после `! cd /tmp` в `&&`-цепочке
      // идёт ветка неудачного `cd`, то есть каталог навыка.
      await _expectLabels(
        ['cd $_skill && ! cd /tmp && touch SKILL.md'],
        [_config],
      );
      // `||` выполняет правую часть только после неудачи левой.
      await _expectOrdinary([
        'cd $_skill || touch SKILL.md',
        '! cd /tmp && touch SKILL.md',
      ]);
    });

    test(
      'перенаправление после блока проверяется в состоянии на выходе',
      () async {
        await _expectLabels(
          [
            'cd $_skill; { echo x; } > SKILL.md',
            'cd $_skill; while read l; do echo x; done < in > SKILL.md',
          ],
          [_config],
        );
      },
    );
  });

  group('правило «неизвестно» и метка (D9)', () {
    test('команды белого списка чтения не критичны', () async {
      await _expectOrdinary([
        'cd "\$(git rev-parse --show-toplevel)" && cat x',
        'cd "\$X" && git log --oneline > /tmp/log.txt',
        'cd - && ls',
        'cd "\$(dirname "\$F")" && grep -r foo . | wc -l',
      ]);
    });

    test(
      'не из белого списка или запись в относительную цель — критично',
      () async {
        await _expectLabels(
          [
            'cd "\$(git rev-parse --show-toplevel)" && make',
            r'cd "$DIR" && npm test',
            r'cd "$X" && cat a > out.txt',
            r'cd "$X" && echo x >> out.txt',
            r'cd "$X" && time -o out ls',
            r'cd "$X" && ls 2> err.log',
          ],
          [_unknown],
        );
      },
    );

    test('абсолютные цели и ~/\$HOME проверяются как раньше', () async {
      await _expectOrdinary([r'cd "$X" && echo x > /tmp/a']);
      await _expectLabels(
        [
          r'cd "$X" && echo x > ~/.codelab/config.yaml',
          r'cd "$X" && echo x > $HOME/.codelab/config.yaml',
          r'cd "$X" && tee /home/u/.codelab/agents/x.md',
        ],
        [_config],
        host: true,
      );
    });

    test(
      'метка write to agent configuration, если известный вариант попал',
      () async {
        await _expectLabels(
          [
            'cd $_skill; cd "\$X"; touch SKILL.md',
            'cd $_skill; cd /nonexistent; touch SKILL.md',
          ],
          [_config],
        );
      },
    );

    test(
      'метка в таблице идёт сразу после write to agent configuration',
      () async {
        expect(
          await _labels(
            r'cd "$X" && sudo git push --force origin main && make',
          ),
          [
            'privileged command',
            _unknown,
            'git force push or remote branch deletion',
          ],
        );
      },
    );

    test('сценарий «Метка неизвестного каталога в autopilot»', () async {
      const command = r'cd "$DIR" && npm test';
      final gate = FakeGate((_) => PermissionDecision.allowAlways);
      final bypass = await _policy(gate: gate);
      bypass.policy.decisions.allowAlways.add(
        const PermissionKey('exec', command),
      );
      await bypass.run('exec', {'command': command});
      await bypass.run('exec', {'command': command}, id: 'call_2');
      expect(gate.requests, hasLength(2));
      for (final request in gate.requests) {
        expect(request.allowAlwaysOffered, isFalse);
        expect(
          request.reason,
          'critical command: write in unknown working directory',
        );
      }

      final quiet = FakeGate();
      final autopilot = await _policy(
        modeOverride: PermissionMode.autopilot,
        gate: quiet,
      );
      final outcome = await autopilot.run('exec', {'command': command});
      expect(quiet.requests, isEmpty);
      expect(outcome.outcome, ToolOutcome.rejected);
      expect(
        textOf(outcome),
        deniedText(
          'exec',
          'critical command blocked in autopilot: '
              'write in unknown working directory',
        ),
      );
    });

    test('сценарий «Предел числа вариантов»', () async {
      // Каждый pushd может не удаться: после 6 штук стеков 64 > 32.
      final five = [for (var i = 1; i <= 5; i++) 'pushd /a$i;'].join(' ');
      expect(await _labels('$five touch SKILL.md'), isNull);
      expect(await _labels('$five pushd /a6; touch SKILL.md'), [_unknown]);
    });

    test(
      'абсолютный скрипт вне защищаемых путей в ⊤ — неизвестный каталог',
      () async {
        // `skillDirs` здесь нет: исключения навыков проверяет
        // `skill_script_exceptions_test.dart` (D11).
        expect(
          await _labels(
            r'cd "$(mktemp -d)" && python3 /opt/tools/fill.py',
            host: true,
          ),
          [_unknown],
        );
      },
    );
  });

  group('обычная работа в корне остаётся обычной (3.2)', () {
    test('сценарий «Обычная работа в корне остаётся обычной»', () async {
      await _expectOrdinary([
        'cd sub && make',
        'cd sub; make',
        'cd build && cd - && make',
        'pushd sub; popd; make',
        'pushd a && pushd b && popd && make',
        '(cd sub && make) && ls',
        'cd /tmp && rm config.yaml',
        'for f in a b; do echo "\$f"; done',
      ], host: true);
      await _expectOrdinary(['cd sub && make', 'cd /tmp && rm config.yaml']);
      // Цена `;` (design.md, «Risks»): ветка неудачного `cd build` даёт
      // `cd -` к унаследованному OLDPWD, то есть неизвестный каталог.
      await _expectLabels(['cd build; cd -; make'], [_unknown]);
    });
  });

  group('второй проход и время (2.7)', () {
    test('ссылка из cd - раскрывается второй фазой канонизации', () async {
      final memory = MemoryExecutionEnv(cwd: _root);
      // Цель ссылки существует: иначе `realpath` ссылки не раскроется.
      await memory.writeText('/home/u/.codelab/agents/a.md', 'old');
      final env = ResolvingEnv(
        memory,
        links: {'$_root/h': '/home/u/.codelab/agents'},
      );
      final h = await ExecutorHarness.create([ExecTool()], base: env);
      final gate = FakeGate();
      final p = await PolicyHarness.wrap(
        h,
        gate: gate,
        agentConfigPaths: _hostPaths,
        pathResolver: env,
      );

      await p.run('exec', {
        'command': 'cd $_root/h && cd /tmp && cd - && tee x.md',
      });

      expect(gate.requests, hasLength(1));
      expect(
        gate.requests.single.reason,
        'critical command: write to agent configuration',
      );
    });

    test('длинная строка из pushd и подстановок разбирается быстро', () async {
      final pushes = [for (var i = 0; i < 200; i++) 'pushd /a$i;'].join(' ');
      final nested = 'echo \$(echo \$(echo \$(echo \$($pushes touch f))))';
      final labels = await timed('$pushes touch SKILL.md; $nested');

      expect(labels, [_unknown]);
    });
  });

  // Двойное ревью change `harden-exec-cwd-tracking`: обходы подтверждены в
  // настоящих sh, dash и bash. Принцип — fail closed.
  group('ревью: фон, отрицание, command -v, trap, динамические имена', () {
    test(
      'B2: & уводит в фон весь and-or список, а не последний конвейер',
      () async {
        await _expectLabels(
          [
            'cd .codelab; cd /tmp && true & touch config.yaml',
            'cd .codelab; { cd /tmp && true & }; touch config.yaml',
            'cd .codelab; cd /tmp && (true) & touch config.yaml',
            'cd .codelab; cd /tmp && true | cat & touch config.yaml',
            'cd .codelab; cd /tmp && true &\ntouch config.yaml',
          ],
          [_config],
        );
      },
    );

    test('H1: ! после перенаправления — обычное слово', () async {
      await _expectLabels(
        [
          'cd .codelab; >/dev/null ! cd /tmp || touch config.yaml',
          'cd $_skill && >/dev/null ! cd /tmp || touch SKILL.md',
        ],
        [_config],
      );
    });

    test('H2, A3: command -v и -V ничего не исполняют', () async {
      await _expectLabels(
        [
          'cd .codelab; command -v cd /tmp && touch config.yaml',
          'cd .codelab; command -V cd /tmp && touch config.yaml',
          'cd .codelab; command -pv cd /tmp && touch config.yaml',
          'cd .codelab; command command -v cd /bin/ls && touch config.yaml',
          'cd .codelab; command -p command -v cd x && touch config.yaml',
        ],
        [_config],
      );
      await _expectOrdinary(['cd sub && command -v cd && make']);
    });

    test('A3: лаунчер с путём — внешняя программа', () async {
      await _expectLabels(
        [
          'cd .codelab && /usr/bin/command cd /tmp && touch config.yaml',
          'cd .codelab && /usr/bin/time cd /tmp && touch config.yaml',
        ],
        [_config],
      );
    });

    test('H3: действие trap, меняющее каталог, делает ⊤', () async {
      await _expectLabels(
        [
          "trap 'cd .codelab' USR1; kill -USR1 \$\$; touch config.yaml",
          "trap 'cd .codelab' DEBUG; touch config.yaml",
        ],
        [_unknown],
      );
    });

    test(
      'A8: trap без смены каталога не критичен; действие проверяется',
      () async {
        await _expectOrdinary([
          r'tmp=$(mktemp); trap '
              "'rm -f \"\$tmp\"' EXIT; make",
          r'trap '
              "'kill \$(jobs -p)' EXIT; npm start",
          "trap - EXIT; trap '' INT; trap -p; make",
        ]);
        // Ловушка сработает в любом состоянии строки, в том числе в `.codelab`.
        await _expectLabels(
          ["cd .codelab; trap 'touch config.yaml' EXIT"],
          [_config],
        );
      },
    );

    test(
      '6.8: ловушка EXIT исполняется в состоянии после последней команды',
      () async {
        await _expectLabels(
          [
            "trap 'touch config.yaml' EXIT; cd /work/demo/.codelab",
            "trap 'touch config.yaml' EXIT; cd .codelab",
            "trap 'touch config.yaml' EXIT; cd .codelab; true",
          ],
          [_config],
        );
      },
    );

    test(
      '6.10: первая следующая команда — потребитель, даже если читает',
      () async {
        await _expectLabels(
          [
            "read EDITOR <<< 'touch SKILL.md'; true; git commit",
            'printf -v EDITOR x; ls; git commit',
            'for EDITOR in vim; do :; done; git commit',
          ],
          [_unknown],
        );
      },
    );

    test(
      'A7: непотреблённое значение переменной-команды проверяет trap',
      () async {
        expect(
          await _labels("trap 'git commit' EXIT; export GIT_EDITOR='rm -rf /'"),
          ['recursive delete of a protected path', _unknown],
        );
        // Без ловушки следующего сегмента нет и проверять нечего.
        expect(await _labels("export GIT_EDITOR='rm -rf /'"), isNull);
      },
    );

    test(
      'H4: динамическое имя команды и eval с нелитеральным текстом',
      () async {
        await _expectLabels(
          [
            "v='cd .codelab'; \$v; touch config.yaml",
            r'c=cd; $c "$(printf .codelab)" && touch config.yaml',
            r'eval "$(echo cd .codelab)"; touch config.yaml',
          ],
          [_unknown],
        );
      },
    );

    test(
      'A2: слово с косой чертой — файл, только если / стоит до раскрытия',
      () async {
        await _expectOrdinary([
          r'$HOME/bin/tool; make',
          r'./$x; make',
          r'"$d"/run; make',
          r'"${d}"/run && make',
          r'${CODELAB_HOME}/bin/tool; make',
          r'~/bin/tool; make',
        ]);
        await _expectLabels(
          [
            r'$(printf cd; : ")/") "$P" && touch SKILL.md',
            r'"$(printf cd; : ")/")" "$P" && touch SKILL.md',
            r'${C:-\}/x} "$P" && touch SKILL.md',
            r'${x:-${y}/} $d; touch config.yaml',
            r'$(echo ")" >/dev/null; echo cd) $d; touch config.yaml',
            r'[c]d $d; touch config.yaml',
            r'{cd,.codel?b}; touch config.yaml',
            r'$(echo /x); touch f',
            // Незакавыченное раскрытие разбивается на слова: `d='cd '`
            // даёт `cd /.codelab` (D17, A2). `${d}/run` раньше считалось файлом.
            r'${d}/run && make',
            r"d='cd '; $d/.codelab; touch config.yaml",
            r'$d/run; make',
            r'`echo /x`; touch f',
            r'$v; touch f',
            r'${v}; touch f',
          ],
          [_unknown],
        );
        // В кавычках маска и скобки — буквы.
        await _expectOrdinary([r'"[c]d" x; make']);
      },
    );

    test('A1: цикл — признак смены состояния берётся из потока', () async {
      await _expectLabels(
        [
          r'C=cd; for d in .codelab/skills/pdf /tmp; do touch SKILL.md; $C "$d"; done',
          r'c=cd; d=.codelab; for i in 1 2; do touch config.yaml; $c $d; done',
        ],
        [_unknown],
      );
    });

    test('A4, M1: недостижимый исход проверяется во входных вариантах', () async {
      await _expectLabels(
        [
          'popd && touch .codelab/config.yaml',
          'popd 2>"\$(cd /tmp && echo /dev/null)" && touch .codelab/config.yaml',
          'popd && cd .codelab && touch config.yaml',
        ],
        [_config],
      );
      await _expectLabels(['popd && env -C "\$X" touch SKILL.md'], [_unknown]);
      expect(await _labels('popd && rm -rf /'), [
        'recursive delete of a protected path',
      ]);
      await _expectOrdinary(['popd && make']);
    });

    test(
      'A5, H5: динамическое имя переменной делает признаки возможными',
      () async {
        await _expectLabels(
          [
            r'printf -v "$(printf '
                "'C%sPATH' D)\" %s /work/demo/.codelab && cd skills && touch SKILL.md",
            r'eval "$(printf '
                "'C%sPATH=/work/demo/.codelab' D)\"; cd skills && touch SKILL.md",
            r'export "$(printf '
                "'C%sPATH' D)=/work/demo/c\"; cd skills && touch SKILL.md",
          ],
          [_unknown],
        );
      },
    );

    test('A5, H6: enable, DIRSTACK, cdable_vars, set -P', () async {
      await _expectLabels(
        [
          'enable -n cd; pushd .codelab; cd /tmp && touch config.yaml',
          'pushd /tmp; DIRSTACK[1]=/work/demo/.codelab; popd && touch config.yaml',
          'shopt -s cdable_vars; x=/work/demo/.codelab; cd x && touch config.yaml',
          r'v=vars; shopt -s cdable_$v; x=/work/demo/.codelab; cd x && touch config.yaml',
          r'p=P; set -$p; cd l/.. && touch config.yaml',
          r'pushd /tmp; p=DIR; read "${p}STACK[1]" <<< /work/demo/.codelab; popd && touch config.yaml',
        ],
        [_unknown],
      );
    });

    test('A5, L1: переменная-команда записана не присваиванием', () async {
      await _expectLabels(
        [
          r'''V=EDITOR; read "$V" <<< 'touch .codelab/config.yaml'; git commit''',
          r'export "${V}=touch x"; git commit',
          r": \${GIT_EDITOR:='rm -rf /'}; export GIT_EDITOR; git commit",
          "for GIT_EDITOR in 'rm -rf /'; do export GIT_EDITOR; done; git commit",
          "printf -v GIT_EDITOR %s 'touch .codelab/config.yaml'; export GIT_EDITOR; git commit",
          'read GIT_EDITOR < x; git commit',
          'mapfile GIT_EDITOR < x; git commit',
          'declare -n r=GIT_EDITOR; r=vim; git commit',
        ],
        [_unknown],
      );
      // Присваивание `+=` без команды остаётся в оболочке; значение проверено.
      expect(
        await _labels("GIT_EDITOR+='rm -rf /'; export GIT_EDITOR; git commit"),
        ['recursive delete of a protected path', _unknown],
      );
      await _expectOrdinary(['printf -v x %s y; git commit', 'read line < x']);
    });

    test('A5: += и NAME[i]= — присваивания, а не имя команды', () async {
      expect(await _labels('a+=1 rm -rf /'), [
        'recursive delete of a protected path',
      ]);
      expect(await _labels('a[0]=1 rm -rf /'), [
        'recursive delete of a protected path',
      ]);
    });

    test('f() { echo hi; }; f — принятая цена D6', () async {
      expect(await _labels('f() { echo hi; }; f'), [_unknown]);
    });
  });

  // Предел времени для всех проверок размера и глубины: один порог на
  // тесты 2.7 и «Пределы разбора» (D17, A6).
  group('ревью: пределы глубины, длины и работы (M2, A6)', () {
    test(
      'глубокие блоки дают unparsable command, а не переполнение стека',
      () async {
        for (final command in [
          '${'{ ' * 10000}a;${' }' * 10000}',
          '${'(' * 10000}a${')' * 10000}',
          '${'if true; then ' * 5000}a; ${'fi; ' * 5000}',
          '{ ' * 10000,
        ]) {
          expect(await timed(command), ['unparsable command']);
        }
      },
    );

    test('слишком длинная команда не разбирается', () async {
      expect(await timed('echo ${'a' * (128 * 1024)}'), ['unparsable command']);
      expect(await timed('echo ${'a' * 1000}'), isNull);
    });

    test(
      'бюджет сегменты × варианты: 32 варианта и строка до 128 KiB',
      () async {
        final five = [for (var i = 1; i <= 5; i++) 'pushd /a$i;'].join(' ');
        expect(await timed('$five ${'touch f; ' * 13000}'), [
          'unparsable command',
        ]);
        // Умеренная строка укладывается в бюджет.
        expect(await timed('$five ${'touch f; ' * 300}'), isNull);
      },
    );
  });

  group('ревью: сценарии спецификации (D17)', () {
    test('for без in не прячет тело', () async {
      await _expectLabels(
        ['for x\ndo touch .codelab/config.yaml; done'],
        [_config],
      );
      await _expectOrdinary(['for x in a b c d; do :; done']);
    });

    test('Фон уводит весь and-or список', () async {
      await _expectLabels(
        ['cd .codelab; cd /tmp && true & touch config.yaml'],
        [_config],
      );
      await _expectOrdinary(['cd sub && make &']);
    });

    test('command -v не меняет каталог', () async {
      await _expectLabels(
        ['cd $_skill && command -v cd /tmp && touch SKILL.md'],
        [_config],
      );
    });

    test('trap, динамическая команда и состояние bash', () async {
      await _expectLabels(
        [
          "trap 'cd $_skill' DEBUG; touch SKILL.md",
          r'$CMD /tmp; touch SKILL.md',
          r'eval "$X"; touch SKILL.md',
          'enable -n cd; cd sub && touch SKILL.md',
          'shopt -s cdable_vars; cd pdf && touch SKILL.md',
          r'export "${N}PATH=/x"; cd pdf && touch SKILL.md',
        ],
        [_unknown],
      );
      // Ловушка без действия состояние не меняет.
      await _expectOrdinary(["trap - EXIT; trap '' INT; trap -p; make"]);
    });

    test('Переменная-команда через read', () async {
      await _expectLabels(
        [
          "read EDITOR <<< 'touch SKILL.md'; git commit",
          "readarray EDITOR <<< 'touch SKILL.md'; git commit",
          'declare -n R=EDITOR; git commit',
        ],
        [_unknown],
      );
    });

    test('Пределы разбора', () async {
      String groups(int n) => '${'{ ' * n}a;${' }' * n}';
      expect(await _labels(groups(65)), ['unparsable command']);
      expect(await _labels(groups(64)), isNull);
    });
  });

  // N9: ~+, ~- и ~user в целях записи и аргументах команд.
  group('ревью: тильда в путях записи (N9)', () {
    test('~+ — каталог варианта, ~- — OLDPWD варианта', () async {
      await _expectLabels(
        [
          'cd .codelab && cd /tmp && echo x > ~-/config.yaml',
          'cd .codelab && cd /tmp && touch ~-/config.yaml',
          'cd .codelab && echo x > ~+/config.yaml',
          'cd .codelab && touch ~+/config.yaml',
        ],
        [_config],
      );
      await _expectOrdinary(['cd sub && echo x > ~+/out.txt']);
    });

    test('~- без известного OLDPWD и ~user в записи — критично', () async {
      await _expectLabels(
        [
          'echo x > ~-/config.yaml',
          'touch ~-/config.yaml',
          'echo x > ~u/.codelab/config.yaml',
          'rm -rf ~u/.codelab',
          'cp a ~u/.codelab/config.yaml',
        ],
        [_config],
      );
    });

    test('чтение по ~- и ~user не критично', () async {
      await _expectOrdinary([
        'cat ~-/x',
        'ls ~u',
        'cat ~u/.codelab/config.yaml',
      ]);
    });
  });

  // Третье ревью (D17): раскрытия, состояние каждой оболочки, циклы, ловушки.
  group('ревью: третий раунд (C1–C4, W1–W7, F1)', () {
    test('C1: ANSI-C строка внутри раскрытия не закрывает его', () async {
      expect(
        await _labels(r"echo ${x:-$'\''}$(touch .codelab/config.yaml)\'}"),
        [_config],
      );
      expect(await _labels(r"echo ${x:-$'\''}$(rm -rf /)\'}"), [
        'recursive delete of a protected path',
      ]);
    });

    test(
      'C2: кавычка или ANSI-C строка внутри раскрытия в кавычках — unparsable command',
      () async {
        for (final command in [
          r'''echo "${x:-'}"$(touch .codelab/config.yaml)"'}"''',
          r'''echo "${x:-$'\''}$(touch .codelab/config.yaml)'}"''',
          r'''echo "${x:-'$(rm -rf ~/.codelab)'}"''',
        ]) {
          expect(await _labels(command), [
            'unparsable command',
          ], reason: command);
        }
        await _expectOrdinary([r'echo "${x:-default}"', r'echo "${x:-$HOME}"']);
      },
    );

    test('C3: кавычки и # внутри арифметики — не арифметика', () async {
      expect(
        await _labels(
          r"echo $(( ${x+'(('} 0 )); touch .codelab/config.yaml # ))",
        ),
        [_config],
      );
      await _expectOrdinary([
        r'echo $(( $(wc -l < f) + 1 ))',
        r'echo $((1+2))',
      ]);
    });

    test('C4: рекурсия раскрытий ограничена', () async {
      expect(await _labels(r'${x:-' * 8000), ['unparsable command']);
    });

    test(
      'W1: ловушка проверяется в конечном состоянии своей оболочки',
      () async {
        await _expectLabels(
          [
            "(trap 'echo > config.yaml' EXIT; cd .codelab)",
            "x=\$(trap 'touch config.yaml' EXIT; cd .codelab)",
            'bash -c "trap \'echo x > SKILL.md\' EXIT; cd $_skill"',
          ],
          [_config],
        );
      },
    );

    test('W1: состояние дочерней оболочки не утекает наружу', () async {
      await _expectOrdinary([
        "sh -c 'f(){ :; }'; make",
        '(alias x=y); make',
        "echo \$(trap 'cd /tmp' EXIT); make",
      ]);
    });

    test(
      'W2: тело цикла повторяется, если оно меняет состояние оболочки',
      () async {
        for (final command in [
          'for i in 1 2; do f; touch config.yaml; f() { cd .codelab; }; done',
          "for i in 1 2; do touch config.yaml; trap 'cd .codelab' DEBUG; done",
          "export GIT_EDITOR; for i in 1 2; do git commit -q; export GIT_EDITOR='touch .codelab/config.yaml'; done",
          'export GIT_EDITOR; for i in 1 2; do git commit -q; read GIT_EDITOR < f; done',
        ]) {
          expect(await _labels(command), isNotNull, reason: command);
        }
      },
    );

    test('W3: действие trap меняет состояние оболочки', () async {
      for (final command in [
        'trap \'alias ls="cd .codelab"\' DEBUG; true; ls; touch config.yaml',
        'export GIT_EDITOR; trap "read GIT_EDITOR < f" DEBUG; git commit',
      ]) {
        expect(await _labels(command), isNotNull, reason: command);
      }
    });

    test('W4: fc, history -s, mapfile -C и declare -n R — как eval', () async {
      for (final command in [
        "set -o history; true cd .codelab; fc -s 'true '=; touch config.yaml",
        "mapfile -C 'cd .codelab;:' -c 1 a < f; touch config.yaml",
        'declare -n R; R=EDITOR; R=vim; export EDITOR; git commit',
        "history -s 'cd .codelab'; touch config.yaml",
      ]) {
        expect(await _labels(command), isNotNull, reason: command);
      }
    });

    test('W5: enable через динамическое имя команды', () async {
      for (final command in [
        'pushd /tmp && x=enable && \$x -n cd && popd && cd /tmp && touch SKILL.md',
        r'a=ena; b=ble; $a$b -n cd; pushd /tmp; cd /tmp && touch SKILL.md',
        r'a=ena; eval "${a}ble -n cd"; pushd /tmp; cd /tmp && touch SKILL.md',
      ]) {
        expect(await _labels(command, cwd: _skill), isNotNull, reason: command);
      }
    });

    test('фоновый and-or список — подоболочка со своими ловушками', () async {
      await _expectLabels(
        [
          "{ trap 'echo > config.yaml' EXIT; cd .codelab; } & wait",
          "{ trap 'touch config.yaml' EXIT; cd .codelab; } & sleep 1",
          "trap 'echo > config.yaml' EXIT && cd .codelab & wait",
          "{ trap 'touch config.yaml' EXIT; cd .codelab; } &",
        ],
        [_config],
      );
      await _expectOrdinary([
        'make & wait',
        'npm run dev & sleep 3 && curl localhost',
        // Функция фонового списка родителя не заражает.
        '{ f() { :; }; cd .codelab; } & touch config.yaml',
      ]);
    });

    test('enable — только имя команды, а не подстрока любого слова', () async {
      await _expectOrdinary([
        './configure --enable-shared && cd build && make',
      ]);
      await _expectLabels(
        [
          'enable -n cd; pushd sub; cd /tmp && touch f',
          'builtin enable -n cd; cd /tmp && touch f',
          'command enable -n cd; cd /tmp && touch f',
          "sh -c 'enable -n cd; cd /tmp'; true; cd /tmp && touch f",
        ],
        [_unknown],
      );
      expect(
        await _labels(
          "eval 'enable -n cd'; cd /tmp && touch SKILL.md",
          cwd: _skill,
        ),
        // `enable` в каталоге навыка сам не из белого списка чтения.
        [_config, _unknown],
      );
    });

    test('W6: ~+ и ~- при неизвестном каталоге — относительные цели', () async {
      await _expectLabels(
        [
          r'cd "$X" && echo x > ~+/config.yaml',
          r'cd "$X" && time -o ~+/config.yaml ls',
        ],
        [_unknown],
      );
    });

    test('W7: растущий стек pushd не тормозит разбор', () async {
      final labels = await timed('${'pushd a && ' * 6660}true');
      expect(labels, anyOf(isNull, [_unknown]));
    });

    test('F1: присваивание без команды с литеральным значением', () async {
      await _expectOrdinary([
        'GIT_EDITOR=true; export GIT_EDITOR; git rebase --continue',
        'PAGER=cat; git log',
      ]);
      await _expectLabels(
        [
          'GIT_EDITOR=vim; export GIT_EDITOR; git commit',
          r'GIT_EDITOR=$x; export GIT_EDITOR; git commit',
        ],
        [_unknown],
      );
    });
  });

  group(
    'ревью: сценарии спецификации (D17), отрицательные и точные случаи',
    () {
      test('тильды', () async {
        await _expectLabels(
          [
            'touch ~bob/.codelab/config.yaml',
            'cp a ~bob/x',
            'touch ~-/SKILL.md',
            'cd $_skill && cd /tmp && touch ~-/SKILL.md',
            'cd $_skill && touch ~+/SKILL.md',
          ],
          [_config],
        );
        await _expectOrdinary(['cat ~bob/.codelab/config.yaml', 'ls ~-']);
      });

      test('физический .. и нелитеральные shopt и set', () async {
        await _expectLabels(
          [
            'cd sub/../b && make',
            r'shopt -s "$o"; cd pdf && touch SKILL.md',
            r'set "$o"; cd a/.. && touch x',
          ],
          [_unknown],
        );
        await _expectOrdinary(['cd ../b && make']);
      });

      test('косвенная запись переменной-команды', () async {
        await _expectLabels(
          [
            'EDITOR+=x git commit',
            'EDITOR[0]=vim; git commit',
            r'echo ${EDITOR:=vim}; git commit',
            'for EDITOR in vim; do git commit; done',
            'printf -v EDITOR x; ls; git commit',
            "read EDITOR <<< 'touch SKILL.md'; true; git commit",
          ],
          [_unknown],
        );
      });

      test('динамическое имя команды', () async {
        await _expectLabels(
          [
            'c[d] /tmp; make',
            '{cd,x} /tmp; make',
            r'$d/run && make',
            r'${d}/run && make',
          ],
          [_unknown],
        );
        await _expectOrdinary([
          r'"$d"/run && make',
          r'$HOME/bin/tool; make',
          '~/bin/tool; make',
          '[ -f a ] && make',
        ]);
      });

      test('цикл, который меняет каталог через переменную', () async {
        await _expectLabels(
          ['cd $_skill; for i in 1; do C=cd; \$C /tmp; done; touch SKILL.md'],
          [_config],
        );
        await _expectLabels(
          [
            r'for d in a b; do cd $d && make && cd ..; done',
            r'for d in packages/*; do (cd "$d" && dart test); done',
          ],
          [_unknown],
        );
      });

      test('trap без смены каталога', () async {
        await _expectOrdinary([
          r'trap '
              "'rm -f \"\$tmp\"' EXIT; make",
        ]);
        await _expectLabels(
          ["trap 'touch config.yaml' EXIT; cd $_root/.codelab"],
          [_config],
        );
        await _expectLabels(['trap : EXIT; export EDITOR=vim'], [_unknown]);
      });

      test('лаунчер command с путём и поиск', () async {
        await _expectLabels(
          [
            'cd $_skill && /usr/bin/command cd /tmp && touch SKILL.md',
            'cd $_skill && command -p command -v cd /tmp && touch SKILL.md',
          ],
          [_config],
        );
      });
    },
  );
}
