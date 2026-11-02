// Замер 7.8: задержка цикла событий UI-isolate под потоком ответа модели
// (design.md change `add-embedded-agent-mode`, D11; embedded-agent
// «Нагрузка встроенного агента на UI-isolate»).
//
// Почему: встроенный агент живёт в одном isolate с клиентом (`InProcessAcpLink`),
// и его работа может отнимать кадры у Flutter UI. Решение «переносить ядро в
// `IsolateAcpLink` или нет» принимается по числам, а не по ощущению
// (D11, критерии: p99 > 8 мс или максимум > 50 мс — переносить).
//
// Для чего: разведка по исключению (д) §9.0 — без теста, не дольше двух дней.
// Сценарий модели отдаёт 10 000 чанков; клиентская сторона — настоящие
// `AcpClientApplication` и `ClientWorkspace`, поэтому замер включает проекцию
// kit (транскрипт, состояние), а не только транспорт. Таймер в 1 мс в том же
// isolate меряет, насколько позже срока он срабатывает: это и есть задержка
// цикла событий, которую увидел бы UI.
//
// Два режима источника чанков (`--mode=sse|scripted`, по умолчанию `sse`):
// * `sse` — настоящий слой провайдера (`localEmbeddedAgentOpener` и разбор SSE)
//   над поддельным `http.Client`; каждый чанк приходит в своём обороте цикла
//   событий, как чтение из сокета. Это реалистичная нагрузка и режим решения;
// * `scripted` — сценарий модели (`scriptedEmbeddedAgentOpener`, D8): он
//   выдаёт все 10 000 дельт синхронно, без единой отдачи циклу событий, поэтому
//   весь ход идёт цепочкой микрозадач и таймер не срабатывает до конца хода.
//   Режим показывает верхнюю границу «ответ пришёл целиком, пачкой».
//
// Как использовать (критерий — AOT, как релиз Flutter, D13 п. 3):
//   fvm dart compile exe packages/dart/codelab_embedded/benchmark/stream_latency_benchmark.dart -o <out>
//   <out>
// либо `fvm dart run packages/dart/codelab_embedded/benchmark/stream_latency_benchmark.dart`
// (JIT, справочно). Сеть и ключи не нужны: модель — сценарий или поддельный провайдер. Бенчмарк лежит вне
// `lib/`, поэтому dev-зависимости `codelab_client_*` сторож импортов не трогает
// (он сканирует `lib/**`).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
// У клиентского слоя свой `Logger`; нужен агентский из `codelab_embedded`.
import 'package:codelab_client_acp/codelab_client_acp.dart' hide Logger;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_embedded/codelab_embedded.dart';
import 'package:codelab_embedded/io.dart';
import 'package:codelab_embedded/testing.dart';
import 'package:http/http.dart' as web;
import 'package:http/testing.dart';

/// Чанков ответа модели. Сценарий режет текст на дельты по 16 символов
/// (`ScriptedStreamFunction`), поэтому длина текста = чанки * 16.
const _chunks = 10000;
const _deltaLength = 16;

