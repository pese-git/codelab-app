import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';

import '../in_process_acp_link.dart';
import 'fixture.dart';
import 'matcher.dart';

/// Conformance агента на golden-фикстурах (`14-golden-fixtures.md` §14.9;
/// design.md change `add-dart-agent-acp-server`, D8).
///
/// Почему отдельный драйвер: клиентский (§14.10) играет агента, а этот —
/// клиента. Кадры `c2a` — и промпты, и ответы клиента на запросы агента
/// (`fs/*`, `terminal/*`, `session/request_permission`) — отправляются
/// агенту, а кадры `a2c` ожидаются от него и сравниваются после
/// нормализации (§14.5, §14.6).
///
/// Для чего: одна и та же фикстура проверяет обе стороны протокола.
/// Драйвер не зависит от пакетов агента: агента поднимает фабрика теста
/// ([AgentFixtureStarter]) на агентском конце `InProcessAcpLink`.
///
/// Как использовать: `await runAgentFixture(fixture, startAgent)`; провал —
/// [AgentFixtureFailure] с индексом кадра и diff, фикстура без роли `agent`
/// — пропуск с причиной.

/// Начальные условия прогона для фабрики агента.
final class AgentFixtureSetup {
  const AgentFixtureSetup({required this.fixture, required this.cwd});

  final AcpFixture fixture;

  /// Временный каталог прогона с файлами `setup.files`: нужен локальному
  /// листингу `ls`/`search` (§10.4). Содержимое файлов агент получает
  /// кадрами `fs/*` фикстуры.
  final String cwd;

  String get profile => fixture.setup.profile ?? 'agent-serve';

  /// Режим сессии на старте; `null` — режим профиля.
  String? get mode => fixture.setup.mode;

  /// Фрагмент конфига агента (§15).
  Map<String, Object?> get config => fixture.setup.config ?? const {};

  /// Блок `llm` для scripted-модели (§14.7); `null` — модель не нужна.
  Map<String, Object?>? get llm => fixture.llm?.json;

  /// Fake MCP-серверы сценария (`setup.mcp`): драйвер только отдаёт их
  /// фабрике, она строит серверы (design.md change `add-agent-mcp-client`,
  /// D15).
  Map<String, FixtureMcpServer> get mcp => fixture.setup.mcp;

  /// Ожидания после сценария (`after`), в том числе `mcpCalls`, которые
  /// сверяет `AgentUnderTest.verify()` фабрики.
  FixtureAfter? get after => fixture.after;

  /// Журналы сессий до сценария (`setup.sessions`) с подставленным
  /// `${cwd}`: фабрика кладёт их в хранилище агента до старта.
  Map<String, List<Map<String, Object?>>> get sessions => {
    for (final MapEntry(key: id, value: records)
        in fixture.setup.sessions.entries)
      id: [for (final record in records) _withCwd(record, cwd)],
  };
}

Map<String, Object?> _withCwd(Map<String, Object?> json, String cwd) {
  Object? walk(Object? value) => switch (value) {
    final String s => s.replaceAll(r'${cwd}', cwd),
    final Map<String, Object?> m => {
      for (final MapEntry(:key, :value) in m.entries) key: walk(value),
    },
    final List<Object?> l => [for (final item in l) walk(item)],
    _ => value,
  };
  return walk(json)! as Map<String, Object?>;
}

/// Агент, поднятый фабрикой.
abstract interface class AgentUnderTest {
  /// Проверки после сценария: все шаги scripted-модели использованы и
  /// лишних запросов не было (§14.9, шаг 9). Бросает при расхождении.
  void verify();

  /// Останавливает агента; вызывается всегда, и при провале.
  Future<void> stop();
}

/// Поднимает агента на [transport] — агентском конце пары в памяти.
typedef AgentFixtureStarter =
    Future<AgentUnderTest> Function(
      AcpTransport transport,
      AgentFixtureSetup setup,
    );

/// Соединение транспортного прогона: клиентский конец и агент за ним.
final class AgentConnection {
  const AgentConnection({required this.client, required this.agent});

