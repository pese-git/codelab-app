import '../cancel/cancel_token.dart';
import '../env/execution_env.dart';
import '../llm/messages.dart';
import '../llm/stream_function.dart';
import '../loop/agent_events.dart';
import '../subagents/subagent_model.dart';
import '../util/canonical_json.dart';
import '../util/clock.dart';
import '../util/logger.dart';
import 'misuse.dart';
import 'tasks/task_list.dart';

/// Contract of a tool (`agent-core-architecture` §6.2): an object that
/// describes itself to the model and runs over [ExecutionEnv]. Built-in,
/// MCP and plugin tools share one registry and one execution point
/// (TOOL-1).

/// `exec` by default (TOOL-5); `network` — a model-chosen address (after
/// MVP).
enum ToolTier { read, write, network, exec }

enum ToolExecutionMode { parallel, sequential }

/// = ACP `ToolKind`.
enum ToolKind { read, edit, delete, move, search, execute, think, fetch, other }

enum ContentTrust { trusted, untrusted }

/// Контракт инструмента (`agent-core-architecture` §6.2).
///
/// Почему: встроенные, MCP- и плагинные инструменты должны проходить одну
/// точку исполнения — с валидацией, разрешениями, блокировкой пути,
/// усечением и оградой (TOOL-1). Поэтому инструмент только описывает себя и
/// исполняет действие, а всё общее делает `ToolExecutor`.
///
/// Как использовать: подкласс задаёт [name], [description], [parameters] и
/// [execute]; остальные члены имеют значения по умолчанию. Экземпляр
/// регистрируется в `ToolRegistry`; вызывать [execute] напрямую нельзя.
abstract base class AgentTool {
  String get name;
  String get description;

  /// JSON Schema объекта (подмножество §6.3.2).
  Map<String, Object?> get parameters;

  /// По умолчанию `exec` (TOOL-5): неизвестный инструмент считается самым
  /// опасным.
  ToolTier get tier => ToolTier.exec;
  ToolExecutionMode? get executionMode => null;
  ToolKind get kind => ToolKind.other;

  ContentTrust outputTrust(Map<String, Object?> args) => ContentTrust.untrusted;

  /// Заголовок, места и diff вызова для клиента и для запроса разрешения;
  /// может читать env из [ctx]. [args] бывают сырыми (до валидации), поэтому
  /// исключение здесь не ошибка: заголовком станет имя инструмента.
  Future<ToolPresentation> present(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async => ToolPresentation(title: name);

  /// Шаблон «разрешить всегда» (§7.5); по умолчанию — канонический JSON
  /// аргументов. [cwd] — корень сессии: пути шаблона относительны ему.
  String permissionPattern(Map<String, Object?> args, String cwd) =>
      canonicalJson(args);

  /// Проверка аргументов до разрешений: английский текст ошибки для модели
  /// или `null`. Без побочных эффектов (PERM-1).
  String? preflight(Map<String, Object?> args) => null;

  /// Путь, который точка исполнения держит под `PathLock` сессии на время
  /// [execute] (§6.3.4, TOOL-7); `null` — блокировка не нужна.
  ///
  /// Почему член контракта: блокировку берёт точка исполнения, а какой путь
  /// меняет вызов, знает только инструмент. [args] — сырые аргументы
  /// модели: место в очереди занимается ещё до валидации, в порядке ответа.
  /// Переопределяют `write` и `edit`.
  String? lockPath(Map<String, Object?> args) => null;

  /// Ключ очереди без пути: вызовы с одним ключом исполняются по одному, в
  /// порядке ответа модели (§6.3.4). Обобщение TOOL-7 на ключи — исследование
  /// D39-alt, §17.16a.4; принятый TOOL-7 относится только к путям
  /// ([lockPath]).
  ///
  /// Почему член контракта: у инструментов с общим состоянием не файлового
  /// рода (список задач сессии) нет пути для [lockPath], а исполнение внутри
  /// параллельного пакета иначе зависело бы от того, чей хук разрешений
  /// ответил раньше. Знает ключ только инструмент; [args] — сырые аргументы.
  ///
  /// Для чего: порядок ответа модели между вызовами одного ключа в
  /// параллельном пакете (id и операции применяются как в последовательном
  /// исполнении), при этом вызовы с другими ключами и без ключа идут
  /// одновременно.
  ///
  /// Как работает: место в очереди занимается в `announce`, захват — на
  /// шаге 6 после `beforeToolCall` (и после [lockPath]). Освобождение —
  /// сразу после шага 7 (`execute` вернул или бросил), ДО обработки
  /// результата и `afterToolCall`: медленный after-хук держателя не
  /// задерживает следующий вызов ключа. Досрочно ключ отпускает сам
  /// инструмент через `ToolContext.releaseLockKey`. Вызов, не дошедший до
  /// `execute` (отказ валидации, блок хука, отмена, `abandon`), отпускает
  /// место на своём пути завершения. Ключи не пересекаются с путями: у них
  /// отдельная очередь (путь отпускается в `complete`, TOOL-7). Переопределяют
  /// `task_*` и `agent` с пунктом списка.
  ///
  /// Хуки: `beforeToolCall` (и ACP `in_progress` из него) срабатывает до
  /// ожидания ключа, поэтому клиент видит `in_progress` у вызова, который
  /// ещё стоит в очереди; ожидание ключа диагностируется логом
  /// `tool.lock.wait` (с полем `key`).
  ///
  /// Отмена (D35 «Отмена»): вызов, прошедший `beforeToolCall` и проверку
  /// отмены, после захвата ключа отмену не проверяет — он исполняется даже
  /// при отмене хода; отмена до шага 6 по-прежнему даёт `cancelled`. Поэтому
  /// ключ — только для коротких атомарных операций над общим состоянием:
  /// под ним нельзя выполнять долгие операции и ждать субагента или другого
  /// держателя того же ключа (взаимная блокировка). Для путей действует
  /// [lockPath] с повторной проверкой отмены после захвата.
  String? lockKey(Map<String, Object?> args) => null;

  /// Инструмент усекает вывод сам, со своим уведомлением (§6.3.5); иначе
  /// точка исполнения усекает голову с общим уведомлением (TOOL-9).
  bool get truncatesOutput => false;

  ToolTier tierOf(Map<String, Object?> args) => tier;
  ToolKind kindOf(Map<String, Object?> args) => kind;
  ToolExecutionMode? executionModeOf(Map<String, Object?> args) =>
      executionMode;
  bool offersAllowAlways(Map<String, Object?> args) => true;

  /// Исполняет вызов с провалидированными и приведёнными [args] (TOOL-2);
  /// вызывается только единой точкой исполнения (TOOL-1).
  Future<ToolExecutionResult> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  );

  ToolSchema toSchema() =>
      ToolSchema(name: name, description: description, parameters: parameters);
}

