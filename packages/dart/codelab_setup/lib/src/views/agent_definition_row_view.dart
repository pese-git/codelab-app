/// Строки таблицы определений агентов для страницы «Agents & modes»
/// (client-agent-setup «Строки определений агентов в мосте»; design.md change
/// `add-settings-agents-modes`, D7; SETUP-8).
///
/// Тесты — `test/views/agent_definition_rows_test.dart`.
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show
        AgentDefinition,
        AgentScope,
        DiagnosticLevel,
        ExtensionDiagnostic,
        agentDefinitionModelNotInCatalogMessage;

/// Статус строки таблицы (D7); подписи для пользователя строит клиент.
enum AgentRowStatus {
  /// `Available`.
  available,

  /// `Overridden by <путь>` — встроенный тип заменён определением; путь в
  /// [AgentDefinitionRowView.overriddenBy].
  overridden,

  /// `Model not configured` — `invalid_value` с текстом
  /// `agentDefinitionModelNotInCatalogMessage` (D18 change
  /// `add-settings-agents-modes`).
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
/// `plan`, затем файлы по имени.
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
/// Порядок: `default`, встроенные типы в порядке [builtins], затем файлы по
/// имени. Встроенный тип заменён определением того же имени с областью
/// `subagent` или `both`; при выключенных субагентах встроенные типы остаются
/// со статусом `subagentsOff` (Q12 (а)) — замена в этом случае не важна, тип
/// всё равно не доступен. Строки отклонённых файлов строятся по диагностике:
/// одна строка на путь, приоритет `duplicate`, затем `modelNotConfigured`,
/// затем `error`; `shadowed` (info) относится к файлу, заменённому проектным.
/// Диагностика без файла (`untrusted_project` и прочие `info`) строк не даёт.
List<AgentDefinitionRowView> agentDefinitionRowsOf({
  required List<AgentDefinition> definitions,
  required List<ExtensionDiagnostic> diagnostics,
  required List<AgentDefinition> builtins,
  required bool subagentsEnabled,
}) {
  final rows = <AgentDefinitionRowView>[
    const AgentDefinitionRowView(
      name: 'default',
      availableIn: AgentRowScope.session,
      status: AgentRowStatus.available,
    ),
  ];

  for (final builtin in builtins) {
    final replacement = definitions
        .where((d) => d.name == builtin.name && d.scope != AgentScope.session)
        .firstOrNull;
    rows.add(
      AgentDefinitionRowView(
        name: builtin.name,
        description: builtin.description,
        availableIn: AgentRowScope.subagent,
        tools: builtin.tools,
        status: !subagentsEnabled
            ? AgentRowStatus.subagentsOff
            : replacement != null
            ? AgentRowStatus.overridden
            : AgentRowStatus.available,
        overriddenBy: subagentsEnabled ? replacement?.source : null,
      ),
    );
  }

  final files = <AgentDefinitionRowView>[
    for (final definition in definitions)
      AgentDefinitionRowView(
        name: definition.name,
        description: definition.description,
        path: definition.source,
        availableIn: switch (definition.scope) {
          AgentScope.session => AgentRowScope.session,
          AgentScope.subagent => AgentRowScope.subagent,
          AgentScope.both => AgentRowScope.both,
        },
        tools: definition.tools,
        model: definition.model == null
            ? null
            : '${definition.model!.provider}/${definition.model!.id}',
        status: AgentRowStatus.available,
      ),
  ];

  final byPath = <String, List<ExtensionDiagnostic>>{};
  for (final item in diagnostics) {
    if (item.code == 'shadowed' ||
        item.code == 'duplicate' ||
        item.level == DiagnosticLevel.error) {
      byPath.putIfAbsent(item.path, () => []).add(item);
    }
  }
  for (final MapEntry(key: path, value: items) in byPath.entries) {
    final name = _fileName(path);
    final duplicate = items.any((d) => d.code == 'duplicate');
    final model = items.any(_isModelDiagnostic);
    final error = items
        .where((d) => d.level == DiagnosticLevel.error && d.code != 'duplicate')
        .firstOrNull;
    if (duplicate) {
      files.add(
        AgentDefinitionRowView(
          name: name,
          path: path,
          status: AgentRowStatus.duplicate,
        ),
      );
    } else if (model) {
      files.add(
        AgentDefinitionRowView(
          name: name,
          path: path,
          status: AgentRowStatus.modelNotConfigured,
        ),
      );
    } else if (error != null) {
      files.add(
        AgentDefinitionRowView(
          name: name,
          path: path,
          status: AgentRowStatus.error,
          errorLine: error.line,
          errorMessage: error.message,
        ),
      );
    } else {
      files.add(
        AgentDefinitionRowView(
          name: name,
          path: path,
          status: AgentRowStatus.shadowed,
        ),
      );
    }
  }

  files.sort((a, b) {
    final byName = a.name.compareTo(b.name);
    return byName != 0 ? byName : (a.path ?? '').compareTo(b.path ?? '');
  });
  return [...rows, ...files];
}

/// Диагностика о модели вне каталога.
///
/// Почему по тексту: разбор ядра отдаёт её кодом `invalid_value`, как и
/// прочие неверные поля, и отличает только фиксированным текстом — публичной
/// константой [agentDefinitionModelNotInCatalogMessage] (`parseAgentDefinitions`);
/// отдельного кода у ядра нет, спецификация `agent-definitions` не меняется
/// (D18 change `add-settings-agents-modes`).
bool _isModelDiagnostic(ExtensionDiagnostic d) =>
    d.level == DiagnosticLevel.error &&
    d.code == 'invalid_value' &&
    d.message == agentDefinitionModelNotInCatalogMessage;

String _fileName(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  return name.endsWith('.md') ? name.substring(0, name.length - 3) : name;
}
