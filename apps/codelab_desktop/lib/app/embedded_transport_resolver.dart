import 'dart:async';

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_embedded/codelab_embedded.dart'
    show EmbeddedAgent, EmbeddedAgentConfigException, EmbeddedAgentOpener;

import 'provider_setup_offer.dart';
import 'secret_migration_offer.dart';

/// Подключение отменено, пока встроенный агент открывался (или резолвер уже
/// закрыт).
///
/// Почему отдельный тип: это не сбой агента, а устаревший `open` (design.md
/// change `add-embedded-agent-mode`, D6, «устаревший результат `open`»;
/// `AGENTS.md` §12). Вызывающий `connect` получает его вместо транспорта
/// агента, которого резолвер уже освободил.
final class EmbeddedOpenCancelledException implements Exception {
  const EmbeddedOpenCancelledException();

  @override
  String toString() =>
      'EmbeddedOpenCancelledException: the connection was cancelled while '
      'the embedded agent was opening.';
}

/// Открывает встроенного агента для `EmbeddedProfile` и владеет его
/// жизненным циклом: один агент на соединение (design.md change
/// `add-embedded-agent-mode`, D6, «Резолвер клиента», «Отмена подключения в
/// app»).
///
/// Почему в `app/`, а не в общем пакете: это отдельная копия резолвера CLI
/// (`apps/codelab_cli/lib/src/embedded_transport_resolver.dart`, около 125
/// строк). Резолвер реализует `TransportResolver` клиентского слоя, а мост
/// `codelab_embedded` не зависит от `codelab_client_*` (D1); обратная
/// зависимость `codelab_client_core` от моста запрещена allowlist сторожа
/// (web-безопасный пакет без ядра агента, D3). Одинаковость копий держат тесты
/// обоих клиентов: правка правил отмены `open` вносится в оба резолвера.
/// Импортирует только основной барель моста, поэтому тестируется без
/// IO-бареля.
///
/// Для чего и как:
/// * `open` **сериализован**: следующий вызов ждёт окончания предыдущего,
///   затем `await _running.dispose()`, затем открыватель. Два агента одного
///   резолвера не пишут один журнал сессий одновременно;
/// * **устаревший результат**: если, пока открыватель работает, пришёл новый
///   `open` (повторный Connect или Reconnect) или `close()` (закрытие root
///   scope), вернувшийся позже агент не становится текущим — ему сразу
///   вызывается `dispose()`, а вызывающий получает
///   [EmbeddedOpenCancelledException]. Иначе агент держал бы MCP-процессы и
///   журнал без владельца. Кнопки Disconnect и метода `disconnect` у
///   `ClientWorkspace` нет (решение L4): закрытие клиентского конца агент
///   замечает сам (D6, «Закрытие клиентом»);
/// * **признак «нужен провайдер»**: при `EmbeddedAgentConfigException`
///   резолвер спрашивает функцию composition root (снимок конфига и признак
///   моста) и записывает ответ в [ProviderSetupOffer] ДО исключения;
///   `ConnectionCubit` читает порт в обработчике сбоя своей попытки. Начало
///   каждого открытия и успех сбрасывают значение; сбой снимка — «не нужен»
///   (design.md change `add-provider-setup-ui`, D26);
/// * **предложение переноса секретов**: после успешного открытия резолвер
///   передаёт `EmbeddedAgent.secretsInConfig` в [SecretMigrationOffer] и
///   сбрасывает его, когда агент закрыт; вместе с признаком передаётся `cwd`
///   агента (перенос идёт по его файлам, а не по текущему проекту UI) (design.md change
///   `add-config-literal-secrets-and-migrate`, D8, п. 2);
/// * [close] вызывает `CodeLabRootLifecycle` при закрытии root scope: ждёт
///   открытие в полёте и `dispose` текущего агента, поэтому журнал дописан до
///   завершения закрытия.
final class EmbeddedTransportResolver implements TransportResolver {
  EmbeddedTransportResolver(
    this._opener, {
    SecretMigrationOffer? offer,
    ProviderSetupOffer? setupOffer,
    Future<bool> Function(String cwd)? providerSetupNeeded,
  }) : _offer = offer,
       _setupOffer = setupOffer,
       _providerSetupNeeded = providerSetupNeeded;

  final EmbeddedAgentOpener _opener;
  final SecretMigrationOffer? _offer;
  final ProviderSetupOffer? _setupOffer;