/// Всё, что инструмент получает на один вызов, кроме аргументов.
///
/// Почему отдельный объект: сигнатура [AgentTool.execute] не должна
/// меняться, когда следующие этапы добавляют сервисы (§6.2).
///
/// Как использовать: создаёт только точка исполнения при объявлении вызова;
/// инструмент читает поля и не хранит контекст после вызова.
final class ToolContext {
  ToolContext({
    required this.env,
    required this.cancel,
    required this.onUpdate,
    required this.toolCallId,
    required this.services,
    List<String> stepTools = const [],
    this.misuse,
    this.supportsImages = false,
    this.onTerminal,
    void Function()? lockKeyRelease,
  }) : _lockKeyRelease = lockKeyRelease,
       stepTools = List.unmodifiable(stepTools);

  /// Всегда ограниченный env сессии (ENV-2).
  final ExecutionEnv env;
  final CancelToken cancel;

  /// Частичный результат для клиента (`ToolCallProgress`).
  final void Function(ToolExecutionResult partial) onUpdate;

  /// Терминал клиента, в котором идёт команда: точка исполнения отдаёт его
  /// клиенту `ToolCallProgress` с `ToolCallTerminal`, а ACP-проекция — блоком
  /// `{"type":"terminal"}` вызова (§13.7). `exec` передаёт его в
  /// `ExecOptions.onTerminal`; `null` — терминал никому не нужен.
  final void Function(String terminalId)? onTerminal;

  /// Заголовок, места и diff вызова, уже построенные `present()` для
  /// `ToolCallStarted`; ставит точка исполнения. Политика разрешений берёт
  /// их для запроса, а не зовёт `present()` второй раз: через ACP-клиента
  /// каждый вызов — лишний кадр `fs/read_text_file` (design.md change
  /// `add-dart-agent-acp-server`, D15). `null` — ещё не построены.
  ToolPresentation? presentation;
  final String toolCallId;
  final ToolServices services;

  /// Освобождает место вызова в очереди `AgentTool.lockKey`; передаёт точка
  /// исполнения при создании контекста. `null` — ключа нет. Поле приватное:
  /// инструмент не может его подменить, ему доступен только
  /// [releaseLockKey].
  final void Function()? _lockKeyRelease;

  /// Досрочно отпускает место в очереди ключа `AgentTool.lockKey`.
  ///
  /// Почему: под ключом нельзя ждать субагента (взаимная блокировка), а
  /// проверка и привязка к общему состоянию должны пройти под ним. Инструмент
  /// делает короткую часть под ключом, зовёт `releaseLockKey()` и только
  /// потом ждёт долгую (`agent{task}`, D39-alt, §17.16a.4).
  ///
  /// Идемпотентно; без ключа — no-op. Точка исполнения всё равно отпускает
  /// место сразу после `execute`. Путь `lockPath` этим НЕ отпускается.
  void releaseLockKey() => _lockKeyRelease?.call();

