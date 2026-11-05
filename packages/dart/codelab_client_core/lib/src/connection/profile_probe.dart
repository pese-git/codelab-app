import 'dart:async';

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';

import '../diagnostics/diagnostics.dart';
import 'connection_profile.dart';
import 'transport_resolver.dart';

/// Исход проверки профиля (design.md change `add-app-settings-shell`, D12).
///
/// Почему закрытая иерархия: форма показывает для каждого исхода свой текст
/// и свои действия, и компилятор проверяет, что ни один не забыт.
sealed class ProfileProbeOutcome {
  const ProfileProbeOutcome();
}

/// Агент ответил на `initialize`; [latency] — время до ответа, имя и версия
/// из `agentInfo`, если агент их прислал.
final class Reachable extends ProfileProbeOutcome {
  const Reachable({required this.latency, this.agentName, this.agentVersion});

  final Duration latency;
  final String? agentName;
  final String? agentVersion;

  @override
  String toString() => 'Reachable(${latency.inMilliseconds} ms)';
}

/// Сервер отказал в доступе (HTTP 401/403 при рукопожатии). Выдаёт только
/// классификатор хоста, и только если транспорт сохранил статус.
final class Unauthorized extends ProfileProbeOutcome {
  const Unauthorized();

  @override
  String toString() => 'Unauthorized()';
}

/// Типизированная причина недоступности (design.md change
/// `add-app-settings-shell`, D12, решение 2026-11-05).
///
/// Почему: UI показывает пользователю текст по причине («Connection
/// refused», «Host not found»…), а текст исключения может нести часть URL и
/// секрет, поэтому детали берутся только из типов и кодов ошибок.
enum UnreachableReason {
  /// Порт никто не слушает (ECONNREFUSED).
  connectionRefused,

  /// Имя хоста не разрешилось.
  hostNotFound,

  /// Не удалось установить TLS (сертификат, протокол).
  tlsFailed,

  /// Сервер ответил на рукопожатие HTTP-статусом, не 401/403; код — в
  /// `Unreachable.statusCode`.
  httpStatus,

  /// Причину по типам установить не удалось.
  unknown,
}

/// Соединиться не удалось.
///
/// Для чего: [reason] и [statusCode] — типизированные данные для UI;
/// [message] прошёл `describeFailure`, секретов не содержит и предназначен
/// только для журнала и диагностики: UI его НЕ показывает.
///
/// Как использовать: kit создаёт `Unreachable(describeFailure(e))` с
/// причиной [UnreachableReason.unknown]; классификатор хоста возвращает
/// `Unreachable(describeFailure(e), reason: …)`. [statusCode] задаётся
/// только вместе с [UnreachableReason.httpStatus].
final class Unreachable extends ProfileProbeOutcome {
  const Unreachable(
    this.message, {
    this.reason = UnreachableReason.unknown,
    this.statusCode,
  }) : assert(
         statusCode == null || reason == UnreachableReason.httpStatus,
         'statusCode задаётся только для UnreachableReason.httpStatus',
       );

  final String message;
  final UnreachableReason reason;

  /// HTTP-статус отказа; только для [UnreachableReason.httpStatus].
  final int? statusCode;

  @override
  String toString() =>
      'Unreachable($reason${statusCode == null ? '' : ' $statusCode'}: $message)';
}

/// Агент не ответил на `initialize` за отведённое время.
final class TimedOut extends ProfileProbeOutcome {
  const TimedOut();

  @override
  String toString() => 'TimedOut()';
}

/// Ответ не разобран или версия протокола несовместима.
final class NotAcp extends ProfileProbeOutcome {
  const NotAcp();

  @override
  String toString() => 'NotAcp()';
}

/// Команда stdio-профиля не найдена.
final class CommandNotFound extends ProfileProbeOutcome {
  const CommandNotFound();

  @override
  String toString() => 'CommandNotFound()';
}

/// Ни один резолвер не открывает такой профиль.
final class Unsupported extends ProfileProbeOutcome {
  const Unsupported();

