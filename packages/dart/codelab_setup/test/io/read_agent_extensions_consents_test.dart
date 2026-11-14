import 'dart:async';
import 'dart:io';

import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart';
import 'package:test/test.dart';

import '../support/real_home.dart';

/// Кандидаты согласия `readAgentExtensions`: предел времени и записей,
/// доверие, ссылки (ревью итерации 1: MEDIUM безопасность «сбор кандидатов
/// без предела», LOW `granted` у недоверенного проекта, ссылки; design.md
/// change `add-app-skills-page`, D4, D7, Q3).
///
/// Почему: каталоги кандидатов называет пользователь, а лежать они могут на
/// сетевом томе или быть огромными; сбор не должен вешать страницу, как не
/// вешает её загрузчик навыков (таймаут фазы 5 с, предел записей).
///
/// Фиксируемый API швов: `readAgentExtensions(..., consentTimeout:,
/// consentEntryLimit:, scanConsentDir:)`; `ConsentDirScanner` —
/// функция `(path, entryLimit)`, возвращающая число подкаталогов, `null` —
/// каталога нет. Таймаут сбора — кандидат остаётся без числа (`skillDirs == null`):
/// каталог, не ответивший за предел, скорее всего существует (том завис), и
/// согласие на него по-прежнему можно дать.
void main() {
  late RealHome home;
  late String project;
  late String userHome;

  void write(String path, String text) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  void skill(String root, String name) => write(
    '$root/$name/SKILL.md',
    '---\nname: $name\ndescription: D\n---\nB\n',
  );

  setUp(() {
    home = RealHome.create('read_consents_');
    userHome = home.root.path;
    project = Directory(home.project).resolveSymbolicLinksSync();
  });

  tearDown(() => home.dispose());

  void config({bool trusted = true, String extra = ''}) => home.writeConfig(
    '$gatewayProvider'
    'agent:\n  default_model: gw/m\n'
    '${trusted ? 'trusted_projects:\n  - $project\n' : ''}'
    '$extra',
  );

  Future<AgentExtensionsView> read({
    Duration consentTimeout = const Duration(seconds: 5),
    int consentEntryLimit = 1000,
    ConsentDirScanner? scan,
  }) async => readAgentExtensions(
    await home.load(),
    codelabHome: home.home,
    environment: {'HOME': userHome, 'CODELAB_HOME': home.home},
    consentTimeout: consentTimeout,
    consentEntryLimit: consentEntryLimit,
    scanConsentDir: scan,
  );

  test('a source that never answers: the candidate stays without a count '
      'after the limit, the page still reads', () async {
    config();
    final asked = <String>[];

    final view = await read(
      consentTimeout: const Duration(milliseconds: 20),
      scan: (path, limit) {
        asked.add(path);
        return Completer<int?>().future;
      },
    );

    expect(asked, ['$project/.claude/skills', '$userHome/.claude/skills']);
    expect(
      [for (final c in view.skills.consents) c.entry],
      ['.claude/skills', '~/.claude/skills'],
    );
    expect(view.skills.consents.map((c) => c.skillDirs), everyElement(isNull));
    expect(view.skills.outcome, isA<SectionRead>());
  });

  test(
    'a scanner that throws drops only that candidate, not the page',
    () async {
      config();

      final view = await read(
        scan: (path, limit) async {
          if (path.startsWith(project)) {
            throw const FileSystemException('denied');
          }
          return 3;
        },
      );

      expect(
        [for (final c in view.skills.consents) (c.entry, c.skillDirs)],
        [('~/.claude/skills', 3)],
      );
    },
  );

  test('a scanner that throws any error, not only a file one, drops only '
      'that candidate and the view is built', () async {
    config();

    final view = await read(
      scan: (path, limit) async {
        if (path.startsWith(project)) {
          throw StateError('boom');
        }
        return 3;
      },
    );

    expect(view.skills.outcome, isA<SectionRead>());
    expect(
      [for (final c in view.skills.consents) (c.entry, c.skillDirs)],
      [('~/.claude/skills', 3)],
    );
  });

  test('the entry limit bounds the scan', () async {
    config();
    for (var i = 0; i < 5; i++) {
      skill('$project/.claude/skills', 's$i');
    }

    final view = await read(consentEntryLimit: 2);

    expect(view.skills.consents.single.skillDirs, 2);
  });

  test('a symlinked subdirectory is neither counted nor followed', () async {
    config();
    skill('$project/.claude/skills', 'real');
    skill('${home.root.path}/outside', 'secret');
    Link(
      '$project/.claude/skills/linked',
    ).createSync('${home.root.path}/outside/secret');

    final view = await read();

    expect(view.skills.consents.single.skillDirs, 1);
  }, skip: Platform.isWindows ? 'symlink needs privileges' : false);

  test(
    'an untrusted project: the relative candidate is listed, but a '
    'relative extra_roots entry is not "granted" (the loader ignores it)',
    () async {
      config(
        trusted: false,
        extra:
            'skills:\n  extra_roots:\n    - .claude/skills\n    - ~/.claude/skills\n',
      );
      skill('$project/.claude/skills', 'one');
      skill('$userHome/.claude/skills', 'home-one');

      final view = await read();

      expect(view.trusted, isFalse);
      expect(
        {
          for (final c in view.skills.consents)
            c.entry: (c.skillDirs, c.granted),
        },
        {
          '.claude/skills': (1, false),
          // Домашний корень читается и в недоверенном проекте.
          '~/.claude/skills': (1, true),
        },
      );
    },
  );
}
