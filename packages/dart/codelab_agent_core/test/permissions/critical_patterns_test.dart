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

    test('чтение и копирование из конфигурации не ограничены', () {
      expect(findCritical('cat .codelab/config.yaml'), isNull);
      expect(findCritical('cp .codelab/config.yaml backup.yaml'), isNull);
      expect(findCritical("sed 's/a/b/' .codelab/config.yaml"), isNull);
      expect(findCritical('echo x > .codelab/notes.md'), isNull);
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
