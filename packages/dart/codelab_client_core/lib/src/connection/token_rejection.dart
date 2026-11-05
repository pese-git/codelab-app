import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';

import 'connection_profile.dart';
import 'profile_token_ref.dart';
import 'secret_source.dart';

/// HTTP-статус отказа по токену (401/403) из цепочки причин ошибки
/// подключения; `null`, если причина другая.
///
/// Почему в kit: «сервер отверг токен или требует его» — единое для app и CLI
/// определение, а `AcpWebSocketHandshakeRejected` живёт в web-безопасном
/// `codelab_acp_transports`, так что `dart:io` здесь не нужен (design.md
/// change `add-app-settings-shell`, D12). По тексту сообщения
/// классифицировать ЗАПРЕЩЕНО: он зависит от ОС и SDK и может нести секрет.
///
/// Для чего: единственное место, где цепочка `cause` читается ради 401/403;
/// им пользуются [describeTokenRejection] и `classifyProbeFailure`
/// (`codelab_client_io`), второй таблицы нет.
///
/// Как использовать: `tokenRejectionStatus(error)` на ошибке, которую
/// бросили `ClientWorkspace.connect` или `AcpClientApplication.connect`.
int? tokenRejectionStatus(Object error) {
  Object? current = error;
  for (var depth = 0; current != null && depth < 8; depth++) {
    if (current is AcpWebSocketHandshakeRejected) {
      final status = current.statusCode;
      return status == 401 || status == 403 ? status : null;
    }
    current = switch (current) {
      AcpClientApplicationException(:final cause) => cause,
      AcpTransportException(:final cause) => cause,
      _ => null,
    };
  }
  return null;
}

/// Текст отказа по токену для хоста: `the agent rejected the token (HTTP
/// 401)` или `the agent requires a token (HTTP 401)`; `null` — ошибка не
/// об отказе по токену, хост печатает `describeFailure`.
///
/// Почему [tokenSent] обязателен: «отверг токен» верно, только если токен
/// ушёл серверу; без токена честный текст — «требует токен» (те же слова, что
/// у `Unauthorized` проверки профиля, D12). Значение токена в текст не
/// попадает.
///
/// Как использовать: [tokenSent] даёт [profileTokenSent] (CLI) или признак
/// «задан» источника токена формы (app).
String? describeTokenRejection(Object error, {required bool tokenSent}) {
  final status = tokenRejectionStatus(error);
  if (status == null) {
    return null;
  }
  return tokenSent
      ? 'the agent rejected the token (HTTP $status)'
      : 'the agent requires a token (HTTP $status)';
}

/// Текст отказа по токену для ошибки подключения по [profile] или `null`.
///
/// Почему одна функция: app и CLI должны читать токен в одном порядке и не
/// обращаться к источнику, когда причина не в токене (ревью
/// `feature/ws-unauthorized-message`).
///
/// Для чего: сначала [tokenRejectionStatus]; нет 401/403 — сразу `null`,
/// источник [source] не вызывается вовсе. Иначе [profileTokenSent] решает,
/// был ли токен, и [describeTokenRejection] строит текст. Значения токена в
/// тексте нет.
///
/// Как использовать: `await describeConnectFailureByToken(error, profile,
/// source) ?? describeFailure(error)`; [source] — тот же `SecretSource`, что
/// открывал транспорт.
Future<String?> describeConnectFailureByToken(
  Object error,
  ConnectionProfile profile,
  SecretSource? source,
) async {
  if (tokenRejectionStatus(error) == null) {
    return null;
  }
  return describeTokenRejection(
    error,
    tokenSent: await profileTokenSent(profile, source),
  );
}

/// Ушёл ли серверу токен при подключении по [profile].
///
/// Почему: `tokenRef` профиля сам ничего не доказывает — переменная может
/// быть не задана, а `secret:` пуст; тогда транспорт открывается без токена
/// (spec acp-client-kit «Ссылка на токен профиля»), и отказ сервера — это
/// «требует токен».
///
/// Для чего: для `ProfileSecretSource` — `hasToken` (`isSet` без чтения
/// значения, D13); для прочих источников — `read` с немедленным отбрасыванием
/// значения. Сбой источника — «не отправлен», исключение не пробрасывается:
/// текст ошибки подключения важнее. Без источника, без ссылки и для
/// не-WebSocket профиля — `false`.
Future<bool> profileTokenSent(
  ConnectionProfile profile,
  SecretSource? secrets,
) async {
  if (profile is! WebSocketProfile || secrets == null) {
    return false;
  }
  try {
    if (secrets is ProfileSecretSource) {
      return await secrets.hasToken(profile);
    }
    final ref = profile.tokenRef;
    if (ref == null) {
      return false;
    }
    final value = await secrets.read(ref);
    return value != null && value.isNotEmpty;
  } on Object catch (_) {
    return false;
  }
}
