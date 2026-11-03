import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show JsonRpcMessage, JsonRpcNotification;
import 'package:codelab_acp_transports/codelab_acp_transports.dart'
    show AcpTransportState;
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_embedded/codelab_embedded.dart';
import 'package:codelab_embedded/io.dart';
import 'package:http/http.dart' as web;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/acp_client.dart';
import 'package:codelab_agent_io/testing.dart' show rewriteUntil;

/// Перезагрузка конфига встроенного агента (embedded-agent «Перезагрузка
/// конфига встроенного агента»; design.md change
/// `add-config-writer-and-reload`, D7, D13).
///
/// Почему так: источник `FileConfigSource` создаёт открыватель, поэтому тест
/// идёт через `localEmbeddedAgentOpener` во временных `CODELAB_HOME` и папке
/// проекта; правку делает сам тест прямой записью файла, то есть «вне агента»,
/// как другой процесс. Сети нет — `MockClient`. Ожидание — событием (кадр
/// клиенту, запись журнала, событие каталога), а не временем.
void main() {
  const keyA = 'sk-test-aaaaaaaaaaaaaaaa';
  const keyB = 'sk-test-bbbbbbbbbbbbbbbb';

  late Directory temp;
  late String home;
  late Directory project;
  late SignalLogger logger;
  late FakeClock clock;
  EmbeddedAgent? agent;
  TestAcpClient? client;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('codelab_embedded_reload_');
    home = '${temp.path}/home';
    Directory(home).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    project = Directory('${temp.path}/project')..createSync();
    logger = SignalLogger();
    clock = FakeClock();
  });

  tearDown(() async {
    await client?.close();
    await agent?.dispose();
    agent = client = null;
    temp.deleteSync(recursive: true);
  });

  String config({
    String models = 'm: {}',
    String secrets = '',
    String tail = '',
  }) =>
      '''
$secrets
providers:
  p:
    kind: openai-compatible
    base_url: https://p.test/v1
    api_key_secret: codelab/p
    models:
      $models
agent:
  default_model: p/m
$tail''';

  void writeConfig(String yaml) =>
      File('$home/config.yaml').writeAsStringSync(yaml);

  void writeSecret(String value, [int attempt = 0]) {
    // Хвост-комментарий делает повторные записи различимыми для sha256.
    final file = File('$home/secrets.yaml')
      ..writeAsStringSync('"codelab/p": "$value"\n# attempt $attempt\n');
    Process.runSync('/bin/chmod', ['600', file.path]);
  }

  /// Ответ 401 завершает ход быстро; заголовок запоминается.
  (web.Client, List<String?>) denyingClient() {
    final authorizations = <String?>[];
    final mock = MockClient.streaming((request, body) async {
      authorizations.add(request.headers['authorization']);
      return web.StreamedResponse(
        Stream.value(utf8.encode('{"error":{"message":"denied"}}')),
        401,
        headers: {'content-type': 'application/json'},
      );
    });
    return (mock, authorizations);
  }

  EmbeddedAgentOpener opener({web.Client? http}) => localEmbeddedAgentOpener(
    environment: {'CODELAB_HOME': home},
    logger: logger,
    clock: clock,
    httpClient: http ?? MockClient((_) async => throw StateError('no net')),
  );

  Future<String> connect(EmbeddedAgent opened) async {
    agent = opened;
    client = TestAcpClient(opened.clientTransport);
    await client!.start();
    await client!.initialize();
    return client!.newSession(project.path);
  }

  /// Значения опции `model` из `config_option_update`, если кадр такой.
  List<String>? modelValues(JsonRpcMessage message) {
    if (message is! JsonRpcNotification || message.method != 'session/update') {
      return null;
    }
    final update = (message.params! as Map)['update']! as Map;
    if (update['sessionUpdate'] != 'config_option_update') {
      return null;
    }
    return [
      for (final option in (update['configOptions']! as List).cast<Map>())
        if (option['id'] == 'model')
          for (final entry in (option['options']! as List).cast<Map>())
            entry['value']! as String,
    ];
  }

  /// Завершается, когда [condition] становится истинным; проверка раз в 5 мс
  /// (событие приходит из ОС, у него нет `Future`, на который можно ждать).
  Future<void> becomes(bool Function() condition) {
    final done = Completer<void>();
    Timer.periodic(const Duration(milliseconds: 5), (timer) {
      if (condition()) {
        timer.cancel();
        done.complete();
      }
    });
    return done.future;
  }

  /// «Свидетель» событий каталога: подписка `Directory.watch`, созданная ДО
  /// действий теста и прогретая записью служебного файла `.witness` (его
  /// источник игнорирует) до первого события. Так подписка заведомо работает,
  /// и счётчик событий можно использовать как «ОС доставила правки».
  Future<({int Function() count, Future<void> Function() cancel})> witness(
    String path,
  ) async {
    var count = 0;
    final subscription = Directory(path).watch().listen((_) => count++);
    await rewriteUntil(
      becomes(() => count > 0),
      (n) => File('$path/.witness').writeAsStringSync('$n'),
    );
    return (count: () => count, cancel: subscription.cancel);
  }

  /// Пишет варианты файла, пока свидетель не увидит ещё [extra] событий:
  /// запас по числу событий переживает разную очередность подписок в ОС.
  Future<void> writeUntilWitnessed(
    ({int Function() count, Future<void> Function() cancel}) w,
    void Function(int attempt) write, {
    int extra = 3,
  }) {
    final target = w.count() + extra;
    return rewriteUntil(becomes(() => w.count() >= target), write);
  }

  test('an edit of config.yaml outside the agent gives the session '
      'config_option_update with the new model, no reconnect '
      '(scenario "Правка из другого процесса")', () async {
    writeConfig(config());
    // Настоящие часы: событие каталога и debounce идут в реальном времени.
    final opened = await localEmbeddedAgentOpener(
      environment: {'CODELAB_HOME': home},
      logger: logger,
      httpClient: MockClient((_) async => throw StateError('no net')),
    )(cwd: project.path, hostProfile: 'embedded-cli');
    await connect(opened);
    final update = client!.frames
        .map(modelValues)
        .firstWhere((values) => values?.contains('p/m2') ?? false);

    // Подписка `watch` стартует с задержкой: запись повторяется (с разным
    // хвостом), пока не придёт кадр с новой моделью.
    await rewriteUntil(
      update,
      (n) => writeConfig(
        config(models: 'm: {}\n      m2: {}', tail: '# edit $n\n'),
      ),
    );

    expect(await update, contains('p/m2'));
    expect(agent!.clientTransport.state, isNot(AcpTransportState.failed));
  });

  test(
    'dispose closes the source: no timers of the clock, a later edit '
    'does not start a load (scenario "dispose закрывает наблюдатель")',
    () async {
      writeConfig(config());
      await connect(
        await opener()(cwd: project.path, hostProfile: 'embedded-cli'),
      );
      final w = await witness(home);
      addTearDown(w.cancel);
      // Правка запускает debounce источника на часах теста; момент запуска
      // виден по событию журнала, а не по таймерам часов.
      final debounced = logger.next(
        (event) => event == 'config.watch.debounce',
      );
      await rewriteUntil(
        debounced,
        (n) => writeConfig(
          config(models: 'm: {}\n      m2: {}', tail: '# edit $n\n'),
        ),
      );
      expect(clock.pendingTimers, greaterThan(0));

      await agent!.dispose();

      expect(clock.pendingTimers, 0);
      final before = logger.eventsOf('config.watch.debounce').length;
      await writeUntilWitnessed(
        w,
        (n) => writeConfig(
          config(models: 'm: {}\n      m3: {}', tail: '# late $n\n'),
        ),
      );
      await pumpEventQueue();
      expect(clock.pendingTimers, 0);
      expect(logger.eventsOf('config.watch.debounce'), hasLength(before));
      expect(logger.eventsOf('config.reload.applied'), isEmpty);
    },
  );

  test('a replaced key in secrets.yaml reaches the next turn without a '
      'restart (scenario "Новый ключ провайдера")', () async {
    writeConfig(config(secrets: 'secrets:\n  backend: file\n'));
    writeSecret(keyA);
    final (mock, authorizations) = denyingClient();
    final session = await connect(
      await opener(http: mock)(cwd: project.path, hostProfile: 'embedded-cli'),
    );
    await client!.prompt(session, 'hi').then<void>((_) {}, onError: (_) {});
    expect(authorizations, ['Bearer $keyA']);

    final reloaded = logger.next(
      (event) =>
          event == 'config.reload.noop' || event == 'config.reload.applied',
    );
    // Событие каталога приходит в реальном времени с задержкой подписки, а
    // debounce источника идёт по часам теста: запись повторяется, а часы
    // двигаются, пока перезагрузка не состоится.
    await rewriteUntil(
      reloaded,
      (n) => writeSecret(keyB, n),
      onTick: () => unawaited(clock.elapse(const Duration(seconds: 1))),
    );
    await client!.prompt(session, 'again').then<void>((_) {}, onError: (_) {});

    expect(authorizations, ['Bearer $keyA', 'Bearer $keyB']);
    expect(logger.records.join('\n'), isNot(contains(keyB)));
  });

  test('a failure after the source is created closes it before the error '
      'is rethrown (scenario "срыв открытия")', () async {
    writeConfig(config());
    final failing = SignalLogger(failOn: 'host.plan');

    await expectLater(
      localEmbeddedAgentOpener(
        environment: {'CODELAB_HOME': home},
        logger: failing,
        clock: clock,
        httpClient: MockClient((_) async => throw StateError('no net')),
      )(cwd: project.path, hostProfile: 'embedded-cli'),
      throwsA(isA<StateError>()),
    );

    // Источник закрыт, если правки не доходят до его debounce: журнал
    // `failing` не получает `config.watch.debounce`, а таймеров на часах нет.
    // Свидетель прогрет заранее, поэтому «событий нет» не объясняется
    // молчанием ОС.
    final w = await witness(home);
    addTearDown(w.cancel);
    await writeUntilWitnessed(
      w,
      (n) => writeConfig(
        config(models: 'm: {}\n      m2: {}', tail: '# edit $n\n'),
      ),
    );
    await pumpEventQueue();
    expect(failing.eventsOf('config.watch.debounce'), isEmpty);
    expect(clock.pendingTimers, 0);
  });
}

/// Журнал теста: записывает события, ждёт нужное и по просьбе ломает
/// запись одного события (имитация сбоя сборки после создания источника).
final class SignalLogger implements Logger {
  SignalLogger({this.failOn});

  final _inner = RecordingLogger();
  List<LogRecord> get records => _inner.records;
  List<LogRecord> eventsOf(String event) => _inner.eventsOf(event);

  @override
  bool isEnabled(LogLevel level) => _inner.isEnabled(level);

  final String? failOn;
  final _waiters = <(bool Function(String), Completer<void>)>[];

  /// Завершается при ближайшей записи события, подходящего под [match].
  Future<void> next(bool Function(String event) match) {
    final completer = Completer<void>();
    _waiters.add((match, completer));
    return completer.future;
  }

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {
    if (event == failOn) {
      throw StateError('injected failure');
    }
    _inner.log(level, event, fields: fields, error: error, stack: stack);
    for (final (match, completer) in [..._waiters]) {
      if (match(event) && !completer.isCompleted) {
        completer.complete();
      }
    }
  }
}
