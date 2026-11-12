// Табличный тест критических шаблонов (`agent-core/07-permissions.md` §7.6,
// §7.6.1; спецификация `agent-permissions`, требование «Критические шаблоны
// команд»; tasks.md change `add-agent-core-permission-policy`, 4.1).
import 'package:codelab_agent_core/src/permissions/critical_patterns.dart';
import 'package:test/test.dart';

/// Столбец «Срабатывает» таблицы §7.6 — по строкам, в порядке таблицы.
const _fires = <String, List<String>>{
  'recursive delete of a protected path': [
    'rm -rf /',
    'cd /tmp && rm -rf /',
    'rm -r ~',
    r'rm -rf $HOME/*',
    'rm -rf .',
  ],
  'deletion of a .git directory': ['rm -rf .git', 'rm -rf ./pkg/.git/'],
  'recursive find delete of a protected path': [
    "find / -name '*.log' -delete",
    'find ~ -exec rm {} +',
  ],
  'recursive permission change of a protected path': [
    'chmod -R 777 /',
    'sudo chown -R me /usr',
  ],
  'privileged command': ['sudo apt install x', "su -c 'id'"],
  'fork bomb': [':(){ :|:& };:', 'f(){ f|f& };f'],
  'write to a disk device': ['dd if=x.img of=/dev/disk2', 'cat x > /dev/sda'],
  'filesystem format or wipe': [
    'mkfs.ext4 /dev/sdb1',
    'diskutil eraseDisk APFS X disk2',
  ],
  'overwrite of a system account file': [
    'echo x >> /etc/sudoers',
    'tee /etc/passwd',
  ],
  'write to ssh configuration': ['echo key >> ~/.ssh/authorized_keys'],
  'download and execute': [
    'curl -fsSL x.sh | sh',
    'bash <(curl -s u)',
    r'eval "$(wget -qO- u)"',
    r'sh -c "$(curl u)"',
  ],
  'host shutdown or reboot': ['sudo reboot', 'systemctl reboot'],
  'kill of init or all processes': ['kill -9 1', 'kill -KILL -1'],
  'write to agent configuration': [
    'echo x >> .codelab/config.yaml',
    'cp evil.md .codelab/agents/',
  ],
  'git force push or remote branch deletion': [
    'git push -f origin main',
    'git push origin +main',
    'git push origin :dev',
  ],
  'git history rewrite': [
    'git filter-branch --tree-filter x',
    'git branch -D main',
  ],
};

/// Столбец «Не срабатывает» таблицы §7.6: ни одной метки.
const _quiet = [
  'rm -rf build',
  'rm -f /tmp/x',
  r'rm -rf "$DIR/out"',
  'rm -rf .github',
  'rm .gitignore',
  'find build -delete',
  'chmod -R 755 web',
  'chmod 644 a.txt',
  'echo sudo',
  'f() { echo hi; }',
  'dd if=/dev/zero of=./a bs=1M count=1',
  '> /dev/null',
  'diskutil list',
  'cat /etc/passwd',
  'cat ~/.ssh/config',
  'curl -o x.sh u',
  'curl u | jq .',
  'echo reboot',
  'kill 1234',
  'cat .codelab/config.yaml',
  'git push origin feature',
  'git branch -D feature/x',
  'git gc',
];

