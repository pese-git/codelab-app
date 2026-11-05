import 'package:codelab_client_core/codelab_client_core.dart'
    show
        CommandNotFound,
        NotAcp,
        ProfileProbeOutcome,
        Reachable,
        TimedOut,
        Unauthorized,
        Unreachable,
        UnreachableReason,
        Unsupported;

import 'profile_view.dart' show EnvTokenView, NoTokenView, ProfileTokenView;

/// Текст исхода проверки для диалога и строки профиля.
///
/// Почему отдельная функция: оба места показывают один и тот же исход, и
/// тексты не должны разойтись (`12-4` §12.4.9, шаг 5; spec app-settings
/// «Диалог «Add connection profile»»; design.md D12, таблица текстов).
///
/// Для чего: единственное место, где [ProfileProbeOutcome] становится
/// строкой. Детали берутся только из типизированных данных: причина
/// `UnreachableReason`, `statusCode`, поле Command профиля и источник токена.
/// `Unreachable.message` и текст исключения в строку НЕ попадают: в них
/// остаются путь и query URL, аргументы команды и произвольный текст сервера
/// (AGENTS.md §10, §16; D17, решение пользователя 2026-11-05).
///
/// Как использовать: `probeOutcomeText(outcome, command: …, token: …)` в
/// `Text`; [command] — значение поля Command (без аргументов и `env`) для
/// stdio-профиля, [token] — источник токена WebSocket-профиля
/// (`tokenViewOf`). «rejected the token» показывается только для
/// `EnvTokenView(isSet: true)`: если переменная не задана или ссылка не
/// поддерживается, токен не отправлялся и честный текст — «requires a
/// token». Успешность — [probeOutcomeIsOk].
String probeOutcomeText(
  ProfileProbeOutcome outcome, {
  String? command,
  ProfileTokenView token = const NoTokenView(),
}) => switch (outcome) {
  Reachable(:final latency, :final agentName, :final agentVersion) => [
    'Reachable',
    '${latency.inMilliseconds} ms',
    ?_agent(agentName, agentVersion),
  ].join(' · '),
  Unauthorized() =>
    token is EnvTokenView && token.isSet
        ? 'Unauthorized: the agent rejected the token'
        : 'Unauthorized: the agent requires a token',
  Unreachable(:final reason, :final statusCode) => switch (reason) {
    UnreachableReason.connectionRefused => 'Unreachable: connection refused',
    UnreachableReason.hostNotFound => 'Unreachable: host not found',
    UnreachableReason.tlsFailed => 'Unreachable: TLS handshake failed',
    UnreachableReason.httpStatus when statusCode != null =>
      'Unreachable: HTTP $statusCode',
    UnreachableReason.httpStatus || UnreachableReason.unknown => 'Unreachable',
  },
  TimedOut() => 'Timed out',
  NotAcp() => 'Not an ACP agent',
  CommandNotFound() =>
    command == null || command.trim().isEmpty
        ? 'Command not found'
        : 'Command not found: ${command.trim()}',
  Unsupported() => 'Not supported here',
};

/// Исход «агент ответил» — показывается зелёным, остальные — как проблема.
bool probeOutcomeIsOk(ProfileProbeOutcome outcome) => outcome is Reachable;

/// Короткое имя исхода для журнала: без адреса и текстов (D17).
String probeOutcomeName(ProfileProbeOutcome outcome) => switch (outcome) {
  Reachable() => 'reachable',
  Unauthorized() => 'unauthorized',
  Unreachable() => 'unreachable',
  TimedOut() => 'timed_out',
  NotAcp() => 'not_acp',
  CommandNotFound() => 'command_not_found',
  Unsupported() => 'unsupported',
};

String? _agent(String? name, String? version) {
  final parts = [
    if (name != null && name.isNotEmpty) name,
    if (version != null && version.isNotEmpty) version,
  ];
  return parts.isEmpty ? null : parts.join(' ');
}
