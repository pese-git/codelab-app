import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_acp_transports/io.dart';

import 'agent_conformance.dart';
import 'fixture.dart';
import 'matcher.dart';

/// Агент, который играет одну фикстуру: на кадры клиента отвечает
/// ожидаемыми кадрами агента той же фикстуры.
///
/// Почему: драйвер фикстур (`codelab test-scenario`) надо проверять на всём
/// корпусе без настоящего агента, а сравнение кадров — то же, что у
/// агентского драйвера (spec acp-golden-fixtures «Агент-повторитель
/// фикстуры»; design.md change `add-codelab-cli`, D12).
///
/// Для чего: кадры клиента (`c2a`) сверяются с шаблонами фикстуры тем же
/// `FrameMatcher`, захваченные значения запоминаются; кадры агента (`a2c`)
/// порождает `FrameMatcher.materialize`. Кадр `repeat: "+"` с `match.$text`
/// уходит одним кадром с этим текстом, необязательный кадр не отправляется.
/// Кадр клиента, которого фикстура не ожидает, — запрос получает JSON-RPC
/// ошибку `-32600` с текстом расхождения, и повтор останавливается.
///
/// Как использовать: в процессе — `FixtureReplayAgent.start(fixture,
/// transport, cwd: …)` на агентском конце `InProcessAcpLink`; процессом —
/// [writeFixtureReplayAgent] и `dart <файл> <фикстура>`. Без [cwd] рабочая
/// папка берётся из `cwd` первого кадра клиента, где она есть
/// (`session/new`). Только для тестов.
final class FixtureReplayAgent implements AgentUnderTest {
  FixtureReplayAgent._(this._fixture, this._transport, String? cwd)
    : _cwd = cwd,
      _frames = [
        if (!_fixture.setup.skipInitialize)
          ...agentFixtureHandshake(_fixture.setup),
        ..._fixture.frames,
      ] {
    _matcher = _matcherFor(cwd ?? _unknownCwd);
  }

  /// Подписывается на [transport] и запускает его.
  static Future<FixtureReplayAgent> start(
    AcpFixture fixture,
    AcpTransport transport, {
    String? cwd,
  }) async {
    final agent = FixtureReplayAgent._(fixture, transport, cwd);
    agent._subscription = transport.inbound.listen(
      agent._onMessage,
      onDone: () {
        if (!agent._done.isCompleted) {
          agent._done.complete();
        }
      },
    );
    if (transport.state == AcpTransportState.idle) {
      await transport.start();
    }
    unawaited(agent._pump());
    return agent;
  }

  /// Папка, которой нет: до `cwd` клиента подстановка `${cwd}` ни с чем
  /// не совпадёт.
  static const _unknownCwd = '/fixture-replay-cwd-unknown';

  final AcpFixture _fixture;
  final AcpTransport _transport;
  final List<FixtureFrame> _frames;
  String? _cwd;
  late FrameMatcher _matcher;
  StreamSubscription<JsonRpcMessage>? _subscription;

  /// Кадры клиента, ещё не сверенные с фикстурой.
  final _received = <Map<String, Object?>>[];
  var _cursor = 0;
  var _stopped = false;
  var _pumping = false;
  final _done = Completer<void>();

  /// Завершается, когда клиент закрыл соединение.
  Future<void> get done => _done.future;

  @override
  void verify() {}

  @override
  Future<void> stop() async {
    _stopped = true;
    await _subscription?.cancel();
    await _transport.close();
  }

  FrameMatcher _matcherFor(String cwd) =>
      FrameMatcher(cwd: cwd, replace: _fixture.normalize.replace);

  void _onMessage(JsonRpcMessage message) {
    final json = jsonDecode(encodeJsonRpcMessage(message));
    _received.add(json as Map<String, Object?>);
    unawaited(_pump());
  }