  /// Клиентский транспорт: драйвер сам вызывает `start` и `close`.
  final AcpTransport client;
  final AgentUnderTest agent;
}

/// Поднимает агента и клиентский транспорт к нему для [setup] — например,
/// процесс бинаря и настоящий stdio или WebSocket (design.md change
/// `add-codelab-agent-binary`, D8).
typedef AgentFixtureConnector =
    Future<AgentConnection> Function(AgentFixtureSetup setup);

final class AgentFixtureResult {
  const AgentFixtureResult._({
    required this.skipped,
    this.skipReason,
    this.variables = const {},
  });

  final bool skipped;
  final String? skipReason;

  /// Переменные прогона: `sessionId` и захваченные значения.
  final Map<String, Object?> variables;
}

/// Агент разошёлся с фикстурой.
final class AgentFixtureFailure implements Exception {
  const AgentFixtureFailure({
    required this.fixtureId,
    required this.frameIndex,
    required this.message,
    this.note,
    this.mismatches = const [],
    this.expected,
    this.actual,
  });

  final String fixtureId;

  /// Индекс в `frames`; отрицательный — стандартный handshake,
  /// `frames.length` — проверки после сценария.
  final int frameIndex;
  final String message;
  final String? note;
  final List<FrameMismatch> mismatches;
  final Object? expected;
  final Object? actual;

  @override
  String toString() {
    final buffer = StringBuffer('AgentFixtureFailure: $fixtureId ')
      ..write(frameIndex < 0 ? 'handshake frame' : 'frame #$frameIndex')
      ..write(note == null ? '' : ' ($note)')
      ..write(': $message');
    for (final mismatch in mismatches) {
      buffer.write('\n  - $mismatch');
    }
    if (expected != null) {
      buffer.write('\n  expected: ${_encode(expected)}');
    }
    if (actual != null) {
      buffer.write('\n  actual:   ${_encode(actual)}');
    }
    return buffer.toString();
  }
}

/// Проигрывает [fixture] против агента из [start] (§14.9) через пару
/// транспортов в памяти.
///
/// [frameTimeout] — ожидание кадра агента по реальным часам; [quietPeriod]
/// — тишина в конце: кадр после неё — провал, так же как лишний запрос
/// `fs/*` или `terminal/*` (агент сделал больше, чем закреплено). Фикстура с
/// `setup.transport` пропускается: её играет [runAgentFixtureOver].
Future<AgentFixtureResult> runAgentFixture(
  AcpFixture fixture,
  AgentFixtureStarter start, {
  Duration frameTimeout = const Duration(seconds: 5),
  Duration quietPeriod = const Duration(milliseconds: 200),
}) async {
  if (_withoutAgentRole(fixture) case final skipped?) {
    return skipped;
  }
  if (fixture.setup.transport != null) {
    return AgentFixtureResult._(
      skipped: true,
      skipReason:
          '${fixture.id} has setup.transport: the transport driver plays it '
          'against the binary process',
    );
  }
  return _play(
    fixture,
    (setup) async {
      final link = InProcessAcpLink();
      final agent = await start(link.agent, setup);
      return AgentConnection(client: link.client, agent: agent);
    },
    frameTimeout: frameTimeout,
    quietPeriod: quietPeriod,
  );
}

/// Транспортный драйвер (acp-golden-fixtures «Транспортный драйвер
/// фикстур»): тот же алгоритм §14.9 поверх соединения из [connect].
///
/// [transportFixtures] выбирает, какие фикстуры играть: `true` — только с
/// `setup.transport` (драйвер бинаря агента; остальные играет
/// [runAgentFixture]); `false` — только без него, через соединение
/// профиля (`codelab test-scenario`; транспортные фикстуры проверяет
/// драйвер бинаря, design.md change `add-codelab-cli`, D12). Фикстура
/// другого вида пропускается с причиной.
Future<AgentFixtureResult> runAgentFixtureOver(
  AcpFixture fixture,
  AgentFixtureConnector connect, {
  Duration frameTimeout = const Duration(seconds: 5),
  Duration quietPeriod = const Duration(milliseconds: 200),
  bool transportFixtures = true,
}) async {
  if (_withoutAgentRole(fixture) case final skipped?) {
    return skipped;
  }
  final hasTransport = fixture.setup.transport != null;
  if (hasTransport != transportFixtures) {
    return AgentFixtureResult._(
      skipped: true,
      skipReason: hasTransport
          ? '${fixture.id} has setup.transport: the transport driver of '
                'codelab-agent plays it against the binary process'
          : '${fixture.id} has no setup.transport: the in-memory run plays it',
    );
  }
  return _play(
    fixture,
    connect,
    frameTimeout: frameTimeout,
    quietPeriod: quietPeriod,
  );
}

