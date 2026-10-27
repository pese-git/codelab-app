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

/// Какого агента не удалось запустить: команда или адрес, без токена.
String describeProfile(ConnectionProfile profile) => switch (profile) {
  StdioProfile(:final command, :final args) =>
    '"${[command, ...args].join(' ')}"',
  WebSocketProfile(:final uri) => '$uri',
};
