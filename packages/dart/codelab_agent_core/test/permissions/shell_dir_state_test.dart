// Модульные тесты состояния рабочего каталога оболочки (`agent-core/
// 07-permissions.md` §7.6.2; change `harden-exec-cwd-tracking`, D1, D3–D5):
// множество вариантов с пределом и переходы встроенных команд без разбора
// строки целиком.
import 'package:codelab_agent_core/src/permissions/agent_config_rules.dart';
import 'package:codelab_agent_core/src/permissions/shell_dir_state.dart';
import 'package:codelab_agent_core/src/permissions/shell_lexer.dart';
import 'package:test/test.dart';

DirContext _context(String command) =>
    DirContext.of(command, parseShell(command), ConfigCheck('/w', null));

DirVariants _at(String dir, {String? oldPwd, List<String>? stack = const []}) =>
    DirVariants({ShellDirState(dir, oldPwd: oldPwd, stack: stack)});

Set<String> _dirs(DirVariants variants) => {
  for (final v in variants.known) v.dir,
};

void main() {
  group('DirVariants', () {
    test('предел известных вариантов схлопывает множество в «неизвестно»', () {
      final many = [
        for (var i = 0; i <= maxDirVariants; i++) ShellDirState('/a$i'),
      ];

      expect(DirVariants(many.take(maxDirVariants)).unknown, isFalse);
      final collapsed = DirVariants(many);
      expect(collapsed.known, isEmpty);
      expect(collapsed.unknown, isTrue);
    });

    test('объединение сохраняет «неизвестно» и убирает повторы', () {
      final both = _at('/a').union(_at('/a')).union(DirVariants.onlyUnknown);

      expect(_dirs(both), {'/a'});
      expect(both.unknown, isTrue);
      expect(DirVariants.empty.isEmpty, isTrue);
    });

    test('варианты отличаются OLDPWD и стеком', () {
      final set = _at('/a', oldPwd: '/b').union(_at('/a', stack: ['/c']));

      expect(set.known, hasLength(2));
    });
  });

  group('dirCommandFlow', () {
    test('cd: успех — новый каталог и OLDPWD, неуспех — прежнее', () {
      final flow = dirCommandFlow('cd', ['/x'], _at('/w'), _context('cd /x'));

      expect(flow.ok.known.single, const ShellDirState('/x', oldPwd: '/w'));
      expect(_dirs(flow.fail), {'/w'});
    });

    test('cd - берёт OLDPWD, без него — «неизвестно»', () {
      final context = _context('cd -');

      expect(
        _dirs(dirCommandFlow('cd', ['-'], _at('/w', oldPwd: '/p'), context).ok),
        {'/p'},
      );
      expect(
        dirCommandFlow('cd', ['-'], _at('/w'), context).ok.unknown,
        isTrue,
      );
    });

    test('pushd и popd ведут стек; пустой стек — неуспех', () {
      final context = _context('pushd /a');
      final pushed = dirCommandFlow('pushd', ['/a'], _at('/w'), context).ok;
      expect(pushed.known.single.stack, ['/w']);

      final popped = dirCommandFlow('popd', [], pushed, context).ok;
      expect(_dirs(popped), {'/w'});
      expect(popped.known.single.stack, isEmpty);

      final empty = dirCommandFlow('popd', [], _at('/w'), context);
      expect(empty.ok.isEmpty, isTrue);
      expect(_dirs(empty.fail), {'/w'});
    });

    test('pushd без аргумента меняет каталог и вершину стека', () {
      final context = _context('pushd');
      final flow = dirCommandFlow(
        'pushd',
        [],
        _at('/a', stack: ['/b', '/c']),
        context,
      );

      expect(flow.ok.known.single.dir, '/b');
      expect(flow.ok.known.single.stack, ['/a', '/c']);
    });

    test('цель с переменной, подстановкой, ~user, маской — «неизвестно»', () {
      for (final target in [r'$X', r'$(pwd)', '`pwd`', '~bob', '*', '{a,b}']) {
        final flow = dirCommandFlow(
          'cd',
          [target],
          _at('/w'),
          _context('cd x'),
        );
        expect(flow.ok.unknown, isTrue, reason: target);
        expect(flow.ok.known, isEmpty, reason: target);
      }
    });

    test('CDPATH в строке: относительная цель без ./ неизвестна', () {
      final context = _context('CDPATH=/x cd sub');

      expect(
        dirCommandFlow('cd', ['sub'], _at('/w'), context).ok.unknown,
        isTrue,
      );
      expect(_dirs(dirCommandFlow('cd', ['./sub'], _at('/w'), context).ok), {
        '/w/sub',
      });
      expect(_dirs(dirCommandFlow('cd', ['/abs'], _at('/w'), context).ok), {
        '/abs',
      });
    });

    test(
      'из «неизвестно» известна только абсолютная цель; стек неизвестен',
      () {
        final context = _context('cd /x');
        final absolute = dirCommandFlow(
          'cd',
          ['/x'],
          DirVariants.onlyUnknown,
          context,
        );

        expect(
          absolute.ok.known.single,
          const ShellDirState('/x', stack: null),
        );
        expect(absolute.fail.unknown, isTrue);
        expect(
          dirCommandFlow(
            'cd',
            ['x'],
            DirVariants.onlyUnknown,
            context,
          ).ok.unknown,
          isTrue,
        );
        expect(
          dirCommandFlow('popd', [], absolute.ok, context).ok.unknown,
          isTrue,
        );
      },
    );

    test('dirs с опциями делает стек неизвестным', () {
      final flow = dirCommandFlow('dirs', ['-c'], _at('/w'), _context('dirs'));

      expect(flow.ok.known.single.stack, isNull);
      expect(
        _dirs(dirCommandFlow('dirs', [], _at('/w'), _context('dirs')).ok),
        {'/w'},
      );
    });
  });
}