  /// Имена схем текущего шага: текст для модели упоминает только те
  /// инструменты, которые она может вызвать (§6.4).
  final List<String> stepTools;

  /// Предохранитель неверных вызовов хода (§6.3.7); один на ход, его
  /// создаёт цикл. `null` — выключен.
  final MisuseBreaker? misuse;

  /// Модель текущего шага принимает картинки (`ModelRef.supportsImages`):
  /// без этого `read` не отдаёт `ImageContent` (§6.4, шаг 2).
  final bool supportsImages;
}

/// Сервисы сессии для инструментов; следующие этапы добавляют поля
/// (`spill`, `jobs` — этап 3; после MVP — §17).
///
/// Как использовать: сессия создаёт один экземпляр и передаёт его точке
/// исполнения; все вызовы сессии видят одни и те же сервисы.
final class ToolServices {
  ToolServices({
    required this.clock,
    required this.logger,
    ApprovalWaitMeter? approvalWait,
    TaskList? tasks,
  }) : approvalWait = approvalWait ?? ApprovalWaitMeter(),
       tasks = tasks ?? SessionTaskList();

  final Clock clock;
  final Logger logger;

  /// Время ожидания человека: не входит во время хода (§5.2, design.md D6).
  final ApprovalWaitMeter approvalWait;

  /// Список задач дерева для `task_*` (`agent-core/17-16-task-list.md`
  /// §17.16.2; change `add-subagents-and-tasks`, D13). Сессия кладёт сюда
  /// `SessionTaskList` с публикацией `TaskListChanged`.
  final TaskList tasks;
}

/// Sum of the waits for `PermissionGate` in the current turn.
final class ApprovalWaitMeter {
  var _total = Duration.zero;

  Duration get total => _total;

  void add(Duration wait) => _total += wait;

  /// Called by the loop at the start of a turn.
  void reset() => _total = Duration.zero;
}

final class ToolExecutionResult {
  const ToolExecutionResult(
    this.content, {
    this.diffs = const [],
    this.isError = false,
  });

  /// [TextContent] and [ImageContent].
  final List<ContentBlock> content;

  /// One per changed file.
  final List<FileDiff> diffs;

  /// The tool reports an error without an exception.
  final bool isError;
}

final class ToolPresentation {
  const ToolPresentation({
    required this.title,
    this.locations = const [],
    this.diffs = const [],
    this.subagent,
  });

  /// Признак вызова `agent`: id и тип, зарезервированные до
  /// `ToolCallStarted` (design.md change `add-subagents-and-tasks`, D28).
  final SubagentCallRef? subagent;

  final String title;
  final List<Location> locations;
  final List<FileDiff> diffs;
}

final class Location {
  const Location(this.path, {this.line});

  /// Absolute path.
  final String path;
  final int? line;

  @override
  bool operator ==(Object other) =>
      other is Location && other.path == path && other.line == line;

  @override
  int get hashCode => Object.hash(path, line);

  @override
  String toString() => 'Location($path${line == null ? '' : ':$line'})';
}

final class FileDiff {
  const FileDiff({
    required this.path,
    required this.oldText,
    required this.newText,
  });

  /// Absolute path.
  final String path;

  /// `null` — a new file.
  final String? oldText;
  final String newText;

  @override
  bool operator ==(Object other) =>
      other is FileDiff &&
      other.path == path &&
      other.oldText == oldText &&
      other.newText == newText;

  @override
  int get hashCode => Object.hash(path, oldText, newText);

  @override
  String toString() => 'FileDiff($path)';
}

/// Content of a call update for the client (= ACP `ToolCallContent`).
sealed class ToolCallContent {
  const ToolCallContent();
}

final class ToolCallBlock extends ToolCallContent {
  const ToolCallBlock(this.block);

  final ContentBlock block;
}

final class ToolCallDiff extends ToolCallContent {
  const ToolCallDiff(this.diff);

  final FileDiff diff;
}

final class ToolCallTerminal extends ToolCallContent {
  const ToolCallTerminal(this.terminalId);

  final String terminalId;
}

/// Thrown by a tool that stopped on cancel and has its own text for the
/// model (`exec`: `[Command was cancelled after <t> s]`): outcome
/// `cancelled` with [content].
final class ToolCancelled implements Exception {
  const ToolCancelled(this.content);

  final List<ContentBlock> content;
}

final class ToolExecutionOutcome {
  ToolExecutionOutcome({
    required this.message,
    required this.outcome,
    List<FileDiff> diffs = const [],
  }) : diffs = List.unmodifiable(diffs);

  final ToolResultMessage message;
  final ToolOutcome outcome;
  final List<FileDiff> diffs;
}