  /// Признак по снимку конфига с теми же `CODELAB_HOME` и окружением, что у
  /// открывателя; `null` — приложение без мастера провайдера.
  final Future<bool> Function(String cwd)? _providerSetupNeeded;

  /// Агент текущего соединения; `null` — ещё не открыт или уже освобождён.
  EmbeddedAgent? _running;

  /// Поколение подключения: растёт на каждый `open` и на `close()`. Результат
  /// открывателя годен, только если поколение не сдвинулось.
  int _generation = 0;

  /// Хвост очереди `open`: следующий вызов начинается после него.
  Future<void> _tail = Future<void>.value();

  Future<void>? _closing;

  @override
  bool supports(ConnectionProfile profile) => profile is EmbeddedProfile;

  @override
  Future<AcpTransport> open(
    ConnectionProfile profile, {
    required String projectDirectory,
  }) {
    final hostProfile = (profile as EmbeddedProfile).hostProfile;
    if (_closing != null) {
      return Future.error(const EmbeddedOpenCancelledException());
    }
    final generation = ++_generation;
    final result = _tail.then(
      (_) => _openSerialized(generation, projectDirectory, hostProfile),
    );
    // Очередь не должна падать вместе с ошибкой одного `open`.
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<AcpTransport> _openSerialized(
    int generation,
    String projectDirectory,
    String hostProfile,
  ) async {
    // Подключение уже вытеснено, пока ждало очередь: открывать агента, чтобы
    // тут же его закрыть, незачем.
    if (generation != _generation) {
      throw const EmbeddedOpenCancelledException();
    }
    final previous = _running;
    _running = null;
    // Предложение переноса принадлежит агенту: прежний уходит — признак
    // сбрасывается, а новое открытие даст цикл `false → true` (закрытое
    // крестиком предупреждение вернётся, D8).
    _offer?.set(null);
    _setupOffer?.set(null);
    await previous?.dispose();
    final EmbeddedAgent agent;
    try {
      agent = await _opener(cwd: projectDirectory, hostProfile: hostProfile);
    } on EmbeddedAgentConfigException catch (error) {
      // Признак выставляется до исключения и только для текущего открытия:
      // вытесненное открытие не должно оставить метку новой попытке (D26).
      if (await _setupNeededAt(projectDirectory) && generation == _generation) {
        _setupOffer?.set(ProviderSetupNeeded(projectDirectory));
      }
      // Баннер соединения показывает `message` у `ClientWorkspaceException`
      // без префикса типа: голый текст проблем и подсказка, как в CLI и по
      // контракту `EmbeddedAgentConfigException.message` (agent-workbench-ui
      // «Тип подключения «Встроенный агент»», D13, п. 2).
      throw ClientWorkspaceException(error.message);
    }
    if (generation != _generation) {
      // `dispose` агента не бросает по контракту (шаги в своих `try`, D6).
      await agent.dispose();
      throw const EmbeddedOpenCancelledException();
    }
    _running = agent;
    _setupOffer?.set(null);
    // Признак вычислил мост при открытии и после переноса не пересчитывает:
    // предупреждение держится до переподключения (D8, п. 1).
    _offer?.set(agent.secretsInConfig ? projectDirectory : null);
    unawaited(
      agent.closed.then<void>(
        (_) => _clearOfferIfCurrent(agent),
        onError: (Object _) => _clearOfferIfCurrent(agent),
      ),
    );
    return agent.clientTransport;
  }

  /// Признак «нужен провайдер»: сбой чтения снимка — «нет», баннер тогда
  /// показывает прежний текст проблем (D26).
  Future<bool> _setupNeededAt(String cwd) async {
    final probe = _providerSetupNeeded;
    if (probe == null) {
      return false;
    }
    try {
      return await probe(cwd);
    } on Object {
      return false;
    }
  }

  /// Агент закрылся сам (клиентский конец закрыт): признак сбрасывается, если
  /// это ещё текущий агент; более новый агент своё значение не теряет.
  void _clearOfferIfCurrent(EmbeddedAgent agent) {
    final running = _running;
    if (running == null || identical(running, agent)) {
      _offer?.set(null);
    }
  }

  /// Закрывает резолвер: дожидается открытия в полёте и `dispose` текущего
  /// агента. Идемпотентен; после него `open` отклоняется.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    // Открытие в полёте станет устаревшим и освободит своего агента само.
    _generation++;
    await _tail;
    final agent = _running;
    _running = null;
    _offer?.set(null);
    _setupOffer?.set(null);
    await agent?.dispose();
  }
}