Future<void> main(List<String> args) async {
  final scripted = args.contains('--mode=scripted');
  // `--burst=N` (режим `sse`): N событий приходят одним чтением сокета.
  final burst =
      int.tryParse(
        args
                .where((a) => a.startsWith('--burst='))
                .map((a) => a.substring('--burst='.length))
                .firstOrNull ??
            '1',
      ) ??
      0;
  if (burst < 1) {
    stderr.writeln('--burst must be an integer >= 1');
    exitCode = 64;
    return;
  }
  final temp = Directory.systemTemp.createTempSync('codelab_stream_latency_');
  EmbeddedAgent? running;
  try {
    final project = Directory('${temp.path}/project')..createSync();
    final EmbeddedAgentOpener opener = scripted
        ? scriptedEmbeddedAgentOpener(
            llm: {
              'steps': [
                {
                  'reply': [
                    {'text': 'x' * (_chunks * _deltaLength)},
                  ],
                },
              ],
            },
            codelabHome: '${temp.path}/home',
            logger: const _SilentLogger(),
          )
        : _sseOpener('${temp.path}/home', burst);
    final resolver = _OneShotResolver(opener, (agent) => running = agent);
    // `--no-client`: без `AcpClientApplication` и `ClientWorkspace` клиентский
    // конец читает только сырой читатель кадров. Разница с полным прогоном —
    // стоимость клиентской проекции kit (грубая оценка по слоям).
    final Future<Object> Function() runTurn;
    final Future<void> Function() close;
    if (args.contains('--no-client')) {
      final agent = await opener(
        cwd: project.path,
        hostProfile: 'embedded-cli',
      );
      running = agent;
      final raw = _RawClient(agent.clientTransport);
      await raw.start();
      await raw.call('initialize', {
        'protocolVersion': 1,
        'clientCapabilities': <String, Object?>{},
      });
      final created = await raw.call('session/new', {
        'cwd': project.path,
        'mcpServers': <Object?>[],
      });
      final sessionId = created['sessionId']! as String;
      runTurn = () async => (await raw.call('session/prompt', {
        'sessionId': sessionId,
        'prompt': [
          {'type': 'text', 'text': 'go'},
        ],
      }))['stopReason']!;
      close = () async {};
    } else {
      final application = AcpClientApplication(
        transport: _NotConnectedTransport(),
        clientInfo: const Implementation(name: 'stream-latency', version: '0'),
      );
      final workspace = ClientWorkspace(
        backend: AcpClientBackend(application),
        resolvers: [resolver],
      );
      await workspace.connect(
        const EmbeddedProfile(
          id: 'bench',
          label: 'bench',
          hostProfile: 'embedded-cli',
        ),
        projectDirectory: project.path,
      );
      final session = await workspace.newSession();
      runTurn = () async => (await session.send('go')).runtimeType;
      close = workspace.dispose;
    }

    // Таймер ставится заново на каждом срабатывании: у `Timer.periodic` сроки
    // привязаны к сетке, а нам нужен именно «насколько позже 1 мс».
    final lateness = <int>[]; // микросекунды
    final clock = Stopwatch()..start();
    var armedAt = 0;
    var sampling = true;
    void arm() {
      armedAt = clock.elapsedMicroseconds;
      Timer(const Duration(milliseconds: 1), () {
        final late = clock.elapsedMicroseconds - armedAt - 1000;
        lateness.add(late < 0 ? 0 : late);
        if (sampling) arm();
      });
    }

    // Холостой фон: гранулярность самого таймера (около 1 мс сверх срока)
    // входит в любые числа ниже, и без базы их не с чем сравнить.
    arm();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final idle = List<int>.of(lateness)..sort();
    lateness.clear();
    final turn = Stopwatch()..start();
    final outcome = await runTurn();
    turn.stop();
    sampling = false;

    final samples = lateness.length;
    if (lateness.isEmpty) {
      // Ни одного оборота цикла событий за весь ход: задержка = время хода.
      lateness.add(turn.elapsedMicroseconds);
    }
    lateness.sort();
    final idleP50 = idle[(idle.length - 1) ~/ 2];
    double ms(int us) => us / 1000;
    int at(double q) => lateness[((lateness.length - 1) * q).round()];
    stdout
      ..writeln('mode: ${scripted ? 'scripted' : 'sse'}')
      ..writeln(
        'chunks: $_chunks, burst: $burst, client: ${!args.contains('--no-client')}',
      )
      ..writeln('outcome: $outcome')
      ..writeln('timer samples: $samples')
      ..writeln(
        'idle p50 (baseline): ${(idleP50 / 1000).toStringAsFixed(3)} ms',
      )
      ..writeln('p50: ${ms(at(0.50)).toStringAsFixed(3)} ms')
      ..writeln('p99: ${ms(at(0.99)).toStringAsFixed(3)} ms')
      ..writeln('max: ${ms(lateness.last).toStringAsFixed(3)} ms')
      ..writeln('turn: ${turn.elapsedMilliseconds} ms');
    await close();
  } finally {
    await running?.dispose();
    temp.deleteSync(recursive: true);
  }
}

