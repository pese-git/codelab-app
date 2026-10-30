import '../host/host_profile.dart';
import '../mcp/mcp_connector.dart';
import '../mcp/mcp_tool_name.dart';
import '../permissions/modes.dart';
import '../project/project_context.dart';
import '../tools/truncate.dart';
import 'prompts.g.dart';
import 'template.dart';

/// Входы сборки системного промпта этапа 2 (`agent-core-architecture`
/// §11.5).
///
/// Почему отдельный тип: промпт зависит только от этих значений, и
/// одинаковые входы обязаны давать побайтово одинаковый текст (PR-3) —
/// иначе кеш промптов провайдера промахивается на каждом шаге.
///
/// Как использовать: сессия собирает значение при создании и при смене
/// режима. [profile] — уже суженный профиль: секции выключенных capability в
/// промпт не входят (HOST-4). [toolNames] — итоговый набор инструментов
/// сессии. [mcpServers] и [projectContext] входят в промпт секциями `mcp` и
/// `project_context`; [agentProfile] — секцией `agent_profile` (шаг 10b);
/// переопределения добавят этапы после MVP.
final class PromptInputs {
  PromptInputs({
    required this.cwd,
    required this.platform,
    required this.today,
    required this.mode,
    required this.profile,
    required Set<String> toolNames,
    List<McpServerSummary> mcpServers = const [],
    this.projectContext,
    this.agentProfile,
  }) : toolNames = Set.unmodifiable(toolNames),
       mcpServers = List.unmodifiable(mcpServers);

  final String cwd;

  /// Платформа хоста (`linux`, `macos`, `web`…): ядро не читает `dart:io`.
  final String platform;

  /// Дата по часам хоста; в промпт входит только `yyyy-MM-dd`.
  final DateTime today;
  final ModeId mode;
  final HostProfile profile;
  final Set<String> toolNames;

  /// Подключённые MCP-серверы сессии и число их включённых инструментов
  /// (`McpSessionTools.servers`, §10.3); в секцию `mcp` входят серверы с
  /// хотя бы одним инструментом (PR-6; design.md change
  /// `add-agent-mcp-client`, D12).
  final List<McpServerSummary> mcpServers;

  /// Инструкции проекта, собранные `assembleProjectContext` (design.md change
  /// `add-agent-project-files`, D5); `null` или пустой список — секции
  /// `project_context` нет, промпт побайтово прежний (PR-3).
  final ProjectContext? projectContext;

  /// Выбранный агент сессии: имя и тело определения (design.md change
  /// `add-agent-project-files`, D11); `null` — агент `default`, секции нет и
  /// промпт побайтово прежний (PR-3). Тело вставляется как значение и шаблоном
  /// не обрабатывается (§11.4).
  final ({String name, String body})? agentProfile;
}

/// Лимит записей `ls` для секции `tools/listing`.
const _lsLimit = 500;

/// Таймаут `exec` по умолчанию, секунды (§6.4).
const _defaultExecTimeout = 120;

