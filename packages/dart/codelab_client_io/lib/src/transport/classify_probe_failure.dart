import 'dart:io';

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';

/// Переводит ошибку открытия IO-транспорта в исход `ProfileProbe`.
///
/// Почему здесь: `ProcessException` и `WebSocketException` — типы
/// `dart:io`, а kit web-безопасен и их не видит (design.md change
/// `add-app-settings-shell`, D12). Классифицировать по тексту сообщения
/// ЗАПРЕЩЕНО: текст зависит от ОС и версии SDK и может нести секрет.
///
/// Для чего: единственное место, где ошибка превращается в
/// `CommandNotFound`; всё, что нельзя установить по типу, остаётся `null`, и
/// `ProfileProbe` выдаёт `Unreachable`.
///
/// Распознаётся:
/// * `ProcessException` с errno `ENOENT` в цепочке причин → `CommandNotFound`.
///
/// * `AcpWebSocketHandshakeRejected` со статусом 401/403 в цепочке причин →
///   `Unauthorized`. Статус берёт из ответа собственное рукопожатие
///   `WebSocketAcpTransport` (задача 3.3a), текст не разбирается.
/// * `AcpWebSocketHandshakeRejected` с другим статусом (404, 500…) →
///   `Unreachable(httpStatus, statusCode)`.
/// * `SocketException` с errno отказа в соединении → `Unreachable
///   (connectionRefused)`; с errno неразрешённого имени → `hostNotFound`.
///   Коды зависят от платформы и лежат в одной таблице [_errnoTable]; если
///   платформа неизвестна или код не из таблицы — причина `unknown`, а не
///   догадка (D12, решение 2026-11-05).
/// * `TlsException` (включая `HandshakeException`, `CertificateException`) →
///   `Unreachable(tlsFailed)`.
///
/// Детали для UI берутся только из типов и кодов; `message` (после
/// `describeFailure`) предназначен журналу.
///
/// Как использовать: `ProfileProbe(resolvers: …, classifier:
/// classifyProbeFailure)`; принимает исходную ошибку и сам идёт по
/// цепочке причин.
ProfileProbeOutcome? classifyProbeFailure(Object error) {
  Object? current = error;
  for (var depth = 0; current != null && depth < 8; depth++) {
    if (current is ProcessException && _isNotFound(current)) {
      return const CommandNotFound();
    }
    if (current is AcpWebSocketHandshakeRejected) {
      // 401/403 определяет kit (`tokenRejectionStatus`): таблица статусов
      // одна для проверки профиля и для подключения.
      if (tokenRejectionStatus(current) != null) {
        return const Unauthorized();
      }
      final status = current.statusCode;
      return Unreachable(
        describeFailure(error),
        reason: UnreachableReason.httpStatus,
        statusCode: status,
      );
    }
    if (current is TlsException) {
      return Unreachable(
        describeFailure(error),
        reason: UnreachableReason.tlsFailed,
      );
    }
    if (current is SocketException) {
      final reason = _socketReason(current);
      if (reason != null) {
        return Unreachable(describeFailure(error), reason: reason);
      }
    }
    current = switch (current) {
      AcpClientApplicationException(:final cause) => cause,
      AcpTransportException(:final cause) => cause,
      _ => null,
    };
  }
  return null;
}

/// Коды ОС для «не найдено», отказа в соединении и неразрешённого имени.
///
/// Почему таблица: errno различаются по платформам (macOS/iOS — BSD,
/// Linux/Android — Linux, Windows — Winsock/Win32), а `Platform.isX` в коде
/// размазывать запрещено (AGENTS.md §11). `Platform` читается только в
/// [_errnoTable]. `getaddrinfo` в Dart отдаёт в `osError.errorCode` значение
/// EAI_*: macOS 8 (EAI_NONAME, проверено), Linux -2 (EAI_NONAME) и -5
/// (EAI_NODATA), Windows 11001 (WSAHOST_NOT_FOUND). `notFound` — ENOENT: 2 на
/// POSIX; 2 (`ERROR_FILE_NOT_FOUND`) и 3 (`ERROR_PATH_NOT_FOUND`) на Windows.
typedef _Errnos = ({
  Set<int> notFound,
  Set<int> refused,
  Set<int> hostNotFound,
});

const _Errnos _bsd = (notFound: {2}, refused: {61}, hostNotFound: {8});
const _Errnos _linux = (notFound: {2}, refused: {111}, hostNotFound: {-2, -5});
const _Errnos _windows = (
  notFound: {2, 3},
  refused: {10061},
  hostNotFound: {11001},
);

/// Таблица текущей платформы или `null`, если платформа неизвестна.
_Errnos? get _errnoTable => switch (Platform.operatingSystem) {
  'macos' || 'ios' => _bsd,
  'linux' || 'android' => _linux,
  'windows' => _windows,
  _ => null,
};

bool _isNotFound(ProcessException error) =>
    _errnoTable?.notFound.contains(error.errorCode) ?? false;

UnreachableReason? _socketReason(SocketException error) {
  final code = error.osError?.errorCode;
  final table = _errnoTable;
  if (code == null || table == null) {
    return null;
  }
  if (table.refused.contains(code)) {
    return UnreachableReason.connectionRefused;
  }
  if (table.hostNotFound.contains(code)) {
    return UnreachableReason.hostNotFound;
  }
  return null;
}
