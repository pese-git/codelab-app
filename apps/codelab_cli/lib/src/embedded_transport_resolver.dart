import 'dart:async';

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_embedded/codelab_embedded.dart'
    show EmbeddedAgent, EmbeddedAgentOpener;

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
/// `add-embedded-agent-mode`, D6, «Резолвер клиента»).
///
/// Почему в CLI, а не в пакете: резолвер реализует `TransportResolver`
/// клиентского слоя, а мост `codelab_embedded` не зависит от `codelab_client_*`
/// (D1). Общий пакет невозможен: `codelab_client_core` не может зависеть от
/// `codelab_embedded` (allowlist зависимостей ядра, `melos run guard`).
/// Поэтому у desktop своя копия (около 125 строк,
/// `apps/codelab_desktop/lib/app/embedded_transport_resolver.dart`);
/// одинаковость поведения держат тесты обоих клиентов — правка здесь требует
/// парной правки там.
///
/// Для чего и как:
/// * `open` **сериализован**: следующий вызов ждёт окончания предыдущего,
///   затем `await _running.dispose()`, затем открыватель. Два агента одного
///   резолвера не пишут один журнал сессий одновременно;
/// * **устаревший результат**: если, пока открыватель работает, пришёл новый
///   `open` или `close()`, вернувшийся позже агент не становится текущим —
///   ему сразу вызывается `dispose()`, а вызывающий получает
///   [EmbeddedOpenCancelledException]. Иначе агент держал бы MCP-процессы и
///   журнал без владельца. Отдельного «disconnect» у `ClientWorkspace` нет:
///   закрытие клиентского конца агент замечает сам (D6, «Закрытие клиентом»);
/// * `close()` вызывает composition root при выходе: ждёт открытие в полёте и
///   `dispose` текущего агента, поэтому журнал дописан до завершения
///   процесса.
final class EmbeddedTransportResolver implements TransportResolver {
  EmbeddedTransportResolver(this._opener);

  final EmbeddedAgentOpener _opener;

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
    await previous?.dispose();
    final agent = await _opener(
      cwd: projectDirectory,
      hostProfile: hostProfile,
    );
    if (generation != _generation) {
      // `dispose` агента не бросает по контракту (шаги в своих `try`, D6).
      await agent.dispose();
      throw const EmbeddedOpenCancelledException();
    }
    _running = agent;
    return agent.clientTransport;
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
    await agent?.dispose();
  }
}
