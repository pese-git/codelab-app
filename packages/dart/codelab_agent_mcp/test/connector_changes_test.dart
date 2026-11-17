// Барель пакета сужен до API хоста; тесты проверяют внутренние типы.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:test/test.dart';

import 'support/supervisor_rig.dart';

/// `McpSessionTools.changes` настоящего коннектора (agent-mcp-client «Поток
/// состояний серверов сессии»; `17-5-agent-setup.md`, OQ4; design.md change
/// `add-provider-setup-ui`, D12): событие — полный список сводок после каждой
/// смены состояния, числа инструментов, `lastError` или состава серверов.
/// Время — `FakeClock`, случайность — `Random(0)`, сервер — `FakeMcpServer`
/// (PKG-6); реального процесса и сети нет.
void main() {
  const leak = 'sk-test-leak-0123456789';

  String line(List<McpServerSummary> list) =>
      list.map((s) => '${s.name}:${s.state.name}:${s.toolCount}').join(',');

  /// Подписывает на `changes` и копит строки событий.
  List<String> record(McpSessionTools session) {
    final seen = <String>[];
    session.changes.listen((list) {
      seen.add(line(list));
    });
    return seen;
  }

  test('падение процесса и переподключение дают failed, connecting, connected '
      'в этом порядке; servers после этого — connected (сценарий «Сбой и '
      'восстановление сервера»)', () async {
    final rig = SupervisorRig({
      'docs': fakeServer(['t']),
    });
    final session = await rig.connect([stdio('docs')]);
    final seen = record(session);

    await rig.crash('docs');
    final retryIn = summaryOf(session, 'docs').retryIn!;
    await rig.clock.elapse(retryIn);

    final states = [for (final s in seen) s.split(':')[1]];
    expect(
      states.skipWhile((s) => s != 'failed').toList(),
      containsAllInOrder(['failed', 'connecting', 'connected']),
    );
    expect(summaryOf(session, 'docs').state, McpServerState.connected);
    expect(
      seen.last,
      line(session.servers),
      reason: 'последнее событие = servers',
    );
  });

  // Причина сбоя (`lastError`) формируется транспортом и пробрасывается
  // коннектором как есть (контракт D13 на `McpTransportClosed.reason` и
  // `McpTransportException.message`: без URL, аргументов, env и текстов
  // сервера), поэтому тест не подставляет маркер в причину фейка — это
  // проверка транспорта, а не коннектора. Здесь проверяется, что значения
  // `env` из конфигурации в событие не попадают.
  test('событие несёт retryIn у failed и текст кода CodeLab: значения env '
      'сервера и секретов в нём нет', () async {
    final rig = SupervisorRig({
      'docs': fakeServer(['t']),
    });
    final session = await rig.connect([
      McpStdioServerConfig(
        name: 'docs',
        command: '/usr/bin/docs',
        env: {'DOCS_TOKEN': leak},
      ),
    ]);
    final events = <List<McpServerSummary>>[];
    session.changes.listen(events.add);

    await rig.crash('docs');

    final failed = events.last.single;
    expect(failed.state, McpServerState.failed);
    expect(failed.retryIn, isNotNull);
    expect('${failed.lastError}', isNot(contains(leak)));
  });

  test('число инструментов: после tools/list_changed последнее событие '
      'совпадает с servers и несёт новое число', () async {
    final server = FakeMcpServer(
      era: FakeMcpEra.modern,
      tools: [FakeMcpTool('a')],
      listChanged: true,
    );
    final rig = SupervisorRig({'docs': server});
    final session = await rig.connect([stdio('docs')]);
    final seen = record(session);

    server.notifyToolsListChanged(
      newTools: [FakeMcpTool('a'), FakeMcpTool('b')],
    );
    await rig.settle();
    session.takeUpdate();
    await rig.settle();

    expect(seen, isNotEmpty);
    expect(seen.last, 'docs:connected:2');
    expect(seen.last, line(session.servers));
  });

  test('replaceServers: добавление и удаление сервера дают события со '
      'списком в порядке servers', () async {
    final rig = SupervisorRig({
      'docs': fakeServer(['t']),
      'wiki': fakeServer(['t']),
    });
    final session = await rig.connect([stdio('docs')]);
    final seen = record(session);

    await session.replaceServers([stdio('docs'), stdio('wiki')]);
    await rig.settle();
    expect(seen.last, line(session.servers));
    expect(seen.last, startsWith('docs:'));
    expect(seen.last, contains('wiki:'));

    await session.replaceServers([stdio('wiki')]);
    await rig.settle();
    expect(seen.last, startsWith('wiki:'));
    expect(seen.last, isNot(contains('docs:')));
  });

  test('replaceServers пустым списком: событие с пустым списком', () async {
    final rig = SupervisorRig({
      'docs': fakeServer(['t']),
    });
    final session = await rig.connect([stdio('docs')]);
    final events = <List<McpServerSummary>>[];
    session.changes.listen(events.add);

    await session.replaceServers(const []);
    await rig.settle();

    expect(events.last, isEmpty);
  });

  test('setEnabled(false) даёт disabled с lastError, setEnabled(true) — '
      'connected', () async {
    final rig = SupervisorRig({
      'docs': fakeServer(['t']),
    });
    final session = await rig.connect([stdio('docs')]);
    final events = <List<McpServerSummary>>[];
    session.changes.listen(events.add);

    await session.setEnabled('docs', false);
    await rig.settle();
    expect(events.last.single.state, McpServerState.disabled);
    expect(events.last.single.lastError, 'disabled by /mcp disable');
    expect(events.last.single.toolCount, 0);

    await session.setEnabled('docs', true);
    await rig.settle();
    expect(events.last.single.state, McpServerState.connected);
  });

  test('reconnect: событие с connecting, затем connected', () async {
    final rig = SupervisorRig({
      'docs': fakeServer(['t']),
    });
    final session = await rig.connect([stdio('docs')]);
    final seen = record(session);

    await session.reconnect('docs');
    await rig.settle();

    expect([
      for (final s in seen) s.split(':')[1],
    ], containsAllInOrder(['connecting', 'connected']));
  });

  test(
    'новый подписчик не получает последнее значение (снимок — servers)',
    () async {
      final rig = SupervisorRig({
        'docs': fakeServer(['t']),
      });
      final session = await rig.connect([stdio('docs')]);
      await rig.crash('docs');

      final late = record(session);
      await rig.settle();

      expect(late, isEmpty);
      expect(summaryOf(session, 'docs').state, McpServerState.failed);
    },
  );

  test('поток широковещательный: два подписчика получают одинаковые '
      'события', () async {
    final rig = SupervisorRig({
      'docs': fakeServer(['t']),
    });
    final session = await rig.connect([stdio('docs')]);
    final a = record(session);
    final b = record(session);

    await rig.crash('docs');

    expect(a, isNotEmpty);
    expect(b, a);
  });

  test('close() закрывает поток, таймеры повтора отменены, событий после '
      'закрытия нет (сценарий «Поток закрывается с сессией»)', () async {
    final rig = SupervisorRig({
      'docs': fakeServer(['t']),
    });
    final session = await rig.connect([stdio('docs')]);
    await rig.crash('docs');
    final retryIn = summaryOf(session, 'docs').retryIn!;
    final seen = record(session);
    final done = Completer<void>();
    session.changes.listen((_) {}, onDone: done.complete);

    await session.close();
    final opened = rig.spy.opened.length;
    await rig.clock.elapse(retryIn * 2);

    await done.future.timeout(const Duration(seconds: 1));
    expect(rig.spy.opened, hasLength(opened), reason: 'повтор отменён');
    expect(seen.where((s) => s.contains(':connecting')), isEmpty);
  });

  test('отмена токена запроса (close сессии рантайма) тоже закрывает '
      'поток', () async {
    final rig = SupervisorRig({
      'docs': fakeServer(['t']),
    });
    final session = await rig.connect([stdio('docs')]);
    final done = Completer<void>();
    session.changes.listen((_) {}, onDone: done.complete);

    rig.cancelSession();
    await session.close();

    await done.future.timeout(const Duration(seconds: 1));
  });

  test('close() во время подключения: после вызова подписчик не получает '
      'ни одного события (в том числе failed «connection cancelled»), '
      'поток завершается', () async {
    final rig = SupervisorRig({
      'docs': fakeServer(['t']),
    });
    final session = await rig.connect([stdio('docs')]);
    await rig.crash('docs');
    final retryIn = summaryOf(session, 'docs').retryIn!;
    // Повтор зависает в `open`: сервер остаётся в `connecting`, пока сессию
    // закрывают.
    final gate = rig.spy.gate = Completer<void>();
    await rig.clock.elapse(retryIn);
    expect(summaryOf(session, 'docs').state, McpServerState.connecting);
    final seen = record(session);
    final done = Completer<void>();
    session.changes.listen((_) {}, onDone: done.complete);

    final closing = session.close();
    gate.complete();
    await closing;
    await rig.settle();
    await rig.clock.elapse(retryIn * 2);

    await done.future.timeout(const Duration(seconds: 1));
    expect(seen, isEmpty, reason: 'после close() событий нет');
  });

  test('close() при живом сервере: событий после вызова нет, поток '
      'завершается', () async {
    final rig = SupervisorRig({
      'docs': fakeServer(['t']),
    });
    final session = await rig.connect([stdio('docs')]);
    final seen = record(session);
    final done = Completer<void>();
    session.changes.listen((_) {}, onDone: done.complete);

    await session.close();
    await rig.settle();

    await done.future.timeout(const Duration(seconds: 1));
    expect(seen, isEmpty);
  });

  test('takeUpdate() в окне между началом close() и закрытием потока события '
      'не шлёт', () async {
    final rig = SupervisorRig({
      'docs': fakeServer(['t']),
    });
    final session = await rig.connect([stdio('docs')]);
    // После `reconnect` ждёт обновление набора: `takeUpdate` обычно уведомил бы
    // подписчиков.
    await session.reconnect('docs');
    await rig.settle();
    final seen = record(session);
    final done = Completer<void>();
    session.changes.listen((_) {}, onDone: done.complete);

    final closing = session.close();
    // `close()` ещё закрывает клиентов (await), поток открыт, но сессия уже
    // закрыта: поздний `takeUpdate` хоста не должен породить событие.
    session.takeUpdate();
    await closing;
    await rig.settle();

    await done.future.timeout(const Duration(seconds: 1));
    expect(seen, isEmpty);
  });
}