  @override
  String toString() => 'Unsupported()';
}

/// Переводит ошибку открытия транспорта в исход или `null` («не знаю»).
///
/// Почему порт: `ProcessException` и `WebSocketException` — типы `dart:io`,
/// kit их не видит; классификатор передаёт composition root
/// (`classifyProbeFailure` из `codelab_client_io`). Получает исходную ошибку
/// и сам разматывает цепочку причин. По тексту сообщения классифицировать
/// ЗАПРЕЩЕНО (D12).
typedef ProbeFailureClassifier = ProfileProbeOutcome? Function(Object error);

/// Флаг отмены проверки.
///
/// Почему не `Future`/`Stream`: нужен однократный сигнал, который можно
/// поставить до старта проверки (закрытие диалога раньше `probe`).
///
/// Как использовать: создать на каждую проверку, передать в
/// [ProfileProbe.probe], вызвать [cancel] при закрытии диалога, повторной
/// проверке или `close()` владельца. Повторный [cancel] безвреден.
final class ProbeCancellation {
  final _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  /// Завершается при [cancel].
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}

/// Проверка профиля: один `initialize` без сессии.
///
/// Почему: пользователь должен узнать, достижим ли агент, до сохранения
/// профиля, но проверка не должна трогать рабочее соединение, открывать
/// сессии или запускать инструменты (SETUP-20, design.md change
/// `add-app-settings-shell`, D12).
///
/// Для чего: открывает транспорт тем же набором [TransportResolver], что
/// `ClientWorkspace`, поднимает временный `AcpClientApplication` без
/// fs- и terminal-адаптеров (возможности клиента `false`) и выполняет
/// `connect`, то есть ровно один `initialize`. `session/new` не
/// отправляется никогда. Транспорт закрывается по ответу, ошибке, таймауту
/// и отмене.
///
/// Как использовать: composition root создаёт
/// `ProfileProbe(resolvers: …, classifier: classifyProbeFailure)`;
/// форма вызывает [probe] и отбрасывает результат, если проверка устарела
/// (номер проверки ведёт владелец — Cubit формы).
final class ProfileProbe {
  ProfileProbe({
    required List<TransportResolver> resolvers,
    this.classifier,
    this.defaultTimeout = const Duration(seconds: 10),
  }) : _resolvers = List.unmodifiable(resolvers);

  final List<TransportResolver> _resolvers;

  /// Классификатор ошибок IO-транспортов; без него всё неопознанное —
  /// [Unreachable].
  final ProbeFailureClassifier? classifier;

  /// Таймаут, если вызов не задал свой (spec: 10 s).
  final Duration defaultTimeout;

  /// Проверяет [profile]. `null` — проверка отменена через [cancellation]:
  /// вызывающий исхода не получает.
  ///
  /// [projectDirectory] нужен резолверу stdio-профиля, который запускается в
  /// папке проекта. Не бросает исключений: любой сбой — исход.
  Future<ProfileProbeOutcome?> probe(
    ConnectionProfile profile, {
    String projectDirectory = '',
    Duration? timeout,
    ProbeCancellation? cancellation,
  }) async {
    TransportResolver? resolver;
    for (final candidate in _resolvers) {
      if (candidate.supports(profile)) {
        resolver = candidate;
        break;
      }
    }
    if (resolver == null) {
      return const Unsupported();
    }
    if (cancellation?.isCancelled ?? false) {
      return null;
    }

    final stopwatch = Stopwatch()..start();
    AcpTransport? transport;
    AcpClientApplication? application;
    var released = false;
    final settled = Completer<ProfileProbeOutcome?>();
    void settle(ProfileProbeOutcome? outcome) {
      if (!settled.isCompleted) {
        settled.complete(outcome);
      }
    }

    // Исход один: побеждает тот из трёх источников (отмена, таймер, ответ
    // агента), чей `settle` вызван первым; поздние вызовы отбрасываются
    // (AGENTS.md §9).
    unawaited(cancellation?.whenCancelled.then((_) => settle(null)));
    final timer = Timer(
      timeout ?? defaultTimeout,
      () => settle(const TimedOut()),
    );

    try {
      unawaited(
        _run(
          resolver,
          profile,
          projectDirectory,
          stopwatch,
          isReleased: () => released,
          onOpened: (opened, app) {
            transport = opened;
            application = app;
          },
        ).then(settle),
      );
      return await settled.future;
    } finally {
      timer.cancel();
      released = true;
      await _release(application, transport);
    }
  }