/// Открыватель с настоящим слоем провайдера: конфиг во временном
/// `CODELAB_HOME`, ключ — выдуманная строка из окружения открывателя (не
/// секрет), ответ провайдера — [_sseClient].
EmbeddedAgentOpener _sseOpener(String home, int burst) {
  Directory(home).createSync(recursive: true);
  // Каталог конфигурации хост проверяет на права владельца.
  final chmod = Process.runSync('/bin/chmod', ['700', home]);
  if (chmod.exitCode != 0) {
    throw StateError('chmod 700 of the benchmark home failed: ${chmod.stderr}');
  }
  File('$home/config.yaml').writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    base_url: https://p.test/v1
    api_key_secret: codelab/p
    models:
      m: {}
agent:
  default_model: p/m
''');
  return localEmbeddedAgentOpener(
    environment: {
      'CODELAB_HOME': home,
      'CODELAB_SECRET_CODELAB_P': 'benchmark-not-a-secret',
    },
    logger: const _SilentLogger(),
    httpClient: _sseClient(burst),
  );
}

/// Поддельный провайдер: [_chunks] SSE-событий по [_deltaLength] символов,
/// по [burst] штук в одном элементе потока байтов (одно чтение сокета); между
/// чтениями — оборот цикла событий (`Future(() {})` — нулевой таймер).
web.Client _sseClient(int burst) => MockClient.streaming((request, body) async {
  String event(Map<String, Object?> delta, String? finish) =>
      'data: ${jsonEncode({
        'id': 'c',
        'object': 'chat.completion.chunk',
        'created': 1,
        'model': 'm',
        'choices': [
          {'index': 0, 'delta': delta, 'finish_reason': finish},
        ],
      })}\n\n';
  final out = StreamController<List<int>>();
  unawaited(() async {
    final piece = 'x' * _deltaLength;
    for (var i = 0; i < _chunks; i += burst) {
      final read = StringBuffer();
      for (var j = i; j < i + burst && j < _chunks; j++) {
        read.write(
          event({if (j == 0) 'role': 'assistant', 'content': piece}, null),
        );
      }
      out.add(utf8.encode('$read'));
      await Future<void>(() {});
    }
    out
      ..add(utf8.encode(event({}, 'stop')))
      ..add(utf8.encode('data: [DONE]\n\n'));
    await out.close();
  }());
  return web.StreamedResponse(
    out.stream,
    200,
    headers: {'content-type': 'text/event-stream'},
  );
});

/// Резолвер одного встроенного агента: в замере хватает `open` без очереди
/// и поколений рабочего резолвера CLI.
final class _OneShotResolver implements TransportResolver {
  _OneShotResolver(this._opener, this._onAgent);

  final EmbeddedAgentOpener _opener;
  final void Function(EmbeddedAgent) _onAgent;

  @override
  bool supports(ConnectionProfile profile) => profile is EmbeddedProfile;

  @override
  Future<AcpTransport> open(
    ConnectionProfile profile, {
    required String projectDirectory,
  }) async {
    final agent = await _opener(
      cwd: projectDirectory,
      hostProfile: (profile as EmbeddedProfile).hostProfile,
    );
    _onAgent(agent);
    return agent.clientTransport;
  }
}

final class _SilentLogger implements Logger {
  const _SilentLogger();

  @override
  bool isEnabled(LogLevel level) => false;

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {}
}

/// Транспорт до `connect`: `AcpClientApplication` требует его при создании,
/// настоящий открывает резолвер (как в `composition_root` CLI).
final class _NotConnectedTransport implements AcpTransport {
  @override
  Stream<JsonRpcMessage> get inbound => const Stream.empty();

  @override
  Stream<AcpTransportEvent> get events => const Stream.empty();

  @override
  AcpTransportState get state => AcpTransportState.idle;

  @override
  Future<void> start() => Future.error(StateError('not connected'));

  @override
  Future<void> send(JsonRpcMessage message) =>
      Future.error(StateError('not connected'));

  @override
  Future<void> close({Duration? timeout}) async {}
}

/// Сырой читатель кадров без клиентского слоя: запрос-ответ по id.
final class _RawClient {
  _RawClient(this._transport) {
    _transport.inbound.listen((m) {
      if (m is JsonRpcResponse) _pending.remove(m.id)?.complete(m);
    });
  }

  final AcpTransport _transport;
  final _pending = <JsonRpcId, Completer<JsonRpcResponse>>{};
  var _next = 0;

  Future<void> start() => _transport.start();

  Future<Map<String, Object?>> call(String method, Object? params) async {
    final id = JsonRpcId.integer(_next++);
    final done = _pending[id] = Completer<JsonRpcResponse>();
    await _transport.send(
      JsonRpcMessage.request(id: id, method: method, params: params),
    );
    final response = await done.future;
    if (response.error case final error?) {
      throw StateError('$method: ${error.message}');
    }
    return (response.result as Map<String, Object?>?) ?? const {};
  }
}