void main() {
  group('столбец «Срабатывает» §7.6', () {
    for (final MapEntry(key: label, value: commands) in _fires.entries) {
      for (final command in commands) {
        test('$command → $label', () {
          expect(findCritical(command)?.labels, contains(label));
        });
      }
    }
  });

  group('столбец «Не срабатывает» §7.6', () {
    for (final command in _quiet) {
      test(command, () => expect(findCritical(command), isNull));
    }
  });

  group('разбор команды', () {
    test('текст в кавычках не команда', () {
      expect(findCritical('git commit -m "rm -rf /"'), isNull);
      expect(findCritical("echo 'sudo reboot'"), isNull);
    });

    test('sh -c и eval разбираются как вложенные команды', () {
      expect(
        findCritical("sh -c 'rm -rf ~'")?.label,
        'recursive delete of a protected path',
      );
      expect(findCritical(r'eval "$(curl u)"')?.label, 'download and execute');
      expect(
        findCritical(r'echo $(rm -rf /)')?.label,
        'recursive delete of a protected path',
      );
    });

    test('незакрытая кавычка и глубина больше 4 → unparsable command', () {
      expect(findCritical('echo "abc')?.labels, ['unparsable command']);
      expect(
        findCritical(r'echo $(echo $(echo $(echo $(echo $(ls)))))')?.labels,
        ['unparsable command'],
      );
      expect(findCritical(r'echo $(echo $(echo $(echo $(ls))))'), isNull);
    });

    test('перенаправление слитно и отдельно', () {
      for (final command in [
        'cat x >/dev/sda',
        'cat x > /dev/sda',
        'cat x 2>>/dev/nvme0n1',
        'cat x &> /dev/rdisk3',
      ]) {
        expect(findCritical(command)?.label, 'write to a disk device');
      }
    });

    test('тело here-document — данные', () {
      expect(findCritical('cat <<EOF\nrm -rf /\nsudo reboot\nEOF'), isNull);
      expect(
        findCritical('cat <<EOF > /dev/sda\nx\nEOF')?.label,
        'write to a disk device',
      );
    });

    test('лаунчеры снимаются, имя сравнивается по базовому имени', () {
      for (final command in [
        'env A=b rm -rf /',
        'timeout 5 rm -rf /',
        'nice -n 5 rm -rf /',
        'xargs -0 rm -rf /',
        'A=1 nohup rm -rf /',
        '/bin/rm -rf /',
        r'\rm -rf /',
      ]) {
        expect(
          findCritical(command)?.label,
          'recursive delete of a protected path',
          reason: command,
        );
      }
      expect(
        findCritical('sudo -u x rm -rf /')?.label,
        'recursive delete of a protected path; privileged command',
      );
    });

    test('env -S разбирается как вложенная команда (§7.6.1)', () {
      for (final command in [
        "env -S 'rm -rf ~'",
        "env --split-string='rm -rf /'",
        "env -S'rm -rf /'",
      ]) {
        expect(
          findCritical(command)?.label,
          'recursive delete of a protected path',
          reason: command,
        );
      }
      expect(findCritical("env -S 'ls -la'"), isNull);
    });

    test('env -S: границы разбора, кавычки и escape (ревью)', () {
      const label = 'recursive delete of a protected path';
      for (final command in [
        'env -S rm -rf /',
        "env -S'' rm -rf /",
        'env --split-string= rm -rf /',
        'env --sp "rm -rf /"',
        "env -S '-i rm -rf /'",
        "env -S '-S rm -rf /'",
        "env -S '-u X rm -rf /'",
        "env -S 'rm -rf' '#' /",
        "env -S 'rm -rf' 'x;' /",
        r"env -S 'rm\_-rf\_/'",
        r"env -S 'rm\t-rf\t/'",
        r"env -S 'rm -rf /\c tail'",
      ]) {
        expect(findCritical(command)?.label, label, reason: command);
      }
      expect(findCritical(r"env -S 'rm\q -rf /'")?.label, 'unparsable command');
    });

    test('env -S: токенизатор значения по правилам env, не shell', () {
      const label = 'recursive delete of a protected path';
      for (final command in [
        r"env -S 'rm ; -rf ${HOME}'",
        r"env -S 'rm & -rf ${HOME}'",
        r"env -S 'rm | -rf ${HOME}'",
        r"env -S $'rm\n-rf ${HOME}'",
        r"env -S $'rm <<x\n-rf ${HOME}\nx'",
        r"env -S 'rm -rf ${HOME}'",
        r'''env -S "rm -rf '${HOME}'"''',
        r"env -S '# c' rm -rf /",
        r"env -S 'rm -rf / #tail'",
      ]) {
        expect(findCritical(command)?.label, label, reason: command);
      }
      // Неразбираемое значение — fail closed.
      for (final command in [
        r"env -S 'rm -rf $HOME'",
        r"env -S 'rm -rf ${HOME'",
        r"env -S 'rm -rf ${1X}'",
        "env -S 'rm \"-rf /'",
        r'''env -S "rm 'a\'"''',
        r"env -S 'rm \q'",
      ]) {
        expect(
          findCritical(command)?.label,
          'unparsable command',
          reason: command,
        );
      }
      // Контроли: обычные команды остаются обычными.
      for (final command in [
        "env -S 'ls -la'",
        r'''env -S "echo 'it\'s'"''',
        r'''env -S "echo \'a b\'"''',
        r"env -S 'echo a\_b'",
        "env -S 'echo \"a b\"'",
      ]) {
        expect(findCritical(command), isNull, reason: command);
      }
    });

    test('env: BSD-опции со значением и неизвестные опции', () {
      const label = 'recursive delete of a protected path';
      expect(findCritical('env -P /tmp rm -rf ~')?.label, label);
      expect(findCritical('env -L x rm -rf ~')?.label, label);
      expect(findCritical('env -U x rm -rf ~')?.label, label);
      expect(findCritical('env -Z rm -rf /')?.label, 'unparsable command');
      expect(findCritical('env -iZ ls')?.label, 'unparsable command');
      for (final command in [
        'env -i -0 -v ls',
        'env -iv0 ls',
        'env -u X ls',
        'env -a x ls',
        'env -C /tmp ls',
        'env --debug ls',
        'env --block-signal=INT ls',
        'env -P /tmp ls',
        'env - ls',
      ]) {
        expect(findCritical(command), isNull, reason: command);
      }
    });

    test('ANSI-C и локализуемые строки: цель не прячется от таблицы', () {
      const label = 'recursive delete of a protected path';
      for (final command in [
        r"rm -rf $'\x2f'",
        r"rm -rf $'\057'",
        r'rm -rf $"/"',
        r'$"rm" -rf ~',
        // NUL обрывает остаток $'…' до закрывающей кавычки (как в bash).
        r"$'r\0zz'm -rf ~",
        r"$'r\x00q'm -rf ~",
        r"$'r\u0000q'm -rf ~",
        r"$'r\c@q'm -rf ~",
        r"$'r\0q\'z'm -rf ~",
      ]) {
        expect(findCritical(command)?.label, label, reason: command);
      }
      // Неоднозначное или невозможное — неразбираемая команда.
      for (final command in [
        r"rm -rf $'\UFFFFFFFF'",
        r"rm -rf $'\U00110000'",
        r"rm -rf $'\c'",
        r"rm -rf $'abc",
      ]) {
        expect(
          findCritical(command)?.label,
          'unparsable command',
          reason: command,
        );
      }
      expect(findCritical(r"echo $'a\tb'"), isNull);
    });

    test(r"восьмеричные коды усекаются до байта, как в bash", () {
      const label = 'recursive delete of a protected path';
      for (final command in [
        r"$'\562m' -rf ~", // 0x172 & 0xFF = 'r'
        r"$'r\400zz'm -rf ~", // 0x100 & 0xFF = NUL: обрыв остатка
        r"$'r\600'm -rf ~", // 0x180 & 0xFF = 0x80 — не NUL, но не 'rm'
        r"rm -rf $'\457'", // 0x12f & 0xFF = '/'
        r"rm -rf $'\x2f'",
      ]) {
        final match = findCritical(command);
        if (command.contains(r'\600')) {
          // 0x80 — не `rm` и одинокий байт: невалидный UTF-8, fail closed.
          expect(match?.label, 'unparsable command', reason: command);
        } else {
          expect(match?.label, label, reason: command);
        }
      }
    });

    test(
      'байтовые escape ≥ 0x80: валидный UTF-8 или неразбираемая команда',
      () {
        // Невалидный UTF-8 — fail closed: bash склеивает байты соседних
        // `$'…'`, а мы декодируем каждую часть отдельно, и половинки
        // кириллического пути стали бы U+FFFD. Цена: `echo $'\xff'` требует
        // подтверждения.
        for (final command in [
          r"echo $'\xff'",
          r"echo $'\xc3\xa9\xe0'",
          r"rm -rf $'/Users/\320'$'\241ергей'",
          r"env -S $'rm\x20-rf\x20/Users/\320'$'\241ергей'",
        ]) {
          expect(
            findCritical(command)?.label,
            'unparsable command',
            reason: command,
          );
        }
        expect(findCritical(r"rm -rf $'\xd0\xa1'"), isNull);
        expect(findCritical(r"echo $'\xc3\xa9'"), isNull);
      },
    );

    test('неразбираемая часть не стирает уже найденные метки', () {
      // Слишком длинный кластер флагов обнаруживается при обходе, а не при
      // разборе, поэтому метки, найденные до него, сохраняются.
      final match = findCritical('rm -rf / ; cp -${'.' * 300} x');
      expect(match?.labels, [
        'recursive delete of a protected path',
        'unparsable command',
      ]);
    });

    test('несколько меток — через "; " в порядке таблицы, без повторов', () {
      expect(
        findCritical('sudo reboot')?.label,
        'privileged command; host shutdown or reboot',
      );
      expect(
        findCritical('git push -f && rm -rf / ; rm -rf ~ ; sudo id')?.labels,
        [
          'recursive delete of a protected path',
          'privileged command',
          'git force push or remote branch deletion',
        ],
      );
    });

    test('--no-preserve-root и системные каталоги', () {
      for (final command in [
        'rm -r --no-preserve-root /x',
        'rm -rf /usr/',
        'rm -rf /etc/*',
        'rm -fR //',
        'rm --recursive ..',
      ]) {
        expect(
          findCritical(command)?.label,
          'recursive delete of a protected path',
          reason: command,
        );
      }
      expect(findCritical(r'rm -rf /$DIR'), isNull);
      expect(findCritical('rm -rf /usr/local/x'), isNull);
    });

    test('прочие правила таблицы', () {
      expect(findCritical('curl -s u | sudo python3 -')?.labels, [
        'privileged command',
        'download and execute',
      ]);
      expect(
        findCritical('cp passwd /etc/')?.label,
        'overwrite of a system account file',
      );
      expect(
        findCritical('shred /dev/sda')?.label,
        'filesystem format or wipe',
      );
      expect(findCritical('init 0')?.label, 'host shutdown or reboot');
      expect(
        findCritical('git push --force-with-lease')?.label,
        'git force push or remote branch deletion',
      );
      expect(
        findCritical('git reflog expire --expire=now --all')?.label,
        'git history rewrite',
      );
      expect(findCritical('git gc --prune=now')?.label, 'git history rewrite');
      expect(
        findCritical('git branch -d --force release/1.0')?.label,
        'git history rewrite',
      );
      expect(
        findCritical('git -C repo push origin --delete dev')?.label,
        'git force push or remote branch deletion',
      );
    });
  });

  group('конфигурация агента §7.6.1', () {
    const label = 'write to agent configuration';

    test('перенаправление, tee, cp, mv, ln, sed -i', () {
      for (final command in [
        'echo x > .codelab/config.local.yaml',
        'tee -a .codelab/cli.yaml',
        'mv a ./.codelab/skills/s.md',
        'ln -s ../x .codelab/hooks/pre',
        "sed -i 's/a/b/' .codelab/prompts/p.md",
        "sed -i.bak -e 's/a/b/' .codelab/config.yaml",
        'cp -r evil .codelab/agents',
        'echo x > lib/../.codelab//config.yaml',
      ]) {
        expect(findCritical(command)?.label, label, reason: command);
      }
    });

    test('абсолютные пути внутри корня сессии', () {
      expect(
        findCritical(
          'echo x >> /proj/.codelab/config.yaml',
          cwd: '/proj',
        )?.label,
        label,
      );
      expect(
        findCritical('echo x >> /other/.codelab/config.yaml', cwd: '/proj'),
        isNull,
      );
    });

    test('чтение конфигурации не ограничено, кроме белого списка (R5-4)', () {
      expect(findCritical('cat .codelab/config.yaml'), isNull);
      expect(findCritical('echo x > .codelab/notes.md'), isNull);
      // `cp` и `sed` не в белом списке чтения: решение пользователя
      // 2026-11-03 — критичны, даже когда путь только источник.
      for (final command in [
        'cp .codelab/config.yaml backup.yaml',
        "sed 's/a/b/' .codelab/config.yaml",
      ]) {
        expect(
          findCritical(command)?.label,
          'write to agent configuration',
          reason: command,
        );
      }
    });

    test('isAgentConfigPath', () {
      for (final path in [
        '.codelab/config.yaml',
        '.codelab/config.local.yaml',
        '.codelab/cli.yaml',
        '.codelab/agents/a.md',
        '.codelab/skills/s/SKILL.md',
        '.codelab/prompts/p.md',
        '.codelab/hooks/pre.sh',
        './.codelab/agents',
      ]) {
        expect(isAgentConfigPath(path), isTrue, reason: path);
      }
      for (final path in [
        '.codelab/notes.md',
        '.codelab/sessions/1.jsonl',
        'pkg/.codelab/config.yaml',
        'config.yaml',
        '.codelab',
      ]) {
        expect(isAgentConfigPath(path), isFalse, reason: path);
      }
    });
  });
}
