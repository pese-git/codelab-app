import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../tools/executor_harness.dart';
import 'policy_harness.dart' show deniedText;
import 'skill_policy_harness.dart';

/// Исключения E1–E3 PERM-11 для скриптов навыка (задача 2.7 change
/// `add-agent-skills`; agent-permissions «Критические пути правок
/// конфигурации агента», сценарии про скрипты навыка; D9, решения
/// Q24, Q25, Q29, Q33–Q38; agent-skills «Скрипт по абсолютному пути при
/// локальном исполнении»).
///
/// Положительные случаи (не критично) требуют нового API
/// `AgentConfigPaths.skillDirs`; отрицательные (критично) дополнительно
/// страхуют от расширения исключений. Режим `bypass`: не критичная команда
/// идёт без вопроса, критичная спрашивается без `allow_always`.
void main() {
  late SkillHarness h;

  Future<void> create({
    ModeId mode = ModeId.bypass,
    bool caseInsensitive = false,
    Map<String, String> links = const {},
    PermissionMode? modeOverride,
    List<String> extraPaths = const [],
  }) async {
    h = await SkillHarness.create(
      mode: mode,
      modeOverride: modeOverride,
      config: skillConfig(
        caseInsensitive: caseInsensitive,
        extraPaths: extraPaths,
      ),
      links: links,
    );
  }

  setUp(create);

  group('E1: the script of a skill', () {
    test('scenario "Скрипт навыка не критичен": standard mode asks as an '
        'ordinary exec with allow_always', () async {
      await create(mode: ModeId.standard);

      await h.exec(
        'python3 scripts/extract.py $workDir/a.pdf',
        cwd: projectPdf,
      );

      expect(h.gate.requests, hasLength(1));
      expect(h.gate.requests.single.allowAlwaysOffered, isTrue);
      expect(h.gate.requests.single.reason, isNot(criticalReason));
    });

    test('scenario "Запись в каталог навыка из скрипта-команды": a '
        'redirect into the skill directory is critical', () async {
      await h.expectCritical([
        'python3 scripts/extract.py > notes.md',
      ], cwd: projectPdf);
    });

    test('scenario "Скрипт навыка по абсолютному пути из рабочей папки" '
        '(Q25)', () async {
      await h.expectOrdinary([
        'python3 $releaseNotes/scripts/x.py --out notes.md',
      ]);
      await h.expectCritical([
        'python3 $releaseNotes/scripts/x.py --out $releaseNotes/notes.md',
      ]);
    });

    test('a recognised interpreter by its bare name with the first '
        'positional script (Q34)', () async {
      await h.expectOrdinary([
        'python $pdf/scripts/x.py',
        'python3 $pdf/scripts/x.py',
        'node $pdf/scripts/x.js',
        'tsx $pdf/scripts/x.ts',
        'bash $pdf/scripts/x.sh',
        'sh $pdf/scripts/x.sh',
        'zsh $pdf/scripts/x.sh',
        'pwsh $pdf/scripts/fill.ps1',
        'ruby $pdf/scripts/x.rb',
        'perl $pdf/scripts/x.pl',
        'deno run $pdf/scripts/x.ts',
        'bun run $pdf/scripts/x.ts',
        'uv run $pdf/scripts/x.py',
        'pipx run $pdf/scripts/x.py',
        '$pdf/scripts/run.sh',
        '$pdf/scripts/lib/tool.py',
      ]);
    });

    test('npx, bunx and unknown programs are not interpreters of the '
        'list', () async {
      await h.expectCritical([
        'npx $pdf/scripts/x.js',
        'bunx $pdf/scripts/x.js',
        'php $pdf/scripts/x.php',
        'java $pdf/scripts/x.py',
      ]);
    });

    test(
      'scenario "Код интерпретатору вместо скрипта критичен" (Q34)',
      () async {
        await h.expectCritical([
          "perl -pi -e 's/a/b/' $pdf/SKILL.md",
          'python3 -c "open(\'$pdf/SKILL.md\',\'w\')" $pdf/scripts/x.py',
          'node -e "1" $pdf/scripts/x.js',
          "bash -c 'true' $pdf/scripts/x.sh",
          'python3 - $pdf/scripts/x.py <<EOF\nprint(1)\nEOF',
          'python3 -m zipfile -c $pdf/SKILL.md /tmp/a',
        ]);
      },
    );

    test('every code, module and stdin option of the list disables E1 '
        'for each interpreter', () async {
      const options = {
        'python3': ['-c x', '-m x', '-i', '-', '-s'],
        'node': [
          '-e x',
          '-p x',
          '-r x',
          '--eval x',
          '--print x',
          '--require x',
          '--import x',
          '--loader x',
        ],
        'tsx': ['-e x', '--eval x', '--import x'],
        'bash': ['-c x', '-s', '-'],
        'sh': ['-c x', '-s', '-'],
        'zsh': ['-c x', '-s', '-'],
        'pwsh': ['-Command x', '-EncodedCommand x', '-NoProfile'],
        'ruby': ['-e x', '-r x', '-n', '-p'],
        'perl': ['-e x', '-E x', '-M x', '-n', '-p', '-i'],
        'deno run': ['--preload x', '--import x', '-A'],
        'bun run': ['--preload x', '--hot'],
        'uv run': ['--with x', '-m x', '--quiet'],
        'pipx run': ['--spec x', '--quiet'],
      };
      for (final MapEntry(key: program, value: opts) in options.entries) {
        for (final option in opts) {
          expect(
            await h.critical('$program $option $pdf/scripts/x.py'),
            isTrue,
            reason: '$program $option',
          );
        }
      }
    });

    test('an unknown option before the script disables E1 (Q34)', () async {
      await h.expectCritical([
        'python3 --unknown $pdf/scripts/x.py',
        'node --max-old-space-size=4096 $pdf/scripts/x.js',
        'bash -x $pdf/scripts/x.sh',
      ]);
    });

    test('scenario "pwsh -File": only -File and -f are allowed', () async {
      await h.expectOrdinary([
        'pwsh -File $pdf/scripts/fill.ps1 $pdf/assets/a.json',
        'pwsh -f $pdf/scripts/fill.ps1',
      ]);
      await h.expectCritical(['pwsh -NoProfile -File $pdf/scripts/fill.ps1']);
    });

    test('scenario "Скрипт-ссылка наружу и интерпретатор с путём"', () async {
      await create(links: {'$pdf/scripts/run': '/bin/cp'});

      await h.expectCritical([
        '$pdf/scripts/run /tmp/x $pdf/assets/a.json',
        '/tmp/python3 $pdf/scripts/x.py $pdf/assets/a.json',
        '/usr/bin/python3 $pdf/scripts/x.py',
      ]);
    });

    test('scenario "Исполняемый файл вне scripts/" (Q36)', () async {
      await h.expectCritical([
        '$pdf/node_modules/.bin/shx cp /tmp/evil $pdf/references/a.md',
        '$pdf/.venv/bin/pip install x',
        '$pdf/scripts/node_modules/.bin/prettier --write '
            '$pdf/references/a.md',
        '$pdf/scripts/.hidden/x.py',
        'python3 $pdf/scripts/vendor/x.py',
        'python3 $pdf/scripts/site-packages/x.py',
        'node $pdf/scripts/node_modules/x.js',
        'python3 $pdf/SKILL.md',
        'bash $pdf/scripts/SKILL.md',
        'python3 $pdf/references/a.md',
      ]);
    });

    test('a missing script and a directory are not scripts', () async {
      await h.expectCritical([
        'python3 $pdf/scripts/missing.py',
        'python3 $pdf/scripts/sub',
      ]);
    });

    test('scenario "Первое слово без косой черты": a bare name is looked '
        'up in PATH', () async {
      await h.expectCritical(['cd $pdf/scripts && run.sh $pdf/assets/a.json']);
      await h.expectOrdinary(['$pdf/scripts/run.sh $pdf/assets/a.json']);
    });

    test(
      'scenario "Переменные окружения перед интерпретатором" (Q37)',
      () async {
        await h.expectCritical([
          'NODE_OPTIONS=--require=/tmp/x.js node $pdf/scripts/x.js '
              '$pdf/assets/a.json',
          'export PYTHONPATH=/tmp; python3 $pdf/scripts/x.py $pdf/assets/a.json',
          "env -S 'python3 -c …' $pdf/scripts/x.py",
          'FOO=1 python3 $pdf/scripts/x.py',
          'env FOO=1 python3 $pdf/scripts/x.py',
          'env -i python3 $pdf/scripts/x.py',
          'env -u HOME python3 $pdf/scripts/x.py',
          'declare -x X=1; python3 $pdf/scripts/x.py',
          'typeset X=1; python3 $pdf/scripts/x.py',
          'readonly X=1; python3 $pdf/scripts/x.py',
          'local X=1; python3 $pdf/scripts/x.py',
        ]);
      },
    );
  });

  group('E2: the working directory of a skill (Q24, Q33)', () {
    test('scripts and read-only commands keep working in the skill '
        'directory', () async {
      await h.expectOrdinary([
        'cd $pdf && python3 scripts/x.py',
        'cd $pdf && ./scripts/x.sh',
        'cd $pdf && ls',
        'cd $pdf && git log',
        'cd $pdf && echo hi',
      ]);
      await h.expectOrdinary(['python3 scripts/x.py', 'ls'], cwd: pdf);
    });

    test('scenario "Чтение из рабочего каталога навыка не критично"', () async {
      await h.expectOrdinary(['cd $pdf && cat references/FORMS.md']);
      await h.expectOrdinary(['cat references/FORMS.md'], cwd: pdf);
    });

    test('scenario "Неявная запись в рабочий каталог навыка критична" '
        '(Q33): after cd', () async {
      await h.expectCritical([
        'cd $pdf && tar -xf $workDir/e.tar',
        'cd $pdf && unzip -o $workDir/e.zip',
        'cd $pdf && 7z x $workDir/e.7z',
        'cd $pdf && cpio -i < $workDir/e.cpio',
        'cd $pdf && jar x',
        'cd $pdf && git pull',
        'cd $pdf && git merge main',
        'cd $pdf && npm install',
        "cd $pdf && find . -name '*.md' -delete",
      ]);
    });

    test('scenario "Неявная запись в рабочий каталог навыка критична" '
        '(Q33): with ExecOptions.cwd', () async {
      await h.expectCritical([
        'tar -xf $workDir/e.tar',
        'unzip -o $workDir/e.zip',
        '7z x $workDir/e.7z',
        'jar x',
        'git pull',
        'git merge main',
        'npm install',
        "find . -name '*.md' -delete",
      ], cwd: pdf);
    });

    test('scenario "cd в каталог навыка не снимает критичность"', () async {
      await h.expectCritical([
        'cd $codelabPdf && rm SKILL.md',
        'cd $pdf && sed -i s/a/b/ SKILL.md',
      ]);
    });

    test('scenario "pushd в каталог навыка"', () async {
      await h.expectCritical(['pushd $pdf && npm install && popd']);
    });

    test('env -C and -C DIR are not covered by E2', () async {
      await h.expectCritical([
        'env -C $pdf tar xf a.tar',
        "env -C $pdf sh -c 'echo x > f'",
        'tar -C $pdf -xf a.tar',
      ]);
    });

    test('scenario "Навыки в autopilot"', () async {
      await create(modeOverride: PermissionMode.autopilot);

      // Критическая команда в autopilot отклоняется без вопроса. Текст для
      // `exec` — прежний (`critical command blocked in autopilot`), см.
      // открытый вопрос в отчёте 2.7: спецификация называет другой текст.
      final denied = await h.exec('cd $pdf && tar -xf $workDir/e.tar');
      expect(
        textOf(denied),
        deniedText(
          'exec',
          'critical command blocked in autopilot: '
              'write to agent configuration',
        ),
      );
      final script = await h.exec(
        'python3 $pdf/scripts/fill.py $pdf/assets/a.json',
      );

      expect(h.gate.requests, isEmpty);
      expect(script.outcome, isNot(ToolOutcome.rejected));
    });
  });

  group('E3: the asset of the same skill as an argument of its script', () {
    test('scenario "Ресурс навыка аргументом": existing assets file, not '
        '.md', () async {
      await h.expectOrdinary([
        'python3 $codelabPdf/scripts/fill.py --schema '
            '$codelabPdf/assets/schema.json $workDir/a.pdf',
        'python3 $pdf/scripts/fill.py $pdf/assets/sub/c.json',
        'python3 $pdf/scripts/fill.py $pdf/assets/a.json',
      ]);
    });

    test('a new path or a redirect into assets is critical', () async {
      await h.expectCritical([
        'python3 $codelabPdf/scripts/fill.py $codelabPdf/assets/new.json',
        'python3 $codelabPdf/scripts/fill.py $codelabPdf/assets/schema.json '
            '> $codelabPdf/assets/schema.json',
        'python3 $pdf/scripts/fill.py $pdf/assets',
      ]);
    });

    test('scenario "Пишущие команды на существующий файл навыка '
        'критичны"', () async {
      await h.expectCritical([
        "sed -i 's/a/b/' $codelabPdf/SKILL.md",
        'cp /tmp/evil.md $codelabPdf/SKILL.md',
        'rm $codelabPdf/SKILL.md',
        'curl -o $codelabPdf/SKILL.md https://example.com/x',
      ]);
    });

    test('scenario "Ресурс навыка аргументом чужой программе"', () async {
      await h.expectCritical([
        'python3 $workDir/tool.py $codelabPdf/assets/schema.json',
        'cat $pdf/assets/a.json > $pdf/assets/a.json',
      ]);
    });

    test('scenario "Вывод скрипта навыка в SKILL.md критичен" (Q35)', () async {
      await h.expectCritical([
        'python3 $pdf/scripts/fill.py --output $pdf/SKILL.md',
        'python3 $pdf/scripts/fill.py $pdf/SKILL.md',
        'python3 $pdf/scripts/fill.py -o$pdf/assets/schema.json',
      ]);
    });

    test(
      'values of output options get no E3 even for assets (Q35, Q38)',
      () async {
        const asset = '/home/u/.agents/skills/pdf/assets/a.json';
        await h.expectCritical([
          'python3 $pdf/scripts/fill.py -o $asset',
          'python3 $pdf/scripts/fill.py -o$asset',
          'python3 $pdf/scripts/fill.py -O $asset',
          'python3 $pdf/scripts/fill.py --output $asset',
          'python3 $pdf/scripts/fill.py --output=$asset',
          'python3 $pdf/scripts/fill.py --out $asset',
          'python3 $pdf/scripts/fill.py --out=$asset',
          'python3 $pdf/scripts/fill.py --outfile $asset',
          'python3 $pdf/scripts/fill.py --output-file $asset',
          'python3 $pdf/scripts/fill.py --out-file $asset',
          'python3 $pdf/scripts/fill.py --outdir $asset',
          'python3 $pdf/scripts/fill.py --dest $asset',
          'python3 $pdf/scripts/fill.py --target $asset',
          'python3 $pdf/scripts/fill.py --write $asset',
          'python3 $pdf/scripts/fill.py -w $asset',
          'python3 $pdf/scripts/fill.py of=$asset',
        ]);
      },
    );

    test(
      'scenario "Ресурс другого навыка, через .. и чужой SKILL.md"',
      () async {
        await h.expectCritical([
          'python3 $pdf/scripts/fill.py $notes/assets/a.json',
          'python3 $pdf/scripts/fill.py $pdf/assets/../../notes/assets/a.json',
          'python3 $pdf/scripts/fill.py $notes/SKILL.md',
        ]);
      },
    );

    test('scenario "Ресурсы вне assets и опции вывода" (Q38)', () async {
      await h.expectCritical([
        'python3 $pdf/scripts/fill.py $pdf/references/a.md',
        'python3 $pdf/scripts/fill.py --out=$pdf/assets/a.json',
        'python3 $pdf/scripts/fill.py $pdf/assets/*.json',
        'python3 $pdf/scripts/fill.py $pdf/assets/{a,schema}.json',
        'python3 $pdf/scripts/fill.py $pdf/assets/b.md',
        'python3 $pdf/scripts/fill.py $pdf/references/a.md',
      ]);
    });

    test('scenario "Ссылка на SKILL.md и регистр имени"', () async {
      await create(links: {'$pdf/assets/x.json': '$pdf/SKILL.md'});

      await h.expectCritical([
        'python3 $pdf/scripts/fill.py $pdf/assets/x.json',
        'python3 $pdf/scripts/fill.py $pdf/skill.md',
      ]);

      // Нечувствительная к регистру ФС: `skill.md` — тот же файл.
      await create(caseInsensitive: true);
      await h.expectCritical([
        'python3 $pdf/scripts/fill.py $pdf/skill.md',
        'python3 $pdf/scripts/fill.py $pdf/assets/../Skill.MD',
      ]);
    });

    test('an argument-link pointing outside the assets directory gets no '
        'exception', () async {
      await create(links: {'$pdf/assets/out.json': '$pdf/references/a.md'});

      await h.expectCritical([
        'python3 $pdf/scripts/fill.py $pdf/assets/out.json',
      ]);
    });
  });

  group('review fixes of iteration 2', () {
    test('bash -c: only the command text is skipped, a path with spaces is '
        'checked (extra root with spaces)', () async {
      await create(
        extraPaths: [
          '/Users/John Doe/.agents/skills',
          '/Volumes/Team Share/skills',
        ],
      );

      await h.expectCritical([
        'bash -c \'rm "\$0"\' "/Users/John Doe/.agents/skills/pdf/SKILL.md"',
        'sh -c \'rm "\$0"\' "/Volumes/Team Share/skills/x/SKILL.md"',
      ]);
      await h.expectOrdinary(["bash -c 'echo hi a b' x"]);
    });

    test('a skill file named like an interpreter obeys the option rule '
        '(Q34, Q36)', () async {
      await h.expectOrdinary([
        '$pdf/scripts/bin/tsx $pdf/assets/a.json',
        '$pdf/scripts/bin/python3 --version-less $pdf/assets/a.json'
            .replaceFirst('--version-less ', ''),
      ]);
      await h.expectCritical([
        '$pdf/scripts/bin/tsx -e "x" $pdf/scripts/x.ts',
        '$pdf/scripts/bin/python3 -c x $pdf/scripts/x.py',
        '$pdf/scripts/bin/python3 -m zipfile $pdf/scripts/x.py',
      ]);
    });

    test(
      'a skill file named like a runner obeys the run rule (Q34, Q36)',
      () async {
        await h.expectCritical([
          '$pdf/scripts/bin/deno eval "x" $pdf/assets/a.json',
          '$pdf/scripts/bin/deno run -A $pdf/assets/a.json',
          '$pdf/scripts/bin/bun x $pdf/assets/a.json',
          '$pdf/scripts/bin/bun $pdf/assets/a.json',
          '$pdf/scripts/bin/uv pip install x',
          '$pdf/scripts/bin/pipx install x',
          '$pdf/scripts/bin/pipx run --spec x $pdf/assets/a.json',
        ]);
        await h.expectOrdinary([
          '$pdf/scripts/bin/deno run $pdf/assets/a.json',
          '$pdf/scripts/bin/pipx run $pdf/assets/a.json',
        ]);
      },
    );

    test('environment tricks before the script fail closed (Q37)', () async {
      const js = '$pdf/scripts/x.js';
      const py = '$pdf/scripts/x.py';
      await h.expectCritical([
        'NODE_OPTIONS=--require=/tmp/e.js bash -c "node $js"',
        'NODE_OPTIONS=x eval "node $js"',
        'NODE_OPTIONS=--require=/tmp/e.js; export NODE_OPTIONS; node $js',
        'NODE_OPTIONS=--require=/tmp/e.js; node $js',
        r'PATH=/tmp/evil:$PATH; python3 ' + py,
        'set -a; PYTHONPATH=/tmp; python3 $py',
        'set -o allexport; PYTHONPATH=/tmp; python3 $py',
        'source /tmp/env.sh; python3 $py',
        '. /tmp/env.sh; python3 $py',
        'hash -p /tmp/evil python3; python3 $py',
        'python3() { /tmp/evil "\$@"; }; python3 $py',
        'alias python3=/tmp/evil; python3 $py',
        'enable -f /tmp/x.so y; python3 $py',
        'export FOO; python3 $py',
      ]);
    });

    test('Q47: only an allowlist of earlier segments keeps E1 '
        '(compound commands, eval, variable readers, trap)', () async {
      const js = '$pdf/scripts/x.js';
      const py = '$pdf/scripts/x.py';
      await h.expectCritical([
        // 1. Составные команды и зарезервированные слова.
        'for i in 1; do export X=1; done; node $js',
        'if true; then export X=1; fi; node $js',
        '! export X=1; node $js',
        'while false; do :; done; python3 $py',
        // 2. eval.
        'eval "export NODE_OPTIONS=x"; node $js',
        'eval export NODE_OPTIONS=x; node $js',
        r'eval "$(cat /tmp/x)"; python3 ' + py,
        // 3. Чтение и запись переменных встроенными.
        'read PATH </tmp/v; python3 $py',
        'IFS=: read -r PATH </tmp/v; python3 $py',
        'printf -v PATH /tmp/e; python3 $py',
        'mapfile PATH </tmp/v; python3 $py',
        // 5. trap и прочие команды вне списка.
        'trap "/tmp/e" DEBUG; python3 $py',
        'mkdir /tmp/x && python3 $py',
        'git pull; python3 $py',
        'sort /tmp/x | python3 $py',
      ]);
    });

    test('Q47: a nested -c text keeps E1 only for sh/bash/dash with plain '
        '-c (startup files and zsh disable it)', () async {
      const py = '$pdf/scripts/x.py';
      await h.expectCritical([
        'bash -lc "python3 $py"',
        'bash -l -c "python3 $py"',
        'bash --login -c "python3 $py"',
        'bash --rcfile /tmp/rc -i -c "python3 $py"',
        'bash --init-file /tmp/rc -c "python3 $py"',
        'sh -i -c "python3 $py"',
        'zsh -c "python3 $py"',
        'ksh -c "python3 $py"',
        'bash -c "python3 $py"; python3 $py',
      ]);
    });

    test('Q47: positive cases keep working', () async {
      const py = '$pdf/scripts/x.py';
      await h.expectOrdinary([
        'cd $pdf && python3 scripts/x.py',
        'cd $pdf/assets && python3 ../scripts/x.py a.png',
        'bash -c "python3 $py"',
        'sh -e -c "python3 $py"',
        'sh -eu -c "python3 $py"',
        'bash -o pipefail -c "python3 $py"',
        'dash -c "python3 $py"',
        'pwsh -File $pdf/scripts/fill.ps1',
        'ls $workDir && python3 $py',
        'echo start; cd $pdf; python3 scripts/x.py',
        'cat $workDir/a.pdf | python3 $py',
      ]);
    });

    test('Q47 scenarios: allowlist of segments, simple nested shell, runner '
        'file of a skill', () async {
      const p = '$pdf/scripts/x.py $pdf/assets/a.json';
      await h.expectCritical([
        'for i in 1; do export X=1; done; python3 $p',
        'if true; then python3 $p; fi',
        'eval "export X=1"; python3 $p',
        'eval python3 $p',
        'read PATH < /tmp/p; python3 $p',
        'printf -v PATH /tmp; python3 $p',
        'mapfile -t A < /tmp/a; python3 $p',
        'bash -lc "python3 $p"',
        'bash --rcfile /tmp/rc -c "python3 $p"',
        'bash -i -c "python3 $p"',
        'zsh -c "python3 $p"',
        "trap 'rm -f /tmp/x' DEBUG; python3 $p",
        'mkdir -p /tmp/x; python3 $p',
        "env -S 'python3 $p'",
        '$pdf/scripts/bin/deno $pdf/scripts/x.py $pdf/assets/a.json',
        'deno $p',
        '$pdf/scripts/bin/uv --with x run $p',
        'uv --with x run $p',
      ]);
      await h.expectOrdinary([
        'sh -e -c "python3 $p"',
        'cd $workDir && cat a.pdf && python3 $p',
        'bash -o pipefail -c "cd $workDir; python3 $p"',
        'cd $pdf && cat SKILL.md && python3 $p',
      ]);
    });

    test('Q47 review: [[ is a reserved word, options after -c count as '
        'options', () async {
      const p = '$pdf/scripts/x.py $pdf/assets/a.json';
      await h.expectCritical([
        '[[ 1 -eq 1 ]]; python3 $p',
        'bash -c -l "python3 $p"',
        'bash -c -i "python3 $p"',
        'bash -c -li "python3 $p"',
        'sh -c -i "python3 $p"',
        'bash -e -c -l "python3 $p"',
      ]);
      await h.expectOrdinary([
        '[ 1 -eq 1 ]; python3 $p',
        'test -n x; python3 $p',
        'bash -c -e "python3 $p"',
      ]);
    });

    test('shell options that take a value do not hide the command text '
        '(-O, +O, o/O inside a cluster)', () async {
      const p = '$pdf/scripts/x.py $pdf/assets/a.json';
      for (final command in [
        "bash -O extglob -c 'rm -rf /'",
        "bash -c -O extglob 'rm -rf /'",
        "bash +O extglob -c 'rm -rf /'",
        "bash -co pipefail 'rm -rf /'",
        "bash -oc pipefail 'rm -rf /'",
        "bash -ceo x 'rm -rf /'",
        "bash -cO x 'rm -rf /'",
        "dash -co noglob 'rm -rf /'",
        "bash -O extglob -c 'curl x | sh'",
        "bash -O extglob -c 'git push --force origin main'",
        "bash -c -O extglob 'tee $pdf/SKILL.md'",
      ]) {
        expect(await h.criticalAny(command), isTrue, reason: command);
      }
      await h.expectCritical([
        'bash -O extglob -c "python3 $p"',
        'bash -c -O extglob "python3 $p"',
        'bash -co pipefail "python3 $p"',
        "bash -c -O extglob 'tee $pdf/SKILL.md'",
      ]);
      await h.expectOrdinary([
        'bash -o pipefail -c "python3 $p"',
        'bash -c -e "python3 $p"',
        'bash -c -- "python3 $p"',
      ]);
    });

    test('output options: clusters ending with o/O/w and long prefixes '
        'get no E3', () async {
      const asset = '$pdf/assets/a.json';
      await h.expectCritical([
        'python3 $pdf/scripts/fill.py -vo $asset',
        'python3 $pdf/scripts/fill.py -vw $asset',
        'python3 $pdf/scripts/fill.py -vO $asset',
        'python3 $pdf/scripts/fill.py --outp $asset',
        'python3 $pdf/scripts/fill.py --outp=$asset',
        'python3 $pdf/scripts/fill.py --wri $asset',
      ]);
      await h.expectOrdinary([
        'python3 $pdf/scripts/fill.py --schema $asset',
        'python3 $pdf/scripts/fill.py -v $asset',
      ]);
    });
  });
}
