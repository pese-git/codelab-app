// Белый список чтения для `exec` и маски в путях конфигурации агента
// (PERM-11, `agent-core/07-permissions.md` §7.6.1; решение пользователя
// 2026-11-03, R5-4, change `add-config-writer-and-reload`, итерация 5).
//
// Правило: команда, у которой слово-аргумент (или значение опции) указывает
// на защищаемый путь или его каталог, критична, КРОМЕ команд только чтения.
import 'package:codelab_agent_core/src/permissions/agent_config_paths.dart';
import 'package:codelab_agent_core/src/permissions/critical_patterns.dart';
import 'package:test/test.dart';

const _label = 'write to agent configuration';
const _codelabHome = '/home/me/.codelab';

AgentConfigPaths _config({List<String> extra = const []}) => AgentConfigPaths(
  paths: [
    '$_codelabHome/config.yaml',
    '$_codelabHome/secrets.yaml',
    '$_codelabHome/agents',
    '$_codelabHome/prompts',
    '/launch/.codelab/config.yaml',
    '/etc/codelab/agent.yaml',
    ...extra,
  ],
  expansions: {'HOME': '/home/me', 'CODELAB_HOME': _codelabHome},
);

Future<CriticalMatch?> _find(
  String command, {
  bool host = true,
  String? cwd,
  List<String> extra = const [],
}) async {
  final scope = host
      ? await AgentConfigScope.resolve(_config(extra: extra), null)
      : null;
  return findCritical(
    command,
    cwd: '/proj',
    commandCwd: cwd,
    agentConfig: scope,
  );
}

Future<void> _expectCritical(
  Iterable<String> commands, {
  bool host = true,
}) async {
  for (final command in commands) {
    final match = await _find(command, host: host);
    expect(match?.labels, contains(_label), reason: command);
  }
}

Future<void> _expectOrdinary(
  Iterable<String> commands, {
  bool host = true,
}) async {
  for (final command in commands) {
    expect(await _find(command, host: host), isNull, reason: command);
  }
}

