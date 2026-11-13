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
  }) async {
    h = await SkillHarness.create(
      mode: mode,
      modeOverride: modeOverride,
      config: skillConfig(caseInsensitive: caseInsensitive),
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
}
