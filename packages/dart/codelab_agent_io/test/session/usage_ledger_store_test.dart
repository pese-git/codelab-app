import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

import 'journal_helpers.dart';

/// Файл `usage.json` в каталоге сессии (agent-sessions «Файл usage.json и
/// порт UsageLedgerStore», сценарий «Удалённый файл восстанавливается»;
/// design.md change `add-usage-ledger`, D3, D13; `agent-core-architecture`
/// §8.9). Задача 1.5.
///
/// Всё — во временном каталоге; настоящий `~/.codelab` не читается.
void main() {
  late String root;
  late JsonlSessionStore sessions;
  late JsonlUsageLedgerStore port;

  const id = '01JB8Q2W6R9T3M5K7N1P4X8Z0A';
  const sid = SessionId(id);

  setUp(() async {
    root = tempRoot('usage_ledger_', addTearDown);
    sessions = storeAt(root);
    port = JsonlUsageLedgerStore(sessions);
    await sessions.create(headerOf(id));
  });

  /// Каталог сессии: путь файла журнала без `.jsonl` (§8.9).
  String sessionDir() {
    final journal = journalFile(root, id).path;
    return journal.substring(0, journal.length - '.jsonl'.length);
  }

  String ledgerPath() => '${sessionDir()}/usage.json';

  test('write: <journal without .jsonl>/usage.json, the content as is, no '
      'temporary file left', () async {
    await port.write(sid, '{"version":1}\n');

    expect(File(ledgerPath()).readAsStringSync(), '{"version":1}\n');
    expect(File('${ledgerPath()}.tmp').existsSync(), isFalse);
    expect(
      Directory(sessionDir()).listSync().map((e) => e.path.split('/').last),
      ['usage.json'],
    );
  });

  test('write replaces the previous content', () async {
    await port.write(sid, 'old\n');

    await port.write(sid, 'new\n');

    expect(File(ledgerPath()).readAsStringSync(), 'new\n');
    expect(File('${ledgerPath()}.tmp').existsSync(), isFalse);
  });

  test('read returns what was written; a missing file is null', () async {
    expect(await port.read(sid), isNull);

    await port.write(sid, '{"version":1}\n');

    expect(await port.read(sid), '{"version":1}\n');
  });

  test('read of a session the store does not know is null', () async {
    expect(
      await port.read(const SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0Z')),
      isNull,
    );
  });

  test('the file path is inside the root of the sessions', () async {
    await port.write(sid, 'x\n');

    expect(ledgerPath(), startsWith('$root/'));
    expect(File(ledgerPath()).existsSync(), isTrue);
  });

  test('a SessionId with a path does not get out of the sessions root: a '
      'typed error, no file anywhere (D13)', () async {
    const evil = SessionId('../../escaped');

    await expectLater(
      port.write(evil, 'x\n'),
      throwsA(isA<UsageLedgerStoreException>()),
    );
    expect(await port.read(evil), isNull);
    // Кандидатные места, куда привёл бы путь, склеенный из id: рядом с корнем
    // и выше него. Список родителя не читается — на macOS он закрыт.
    for (final path in [
      '$root/../../escaped',
      '$root/../../escaped/usage.json',
      '$root/../escaped',
    ]) {
      expect(
        FileSystemEntity.typeSync(path),
        FileSystemEntityType.notFound,
        reason: path,
      );
    }
  });

  test('a journal that leads out of the root through a symlink: read is '
      'null, write is a typed error, nothing appears outside (D13)', () async {
    final outside = tempRoot('usage_ledger_outside_', addTearDown);
    final journal = journalFile(root, id);
    final moved = File('$outside/moved.jsonl');
    journal.copySync(moved.path);
    journal.deleteSync();
    Link(journal.path).createSync(moved.path);

    expect(await port.read(sid), isNull);
    await expectLater(
      port.write(sid, 'x\n'),
      throwsA(isA<UsageLedgerStoreException>()),
    );

    expect(File(ledgerPath()).existsSync(), isFalse);
    expect(
      Directory(
        outside,
      ).listSync(recursive: true).where((e) => e.path.contains('usage.json')),
      isEmpty,
    );
  }, skip: Platform.isWindows ? 'symlink требует прав на Windows' : false);

  test('a session directory that is a symlink out of the root: the same '
      '(D13)', () async {
    final outside = tempRoot('usage_ledger_outside_', addTearDown);
    final slug = Directory(journalFile(root, id).parent.path);
    final moved = Directory('$outside/slug')..createSync();
    for (final entity in slug.listSync()) {
      (entity as File).copySync(
        '${moved.path}/${entity.uri.pathSegments.last}',
      );
    }
    slug.deleteSync(recursive: true);
    Link(slug.path).createSync(moved.path);

    expect(await port.read(sid), isNull);
    await expectLater(
      port.write(sid, 'x\n'),
      throwsA(isA<UsageLedgerStoreException>()),
    );

    expect(
      Directory(
        outside,
      ).listSync(recursive: true).where((e) => e.path.contains('usage.json')),
      isEmpty,
    );
  }, skip: Platform.isWindows ? 'symlink требует прав на Windows' : false);

  group('links inside the session data (review, D13)', () {
    final noLinks = Platform.isWindows
        ? 'symlink требует прав на Windows'
        : false;

    /// Файл вне корня с содержимым [text].
    File outsideFile(String text) {
      final dir = tempRoot('usage_ledger_outside_', addTearDown);
      return File('$dir/target.txt')..writeAsStringSync(text);
    }

    test('the data directory is a symlink out of the root: read is null, '
        'write is a typed error, nothing is written outside', () async {
      final outside = tempRoot('usage_ledger_outside_', addTearDown);
      Link(sessionDir()).createSync(outside);

      expect(await port.read(sid), isNull);
      await expectLater(
        port.write(sid, 'x\n'),
        throwsA(isA<UsageLedgerStoreException>()),
      );

      expect(Directory(outside).listSync(), isEmpty);
    }, skip: noLinks);

    test('usage.json.tmp is a symlink: it is replaced, the target outside '
        'is not touched', () async {
      final target = outsideFile('KEEP');
      Directory(sessionDir()).createSync(recursive: true);
      Link('${ledgerPath()}.tmp').createSync(target.path);

      await port.write(sid, 'new\n');

      expect(target.readAsStringSync(), 'KEEP');
      expect(File(ledgerPath()).readAsStringSync(), 'new\n');
      expect(
        FileSystemEntity.typeSync(ledgerPath(), followLinks: false),
        FileSystemEntityType.file,
      );
    }, skip: noLinks);

    test('usage.json is a symlink: read is null (a huge target is not read), '
        'write replaces the link and leaves the target alone', () async {
      final target = outsideFile('KEEP');
      Directory(sessionDir()).createSync(recursive: true);
      Link(ledgerPath()).createSync(target.path);

      expect(await port.read(sid), isNull);
      await port.write(sid, 'new\n');

      expect(target.readAsStringSync(), 'KEEP');
      expect(await port.read(sid), 'new\n');
    }, skip: noLinks);

    test('usage.json is a symlink to a file over the limit: read is null '
        'without reading it', () async {
      final target = outsideFile('');
      final handle = target.openSync(mode: FileMode.write)
        ..truncateSync(64 * 1024 * 1024)
        ..closeSync();
      expect(handle, isNotNull);
      Directory(sessionDir()).createSync(recursive: true);
      Link(ledgerPath()).createSync(target.path);

      expect(await port.read(sid), isNull);
    }, skip: noLinks);
  });

  test('a file over the limit (32 MiB): read is a typed error, so the core '
      'treats it as invalid and rebuilds', () async {
    Directory(sessionDir()).createSync(recursive: true);
    File(ledgerPath()).openSync(mode: FileMode.write)
      ..truncateSync(33 * 1024 * 1024)
      ..closeSync();

    await expectLater(
      port.read(sid),
      throwsA(isA<UsageLedgerStoreException>()),
    );
    // Файл в пределах нормы читается.
    File(ledgerPath()).writeAsStringSync('ok\n');
    expect(await port.read(sid), 'ok\n');
  });

  test('an OS failure while looking for the journal is a typed error '
      'without the path (not a crash)', () async {
    // Свежее хранилище без кеша путей: поиск журнала листает каталог слага.
    final fresh = JsonlUsageLedgerStore(storeAt(root));
    final slug = journalFile(root, id).parent;
    Process.runSync('chmod', ['000', slug.path]);
    addTearDown(() => Process.runSync('chmod', ['700', slug.path]));
    try {
      slug.listSync();
      markTestSkipped('the user can list a closed directory (root)');
      return;
    } on FileSystemException {
      // Каталог закрыт — то, что нужно.
    }

    for (final action in [() => fresh.read(sid), () => fresh.write(sid, 'x')]) {
      await expectLater(
        action(),
        throwsA(
          isA<UsageLedgerStoreException>().having(
            (e) => e.message,
            'message',
            allOf(isNotEmpty, isNot(contains(root))),
          ),
        ),
      );
    }
  }, skip: Platform.isWindows ? 'chmod есть только на POSIX' : false);

  test('a directory without write permission: UsageLedgerStoreException '
      'with a reason, the process lives, no temporary file', () async {
    final dir = Directory(sessionDir())..createSync(recursive: true);
    final chmod = await Process.run('chmod', ['500', dir.path]);
    expect(chmod.exitCode, 0);
    addTearDown(() => Process.runSync('chmod', ['700', dir.path]));
    // Суперпользователь пишет и в такой каталог: проверка бессмысленна.
    try {
      File('${dir.path}/probe').writeAsStringSync('x');
      File('${dir.path}/probe').deleteSync();
      markTestSkipped('the user can write to a read-only directory (root)');
      return;
    } on FileSystemException {
      // Каталог закрыт — то, что нужно.
    }

    await expectLater(
      port.write(sid, 'x\n'),
      throwsA(
        isA<UsageLedgerStoreException>().having(
          (e) => e.message,
          'message',
          isNotEmpty,
        ),
      ),
    );
    expect(File('${ledgerPath()}.tmp').existsSync(), isFalse);
    expect(File(ledgerPath()).existsSync(), isFalse);
  }, skip: Platform.isWindows ? 'chmod есть только на POSIX' : false);

  test('a deleted usage.json is rebuilt byte for byte the same by the core '
      '(scenario "Удалённый файл восстанавливается")', () async {
    final logger = RecordingLogger();
    final model = ScriptedStreamFunction.fromJson({
      'steps': [
        for (var i = 0; i < 2; i++)
          {
            'reply': [
              {'text': 'answer $i'},
            ],
            'usage': {
              'input': 100 + i,
              'output': 10,
              'cost': {'input': 0.0003, 'output': 0.0001},
            },
          },
      ],
    });
    final core = buildAgentCore(
      profile: HostProfile.of('agent-serve').narrowed({
        HostCapability.shellExec: const CapabilityOff('тест без shell'),
      }),
      services: AgentCoreServices(
        baseEnv: MemoryExecutionEnv(cwd: '/work/demo'),
        logger: logger,
        clock: FakeClock(start: t0),
        ids: SequentialIdGenerator(),
        sessions: sessions,
        usageLedger: port,
      ),
      config: CoreConfig(
        defaultModel: ModelRef(
          provider: 'test',
          id: 'model-1',
          api: ProviderApi.openaiChat,
          baseUrl: Uri.parse('http://localhost:8080/v1'),
          contextWindow: 32768,
          maxOutputTokens: 4096,
        ),
      ),
      streamFunction: model.call,
    );
    addTearDown(core.runtime.dispose);
    final session = await core.runtime.createSession(
      SessionSpec(cwd: '/work/demo'),
    );
    await session.prompt(const [TextContent('first task')]);
    await session.prompt(const [TextContent('second task')]);
    final first = await session.usageLedger();
    final file = File('${_sessionDirOf(root, session.id.value)}/usage.json');
    expect(first.state, UsageLedgerFileState.rebuilt);
    expect(file.existsSync(), isTrue);
    final bytes = file.readAsBytesSync();
    file.deleteSync();

    final again = await session.usageLedger();

    expect(again.state, UsageLedgerFileState.rebuilt);
    expect(again.reason, UsageLedgerRebuildReason.missing);
    expect(file.readAsBytesSync(), bytes);
  });
}

/// Каталог сессии с идентификатором [id] под [root] (§8.9).
String _sessionDirOf(String root, String id) {
  final journal = journalFile(root, id).path;
  return journal.substring(0, journal.length - '.jsonl'.length);
}