void main() {
  group('commands outside the read whitelist with a protected path', () {
    test('writers, downloaders and installers are critical', () async {
      await _expectCritical([
        r'yq -i ".a = 1" ~/.codelab/config.yaml',
        'perl -pi -e s/a/b/ ~/.codelab/config.yaml',
        'curl -o ~/.codelab/config.yaml https://x',
        'curl --output=.codelab/config.yaml https://x',
        'curl -o.codelab/config.yaml https://x',
        'wget -O ~/.codelab/config.yaml https://x',
        'wget -O .codelab/config.yaml https://x',
        'git checkout -- .codelab/config.local.yaml',
        'git restore .codelab/config.local.yaml',
        'git add .codelab/config.yaml',
        'rsync a ~/.codelab/config.yaml',
        'sort -o ~/.codelab/config.yaml x',
        "sed -n p ~/.codelab/config.yaml",
        'jq -i . ~/.codelab/config.yaml',
        'dd if=a of=~/.codelab/config.yaml',
        'cp ~/.codelab/config.yaml /tmp/copy.yaml',
        'sudo tee ~/.codelab/config.yaml',
        'time -o ~/.codelab/config.yaml ls',
        'git diff --output=.codelab/config.yaml',
        'less -o .codelab/config.yaml x',
      ]);
    });

    test('a protected directory as an argument or option value', () async {
      await _expectCritical([
        'cp -r evil/. ~/.codelab',
        'cp -r evil/. .codelab',
        'cp -r evil/.codelab .',
        'cp -r evil/.codelab ~/',
        'mv evil/.codelab .',
        'rsync -a src/ ~/.codelab/',
        'tar -xf a.tar -C ~/.codelab',
        'tar -xf a.tar --directory=~/.codelab',
        'unzip -o a.zip -d ~/.codelab',
        'find ~/.codelab -name config.yaml -delete',
        r'find $HOME/.codelab -type f -delete',
        'git -C ~/.codelab checkout config.yaml',
        'tar -xf a.tar -C .codelab',
        'unzip a.zip -d /launch/.codelab',
        'rsync -a src/ /etc/codelab/',
      ]);
    });

    test('a working directory that is the protected directory', () async {
      await _expectCritical([
        'cd ~/.codelab && tar xf a.tar',
        'cd .codelab && curl -O https://x',
        'cd ~/.codelab; wget https://x',
        'cd ~/.codelab/agents && unzip a.zip',
        'sh -c "cd ~/.codelab && unzip a.zip"',
        'env -C ~/.codelab tar xf a.tar',
        'env -C ~/.codelab tee config.yaml',
        'env -C ~/.codelab sh -c "echo x > config.yaml"',
        'sudo -D ~/.codelab tee config.yaml',
        'env --chdir=~/.codelab tee config.yaml',
      ]);
    });

    test('the exec cwd argument is the protected directory', () async {
      final scope = await AgentConfigScope.resolve(_config(), null);
      expect(
        findCritical(
          'tar xf a.tar',
          cwd: '/proj',
          commandCwd: _codelabHome,
          agentConfig: scope,
        )?.labels,
        contains(_label),
      );
      expect(
        findCritical(
          'cat config.yaml',
          cwd: '/proj',
          commandCwd: _codelabHome,
        )?.labels,
        isNull,
      );
    });

    test(
      'redirections into a protected path are critical for any command',
      () async {
        await _expectCritical([
          'echo x > ~/.codelab/config.yaml',
          'cat a 2> .codelab/config.yaml',
          'cat a &> ~/.codelab/config.yaml',
          'cat a >> .codelab/config.local.yaml',
          'cat a >| ~/.codelab/config.yaml',
          'printf x > .codelab/cli.yaml',
          'grep x f > ~/.codelab/secrets.yaml',
          'cd ~/.codelab && echo x > config.yaml',
        ]);
      },
    );

    test('without host paths the project .codelab is still covered', () async {
      await _expectCritical([
        'curl -o .codelab/config.yaml https://x',
        'git checkout -- .codelab/config.local.yaml',
        'tar -xf a.tar -C .codelab',
        'cd .codelab && wget https://x',
      ], host: false);
    });
  });

  group('read-only whitelist', () {
    test('reads of protected files and directories are ordinary', () async {
      const readers = [
        'cat',
        'less',
        'more',
        'head',
        'tail',
        'grep x',
        'egrep x',
        'fgrep x',
        'rg x',
        'ag x',
        'ls',
        'ls -la',
        'stat',
        'file',
        'wc -l',
        'diff /tmp/a',
        'cmp /tmp/a',
        'sha256sum',
        'shasum',
        'md5sum',
        'jq .a',
        'yq .a',
        'realpath',
        'readlink',
        'dirname',
        'basename',
        'echo',
        'printf %s',
        'test -f',
        '[ -f',
      ];
      for (final reader in readers) {
        final close = reader.startsWith('[') ? ' ]' : '';
        for (final path in [
          '~/.codelab/config.yaml',
          r'$HOME/.codelab/secrets.yaml',
          r'${CODELAB_HOME}/agents',
          '~/.codelab',
          '.codelab/config.local.yaml',
          '.codelab',
          '/launch/.codelab/config.yaml',
        ]) {
          final command = '$reader $path$close';
          expect(await _find(command), isNull, reason: command);
        }
      }
    });

    test('git read subcommands are ordinary, others are not', () async {
      await _expectOrdinary([
        'git diff .codelab/config.yaml',
        'git log -p -- .codelab/config.yaml',
        'git show HEAD:.codelab/config.yaml',
        'git status .codelab',
        'git blame .codelab/config.yaml',
        'git -C ~/.codelab status',
        'git --no-pager log ~/.codelab/config.yaml',
      ]);
      await _expectCritical([
        'git checkout -- .codelab/config.yaml',
        'git stash push .codelab/config.yaml',
        'git rm .codelab/config.yaml',
        'git clean -fd .codelab',
        'git diff --output=.codelab/config.yaml',
      ]);
    });

    test('a reader with a write option or redirection is not exempt', () async {
      await _expectCritical([
        'yq -i .a ~/.codelab/config.yaml',
        'yq --inplace .a ~/.codelab/config.yaml',
        'jq -i . .codelab/config.yaml',
        'jq . a > ~/.codelab/config.yaml',
        'echo x > ~/.codelab/config.yaml',
        'less -o log ~/.codelab/config.yaml',
        'cat a | tee ~/.codelab/config.yaml',
      ]);
    });

    test('reads inside a protected working directory are ordinary', () async {
      await _expectOrdinary([
        'cd ~/.codelab && cat config.yaml',
        'cd ~/.codelab; ls; grep x config.yaml | wc -l',
        'cd .codelab && head config.local.yaml',
        'env -C ~/.codelab cat config.yaml',
        'ls ~/.codelab/*',
        'cat .codelab/*.yaml',
        'cat ~/.codelab/config.{yaml,bak}',
      ]);
    });
  });

  group('ordinary project operations stay ordinary', () {
    test('the project root and cwd as an argument are not enough', () async {
      await _expectOrdinary([
        'rm -rf build',
        'mv a .',
        'mkdir -p src/x',
        'mkdir src',
        'cp -r src dst',
        'cp -r src .',
        'make',
        'npm test',
        'npm test -- --reporter=json',
        'git add .',
        'git commit -m "update .codelab/config.yaml"',
        'curl -o out.json https://x',
        'find . -name x',
        'tar -xf a.tar -C build',
        'unzip a.zip -d build',
        'echo x > /tmp/ok.yaml',
        'rsync -a src/ /tmp/dst/',
        'mkdir -p /tmp/work',
      ]);
    });

    test('a host path directly in HOME does not protect HOME itself', () async {
      final scope = await AgentConfigScope.resolve(
        _config(extra: ['/home/me/my.yaml']),
        null,
      );
      CriticalMatch? find(String c) =>
          findCritical(c, cwd: '/proj', agentConfig: scope);

      expect(find('cp -r src ~'), isNull);
      expect(find('cp a ~/my.yaml')?.labels, contains(_label));
    });

    test('destroying the root or an ancestor stays critical', () async {
      await _expectCritical([
        'rm -rf ~',
        'mv ~ /tmp/x',
        'rmdir /home',
        'ln -s x /launch',
      ]);
    });
  });

  group('masks (glob and brace) that can reach a protected path', () {
    test('are critical (fail closed)', () async {
      await _expectCritical([
        'rm .codelab/*',
        'rm ~/.codelab/*.yaml',
        'rm -f ~/.codelab/**',
        'echo x > .codelab/config.local.y?ml',
        'echo x > ~/.codelab/config.y?ml',
        'rm ~/.codelab/config.{yaml,bak}',
        'mv ~/.codelab/config.yaml{,.bak}',
        'rm .codelab/config.[a-z]*',
        'rm .codelab/{config,cli}.yaml',
        'cp x .codelab/{a,config.yaml}',
        'rm ~/.codelab/age*/x.md',
        'rm -rf ~/.c*',
        'rm -rf .c*',
        'rm ~/.codelab/c*',
        'rm ~/.codelab/s*',
        'rm .codelab/c*',
        'ln -s ~/.codelab/config.yaml link',
        'ln -s .codelab/config.local.yaml /tmp/x',
        r'ln -sf $CODELAB_HOME/secrets.yaml x',
        'rm -rf .*',
        'rm ~/.codelab/agents/*.md',
        r'rm $CODELAB_HOME/*',
        'rm /launch/.codelab/conf*',
        'echo x > /etc/codelab/*.yaml',
        'rm .codelab/config.*',
        'cp x .codelab/*',
      ]);
    });

    test('that cannot reach a protected path are ordinary', () async {
      await _expectOrdinary([
        'rm build/*',
        'rm *.o',
        'rm -rf b*',
        'rm -rf ./b*',
        'rm ~/*.log',
        'rm .codelab/notes*',
        'echo x > /tmp/*.yaml',
        'rm -f {a,b}.txt',
        'rm ~/.cache/*',
        'cp x src/{a,b}',
      ]);
    });

    test('without host paths: only the project masks', () async {
      await _expectCritical([
        'rm .codelab/*',
        'echo x > .codelab/config.local.y?ml',
        'rm .codelab/config.{yaml,bak}',
      ], host: false);
      await _expectOrdinary(['rm ~/.codelab/*'], host: false);
    });
  });

  group('git commands that wipe or roll back the working tree', () {
    test('are critical', () async {
      await _expectCritical([
        'git clean -f',
        'git clean -fd',
        'git clean -fdx',
        'git clean -fX',
        'git clean --force -d',
        'git checkout .',
        'git checkout -- .',
        'git checkout HEAD -- .',
        'git checkout -- ..',
        'git checkout -- /proj',
        'git checkout -f main',
        'git checkout --force main',
        'git checkout --discard-changes main',
        'git restore .',
        'git restore --source=HEAD~1 .',
        'git restore -W .',
        'git restore --staged --worktree .',
        'git reset --hard',
        'git reset --hard HEAD~1',
        'git stash',
        'git stash push',
        'git stash -u',
        'git stash pop',
        'git stash drop',
        'git switch -f main',
        'git switch --discard-changes main',
        'git -C . clean -fdx',
      ]);
      await _expectCritical([
        'git clean -fdx',
        'git reset --hard',
      ], host: false);
    });

    test('safe forms are ordinary', () async {
      await _expectOrdinary([
        'git status',
        'git diff',
        'git log',
        'git add .',
        'git add -A',
        'git commit -m x',
        'git checkout main',
        'git checkout -b feature/x',
        'git switch main',
        'git pull',
        'git fetch',
        'git stash list',
        'git stash show -p',
        'git clean -n',
        'git clean --dry-run -d',
        'git reset',
        'git reset --soft HEAD~1',
        'git restore --staged file.txt',
        'git checkout -- src/a.dart',
        'git restore src',
      ]);
    });
  });

  group('read-only exceptions cannot be bypassed (A)', () {
    test('writers hidden behind readers are critical', () async {
      await _expectCritical([
        'yq --inplace=true .x=1 .codelab/config.local.yaml',
        'yq --in-place=true .x=1 ~/.codelab/config.yaml',
        'yq --inplace .x=1 ~/.codelab/config.yaml',
        'yq -ri .x=1 ~/.codelab/config.yaml',
        'yq -i.bak .x=1 ~/.codelab/config.yaml',
        'yq -s config x.yaml ~/.codelab/config.yaml',
        'yq --split-exp=x .a ~/.codelab/config.yaml',
        'jq --inplace .a ~/.codelab/config.yaml',
        'cd ~/.codelab && yq --inplace=true .x=1 config.yaml',
        'cd ~/.codelab && yq -s config x.yaml',
        'cd ~/.codelab && rg --pre "tee config.yaml" x',
        'cd ~/.codelab && rg --pre-glob "*" x',
        'cd ~/.codelab && rg --search-zip x',
        'cd ~/.codelab && rg -z x',
        'cd ~/.codelab && ag --search-zip x',
        'rg --pre "tee config.yaml" x ~/.codelab/config.yaml',
        'cd ~/.codelab && git -c core.pager="tee config.yaml" log',
        'cd ~/.codelab && git -c core.fsmonitor="sh -c x" status',
        'cd ~/.codelab && git -c diff.external=evil diff',
        'cd ~/.codelab && git --config-env=a=B log',
        'cd ~/.codelab && git --exec-path=/tmp/x log',
        'cd ~/.codelab && git --git-dir=/tmp/x log',
        'cd ~/.codelab && git --work-tree=/tmp/x log',
        'cd ~/.codelab && git --no-pager -c x=y log',
        'cd ~/.codelab && git diff --ext-diff',
        'cd ~/.codelab && git diff --textconv',
        'cd ~/.codelab && git log --output=x',
        'cd ~/.codelab && file -C -m x',
        'cd ~/.codelab && file --compile -m x',
      ]);
    });

    test('plain reads in the same places stay ordinary', () async {
      await _expectOrdinary([
        'cd ~/.codelab && git log',
        'cd ~/.codelab && git diff',
        'cd ~/.codelab && git --no-pager log',
        'cd ~/.codelab && git -C . status',
        'cd ~/.codelab && rg x',
        'rg x .codelab',
        'rg -n x ~/.codelab',
        'ag x .codelab',
        'cd ~/.codelab && yq .a config.yaml',
        'cd ~/.codelab && jq .a config.yaml',
        'yq --indent 2 .a ~/.codelab/config.yaml',
        'grep -f pats ~/.codelab/config.yaml',
        'diff --to-file=x ~/.codelab/config.yaml',
        'cd ~/.codelab && file config.yaml',
      ]);
    });
  });

  group('two-step writes into a broad ancestor (B)', () {
    test('extractors and patchers are critical', () async {
      await _expectCritical([
        'tar -xf a.tar',
        'tar xf a.tar',
        'tar -xzf a.tar.gz',
        'tar --extract -f a.tar',
        'tar -xf a.tar -C .',
        'tar -xf a.tar --directory=.',
        'tar -xf a.tar -C ..',
        'tar -xf a.tar -C ~',
        'tar -xf a.tar -C /home',
        'bsdtar -xf a.tar',
        'cd ~ && tar -xf a.tar',
        'cd /proj && unzip -o evil.zip',
        'unzip -o evil.zip',
        'unzip evil.zip -d .',
        'unzip evil.zip -d ~',
        'cpio -id < a.cpio',
        'cpio -i < a.cpio',
        'cpio --extract < a.cpio',
        'cpio -p .',
        '7z x a.7z',
        '7z e a.7z',
        '7za x a.7z -o.',
        'rsync -a evil/ ./',
        'rsync -a evil .',
        'rsync -a --delete empty/ ~/.codelab/',
        'rsync -a evil/ ~/',
        'cp -r evil/. .',
        'cp -r evil/* .',
        'cp -a evil/. .',
        'cp -R evil/.* .',
        'cp -r evil/. ~',
        'git apply p.patch',
        'git apply --check p.patch',
        'git am evil.mbox',
        'git -C sub apply p.patch',
        'patch -p1 -i p.patch',
        'patch -p1 < evil.patch',
        'cd build && patch -p1 < evil.patch',
      ]);
    });

    test('extraction elsewhere and archive reads are ordinary', () async {
      await _expectOrdinary([
        'tar -xf a.tar -C build',
        'tar -xf a.tar --directory=build',
        'cd build && tar -xf a.tar',
        'cd build && unzip a.zip',
        'unzip x.zip -d /tmp/x',
        'unzip -l a.zip',
        'unzip -p a.zip f',
        'rsync -a src/ build/',
        'rsync -a src/ /tmp/dst/',
        'rsync -a -e ssh src/ build/',
        'tar -cf a.tar src',
        'tar -tf a.tar',
        'tar -czf a.tar.gz src',
        'cpio -o < list',
        'cd build && cpio -id < a.cpio',
        'cd build && 7z x a.7z',
        '7z x a.7z -obuild',
        '7z l a.7z',
        'cp -r src dst',
        'cp -r src .',
        'cp -r build/. /tmp/b',
        'cp -r evil/* build',
        'cp file.txt .',
      ]);
    });
  });

  group('option values that are commands (A2)', () {
    test('are analysed as nested command text', () async {
      await _expectCritical([
        'git -c core.pager="tee ~/.codelab/config.yaml" log',
        'git -c core.fsmonitor="sh -c \'echo x > .codelab/config.yaml\'" status',
        'git -c core.sshCommand="tee .codelab/config.yaml" fetch',
        'git -c core.editor="tee ~/.codelab/config.yaml" commit',
        'git -c diff.external="tee ~/.codelab/config.yaml" diff',
        'git -c diff.x.textconv="tee ~/.codelab/config.yaml" diff',
        'git -c sequence.editor="tee ~/.codelab/config.yaml" rebase -i HEAD',
        'git -c alias.x="!tee ~/.codelab/config.yaml" x',
        'git --no-pager -c core.pager="rm ~/.codelab/config.yaml" log',
        'git --config-env=core.pager=EVIL log',
        'git --config-env core.pager=EVIL log',
        'rg --pre "tee ~/.codelab/config.yaml" x',
        'rg --pre="tee ~/.codelab/config.yaml" x',
        r'find . -exec tee ~/.codelab/config.yaml \;',
        r'find . -execdir sh -c "echo x > .codelab/config.yaml" \;',
        r'find . -ok rm .codelab/config.yaml \;',
        'find . -name x -exec rm ~/.codelab/config.yaml {} +',
      ]);
    });

    test('harmless values stay ordinary', () async {
      await _expectOrdinary([
        'git -c core.pager=less log',
        'git -c user.name=x commit -m y',
        "git -c user.name=\"O'Brien\" commit -m y",
        'git -c alias.x="!echo hi" x',
        'rg --pre cat x',
        'rg --pre="cat" x src',
        r'find . -name x -exec echo {} \;',
        'find . -exec grep x {} +',
      ]);
    });
  });

  group('environment and launcher commands (final pass)', () {
    test('environment variables holding a command', () async {
      await _expectCritical([
        'GIT_PAGER="tee ~/.codelab/config.yaml" git log',
        'env GIT_PAGER="tee ~/.codelab/config.yaml" git log',
        'export GIT_PAGER="tee ~/.codelab/config.yaml"; git log',
        'export GIT_PAGER="tee ~/.codelab/config.yaml" && git log',
        'GIT_PAGER="tee ~/.codelab/config.yaml"; git log',
        'PAGER="tee ~/.codelab/config.yaml" git log',
        'GIT_EXTERNAL_DIFF="tee .codelab/config.yaml" git diff',
        'GIT_EDITOR="tee .codelab/config.yaml" git commit',
        'EDITOR="tee .codelab/config.yaml" git commit',
        'VISUAL="tee .codelab/config.yaml" git commit',
        'GIT_SEQUENCE_EDITOR="tee .codelab/config.yaml" git rebase -i HEAD',
        'GIT_SSH_COMMAND="tee .codelab/config.yaml" git fetch',
        'GIT_SSH="tee .codelab/config.yaml" git fetch',
        'GIT_ASKPASS="tee .codelab/config.yaml" git fetch',
        'SSH_ASKPASS="tee .codelab/config.yaml" ssh x',
        'LESSOPEN="|tee ~/.codelab/config.yaml %s" less x',
        'LESSOPEN="||tee ~/.codelab/config.yaml %s" less x',
        'LESSCLOSE="tee ~/.codelab/config.yaml" less x',
        'EDITOR="tee ~/.codelab/config.yaml" git commit',
        'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.pager '
            'GIT_CONFIG_VALUE_0=evil git log',
        'GIT_CONFIG_PARAMETERS="\'core.pager=evil\'" git log',
        'GIT_EXEC_PATH=/tmp/x git log',
        'GIT_DIR=/tmp/x git log',
        'env GIT_WORK_TREE=/tmp/x git status',
        'export GIT_DIR=/tmp/x',
      ]);
      // Изменено change `harden-exec-cwd-tracking` (D8, D9): переменная-
      // команда запускается программой в неизвестном каталоге, и команда не
      // из белого списка чтения (`vim`, `lesspipe`) там критична с меткой
      // `write in unknown working directory`. Прежние ожидания
      // `EDITOR=vim git commit` и `LESSOPEN="|lesspipe %s" less x`
      // перенесены в `exec_working_dir_test.dart`.
      await _expectOrdinary([
        'PAGER=less git log',
        'GIT_PAGER=cat git log',
        'export EDITOR=vim',
        'FOO=bar make',
      ]);
    });

    test('BSD cp, ditto and jar', () async {
      await _expectCritical([
        'cp -R evil/ .',
        'cp -pR evil/ ~/',
        'cd /proj && cp -a /tmp/evil/ .',
        'ditto evil .',
        'ditto evil/ ~/',
        'jar xf a.jar',
        'jar -xf a.jar',
        'jar x',
      ]);
      await _expectOrdinary([
        'cp -r src/ build/',
        'cp -R src/ /tmp/b/',
        'ditto src build',
        'cd build && jar xf a.jar',
        'jar cf a.jar src',
        'jar tf a.jar',
      ]);
    });

    test('git config keys with commands or includes, tree rewriters', () async {
      await _expectCritical([
        'git -c interactive.diffFilter="tee ~/.codelab/config.yaml" add -p',
        'git -c core.hooksPath=/tmp/h commit',
        'git -ccore.hooksPath=/tmp/h commit',
        'git -ccore.pager="tee ~/.codelab/config.yaml" log',
        'git -c user.name=x -c core.hooksPath=/tmp/h commit',
        'git -c include.path=/tmp/x log',
        'git -c includeIf.gitdir:/a/.path=/tmp/x log',
        'git checkout-index -a',
        'git checkout-index -f -a',
        'git checkout-index --all',
        'git read-tree -u HEAD',
        'git read-tree -m -u HEAD',
      ]);
      await _expectOrdinary([
        'git -c interactive.diffFilter=cat add -p',
        'git checkout-index file.txt',
        'git read-tree HEAD',
        'git read-tree -m HEAD',
      ]);
    });

    test('launchers with a command string', () async {
      await _expectCritical([
        'watch "tee ~/.codelab/config.yaml"',
        'watch -n 1 "tee ~/.codelab/config.yaml"',
        'watch -n1 tee ~/.codelab/config.yaml',
        'watch --interval 2 "rm .codelab/config.yaml"',
        'script -c "tee ~/.codelab/config.yaml" out.txt',
        'script -q -c "rm .codelab/config.yaml" /dev/null',
        'script --command="tee .codelab/config.yaml" out',
      ]);
      await _expectOrdinary([
        'watch -n 1 ls',
        'watch "git status"',
        'script -c "ls" out.txt',
      ]);
    });
  });

  // Исправление пределов §7.6.1: `env -S` и склеенные короткие флаги.
  group('env -S и склеенные флаги со значением (PERM-11, §7.6.1)', () {
    const skill = '/home/me/.agents/skills/x/SKILL.md';
    const extra = [skill];

    Future<void> expectCriticalWith(Iterable<String> commands) async {
      for (final command in commands) {
        final match = await _find(command, extra: extra);
        expect(match?.labels, contains(_label), reason: command);
      }
    }

    test('значение env -S / --split-string — вложенная команда', () async {
      await expectCriticalWith([
        "env -S 'rm ~/.codelab/config.yaml'",
        "env --split-string='rm ~/.codelab/config.yaml'",
        "env --split-string 'rm ~/.codelab/config.yaml'",
        "env -S'rm ~/.codelab/config.yaml'",
        "env -iS 'rm ~/.codelab/config.yaml'",
        "env -S 'rm ~/.agents/skills/x/SKILL.md'",
        "env -u A -S 'rm ~/.agents/skills/x/SKILL.md'",
        "env -S 'tee .codelab/config.yaml'",
      ]);
    });

    test(
      'склеенные короткие флаги со значением дают кандидатов пути',
      () async {
        await expectCriticalWith([
          'curl -sSo/home/me/.agents/skills/x/SKILL.md https://x',
          'curl -sSo /home/me/.agents/skills/x/SKILL.md https://x',
          r'curl -sSo$CODELAB_HOME/config.yaml https://x',
          r'wget -qO$CODELAB_HOME/config.yaml https://x',
          'wget -qO ~/.codelab/config.yaml https://x',
          'wget -qO~/.agents/skills/x/SKILL.md https://x',
          'curl -sSo.codelab/config.yaml https://x',
          'curl -fsSo.codelab/config.yaml https://x',
        ]);
      },
    );

    test('обычные формы остаются обычными', () async {
      for (final command in [
        'env FOO=1 ls',
        'env -S ls',
        "env -S 'ls -la'",
        "env --split-string='echo hi'",
        'ls -la',
        'grep -rn x',
        'wget -qO- https://x',
        'curl -sSo out.json https://x',
        'curl -sSoout.json https://x',
        'wget -qOout.json https://x',
      ]) {
        expect(await _find(command, extra: extra), isNull, reason: command);
      }
    });
  });

  // Ревью fix «env -S» (PERM-11, §7.6.1): кластеры флагов и разбор env -S.
  group('кластеры флагов: границы и предел длины', () {
    test('числовые и символьные флаги не роняют политику', () async {
      for (final command in [
        'kill -15 4242',
        'zstd -19 f',
        'xz -9e f',
        'zip -9r a d',
        'date -d -1day',
        'curl -#o out x',
        'cp -/x y',
      ]) {
        expect(await _find(command), isNull, reason: command);
      }
    });

    test('цифры внутри кластера не прячут значение', () async {
      await _expectCritical([
        'wget -q4O~/.codelab/config.yaml https://x',
        'curl -s1o.codelab/config.yaml https://x',
        r'wget -q4O$CODELAB_HOME/config.yaml https://x',
      ]);
    });

    test('слишком длинный кластер — неразбираемая команда', () async {
      // Не `\w`-символы: регулярное выражение forkBomb на длинной цепочке
      // `\w` квадратично само по себе (известная проблема §7.6.1,
      // «исправляется отдельной задачей»). Предел проверяем по метке, а не
      // по времени: перебор суффиксов не запускается вовсе.
      final match = await _find('cp -${'.' * 32000} x');
      expect(match?.labels, ['unparsable command']);
      // Длинный параметр `-d{json}` у curl тоже попадает под предел.
      final json = await _find('curl -d${'{"a":1}' * 100} https://x');
      expect(json?.labels, ['unparsable command']);
      // Слово у команды чтения предел не затрагивает.
      expect(await _find('grep -${'a' * 400} x'), isNull);
    });

    test('суффиксы кластера: пути находятся, обычные слова — нет', () async {
      await _expectCritical([
        'curl -sSo/home/me/.codelab/config.yaml https://x',
        'wget -q4O~/.codelab/config.yaml https://x',
        r'wget -q4O$CODELAB_HOME/config.yaml https://x',
        'curl -sSo.codelab/config.yaml https://x',
      ]);
      // Относительное имя при cwd в каталоге конфигурации.
      final inConfig = await _find(
        'curl -sSoconfig.yaml https://x',
        cwd: '/home/me/.codelab',
      );
      expect(inConfig?.labels, contains(_label));
      expect(await _find('curl -sSoout.json https://x'), isNull);
    });
  });

  group('env -S: границы разбора (ревью)', () {
    test('опции env кончаются на значении -S', () async {
      await _expectCritical([
        'env -S rm -rf ~/.codelab',
        "env -S'' rm -rf ~/.codelab",
        'env --split-string= rm -rf ~/.codelab',
      ]);
    });

    test('значение -S может начинаться с опций и присваиваний', () async {
      await _expectCritical([
        "env -S '-i rm ~/.codelab/config.yaml'",
        "env -S '-S rm ~/.codelab/config.yaml'",
        "env -S '-u X rm ~/.codelab/config.yaml'",
        "env -S 'A=1 rm ~/.codelab/config.yaml'",
        "env -S '-C ~/.codelab rm config.yaml'",
        "env -C ~/.codelab -S 'rm config.yaml'",
      ]);
    });

    test('слова после значения передаются как есть, без склейки', () async {
      await _expectCritical([
        "env -S 'rm' '#' ~/.codelab/config.yaml",
        "env -S 'rm' 'x;' ~/.codelab/config.yaml",
        "env -S 'rm' \"it's\" ~/.codelab/config.yaml",
      ]);
    });

    test('escape-последовательности GNU env -S', () async {
      await _expectCritical([
        r"env -S 'rm\_~/.codelab/config.yaml'",
        r"env -S 'rm\t~/.codelab/config.yaml'",
        r"env -S 'rm\n~/.codelab/config.yaml'",
        r"env -S 'rm ~/.codelab/config.yaml\c ignored'",
        r"env -S 'rm \$X ~/.codelab/config.yaml'",
      ]);
      await _expectOrdinary([r"env -S 'ls\cX'"]);
      // Неизвестный escape — неразбираемая команда (fail closed).
      expect(
        (await _find(r"env -S 'rm\q x'"))?.labels,
        contains('unparsable command'),
      );
      expect(
        (await _find(r"env -S 'rm\'"))?.labels,
        contains('unparsable command'),
      );
    });

    test('сокращения длинных опций env', () async {
      await _expectCritical([
        "env --sp 'rm ~/.codelab/config.yaml'",
        "env --split 'rm ~/.codelab/config.yaml'",
        "env --split-s='rm ~/.codelab/config.yaml'",
        'env --ch=~/.codelab tee config.yaml',
        'env --chd ~/.codelab tee config.yaml',
        'env --un X rm ~/.codelab/config.yaml',
        'env --unset X rm ~/.codelab/config.yaml',
      ]);
    });

    test('много -S: остаток собирается один раз, результат обычный', () async {
      // Опции env заканчиваются на первом -S, остальные -S — слова остатка.
      expect(await _find('env${' -S x' * 1000}'), isNull);
    });

    test('-a / --argv0 / -P берут значение', () async {
      await _expectCritical([
        'env -a x rm ~/.codelab/config.yaml',
        'env --argv0 x rm ~/.codelab/config.yaml',
        'env --argv0=x rm ~/.codelab/config.yaml',
        'env -P /tmp rm ~/.codelab/config.yaml',
      ]);
      await _expectOrdinary(['env -a x ls', 'env --argv0=x ls']);
    });
  });

  group(r"ANSI-C $'…' в путях (PERM-11, §7.6.1)", () {
    test('раскрытый путь конфигурации критичен', () async {
      await _expectCritical([
        r"rm $'\x7e'/.codelab/config.yaml",
        r"rm $'\x7e/.codelab/config.yaml'",
        r'rm $"~/.codelab/config.yaml"',
      ]);
      await _expectOrdinary([r"echo $'a\tb'", r"ls $'\x7e'"]);
    });

    test(r"байты кириллицы в соседних $'…' не ускользают", () async {
      const extra = ['/home/Сергей/.codelab/config.yaml'];
      for (final command in [
        r"rm $'/home/\320'$'\241ергей/.codelab/config.yaml'",
        r"rm -rf $'/home/\320'$'\241ергей'",
        r"env -S $'rm\x20-rf\x20/home/\320'$'\241ергей'",
      ]) {
        expect(await _find(command, extra: extra), isNotNull, reason: command);
      }
    });

    test(
      'путь с кириллицей, записанный байтами, совпадает с защищаемым',
      () async {
        const extra = ['/home/Сергей/.codelab/config.yaml'];
        const name = r'\320\241\320\265\321\200\320\263\320\265\320\271';
        const hexName = r'\xd0\xa1\xd0\xb5\xd1\x80\xd0\xb3\xd0\xb5\xd0\xb9';
        for (final command in [
          "rm \$'/home/$name/.codelab/config.yaml'",
          "rm \$'/home/$hexName/.codelab/config.yaml'",
          "rm \$'/home/$name'/.codelab/config.yaml",
        ]) {
          final match = await _find(command, extra: extra);
          expect(match?.labels, contains(_label), reason: command);
        }
        expect(
          await _find('rm /home/Сергей/.codelab/config.yaml', extra: extra),
          isNotNull,
        );
      },
    );
  });
}
