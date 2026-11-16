import 'package:codelab_setup/codelab_setup.dart';

/// Результат загрузки определений агентов для страницы «Agents & modes»
/// (design.md change `add-settings-agents-modes`, D7, D11).
///
/// Почему отдельный тип, а не `AgentDefinitionRows` моста: тот живёт в
/// `codelab_setup/io.dart`, который сторож пускает только в `lib/app/`;
/// `features/` получает определения через этот тип, а адаптер в `lib/app/`
/// (`agentDefinitionRowsAt`) его строит (SETUP-9).
///
/// Для чего: строки моста, признаки диагностики и каталоги определений;
/// значений и тел файлов здесь нет.
final class AgentDefinitionsLoad {
  const AgentDefinitionsLoad({
    required this.rows,
    required this.userDirectory,
    required this.userDirectoryExists,
    this.projectTrusted = false,
    this.timedOut = false,
    this.projectDirectory,
    this.projectDirectoryExists = false,
  });

  /// Строки таблицы: `default`, встроенные типы, файлы.
  final List<AgentDefinitionRowView> rows;

  /// Папка проекта в `trusted_projects`. По умолчанию `false`: без явного
  /// признака проект считается недоверенным (fail-closed, D7, D19). Без папки
  /// проекта признак не используется.
  final bool projectTrusted;

  /// Загрузка не уложилась в тайм-аут (5 с).
  final bool timedOut;

  /// `$CODELAB_HOME/agents` и признак его наличия.
  final String userDirectory;
  final bool userDirectoryExists;

  /// `<project>/.codelab/agents` при любой известной папке проекта; `null` —
  /// папка проекта не известна. Недоверие отсекает Cubit: для недоверенного
  /// проекта путь не открывается и не показывается как доступный.
  final String? projectDirectory;
  final bool projectDirectoryExists;
}

/// Загрузчик определений: адаптер `agentDefinitionRowsAt` собирает
/// composition root (`lib/app/`).
///
/// [cancel] обрывает загрузку при новом «Reload» и закрытии страницы (D11).
typedef AgentDefinitionsLoader =
    Future<AgentDefinitionsLoad> Function({
      required AgentConfigSnapshot snapshot,
      required EditableSettings access,
      required Map<String, String> environment,
      CancelToken? cancel,
    });