  /// Отправляет кадры агента, пока следующий кадр фикстуры — не кадр
  /// клиента, которого ещё нет.
  Future<void> _pump() async {
    if (_pumping) {
      return;
    }
    _pumping = true;
    try {
      while (!_stopped) {
        while (_cursor < _frames.length &&
            _frames[_cursor].direction == FrameDirection.a2c) {
          await _sendAgentFrame(_frames[_cursor++]);
        }
        if (_cursor >= _frames.length) {
          // Сценарий сыгран: любой новый кадр клиента — лишний.
          for (final extra in _received) {
            await _reject(extra, 'the fixture has no more client frames');
          }
          _received.clear();
          return;
        }
        final frame = _frames[_cursor];
        final templates = frame.unordered ?? [frame.frame!];
        if (_received.length < templates.length) {
          return;
        }
        final actual = _received.sublist(0, templates.length);
        _received.removeRange(0, templates.length);
        actual.forEach(_learnCwd);
        final mismatches = templates.length == 1 && frame.unordered == null
            ? _matcher.match(templates.single, actual.single)
            : _matcher.matchUnordered(templates, actual);
        if (mismatches.isNotEmpty) {
          _stopped = true;
          await _reject(
            actual.first,
            'frame #${frame.index}${frame.note == null ? '' : ' (${frame.note})'}: '
            'expected ${_encode(_matcher.substitute(templates))}, got '
            '${_encode(actual)}; ${mismatches.join('; ')}',
          );
          return;
        }
        _cursor++;
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _sendAgentFrame(FixtureFrame frame) async {
    if (frame.optional) {
      return;
    }
    for (final template in frame.unordered ?? [frame.frame!]) {
      final concrete = _matcher.materialize(template)! as Map<String, Object?>;
      if (frame.matchText case final text? when frame.repeated) {
        final params = concrete['params'];
        if (params case {'update': {'content': final Map<String, Object?> c}}) {
          c['text'] = _matcher.substitute(text);
        }
      }
      await _transport.send(jsonRpcMessageFromJson(concrete));
    }
  }

  /// Рабочая папка из `params.cwd` кадра клиента, пока она не известна.
  void _learnCwd(Map<String, Object?> frame) {
    if (_cwd != null) {
      return;
    }
    if (frame['params'] case {'cwd': final String cwd}) {
      _cwd = cwd;
      final variables = _matcher.variables;
      _matcher = _matcherFor(cwd)..variables.addAll(variables);
    }
  }

  /// Запрос клиента, которого фикстура не ожидает: `-32600` с текстом.
  Future<void> _reject(Map<String, Object?> frame, String reason) async {
    final id = frame['id'];
    if (frame['method'] is! String || id == null) {
      return;
    }
    await _transport.send(
      JsonRpcMessage.response(
        id: id is int ? JsonRpcId.integer(id) : JsonRpcId.string('$id'),
        error: JsonRpcError(
          code: -32600,
          message: '${_fixture.id} does not expect this frame: $reason',
        ),
      ),
    );
  }

  static String _encode(Object? value) => jsonEncode(value);
}

/// Тело процесса повторителя: фикстура [fixturePath] по stdin/stdout до
/// конца ввода.
Future<void> serveFixtureReplay(String fixturePath) async {
  final agent = await FixtureReplayAgent.start(
    loadFixtureFile(fixturePath),
    StdioServerAcpTransport(),
  );
  await agent.done;
  await agent.stop();
}

/// Пишет исходник процессного повторителя в [directory].
///
/// Как использовать: `dart --packages=КОНФИГ ФАЙЛ ФИКСТУРА`, где КОНФИГ —
/// [fixtureReplayPackageConfig], или `dart compile kernel` один раз для
/// многих запусков: исходник импортирует этот пакет.
Future<File> writeFixtureReplayAgent(
  Directory directory, {
  String fileName = 'fixture_replay_agent.dart',
}) async {
  final file = File('${directory.path}/$fileName');
  await file.writeAsString('''
import 'package:codelab_acp_testing/codelab_acp_testing.dart';

Future<void> main(List<String> args) => serveFixtureReplay(args.single);
''');
  return file;
}

/// `package_config.json`, с которым запускается исходник повторителя.
///
/// Под `flutter test` `Isolate.packageConfig` недоступен; тогда берётся
/// ближайший `.dart_tool/package_config.json` выше текущей папки — у
/// workspace он один и перечисляет все пакеты.
Future<String> fixtureReplayPackageConfig() async {
  try {
    final config = await Isolate.packageConfig;
    if (config != null) {
      return config.toFilePath();
    }
  } on UnsupportedError {
    // Ниже — поиск файла.
  }
  for (
    var dir = Directory.current.absolute;
    dir.parent.path != dir.path;
    dir = dir.parent
  ) {
    final file = File('${dir.path}/.dart_tool/package_config.json');
    if (file.existsSync()) {
      return file.path;
    }
  }
  throw StateError(
    'no .dart_tool/package_config.json above ${Directory.current.path}',
  );
}
