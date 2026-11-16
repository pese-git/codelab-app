/// Строки таблицы определений агентов для страницы «Agents & modes»
/// (client-agent-setup «Строки определений агентов в мосте»; design.md change
/// `add-settings-agents-modes`, D7; SETUP-8).
///
/// ЗАГЛУШКА итерации 2, задача 2.4: сигнатуры и поля стабильны (на них
/// опирается desktop), логики нет — [agentDefinitionRowsOf] бросает
/// [UnimplementedError]. Красные тесты —
/// `test/views/agent_definition_rows_test.dart`.
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show AgentDefinition, ExtensionDiagnostic;

/// Статус строки таблицы (D7); подписи для пользователя строит клиент.
enum AgentRowStatus {
  /// `Available`.
  available,

  /// `Overridden by <путь>` — встроенный тип заменён определением; путь в
  /// [AgentDefinitionRowView.overriddenBy].
  overridden,

  /// `Model not configured` — диагностика `error` кода `model`.
  modelNotConfigured,

  /// `Error · line N` — другая диагностика `error`; номер строки и фиксированный
  /// текст — [AgentDefinitionRowView.errorLine] и `errorMessage`.
  error,

  /// `Not loaded: duplicate name`.
  duplicate,

  /// `Shadowed by project` — пользовательский файл заменён проектным.
  shadowed,

  /// `Subagents off` — встроенный тип при `subagents.enabled: false`.
  subagentsOff,
}

/// Где определение доступно (поле `scope`).
enum AgentRowScope { session, subagent, both }

/// Строка таблицы определений агентов.
///
/// Почему отдельный тип: клиент не разбирает диагностику, области и замены
/// встроенных типов сам (SETUP-8) и не получает тел файлов и имён неизвестных
/// ключей — только то, что показывает таблица.
///
/// Как использовать: строит [agentDefinitionRowsOf] (или `agentDefinitionRowsAt`
/// из `io.dart`); порядок строк — `default`, `general`, `explore`, `review`,
/// `plan`, затем файлы по имени. Заглушка итерации 2, задача 2.4.
final class AgentDefinitionRowView {
  const AgentDefinitionRowView({
    required this.name,
    required this.status,
    this.description,
    this.path,
    this.availableIn,
    this.tools,
    this.model,
    this.overriddenBy,
    this.errorLine,
    this.errorMessage,
  });

  /// Имя строки; у отклонённого файла — имя файла без `.md`.
  final String name;

  /// Описание принятого определения; `null` — у отклонённых файлов и
  /// `default`.
  final String? description;

  /// Путь файла определения как в диагностике; `null` — встроенная строка
  /// (в таблице `built-in`).
  final String? path;

  /// «Где доступно»; `null` — у отклонённых файлов.
  final AgentRowScope? availableIn;

  /// Имена инструментов; `null` — все (`all`) либо строка отклонена.
  final List<String>? tools;

  /// `<provider>/<model>`; `null` — модель сессии (`session model`).
  final String? model;

  final AgentRowStatus status;

  /// Путь определения, заменившего встроенный тип (только `overridden`).
  final String? overriddenBy;

  /// Номер строки ошибки (только `error`, если он известен).
  final int? errorLine;

  /// Фиксированный текст диагностики `error` без ключей и фрагментов файла.
  final String? errorMessage;
}

/// Строит строки таблицы по определениям, диагностике, встроенным типам и
/// признаку `subagents.enabled` (D7). Чистая функция, без `dart:io`.
///
/// Заглушка итерации 2, задача 2.4: бросает [UnimplementedError].
List<AgentDefinitionRowView> agentDefinitionRowsOf({
  required List<AgentDefinition> definitions,
  required List<ExtensionDiagnostic> diagnostics,
  required List<AgentDefinition> builtins,
  required bool subagentsEnabled,
}) => throw UnimplementedError('agentDefinitionRowsOf: задача 2.4');