  Future<ProfileProbeOutcome> _run(
    TransportResolver resolver,
    ConnectionProfile profile,
    String projectDirectory,
    Stopwatch stopwatch, {
    required bool Function() isReleased,
    required void Function(AcpTransport, AcpClientApplication) onOpened,
  }) async {
    try {
      final transport = await resolver.open(
        profile,
        projectDirectory: projectDirectory,
      );
      if (isReleased()) {
        // Проверка отменена или истекла, пока резолвер открывал транспорт:
        // `probe` уже вернулся и этот транспорт не закроет никто, кроме нас.
        await transport.close();
        return const Unreachable('Probe finished before the transport opened.');
      }
      // `connect` сначала закрывает прежний транспорт приложения, поэтому
      // приложение создаётся на пустышке, а настоящий транспорт приходит в
      // `connect` — как в `ClientWorkspace`.
      final application = AcpClientApplication(transport: _IdleTransport());
      onOpened(transport, application);
      final state = await application.connect(transport);
      final agent = state is ClientConnectionReady ? state.agentInfo : null;
      return Reachable(
        latency: stopwatch.elapsed,
        agentName: agent?.name,
        agentVersion: agent?.version,
      );
    } on Object catch (error) {
      return _outcomeFor(error);
    }
  }

  ProfileProbeOutcome _outcomeFor(Object error) {
    if (_causes(error).any((e) => e is AcpRequestTimeoutException)) {
      return const TimedOut();
    }
    if (_causes(error).any(
      (e) =>
          e is UnsupportedProtocolVersionException ||
          (e is AcpTransportException &&
              e.code == AcpTransportErrorCode.protocolViolation),
    )) {
      return const NotAcp();
    }
    return classifier?.call(error) ?? Unreachable(describeFailure(error));
  }

  /// Закрывает приложение и транспорт; сбои закрытия проверку не меняют
  /// (исход уже известен), но и не теряются тихо — закрытие идемпотентно.
  Future<void> _release(
    AcpClientApplication? application,
    AcpTransport? transport,
  ) async {
    try {
      await application?.dispose();
    } on Object catch (_) {
      // dispose закрывает транспорт сам; ошибка закрытия не меняет исход.
    }
    try {
      await transport?.close();
    } on Object catch (_) {
      // Транспорт уже закрыт приложением или упал при закрытии.
    }
  }

  /// Ошибка и цепочка её причин (`cause`).
  static Iterable<Object> _causes(Object error) sync* {
    Object? current = error;
    var depth = 0;
    while (current != null && depth++ < 8) {
      yield current;
      current = switch (current) {
        AcpClientApplicationException(:final cause) => cause,
        AcpTransportException(:final cause) => cause,
        _ => null,
      };
    }
  }
}

/// Пустой транспорт-заглушка для конструктора `AcpClientApplication`: тот
/// требует транспорт сразу, а `connect` его заменяет и закрывает.
final class _IdleTransport implements AcpTransport {
  final _inbound = StreamController<JsonRpcMessage>.broadcast();
  final _events = StreamController<AcpTransportEvent>.broadcast();

  @override
  Stream<JsonRpcMessage> get inbound => _inbound.stream;

  @override
  Stream<AcpTransportEvent> get events => _events.stream;

  @override
  AcpTransportState get state => AcpTransportState.idle;

  @override
  Future<void> start() async {}

  @override
  Future<void> send(JsonRpcMessage message) async {}

  @override
  Future<void> close({Duration? timeout}) async {
    await _inbound.close();
    await _events.close();
  }
}