/// Отрендеренные секции промпта в фиксированном порядке §11.5: `(id, текст)`.
List<(String, String)> _sections(PromptInputs inputs) {
  bool on(PromptTemplate t) => inputs.toolNames.containsAll(t.tools);
  final listing = inputs.profile.isOn(HostCapability.fileListing);
  final shell = inputs.profile.isOn(HostCapability.shellExec);
  final maxLines = '$defaultMaxLines';
  final maxKb = '${defaultMaxBytes ~/ 1024}';
  final servers = [
    for (final s in inputs.mcpServers)
      if (s.toolCount > 0) s,
  ];
  return [
    (
      Prompts.systemBase.id,
      Prompts.systemBase.render({
        'cwd': inputs.cwd,
        'date': _date(inputs.today),
        'platform': inputs.platform,
        'modeName': inputs.mode.value,
      }),
    ),
    (Prompts.systemUntrusted.id, Prompts.systemUntrusted.render({})),
    if (inputs.mode == ModeId.plan)
      (Prompts.modesPlan.id, Prompts.modesPlan.render({})),
    if (on(Prompts.toolsRead))
      (
        Prompts.toolsRead.id,
        Prompts.toolsRead.render({'maxLines': maxLines, 'maxKb': maxKb}),
      ),
    if (on(Prompts.toolsEdit))
      (Prompts.toolsEdit.id, Prompts.toolsEdit.render({})),
    if (listing && on(Prompts.toolsListing))
      (
        Prompts.toolsListing.id,
        Prompts.toolsListing.render({'limit': '$_lsLimit'}),
      ),
    if (shell && on(Prompts.toolsExec))
      (
        Prompts.toolsExec.id,
        Prompts.toolsExec.render({
          'maxLines': maxLines,
          'defaultTimeout': '$_defaultExecTimeout',
        }),
      ),
    if (on(Prompts.toolsPlan))
      (Prompts.toolsPlan.id, Prompts.toolsPlan.render({})),
    // Шаг 9 §11.5: секция `mcp` только при включённой capability и хотя бы
    // одном сервере с инструментами, строки — в порядке регистрации.
    if (inputs.profile.isOn(HostCapability.mcp) && servers.isNotEmpty)
      (
        Prompts.mcp.id,
        Prompts.mcp.render({
          'servers': [
            for (final server in servers)
              '- ${server.name}: ${server.toolCount} tools, '
                  'prefix ${mcpServerPrefix(server.name)}',
          ].join('\n'),
        }),
      ),
    // Шаг 10 §11.5: инструкции проекта идут последними среди секций этапа:
    // они уточняют общие правила базы, а не наоборот (D5).
    if (inputs.projectContext case final context? when context.files.isNotEmpty)
      (
        Prompts.projectContext.id,
        Prompts.projectContext.render({
          'files': [
            for (final file in context.files)
              Prompts.projectContextFile.render({
                'path': _attributeSafe(file.path),
                'content': _escapeClosingTag(file.text),
              }),
          ].join('\n\n'),
        }),
      ),
    // Шаг 10b §11.5: профиль агента идёт последним. База, правило ограды и
    // секции инструментов остаются выше и не заменяются телом файла (CFG-8).
    // Края тела обрезаются, чтобы пробелы файла не меняли границы секций.
    if (inputs.agentProfile case final profile?)
      (
        Prompts.agentProfile.id,
        Prompts.agentProfile.render({
          'name': profile.name,
          'body': profile.body.trim(),
        }),
      ),
  ];
}

/// Системный промпт сессии: секции §11.5 через пустую строку и один `\n` в
/// конце.
String composeSystemPrompt(PromptInputs inputs) =>
    '${[for (final (_, text) in _sections(inputs)) text].join('\n\n')}\n';

/// Id секций, вошедших в промпт, в порядке сборки — для
/// `CorePlan.promptSections` и диагностики.
List<String> systemPromptSections(PromptInputs inputs) => [
  for (final (id, _) in _sections(inputs)) id,
];

/// Любой открывающий или закрывающий тег блока файла в тексте файла:
/// без учёта регистра и с пробелами внутри (`< / Project-Instructions`).
/// Так файл не закроет свой блок и не откроет чужой, выдав продолжение за
/// текст агента (D5; приоритет 1). Собственные теги шаблона в совпадение не
/// попадают: экранируется только содержимое файла до подстановки.
final _blockTag = RegExp(
  r'<\s*/?\s*project-instructions',
  caseSensitive: false,
);

/// Экранирование на рендере, а не при сборке: это последний рубеж перед
/// промптом, и он действует для любого [ProjectContext], в том числе
/// собранного хостом вручную. Между `<` и остальным вставляется `\`:
/// `</project-instructions` превращается в `<\/project-instructions`, и
/// разбор тега ломается при любом написании.
String _escapeClosingTag(String text) =>
    text.replaceAllMapped(_blockTag, (m) => '<\\${m[0]!.substring(1)}');

/// Значение атрибута `path`: путь приходит из дерева репозитория, и символы
/// разметки в нём не должны выводить текст за кавычки атрибута.
String _attributeSafe(String path) =>
    path.replaceAll(RegExp(r'["<>\r\n]'), '_');

String _date(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';
