import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

import '../support/fake_secret_process_runner.dart';

/// Бэкенд `file` (agent-secrets «Бэкенд file», все сценарии; design.md change
/// `add-agent-secret-store`, D14). Файлы — во временном `CODELAB_HOME`; тест
/// не читает настоящий `~/.codelab`. Права и ссылки проверяются на macOS и
/// Linux; ветка Windows — подменённой платформой.
void main() {
  late Directory root;
  late String path;
  late String home;
  late String tmpDir;
  late RecordingLogger logger;
  late FakeSecretProcessRunner runner;

  FileSecretStore open({
    String? platform,
    SecretProcessRunner? with_,
    void Function()? onRenamed,
  }) => FileSecretStore(
    path: path,
    runner: with_ ?? runner,
    logger: logger,
    platform: platform ?? 'linux',
    onRenamed: onRenamed,
  );

  void chmod(String mode, String target) {
    final result = Process.runSync('/bin/chmod', [mode, target]);
    expect(result.exitCode, 0);
  }

  /// Файл в формате D14 с правами [mode].
  void seed(Map<String, String> values, {String mode = '600'}) {
    final lines = [
      '# CodeLab secrets in plaintext. Managed by: codelab secret set|delete',
      for (final key in values.keys.toList()..sort())
        '${jsonEncode(key)}: ${jsonEncode(values[key])}',
    ];
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('${lines.join('\n')}\n');
    chmod('700', File(path).parent.path);
    chmod(mode, path);
  }

  String modeOf(String target) =>
      (File(target).statSync().mode & 0x1ff).toRadixString(8);

  Future<void> expectRefused(
    Future<Object?> Function() action,
    Matcher reason,
  ) => expectLater(
    action(),
    throwsA(
      isA<SecretStoreUnavailableException>()
          .having((e) => e.backend, 'backend', 'file')
          .having((e) => e.reason, 'reason', reason),
    ),
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('file_secret_store_test');
    home = '${root.path}/home';
    path = '$home/secrets.yaml';
    tmpDir = '$home/.secrets-tmp';
    logger = RecordingLogger();
    runner = FakeSecretProcessRunner();
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('describes itself as the writable file backend', () {
    final backend = open().backend;

    expect(backend.id, 'file');
    expect(backend.writable, isTrue);
  });

  group('permissions are checked before every access', () {
    test(
      '0644 refuses read, write, delete and names with chmod hint',
      () async {
        seed({'codelab/openai': 'sk-file-value'}, mode: '644');
        final store = open();
        final hint = allOf(
          contains('has permissions 0644; run: chmod 600 $path'),
          isNot(contains('sk-file-value')),
        );

        await expectRefused(() => store.read('codelab/openai'), hint);
        await expectRefused(() => store.write('codelab/b', 'x'), hint);
        await expectRefused(() => store.delete('codelab/openai'), hint);
        await expectRefused(() => store.names(), hint);

        final refused = logger.eventsOf('secrets.file.refused');
        expect(refused, hasLength(1));
        expect(refused.single.level, LogLevel.warning);
        expect(refused.single.fields, {'path': path, 'mode': '0644'});
        expect(logger.records.join('\n'), isNot(contains('sk-file-value')));
        expect(runner.calls, isEmpty);
      },
    );

    test('0640 and 0604 are refused as well (group or other bits)', () async {
      for (final mode in ['640', '604']) {
        seed({'codelab/a': 'v'}, mode: mode);
        await expectRefused(
          () => open().read('codelab/a'),
          contains('has permissions 0$mode'),
        );
      }
    });

    test('0400 is accepted for reading', () async {
      seed({'codelab/a': 'v'}, mode: '400');

      expect(await open().read('codelab/a'), 'v');
    });

    test('a symbolic link is refused even if its target is 0600', () async {
      final real = '${root.path}/real.yaml';
      File(real).writeAsStringSync('"codelab/a": "v"\n');
      chmod('600', real);
      Directory(home).createSync(recursive: true);
      chmod('700', home);
      Link(path).createSync(real);

      await expectRefused(
        () => open().read('codelab/a'),
        contains('is a symbolic link; refusing to read secrets'),
      );

      final refused = logger.eventsOf('secrets.file.refused');
      expect(refused, hasLength(1));
      expect(refused.single.fields, {'path': path, 'reason': 'symlink'});
    });
  });

  group('the file is created only by write', () {
    test('read, delete and names of a missing file do not create it', () async {
      final store = open();

      expect(await store.read('codelab/a'), isNull);
      await store.delete('codelab/a');
      expect(await store.names(), isEmpty);

      expect(File(path).existsSync(), isFalse);
      expect(Directory(File(path).parent.path).existsSync(), isFalse);
      expect(runner.calls, isEmpty);
    });

    test(
      'write creates the file with 0600 and read returns the value',
      () async {
        final store = open();

        await store.write('codelab/a', 'topvalue-1');

        expect(File(path).statSync().mode & 0x1ff, 0x180); // 0o600
        expect(await open().read('codelab/a'), 'topvalue-1');
        expect(await store.names(), ['codelab/a']);
        expect(
          File(path).readAsStringSync(),
          startsWith('# CodeLab secrets in plaintext.'),
        );
      },
    );

    test('permissions are set before the value is written; argv has only the '
        'path', () async {
      await open().write('codelab/a', 'topvalue-2');

      // Первая запись создаёт и сам каталог (700), затем приватный каталог
      // tmp (700) и временный файл (600).
      expect(runner.calls.map((c) => c.arguments.first), ['700', '700', '600']);
      expect(runner.calls[0].arguments.last, home);
      expect(runner.calls[1].arguments.last, tmpDir);
      final call = runner.calls[2];
      expect(call.executable, '/bin/chmod');
      expect(call.arguments, hasLength(2));
      expect(call.arguments.last, startsWith('$tmpDir/secrets.tmp-'));
      for (final c in runner.calls) {
        expect(c.arguments.join(' '), isNot(contains('topvalue-2')));
        expect(c.stdin, isNull);
      }
      // В момент chmod временный файл уже есть и ещё пуст.
      expect(call.lastArgumentLength, 0);
    });

    test('the tmp file lives in a private 0700 directory while it is still '
        'unrestricted: nobody else can open it by path', () async {
      String? dirModeAtChmod;
      List<String>? homeEntries;
      String? tmpParent;
      late final FakeSecretProcessRunner spy;
      spy = FakeSecretProcessRunner(
        beforeRun: (n) {
          final target = spy.calls.last.arguments.last;
          if (spy.calls.last.arguments.first == '600') {
            tmpParent = File(target).parent.path;
            dirModeAtChmod = modeOf(tmpParent!);
            homeEntries = Directory(home)
                .listSync(followLinks: false)
                .map((e) => e.uri.pathSegments.where((x) => x.isNotEmpty).last)
                .toList();
            // Пока права файла шире, а дескриптор можно открыть только
            // владельцем: путь недоступен остальным пользователям.
            expect(modeOf(target), isNot('600'));
          }
        },
      );

      await open(with_: spy).write('codelab/a', 'topvalue-5');

      expect(tmpParent, tmpDir);
      expect(dirModeAtChmod, '700');
      expect(homeEntries, ['.secrets-tmp']);
      expect(modeOf(path), '600');
      expect(File(tmpDir).existsSync(), isFalse);
      expect(Directory(tmpDir).listSync(), isEmpty);
    });

    test(
      'a tmp file with wider permissions never receives the value',
      () async {
        seed({'codelab/old': 'oldvalue'});
        // Независимо от umask: права файла явно 0644, «успех без эффекта».
        late final FakeSecretProcessRunner lying;
        lying = FakeSecretProcessRunner(
          skipWhen: (arguments) => arguments.first == '600',
          beforeRun: (_) {
            final arguments = lying.calls.last.arguments;
            if (arguments.first == '600') {
              chmod('644', arguments.last);
            }
          },
        );

        await expectRefused(
          () => open(with_: lying).write('codelab/a', 'topvalue-3'),
          contains('permissions'),
        );

        for (final entity in Directory(home).listSync(recursive: true)) {
          if (entity is File) {
            expect(entity.readAsStringSync(), isNot(contains('topvalue-3')));
          }
        }
        expect(await open().read('codelab/old'), 'oldvalue');
      },
    );

    test('a failing chmod keeps the previous file untouched', () async {
      seed({'codelab/old': 'oldvalue'});
      final before = File(path).readAsStringSync();
      final failing = FakeSecretProcessRunner(
        beforeRun: (_) => throw const FileSystemException('boom'),
      );

      await expectRefused(
        () => open(with_: failing).write('codelab/a', 'topvalue-4'),
        isNot(contains('topvalue-4')),
      );

      expect(File(path).readAsStringSync(), before);
    });
  });

  group('atomic write', () {
    test('a failure before the rename keeps the old file and the next write '
        'removes the leftover tmp', () async {
      seed({'codelab/old': 'oldvalue'});
      final before = File(path).readAsBytesSync();
      final failing = FakeSecretProcessRunner(
        beforeRun: (_) => throw const FileSystemException('interrupted'),
      );
      await expectLater(
        open(with_: failing).write('codelab/a', 'v'),
        throwsA(isA<SecretStoreUnavailableException>()),
      );
      expect(File(path).readAsBytesSync(), before);

      // Остаток от убитого процесса: старый tmp с чужим pid (отказ случился
      // при проверке владельца, до создания .secrets-tmp, поэтому каталог
      // создаётся здесь).
      Directory(tmpDir).createSync();
      chmod('700', tmpDir);
      final stale = File('$tmpDir/secrets.tmp-424242-0-aa')
        ..writeAsStringSync('junk');
      stale.setLastModifiedSync(
        DateTime.now().subtract(const Duration(minutes: 11)),
      );

      await open().write('codelab/a', 'v');

      expect(stale.existsSync(), isFalse);
      expect(Directory(tmpDir).listSync(), isEmpty);
      expect(await open().read('codelab/old'), 'oldvalue');
      expect(await open().read('codelab/a'), 'v');
    });

    test('writes of one store are queued and none is lost', () async {
      final store = open();

      await Future.wait([
        for (var i = 0; i < 6; i++) store.write('codelab/k$i', 'v$i'),
      ]);

      expect(await store.names(), [for (var i = 0; i < 6; i++) 'codelab/k$i']);
    });
  });

  group('values and structure', () {
    test(
      'quotes, backslashes, unicode and YAML-looking text read back',
      () async {
        final values = {
          'codelab/quote': 'a"b',
          'codelab/slash': r'back\slash \n literal',
          'codelab/unicode': 'пароль 日本語 🔑',
          'codelab/yaml': 'x: y # z - [w] {v} &a *b !t',
          'codelab/spaces': '  lead and trail  ',
          'codelab/tab': 'a\tb',
          'codelab/lsep': 'a\u2028b\u0085c\u007fd\ufeffe',
        };
        final store = open();
        for (final entry in values.entries) {
          await store.write(entry.key, entry.value);
        }

        final fresh = open();
        for (final entry in values.entries) {
          expect(await fresh.read(entry.key), entry.value, reason: entry.key);
        }
        expect(await fresh.names(), values.keys.toList()..sort());
      },
    );

    test(
      'a value with a line break is rejected and nothing is created',
      () async {
        for (final value in ['a\nb-secretvalue', 'a\rb-secretvalue']) {
          await expectRefused(
            () => open().write('codelab/a', value),
            allOf(contains('single line'), isNot(contains('secretvalue'))),
          );
        }
        expect(File(path).existsSync(), isFalse);
      },
    );

    test(
      'an invalid name is rejected without the name in the message',
      () async {
        await expectRefused(
          () => open().write('Bad Name', 'v'),
          isNot(contains('Bad Name')),
        );
        expect(File(path).existsSync(), isFalse);
      },
    );

    test(
      'delete removes only the key; delete of an absent key is a no-op',
      () async {
        seed({'codelab/a': '1', 'codelab/b': '2'});
        final store = open();

        await store.delete('codelab/a');
        await store.delete('codelab/zzz');

        expect(await store.read('codelab/a'), isNull);
        expect(await store.read('codelab/b'), '2');
        expect(await store.names(), ['codelab/b']);
        expect(File(path).statSync().mode & 0x1ff, 0x180);
      },
    );

    for (final (label, text) in [
      ('a list', '- a\n- b-TOPSECRETLINE\n'),
      ('a nested map', 'codelab/a:\n  nested: TOPSECRETLINE\n'),
      ('a non-string value', '"codelab/a": 12\n'),
      ('a null value', '"codelab/a":\n'),
      ('a name outside SecretNames', '"Bad Name": "TOPSECRETLINE"\n'),
      ('a syntax error', 'TOPSECRETLINE: [unclosed\n'),
    ]) {
      test('$label is a typed failure without file lines', () async {
        File(path)
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(text);
        chmod('700', home);
        chmod('600', path);

        for (final action in [
          () => open().read('codelab/a'),
          () => open().names(),
          () => open().write('codelab/b', 'v'),
        ]) {
          await expectRefused(
            action,
            equals('$path is not a map of secret names to strings'),
          );
        }
      });
    }
  });

  group('process-wide write queue', () {
    test(
      'two instances over one path lose no update; file stays 0600',
      () async {
        final a = open();
        final b = open();

        await Future.wait([
          for (var i = 0; i < 5; i++) ...[
            a.write('codelab/a$i', 'va$i'),
            b.write('codelab/b$i', 'vb$i'),
          ],
        ]);

        final names = await open().names();
        expect(names, hasLength(10));
        expect(await open().read('codelab/a4'), 'va4');
        expect(await open().read('codelab/b4'), 'vb4');
        expect(modeOf(path), '600');
        expect(Directory(tmpDir).listSync(), isEmpty);
      },
    );

    test('write and delete of different instances are serialized', () async {
      seed({'codelab/x': '1'});

      await Future.wait([
        open().delete('codelab/x'),
        open().write('codelab/y', '2'),
        open().write('codelab/z', '3'),
      ]);

      expect(await open().names(), ['codelab/y', 'codelab/z']);
    });
  });

  group('CODELAB_HOME ownership and tmp directory re-verification', () {
    test('a failing no-op chmod of home (foreign owner) refuses the write '
        'before any tmp file exists', () async {
      seed({'codelab/old': 'oldvalue'});
      final before = File(path).readAsStringSync();
      final foreign = FakeSecretProcessRunner(
        failWhen: (arguments) => arguments.last == home,
      );

      await expectRefused(
        () => open(with_: foreign).write('codelab/a', 'topvalue-10'),
        allOf(
          equals(
            '$home is not owned by the current user; refusing to write '
            'secrets',
          ),
          isNot(contains('topvalue-10')),
        ),
      );

      // Единственный вызов — no-op chmod с текущим режимом каталога.
      expect(foreign.calls, hasLength(1));
      expect(foreign.calls.single.arguments, ['0700', home]);
      expect(Directory(tmpDir).existsSync(), isFalse);
      expect(File(path).readAsStringSync(), before);
      expect(logger.eventsOf('secrets.file.refused').single.fields, {
        'path': path,
        'reason': 'home_owner',
      });
    });

    test('delete is refused for a foreign home as well', () async {
      seed({'codelab/old': 'oldvalue'});
      final foreign = FakeSecretProcessRunner(
        failWhen: (arguments) => arguments.last == home,
      );

      await expectRefused(
        () => open(with_: foreign).delete('codelab/old'),
        contains('is not owned by the current user'),
      );
      expect(await open().read('codelab/old'), 'oldvalue');
    });

    test('tmp directory widened after createSync: refused, no value on '
        'disk', () async {
      seed({'codelab/old': 'oldvalue'});
      late final FakeSecretProcessRunner widening;
      widening = FakeSecretProcessRunner(
        beforeRun: (_) {
          if (widening.calls.last.arguments.first == '600') {
            chmod('777', tmpDir);
          }
        },
      );

      await expectRefused(
        () => open(with_: widening).write('codelab/a', 'topvalue-11'),
        allOf(
          contains('$tmpDir must be private'),
          isNot(contains('topvalue-11')),
        ),
      );

      for (final entity in Directory(home).listSync(recursive: true)) {
        if (entity is File) {
          expect(entity.readAsStringSync(), isNot(contains('topvalue-11')));
        }
      }
      expect(await open().read('codelab/old'), 'oldvalue');
    });

    test(
      'tmp directory replaced by a link after createSync: refused',
      () async {
        seed({'codelab/old': 'oldvalue'});
        final outside = Directory('${root.path}/elsewhere')..createSync();
        chmod('700', outside.path);
        late final FakeSecretProcessRunner swapping;
        swapping = FakeSecretProcessRunner(
          beforeRun: (_) {
            if (swapping.calls.last.arguments.first == '600') {
              final tmp = swapping.calls.last.arguments.last;
              File(tmp).copySync('${outside.path}/moved');
              Directory(tmpDir).deleteSync(recursive: true);
              Link(tmpDir).createSync(outside.path);
              File('$tmpDir/${tmp.split('/').last}').createSync();
              chmod('600', tmp);
            }
          },
        );

        await expectRefused(
          () => open(with_: swapping).write('codelab/a', 'topvalue-12'),
          isNot(contains('topvalue-12')),
        );

        for (final entity in root.listSync(recursive: true)) {
          if (entity is File) {
            expect(entity.readAsStringSync(), isNot(contains('topvalue-12')));
          }
        }
      },
    );
  });

  group('wide permissions after rename', () {
    test('a successful chmod 600 retry keeps the secrets', () async {
      final store = open(onRenamed: () => chmod('644', path));

      await store.write('codelab/a', 'topvalue-13');

      expect(modeOf(path), '600');
      expect(await open().read('codelab/a'), 'topvalue-13');
    });

    test(
      'a failed retry deletes the file and says so, without values',
      () async {
        late final FakeSecretProcessRunner stubborn;
        stubborn = FakeSecretProcessRunner(
          skipWhen: (arguments) => arguments.last == path,
        );
        final store = open(
          with_: stubborn,
          onRenamed: () => chmod('644', path),
        );

        await expectRefused(
          () => store.write('codelab/a', 'topvalue-14'),
          allOf(
            contains('$path has wider permissions than 0600 after write'),
            contains('the file was removed'),
            isNot(contains('topvalue-14')),
          ),
        );

        expect(File(path).existsSync(), isFalse);
        final refused = logger.eventsOf('secrets.file.refused');
        expect(refused.single.fields['reason'], 'wide_after_write');
        expect(logger.records.join('\n'), isNot(contains('topvalue-14')));
      },
    );
  });

  group('queue isolation and key', () {
    test('a failing write does not break the queue of the same path', () async {
      Directory(home).createSync(recursive: true);
      chmod('700', home);
      final failing = open(
        with_: FakeSecretProcessRunner(
          beforeRun: (_) => throw const FileSystemException('boom'),
        ),
      );
      final ok = open();

      final results = await Future.wait([
        failing
            .write('codelab/a', 'v1')
            .then<Object?>((_) => null)
            .catchError((Object e) => e),
        ok
            .write('codelab/b', 'v2')
            .then<Object?>((_) => null)
            .catchError((Object e) => e),
      ], eagerError: false);

      expect(results[0], isA<SecretStoreUnavailableException>());
      expect(results[1], isNull);
      expect(await open().read('codelab/b'), 'v2');
      expect(await open().read('codelab/a'), isNull);
    });

    test('equivalent paths share one queue: no update is lost', () async {
      Directory(home).createSync(recursive: true);
      chmod('700', home);
      final alias = '${root.path}/other/../home/secrets.yaml';
      Directory('${root.path}/other').createSync();
      final a = open();
      final b = FileSecretStore(
        path: alias,
        runner: runner,
        logger: logger,
        platform: 'linux',
      );

      await Future.wait([
        for (var i = 0; i < 5; i++) ...[
          a.write('codelab/a$i', 'va$i'),
          b.write('codelab/b$i', 'vb$i'),
        ],
      ]);

      expect(await open().names(), hasLength(10));
    });
  });

  group('tmp directory cleanup', () {
    test(
      'removes only abandoned files; fresh foreign tmp and links survive',
      () async {
        Directory(tmpDir).createSync(recursive: true);
        chmod('700', home);
        chmod('700', tmpDir);
        final fresh = File('$tmpDir/secrets.tmp-111-0-aa')
          ..writeAsStringSync('foreign');
        final old = File('$tmpDir/secrets.tmp-222-0-bb')
          ..writeAsStringSync('abandoned');
        old.setLastModifiedSync(
          DateTime.now().subtract(const Duration(minutes: 11)),
        );
        final target = File('${root.path}/outside.txt')
          ..writeAsStringSync('keep me');
        target.setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 5)),
        );
        final link = Link('$tmpDir/secrets.tmp-333-0-cc')
          ..createSync(target.path);

        await open().write('codelab/a', 'v');

        expect(fresh.existsSync(), isTrue);
        expect(old.existsSync(), isFalse);
        expect(link.existsSync(), isTrue);
        expect(target.readAsStringSync(), 'keep me');
      },
    );
  });

  group('directory safety', () {
    test(
      'a group-writable CODELAB_HOME is refused without chmod of it',
      () async {
        seed({'codelab/a': 'v'});
        chmod('775', home);
        final store = open();
        final hint = allOf(
          contains('$home is writable by group or others (mode 0775)'),
          contains('chmod go-w $home'),
          isNot(contains('v"')),
        );

        await expectRefused(() => store.read('codelab/a'), hint);
        await expectRefused(() => store.write('codelab/b', 'topvalue-6'), hint);
        await expectRefused(() => store.delete('codelab/a'), hint);
        await expectRefused(() => store.names(), hint);

        expect(modeOf(home), '775');
        expect(runner.calls, isEmpty);
        expect(Directory(tmpDir).existsSync(), isFalse);
        expect(logger.eventsOf('secrets.file.refused'), hasLength(1));
      },
    );

    test('a world-writable CODELAB_HOME is refused as well', () async {
      seed({'codelab/a': 'v'});
      chmod('757', home);

      await expectRefused(
        () => open().read('codelab/a'),
        contains('writable by group or others (mode 0757)'),
      );
    });

    test('CODELAB_HOME that is a symbolic link is refused', () async {
      final real = Directory('${root.path}/real')..createSync();
      chmod('700', real.path);
      Link(home).createSync(real.path);

      await expectRefused(
        () => open().write('codelab/a', 'topvalue-7'),
        contains('$home is a symbolic link'),
      );
      await expectRefused(() => open().read('codelab/a'), isNotNull);

      expect(real.listSync(), isEmpty);
      expect(runner.calls, isEmpty);
    });

    test(
      'a newly created CODELAB_HOME is made private independent of umask',
      () async {
        await open().write('codelab/a', 'v');

        expect(modeOf(home), '700');
        expect(modeOf(tmpDir), '700');
      },
    );

    test(
      'a tmp directory with wider mode is refused when chmod has no effect',
      () async {
        seed({'codelab/old': 'oldvalue'});
        Directory(tmpDir).createSync();
        chmod('755', tmpDir);
        final noop = FakeSecretProcessRunner(skipChmod: true);

        await expectRefused(
          () => open(with_: noop).write('codelab/a', 'topvalue-8'),
          contains('$tmpDir must be private'),
        );

        expect(Directory(tmpDir).listSync(), isEmpty);
        expect(await open().read('codelab/old'), 'oldvalue');
      },
    );

    test('a tmp directory that is a symbolic link is refused and not '
        'chmod-ed', () async {
      seed({'codelab/old': 'oldvalue'});
      final outside = Directory('${root.path}/outside')..createSync();
      chmod('755', outside.path);
      Link(tmpDir).createSync(outside.path);

      await expectRefused(
        () => open().write('codelab/a', 'topvalue-9'),
        contains('$tmpDir is a symbolic link'),
      );

      expect(modeOf(outside.path), '755');
      expect(outside.listSync(), isEmpty);
      // Допустима только проверка владельца CODELAB_HOME (no-op chmod), но не
      // chmod по ссылке.
      expect(runner.calls.map((c) => c.arguments.last), [home]);
    });
  });

  group('size and encoding', () {
    test(
      'content over 1 MiB is refused before replacing; file untouched',
      () async {
        final store = open();
        // 17 значений по 60 000 байт укладываются в мегабайт (одно значение не
        // может быть больше 64 КиБ), 18-е — нет.
        for (var i = 0; i < 17; i++) {
          await store.write('codelab/k$i', 'x' * 60000);
        }
        final before = File(path).readAsBytesSync();

        await expectRefused(
          () => store.write('codelab/k17', 'x' * 60000),
          equals('$path would be larger than 1 MiB'),
        );

        expect(File(path).readAsBytesSync(), before);
        expect(await open().names(), hasLength(17));
      },
    );

    test('a value over 64 KiB is refused by the store itself', () async {
      await expectRefused(
        () => open().write('codelab/a', 'x' * (64 * 1024 + 1)),
        equals('secret value is longer than 64 KiB'),
      );
      await open().write('codelab/a', 'x' * (64 * 1024));
      expect(File(path).existsSync(), isTrue);
    });

    test('a lone surrogate is rejected and nothing is written', () async {
      await expectRefused(
        () => open().write('codelab/sur', 'a\uD800b'),
        equals('secret value is not valid Unicode (unpaired surrogate)'),
      );

      expect(File(path).existsSync(), isFalse);
    });
  });

  test('secrets.file.refused is logged once per process for a path', () async {
    seed({'codelab/a': 'v'}, mode: '644');
    final second = RecordingLogger();

    await expectRefused(() => open().read('codelab/a'), isNotNull);
    await expectRefused(
      () => FileSecretStore(
        path: path,
        runner: runner,
        logger: second,
        platform: 'linux',
      ).read('codelab/a'),
      isNotNull,
    );

    expect(logger.eventsOf('secrets.file.refused'), hasLength(1));
    expect(second.eventsOf('secrets.file.refused'), isEmpty);
  });

  group('Windows', () {
    test('the substituted platform refuses every operation', () async {
      seed({'codelab/a': 'v'});
      final store = open(platform: 'windows');

      for (final action in [
        () => store.read('codelab/a'),
        () => store.write('codelab/a', 'v'),
        () => store.delete('codelab/a'),
        () => store.names(),
      ]) {
        await expectRefused(
          action,
          equals(
            'file backend is not supported on Windows; use env with '
            'CODELAB_SECRET_* variables',
          ),
        );
      }
      expect(runner.calls, isEmpty);
    });
  });

  test('the logger is optional', () async {
    final store = FileSecretStore(path: path, runner: runner);
    await store.write('codelab/a', 'v');

    expect(await store.read('codelab/a'), 'v');
  });

  test('utf8 content is stored as UTF-8', () async {
    await open().write('codelab/u', 'пароль');

    expect(utf8.decode(File(path).readAsBytesSync()), contains('пароль'));
  });
}
