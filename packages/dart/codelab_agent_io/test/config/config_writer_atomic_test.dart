import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:codelab_agent_io/src/config/config_writer.dart'
    show ConfigWriteSeam;
import 'package:test/test.dart';

import '../support/config_writer_harness.dart';
import '../support/fake_secret_process_runner.dart';

/// Атомарность и права записи `ConfigWriter` (agent-configuration «Запись
/// конфига ConfigWriter», сценарии «Сбой между tmp и переименованием»,
/// «Сбой смены прав», «Символическая ссылка и права»; design.md change
/// `add-config-writer-and-reload`, D5, шаги 3 и 7 §17.5.5; CFG-13).
///
/// `chmod` идёт через фейковый `SecretProcessRunner`: порядок вызовов и
/// размер tmp в момент вызова фиксирует фейк. Между записью tmp и `rename`
/// стоит тестовый шов `ConfigWriteSeam.tmpWritten`.
void main() {
  const user = ConfigTarget.user();
  late ConfigWriterHarness h;

  tearDown(() => h.dispose());

  Future<ConfigWriteResult> setSteps(
    ConfigWriterHarness harness, [
    int v = 3,
  ]) => harness.writer
      .read(user)
      .then(
        (snapshot) =>
            harness.writer.apply(snapshot, [SetValue('budget.max_steps', v)]),
      );

  /// Первая запись в пустой слой: загрузке нужна модель по умолчанию, поэтому
  /// провайдер и `agent.default_model` пишутся одной правкой.
  Future<ConfigWriteResult> writeFirst(ConfigWriterHarness harness) => harness
      .writer
      .read(user)
      .then(
        (snapshot) => harness.writer.apply(snapshot, [
          const SetValue('providers.p.kind', 'openai-compatible'),
          const SetValue('providers.p.base_url', 'https://llm.test/v1'),
          const SetValue('providers.p.models.m.context_window', 8192),
          const SetValue('agent.default_model', 'p/m'),
        ]),
      );

  int mode(String path) => File(path).statSync().mode & 0x1FF;

  group('сбой между tmp и переименованием', () {
    test('исходный файл цел, tmp и lock убраны, ошибка называет тип', () async {
      String? tmpDuringSeam;
      String? contentDuringSeam;
      late ConfigWriterHarness local;
      h = local = ConfigWriterHarness.create(
        seam: (point) async {
          if (point != ConfigWriteSeam.tmpWritten) {
            return;
          }
          final tmps = local
              .leftovers(local.userPath)
              .where((name) => name.startsWith('config.yaml.tmp-'));
          tmpDuringSeam = tmps.single;
          contentDuringSeam = local.read('${local.home}/$tmpDuringSeam');
          throw const FileSystemException('simulated crash before rename');
        },
      );
      h.write(h.userPath, baseConfig);

      await expectLater(
        setSteps(h),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.issues.single.message,
            'message',
            'cannot write ${h.userPath}: FileSystemException',
          ),
        ),
      );

      expect(contentDuringSeam, contains('max_steps: 3'));
      expect(tmpDuringSeam, isNotNull);
      expect(h.read(h.userPath), baseConfig);
      expect(h.leftovers(h.userPath), isEmpty);
    });

    test('следующая запись удаляет брошенный tmp старше 10 с', () async {
      h = ConfigWriterHarness.create();
      h.write(h.userPath, baseConfig);
      final dead = '${h.userPath}.tmp-999-dead';
      final live = '${h.userPath}.tmp-998-live';
      final foreign = '${h.userPath}.bak';
      for (final path in [dead, live, foreign]) {
        h.write(path, 'x');
      }
      h.touch(dead, age: const Duration(seconds: 11));
      h.touch(live, age: const Duration(seconds: 1));
      h.touch(foreign, age: const Duration(minutes: 5));

      await setSteps(h);

      expect(File(dead).existsSync(), isFalse);
      expect(File(live).existsSync(), isTrue);
      expect(File(foreign).existsSync(), isTrue);
    });
  });

  group('права файла', () {
    test('chmod выставляется на пустой tmp до записи содержимого', () async {
      final runner = FakeSecretProcessRunner();
      int? sizeAtSeam;
      late ConfigWriterHarness local;
      h = local = ConfigWriterHarness.create(
        runner: runner,
        seam: (point) async {
          if (point == ConfigWriteSeam.tmpWritten) {
            sizeAtSeam = File(runner.calls.single.arguments.last).lengthSync();
          }
        },
      );
      h.write(h.userPath, baseConfig);
      Process.runSync('/bin/chmod', ['640', h.userPath]);

      await setSteps(local);

      final call = runner.calls.single;
      expect(call.executable, endsWith('/chmod'));
      expect(call.arguments.first, '640');
      expect(call.arguments.last, startsWith('${h.userPath}.tmp-'));
      expect(call.lastArgumentLength, 0, reason: 'tmp пуст при вызове chmod');
      expect(sizeAtSeam, greaterThan(0), reason: 'потом содержимое записано');
      expect(mode(h.userPath), 0x1A0); // 0640
    });

    test('новый файл: chmod не вызывается, права по umask', () async {
      final runner = FakeSecretProcessRunner();
      h = ConfigWriterHarness.create(runner: runner);

      await writeFirst(h);

      expect(runner.calls, isEmpty);
      expect(File(h.userPath).existsSync(), isTrue);
    });

    test('Сбой смены прав: код выхода не 0', () async {
      final runner = FakeSecretProcessRunner(failWhen: (_) => true);
      var reachedSeam = false;
      h = ConfigWriterHarness.create(
        runner: runner,
        seam: (point) async => reachedSeam = true,
      );
      h.write(h.userPath, baseConfig);
      Process.runSync('/bin/chmod', ['600', h.userPath]);

      await expectLater(
        setSteps(h),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.issues.single.message,
            'message',
            'cannot set permissions on ${h.userPath}',
          ),
        ),
      );

      expect(h.read(h.userPath), baseConfig);
      expect(mode(h.userPath), 0x180);
      expect(h.leftovers(h.userPath), isEmpty, reason: 'tmp удалён, lock снят');
      expect(runner.calls.single.lastArgumentLength, 0);
      expect(reachedSeam, isFalse, reason: 'содержимое в tmp не писалось');
    });

    test('Сбой смены прав: исключение порта и таймаут', () async {
      for (final SecretProcessRunner runner in [
        FakeSecretProcessRunner(
          beforeRun: (_) => throw const ProcessException('chmod', ['600']),
        ),
        _TimedOutRunner(),
      ]) {
        h = ConfigWriterHarness.create(runner: runner);
        h.write(h.userPath, baseConfig);

        await expectLater(
          setSteps(h),
          throwsA(
            isA<ConfigException>().having(
              (e) => e.issues.single.message,
              'message',
              startsWith('cannot set permissions on'),
            ),
          ),
        );
        expect(h.read(h.userPath), baseConfig);
        expect(h.leftovers(h.userPath), isEmpty);
        h.dispose();
      }
      h = ConfigWriterHarness.create();
    });

    test('ветка Windows: права не переносятся', () async {
      final runner = FakeSecretProcessRunner();
      h = ConfigWriterHarness.create(runner: runner, platform: 'windows');
      h.write(h.userPath, baseConfig);

      await setSteps(h);

      expect(runner.calls, isEmpty);
      expect(h.read(h.userPath), contains('max_steps: 3'));
    });
  });

  group('символическая ссылка', () {
    test(
      'Символическая ссылка и права: правится цель, ссылка остаётся',
      () async {
        h = ConfigWriterHarness.create();
        final target = '${h.root.path}/dotfiles/config.yaml';
        h.write(target, baseConfig);
        Process.runSync('/bin/chmod', ['600', target]);
        Link(h.userPath).createSync(target);

        final result = await setSteps(h);

        expect(
          FileSystemEntity.typeSync(h.userPath, followLinks: false),
          FileSystemEntityType.link,
        );
        expect(Link(h.userPath).targetSync(), target);
        expect(h.read(target), contains('max_steps: 3'));
        expect(mode(target), 0x180);
        expect(result.path, target);
        expect(h.leftovers(target), isEmpty);
        expect(h.leftovers(h.userPath), isEmpty);
      },
    );

    test(
      'ссылка на несуществующий файл: цель создаётся, ссылка остаётся',
      () async {
        h = ConfigWriterHarness.create();
        final target = '${h.root.path}/dotfiles/config.yaml';
        Directory('${h.root.path}/dotfiles').createSync();
        Link(h.userPath).createSync(target);

        await writeFirst(h);

        expect(
          FileSystemEntity.typeSync(h.userPath, followLinks: false),
          FileSystemEntityType.link,
        );
        expect(h.read(target), contains('default_model: p/m'));
      },
    );
  });

  group('каталоги', () {
    test('созданный писателем CODELAB_HOME получает права 0700', () async {
      final runner = FakeSecretProcessRunner();
      h = ConfigWriterHarness.create(runner: runner);
      Directory(h.home).deleteSync();

      await writeFirst(h);

      expect(mode(h.home), 0x1C0); // 0700
      expect(runner.calls.first.arguments, ['700', h.home]);
    });

    test('цепочка ссылок длиннее 32 переходов — ConfigException', () async {
      h = ConfigWriterHarness.create();
      Link('${h.home}/loop-b').createSync(h.userPath);
      Link(h.userPath).createSync('${h.home}/loop-b');

      await expectLater(
        h.writer.read(user),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.issues.single.message,
            'message',
            contains('too many symbolic links'),
          ),
        ),
      );
    });
  });

  test('относительный codelabHome приводится к абсолютному', () async {
    // Каталог процесса — общий временный каталог, `home` — путь относительно
    // него. Каталог процесса возвращается в `addTearDown`.
    final previous = Directory.current;
    addTearDown(() => Directory.current = previous);
    final temp = Directory.systemTemp.resolveSymbolicLinksSync();
    Directory.current = temp;
    h = ConfigWriterHarness.create(
      homeFor: (home) => home.substring(temp.length + 1),
    );
    h.write(h.userPath, baseConfig);

    final snapshot = await h.writer.read(user);
    final result = await h.writer.apply(snapshot, [
      const SetValue('budget.max_steps', 3),
    ]);

    expect(snapshot.path, h.userPath);
    expect(result.path, h.userPath);
    expect(h.read(h.userPath), contains('max_steps: 3'));
  });

  group('ссылки проектных слоёв', () {
    late String outside;
    late ConfigTarget project;

    setUp(() {
      h = ConfigWriterHarness.create();
      outside = '${h.root.path}/outside';
      Directory(outside).createSync();
      project = ConfigTarget.project(h.cwd);
      h.write(h.userPath, '${baseConfig}trusted_projects: ["${h.cwd}"]\n');
    });

    Future<void> expectRefused() async {
      await expectLater(
        h.writer
            .read(project)
            .then(
              (snapshot) => h.writer.apply(snapshot, [
                const SetValue('budget.max_steps', 3),
              ]),
            ),
        throwsA(isA<ConfigException>()),
      );
    }

    test('ссылка на существующий файл вне .codelab отклоняется', () async {
      h.write('$outside/real.yaml', 'budget:\n  max_steps: 9\n');
      Directory('${h.cwd}/.codelab').createSync();
      Link(h.projectPath).createSync('$outside/real.yaml');

      await expectRefused();

      expect(h.read('$outside/real.yaml'), 'budget:\n  max_steps: 9\n');
      expect(h.leftovers('$outside/real.yaml'), isEmpty);
    });

    test('висячая ссылка наружу отклоняется, цель не создаётся', () async {
      Directory('${h.cwd}/.codelab').createSync();
      Link(h.projectPath).createSync('$outside/new.yaml');

      await expectRefused();

      expect(File('$outside/new.yaml').existsSync(), isFalse);
      expect(Directory(outside).listSync(), isEmpty);
    });

    test('сам .codelab — ссылка наружу: каталоги не создаются', () async {
      Link('${h.cwd}/.codelab').createSync(outside);

      await expectRefused();

      expect(Directory(outside).listSync(), isEmpty);
    });

    test(
      'относительная ссылка с .. на несуществующий каталог отклоняется',
      () async {
        Directory('${h.cwd}/.codelab').createSync();
        Link(h.localPath).createSync('../../missing/x.yaml');

        await expectLater(
          h.writer
              .read(ConfigTarget.projectLocal(h.cwd))
              .then(
                (snapshot) => h.writer.apply(snapshot, [
                  const SetValue('budget.max_steps', 3),
                ]),
              ),
          throwsA(isA<ConfigException>()),
        );

        expect(Directory('${h.root.path}/missing').existsSync(), isFalse);
        expect(h.leftovers(h.localPath), isEmpty);
      },
    );

    test(
      'относительная ссылка на соседний новый каталог отклоняется',
      () async {
        Directory('${h.cwd}/.codelab').createSync();
        Link(h.localPath).createSync('../../sibling/new/x.yaml');

        await expectLater(
          h.writer
              .read(ConfigTarget.projectLocal(h.cwd))
              .then(
                (snapshot) => h.writer.apply(snapshot, [
                  const SetValue('budget.max_steps', 3),
                ]),
              ),
          throwsA(isA<ConfigException>()),
        );

        expect(Directory('${h.root.path}/sibling').existsSync(), isFalse);
      },
    );

    test('ссылка внутри .codelab допустима', () async {
      Directory('${h.cwd}/.codelab').createSync();
      h.write('${h.cwd}/.codelab/shared.yaml', '# shared\n');
      Link(h.projectPath).createSync('${h.cwd}/.codelab/shared.yaml');

      await h.writer
          .read(project)
          .then(
            (snapshot) => h.writer.apply(snapshot, [
              const SetValue('budget.max_steps', 3),
            ]),
          );

      expect(h.read('${h.cwd}/.codelab/shared.yaml'), contains('max_steps'));
    });
  });

  group('lock', () {
    test('содержимое lock: pid и случайный nonce хоста', () async {
      String? lockText;
      late ConfigWriterHarness local;
      h = local = ConfigWriterHarness.create(
        seam: (point) async {
          if (point == ConfigWriteSeam.tmpWritten) {
            lockText = local.read('${local.userPath}.lock');
          }
        },
      );

      h.write(h.userPath, baseConfig);
      await setSteps(local);

      expect(lockText, matches(RegExp('^$pid [0-9a-f]{32}\$')));
      expect(File('${h.userPath}.lock').existsSync(), isFalse);
    });

    test(
      'lock подменён другим писателем до rename: конфликт, файл цел',
      () async {
        // Писатель, потерявший lock (его сочли устаревшим), не должен
        // переименовывать tmp поверх файла (D5, шаг 2; ревью итерации 3).
        late ConfigWriterHarness local;
        h = local = ConfigWriterHarness.create(
          seam: (point) async {
            if (point == ConfigWriteSeam.tmpWritten) {
              local.write('${local.userPath}.lock', '31337 other');
            }
          },
        );
        h.write(h.userPath, baseConfig);

        await expectLater(
          setSteps(local),
          throwsA(isA<ConfigConflictException>()),
        );

        expect(h.read('${h.userPath}.lock'), '31337 other', reason: 'чужой');
        expect(h.read(h.userPath), baseConfig);
        expect(h.leftovers(h.userPath), ['config.yaml.lock']);
      },
    );

    test('lock снят другим писателем до rename: конфликт', () async {
      late ConfigWriterHarness local;
      h = local = ConfigWriterHarness.create(
        seam: (point) async {
          if (point == ConfigWriteSeam.tmpWritten) {
            File('${local.userPath}.lock').deleteSync();
          }
        },
      );
      h.write(h.userPath, baseConfig);

      await expectLater(
        setSteps(local),
        throwsA(isA<ConfigConflictException>()),
      );

      expect(h.read(h.userPath), baseConfig);
      expect(h.leftovers(h.userPath), isEmpty);
    });

    test('файл изменён до rename: конфликт, правка другого цела', () async {
      late ConfigWriterHarness local;
      const manual = '$baseConfig# manual\n';
      h = local = ConfigWriterHarness.create(
        seam: (point) async {
          if (point == ConfigWriteSeam.tmpWritten) {
            File(local.userPath).writeAsStringSync(manual);
          }
        },
      );
      h.write(h.userPath, baseConfig);

      await expectLater(
        setSteps(local),
        throwsA(isA<ConfigConflictException>()),
      );

      expect(h.read(h.userPath), manual);
      expect(h.leftovers(h.userPath), isEmpty);
    });

    test('чистка брошенных tmp идёт только под своим lock', () async {
      h = ConfigWriterHarness.create();
      h.write(h.userPath, baseConfig);
      h.write('${h.userPath}.lock', '4242 aaaa');
      h.touch('${h.userPath}.lock', age: const Duration(seconds: 1));
      final dead = '${h.userPath}.tmp-999-dead';
      h.write(dead, 'x');
      h.touch(dead, age: const Duration(seconds: 60));

      await expectLater(setSteps(h), throwsA(isA<ConfigConflictException>()));

      expect(File(dead).existsSync(), isTrue);
    });

    test('таймаут chmod строго меньше возраста устаревшего lock', () async {
      final runner = _CapturingRunner();
      h = ConfigWriterHarness.create(runner: runner);
      h.write(h.userPath, baseConfig);

      await setSteps(h);

      expect(runner.timeout, isNotNull);
      expect(runner.timeout! < const Duration(seconds: 10), isTrue);
    });

    test('lock снимается и после отказа проверки', () async {
      h = ConfigWriterHarness.create();
      h.write(h.userPath, baseConfig);

      await expectLater(setSteps(h, 0), throwsA(isA<ConfigException>()));

      expect(h.leftovers(h.userPath), isEmpty);
    });
  });
}

/// Порт, чей процесс убит по таймауту (`timedOut: true`).
final class _TimedOutRunner implements SecretProcessRunner {
  @override
  Future<SecretProcessResult> run(
    String executable,
    List<String> arguments, {
    String? stdin,
    Duration? timeout,
  }) async => const SecretProcessResult(exitCode: -1, timedOut: true);
}

/// Порт, запоминающий таймаут вызова `chmod`.
final class _CapturingRunner implements SecretProcessRunner {
  Duration? timeout;

  @override
  Future<SecretProcessResult> run(
    String executable,
    List<String> arguments, {
    String? stdin,
    Duration? timeout,
  }) async {
    this.timeout = timeout;
    return const SecretProcessResult(exitCode: 0);
  }
}