AgentFixtureResult? _withoutAgentRole(AcpFixture fixture) =>
    fixture.roles.contains(FixtureRole.agent)
    ? null
    : AgentFixtureResult._(
        skipped: true,
        skipReason:
            '${fixture.id} has roles '
            '[${fixture.roles.map((r) => r.name).join(', ')}] without "agent"',
      );

Future<AgentFixtureResult> _play(
  AcpFixture fixture,
  AgentFixtureConnector connect, {
  required Duration frameTimeout,
  required Duration quietPeriod,
}) async {
  final directory = Directory.systemTemp.createTempSync('agent_fixture_');
  final cwd = directory.resolveSymbolicLinksSync().replaceAll(r'\', '/');
  for (final MapEntry(key: path, value: content)
      in fixture.setup.files.entries) {
    File('$cwd/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }
  AgentConnection? connection;
  _Inbox? inbox;
  try {
    connection = await connect(AgentFixtureSetup(fixture: fixture, cwd: cwd));
    final client = connection.client;
    inbox = _Inbox(client);
    await client.start();
    final run = _AgentRun(
      fixture: fixture,
      client: client,
      inbox: inbox,
      matcher: FrameMatcher(cwd: cwd, replace: fixture.normalize.replace),
      frameTimeout: frameTimeout,
      quietPeriod: quietPeriod,
    );
    await run.play(connection.agent);
    return AgentFixtureResult._(
      skipped: false,
      variables: Map.unmodifiable(run.matcher.variables),
    );
  } finally {
    // Сначала клиентский конец: ожидания агента (fs/*, terminal/*,
    // разрешения) завершаются разрывом, и остановка не ждёт таймаутов,
    // которые у агента идут по FakeClock.
    await connection?.client.close();
    await connection?.agent.stop();
    await inbox?.cancel();
    directory.deleteSync(recursive: true);
  }
}

final class _AgentRun {
  _AgentRun({
    required this.fixture,
    required this.client,
    required this.inbox,
    required this.matcher,
    required this.frameTimeout,
    required this.quietPeriod,
  });

  final AcpFixture fixture;
  final AcpTransport client;
  final _Inbox inbox;
  final FrameMatcher matcher;
  final Duration frameTimeout;
  final Duration quietPeriod;

  /// Последний `content` кадра `fs/write_text_file` по пути (§14.9, шаг 10).
  final _written = <String, String>{};

  Future<void> play(AgentUnderTest agent) async {
    final frames = [
      if (!fixture.setup.skipInitialize)
        ...agentFixtureHandshake(fixture.setup),
      ...fixture.frames,
    ];
    for (final frame in frames) {
      switch (frame.direction) {
        case FrameDirection.c2a:
          await _send(frame);
        case FrameDirection.a2c:
          await _expect(frame);
      }
    }
    await _expectSilence();
    try {
      agent.verify();
    } on Object catch (error) {
      _fail(_endFrame(), 'the agent check after the scenario failed: $error');
    }
    _checkAfter();
  }

  List<Map<String, Object?>> _templates(FixtureFrame frame) =>
      frame.unordered ?? [frame.frame!];

  Future<void> _send(FixtureFrame frame) async {
    for (final template in _templates(frame)) {
      final Object? concrete;
      try {
        concrete = matcher.materialize(template);
      } on FixtureMatchException catch (error) {
        _fail(frame, error.message, expected: template);
      }
      final JsonRpcMessage message;
      try {
        message = jsonRpcMessageFromJson(concrete! as Map<String, Object?>);
      } on Object catch (error) {
        _fail(
          frame,
          'c2a frame is not a JSON-RPC message: $error',
          expected: concrete,
        );
      }
      await client.send(message);
    }
  }

  Future<void> _expect(FixtureFrame frame) async {
    if (frame.unordered case final templates?) {
      final actual = <Object?>[];
      for (var i = 0; i < templates.length; i++) {
        actual.add(await _next(frame));
      }
      final mismatches = matcher.matchUnordered(templates, actual);
      if (mismatches.isNotEmpty) {
        _fail(
          frame,
          'unordered frames differ',
          mismatches: mismatches,
          expected: templates,
          actual: actual,
        );
      }
      actual.forEach(_remember);
      return;
    }
    final template = frame.frame!;
    if (frame.optional) {
      // Необязательный кадр: при несовпадении не потребляется (§14.9).
      if (await inbox.waitFor(quietPeriod) &&
          matcher.match(template, inbox.peek()).isEmpty) {
        _remember(inbox.take());
      }
      return;
    }
    final first = await _next(frame);
    final mismatches = matcher.match(template, first);
    if (mismatches.isNotEmpty) {
      _fail(
        frame,
        'a2c frame differs',
        mismatches: mismatches,
        expected: matcher.substitute(template),
        actual: first,
      );
    }
    _remember(first);
    if (!frame.repeated) {
      return;
    }
    final repeats = [first];
    while (await inbox.waitFor(quietPeriod) &&
        matcher.match(template, inbox.peek()).isEmpty) {
      repeats.add(inbox.take());
    }
    if (frame.matchText case final text?) {
      final textMismatches = matcher.matchText(text, repeats);
      if (textMismatches.isNotEmpty) {
        _fail(
          frame,
          'repeated frames differ',
          mismatches: textMismatches,
          actual: repeats,
        );
      }
    }
  }

  Future<Object?> _next(FixtureFrame frame) async {
    if (!await inbox.waitFor(frameTimeout)) {
      _fail(
        frame,
        'timed out after ${frameTimeout.inMilliseconds} ms waiting for an '
        'a2c frame',
        expected: _templates(frame).length == 1
            ? matcher.substitute(_templates(frame).single)
            : _templates(frame),
      );
    }
    return inbox.take();
  }

  void _remember(Object? frame) {
    if (frame case {
      'method': 'fs/write_text_file',
      'params': {'path': final String path, 'content': final String content},
    }) {
      _written[matcher.normalize(path)! as String] = content;
    }
  }

  Future<void> _expectSilence() async {
    await Future<void>.delayed(quietPeriod);
    if (inbox.isEmpty) {
      return;
    }
    final extra = inbox.takeAll();
    final requests = [
      for (final frame in extra)
        if (frame case {'method': final String method, 'id': _?})
          if (method.startsWith('fs/') || method.startsWith('terminal/'))
            method,
    ];
    _fail(
      _endFrame(),
      requests.isEmpty
          ? 'unexpected frames from the agent after the scenario'
          : 'unexpected frames from the agent after the scenario: the agent '
                'did more than the fixture records (${requests.join(', ')})',
      actual: extra,
    );
  }

  void _checkAfter() {
    final expected = fixture.after?.files ?? const {};
    // Без записи файл остался как в setup.files (§14.4, `after`).
    String? actual(String path) =>
        _written['\${cwd}/$path'] ?? fixture.setup.files[path];
    final mismatches = [
      for (final MapEntry(key: path, value: content) in expected.entries)
        if (actual(path) != content)
          FrameMismatch(
            'after.files["$path"]',
            'expected ${_encode(content)}, got ${_encode(actual(path))} '
                '(the last fs/write_text_file or setup.files)',
          ),
    ];
    if (mismatches.isNotEmpty) {
      _fail(
        _endFrame(),
        'files after the scenario differ',
        mismatches: mismatches,
      );
    }
  }

  FixtureFrame _endFrame() => FixtureFrame(
    index: fixture.frames.length,
    direction: FrameDirection.a2c,
    optional: false,
    repeated: false,
    note: 'after the scenario',
    frame: const {},
  );

  Never _fail(
    FixtureFrame frame,
    String message, {
    List<FrameMismatch> mismatches = const [],
    Object? expected,
    Object? actual,
  }) => throw AgentFixtureFailure(
    fixtureId: fixture.id,
    frameIndex: frame.index,
    message: message,
    note: frame.note,
    mismatches: mismatches,
    expected: expected,
    actual: actual,
  );
}

/// Стандартный handshake (§14.9, шаг 6): `initialize` с
/// `setup.clientCapabilities`, `session/new` в `cwd`; `sessionId` ответа —
/// переменная прогона. `available_commands_update` после ответа — часть
/// handshake: фикстуры начинаются с первого кадра сценария. Общий для
/// драйвера и `FixtureReplayAgent`, который играет его зеркально.
List<FixtureFrame> agentFixtureHandshake(FixtureSetup setup) {
  FixtureFrame frame(
    int index,
    FrameDirection dir,
    String note,
    Map<String, Object?> json, {
    bool optional = false,
  }) => FixtureFrame(
    index: index,
    direction: dir,
    optional: optional,
    repeated: false,
    note: note,
    frame: json,
  );

  return [
    frame(-5, FrameDirection.c2a, 'handshake: initialize', {
      'jsonrpc': '2.0',
      'id': 0,
      'method': 'initialize',
      'params': {
        'protocolVersion': 1,
        'clientCapabilities':
            setup.clientCapabilities ??
            {
              'fs': {'readTextFile': true, 'writeTextFile': true},
              'terminal': true,
            },
        'clientInfo': {'name': 'fixture-client', 'version': '0.0.0'},
      },
    }),
    frame(-4, FrameDirection.a2c, 'handshake: initialize result', {
      'jsonrpc': '2.0',
      'id': 0,
      'result': {
        r'$partial': {'protocolVersion': 1},
      },
    }),
    frame(-3, FrameDirection.c2a, 'handshake: session/new', {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'session/new',
      'params': {'cwd': r'${cwd}', 'mcpServers': <Object?>[]},
    }),
    frame(-2, FrameDirection.a2c, 'handshake: session/new result', {
      'jsonrpc': '2.0',
      'id': 1,
      'result': {
        r'$partial': {
          'sessionId': {r'$capture': 'sessionId'},
        },
      },
    }),
    frame(-1, FrameDirection.a2c, 'handshake: available_commands_update', {
      'jsonrpc': '2.0',
      'method': 'session/update',
      'params': {
        'sessionId': r'${sessionId}',
        'update': {
          r'$partial': {'sessionUpdate': 'available_commands_update'},
        },
      },
    }, optional: true),
  ];
}

/// Кадры агента в виде JSON провода, по порядку.
final class _Inbox {
  _Inbox(AcpTransport client) {
    _subscription = client.inbound.listen((message) {
      _queue.add(jsonDecode(encodeJsonRpcMessage(message)));
      _wake();
    });
  }

  late final StreamSubscription<JsonRpcMessage> _subscription;
  final _queue = Queue<Object?>();
  Completer<void>? _signal;

  bool get isEmpty => _queue.isEmpty;

  Object? peek() => _queue.first;

  Object? take() => _queue.removeFirst();

  List<Object?> takeAll() {
    final all = _queue.toList();
    _queue.clear();
    return all;
  }

  void _wake() {
    final signal = _signal;
    _signal = null;
    if (signal != null && !signal.isCompleted) {
      signal.complete();
    }
  }

  /// Ждёт кадр; `false` — за [timeout] кадра не было.
  Future<bool> waitFor(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_queue.isEmpty) {
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) {
        return false;
      }
      final signal = _signal ??= Completer<void>();
      try {
        await signal.future.timeout(left);
      } on TimeoutException {
        return _queue.isNotEmpty;
      }
    }
    return true;
  }

  Future<void> cancel() => _subscription.cancel();
}

String _encode(Object? value) =>
    const JsonEncoder.withIndent(null).convert(value);
