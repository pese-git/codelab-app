// Только тип ошибки для второй линии D9 в [describeStartFailure]; процессы
// и файлы этот модуль не трогает (`apps/codelab_cli/AGENTS.md` §2).
import 'dart:io' show ProcessException;

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';

/// Подготовка сессии с готовым текстом для человека: нет сессии для
/// `--continue`, неизвестная опция или значение.
///
/// Почему отдельный тип: такие ошибки печатаются как есть, без префикса
/// «cannot start the agent», — агент запустился, не сошлись аргументы.
final class SessionSetupError implements Exception {
  const SessionSetupError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Новая сессия в [cwd], сессия [resume] (`session/load`) или последняя
/// сессия папки по `updatedAt` из `session/list` ([last], `--continue`).
///
/// Почему общая функция: headless и REPL открывают сессию по одним флагам
/// одинаково (spec cli-headless «Источники промпта headless», codelab-cli
/// «Сессии в REPL»; design.md change `add-codelab-cli`, D7, D9).
///
/// Как использовать: после `ClientWorkspace.connect`. Нет сессии для
/// [last] — [SessionSetupError]; агент без `loadSession` — ошибка kit.
Future<SessionHandle> openCliSession(
  ClientWorkspace workspace,
  String cwd, {
  String? resume,
  bool last = false,
}) async {
  if (resume != null) {
    return workspace.loadSession(SessionId(resume), cwd: cwd);
  }
  if (!last) {
    return workspace.newSession(cwd: cwd);
  }
  final sessions = [
    for (final summary in workspace.current.sessions)
      if (summary.cwd == cwd) summary,
  ];
  if (sessions.isEmpty) {
    throw SessionSetupError('No session to continue in $cwd.');
  }
  final latest = sessions.reduce(
    (a, b) => (b.updatedAt ?? DateTime(0)).isAfter(a.updatedAt ?? DateTime(0))
        ? b
        : a,
  );
  return workspace.loadSession(latest.id, cwd: cwd);
}

/// Устанавливает опцию конфигурации [name] (`model`, `mode`) значением
/// [value] до промпта: опция ищется по id, затем по категории; неизвестная
/// опция или значение — [SessionSetupError] без запроса к агенту, текущее
/// значение — без запроса. `null` — флаг не задан.
Future<void> applyConfigFlag(
  SessionHandle session,
  String name,
  String? value,
) async {
  if (value == null) {
    return;
  }
  final options = session.current.configOptions;
  final option =
      options.where((o) => o.id == name).firstOrNull ??
      options.where((o) => o.category == name).firstOrNull;
  if (option == null) {
    throw SessionSetupError('The agent has no "$name" option.');
  }
  if (!option.values.any((v) => v.value == value)) {
    throw SessionSetupError(
      'Unknown $name "$value". Available: '
      '${option.values.map((v) => v.value).join(', ')}.',
    );
  }
  if (option.currentValue == value) {
    return;
  }
  try {
    await session.setConfigOption(option.id, value);
  } on Object catch (error) {
    throw SessionSetupError(
      'Cannot set $name "$value": ${describeFailure(error)}',
    );
  }
}

/// Число аргументов для человека: `1 argument`, `0 arguments`, `2 arguments`.
///
/// Почему: значения аргументов stdio-профиля CLI не печатает нигде — среди них
/// бывает токен (`--token sk-…`), а по строке секретный аргумент не отличить
/// от обычного (design.md change `redact-cli-stdio-profile-args`, D1). Число
/// отличает «агент без аргументов» от «агента с аргументами», значений не
/// раскрывая.
///
/// Как использовать: единая формулировка D2 для `describeProfile`, `/profile`,
/// `profiles list` и `profiles show`; [count] — `StdioProfile.args.length`.
String argumentCount(int count) =>
    count == 1 ? '1 argument' : '$count arguments';

/// Какого агента не удалось запустить: команда или адрес, без токена.
///
/// Почему адрес WebSocket — только origin `scheme://host[:port]`: query вида
/// `?t=<токен>` и userinfo `user:pass@` несут секреты и не должны попадать в
/// stderr и журналы (AGENTS.md §10, §16; `profileOrigin` kit — та же формула,
/// что у экрана настроек app, IPv6 в скобках). Путь тоже отбрасывается — он
/// может нести идентификатор.
///
/// Для stdio — команда как есть в кавычках и число аргументов без значений
/// (`"my-agent" with 2 arguments`; design.md change
/// `redact-cli-stdio-profile-args`, D1, D2): путь с пробелами читается
/// однозначно, а токен из аргументов в stderr и stdout не попадает. Без
/// аргументов — одна команда в кавычках.
///
/// Для чего: единый текст для строк `cannot start the agent`, `cannot
/// connect to`, `cannot reconnect`, `/profile`.
String describeProfile(ConnectionProfile profile) => switch (profile) {
  StdioProfile(:final command, :final args) when args.isEmpty => '"$command"',
  StdioProfile(:final command, :final args) =>
    '"$command" with ${argumentCount(args.length)}',
  WebSocketProfile(:final uri) => profileOrigin(uri),
  EmbeddedProfile(:final hostProfile) => 'embedded agent ($hostProfile)',
};

/// Причина, по которой агент [profile] не запустился или не принял
/// подключение, для строки `codelab: cannot start the agent …: <причина>`.
///
/// Почему отдельная функция: REPL, TUI и `-p` печатают одну и ту же причину;
/// без неё отказ рукопожатия (HTTP 401/403) выглядел бы как «Failed to
/// connect ACP transport.», а токен и статус были бы видны только в журнале
/// агента (`serve.ws.unauthorized`).
///
/// Для чего: отказ по токену даёт `the agent rejected the token (HTTP 401).`
/// или `the agent requires a token (HTTP 401).` (определение — kit,
/// [describeTokenRejection]; значение токена в текст не попадает); сырая
/// `ProcessException` — только её `message`, без `Command: <аргументы>`
/// (design.md change `redact-cli-stdio-profile-args`, D9); все прочие
/// ошибки — прежний `describeFailure`.
///
/// Как использовать: [tokenSource] — тот же источник, что открывает транспорт
/// (`ProfileSecretSource`): по нему видно, ушёл ли токен. Без него токен
/// считается неотправленным.
Future<String> describeStartFailure(
  Object error,
  ConnectionProfile profile, {
  SecretSource? tokenSource,
}) async {
  // Порядок чтения токена — в kit: без 401/403 источник не вызывается.
  final rejection = await describeConnectFailureByToken(
    error,
    profile,
    tokenSource,
  );
  if (rejection != null) {
    return '$rejection.';
  }
  // Сырая `ProcessException` печатает `Command: <аргументы>` (D1). Обычно kit
  // оборачивает её в `AcpClientApplicationException`, а транспорт убирает
  // аргументы сам (D8); здесь — вторая линия на случай ошибки, брошенной
  // резолвером или будущим транспортом мимо обёртки (как D9 у `test-scenario`).
  return error is ProcessException ? error.message : describeFailure(error);
}
