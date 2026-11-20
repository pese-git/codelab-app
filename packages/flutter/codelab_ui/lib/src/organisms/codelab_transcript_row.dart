import 'package:fluent_ui/fluent_ui.dart';

import '../molecules/molecules.dart';
import 'codelab_approval_prompt.dart';

/// Строка ленты переписки.
///
/// Почему: одна запись с полем «вид» на все случаи давала невозможные
/// сочетания — одобрение у заметки, «стрим» у сообщения пользователя — и
/// одну и ту же карточку для всего (design D1 change
/// `redesign-transcript-rows`; `dart-agent-and-clients` §12.3.2).
///
/// Для чего: неизменяемая презентационная модель ленты без зависимости от
/// ядра клиента (DSK-1); каждый наследник рисуется своим виджетом в
/// [CodeLabTranscriptPanel].
///
/// Как использовать: строки строит маппер приложения из транскрипта сессии;
/// [id] стабилен между ревизиями — по нему лента хранит ручное раскрытие
/// блоков и ключи виджетов.
sealed class CodeLabTranscriptRow {
  const CodeLabTranscriptRow();

  String get id;
}

/// Сообщение пользователя — пузырь справа.
final class CodeLabUserRow extends CodeLabTranscriptRow {
  const CodeLabUserRow({required this.id, required this.text});

  @override
  final String id;
  final String text;
}

/// Ответ агента: текст markdown, который рисует `CodeLabMarkdown`.
///
/// Почему: ответ — один `AgentTextItem`; разбор и кеш блоков внутри
/// `gpt_markdown` (design.md `add-desktop-markdown`, D1, D3), поэтому строка
/// одна на ответ, а не по блокам. Прежний `preformatted` убран: огороженный
/// ответ (`/mcp list`) теперь частный случай markdown (D11).
///
/// Для чего: [streaming] — ответ ещё стримится (последний элемент идущего
/// хода, как у мыслей); флаг вычисляет маппер app, виджет его не выводит.
/// [id] стабилен между ревизиями и входит в ключи `code-copy-<id>-<n>`.
final class CodeLabAgentTextRow extends CodeLabTranscriptRow {
  const CodeLabAgentTextRow({
    required this.id,
    required this.text,
    this.streaming = false,
  });

  @override
  final String id;
  final String text;
  final bool streaming;
}

/// Мысли модели: текст как есть, без markdown (§12.1.2, шаг 7).
///
/// [streaming] — мысли ещё идут: блок раскрыт и показывает «Thinking…»
/// (DSK-10). Флаг вычисляет маппер (design D4).
final class CodeLabThoughtRow extends CodeLabTranscriptRow {
  const CodeLabThoughtRow({
    required this.id,
    required this.text,
    this.streaming = false,
  });

  @override
  final String id;
  final String text;
  final bool streaming;
}

/// Вызов инструмента: одна строка «метка · деталь · статус» и раскрываемые
/// подробности (§12.1.6).
///
/// [label], [detail] и [secondary] — готовые строки из ядра клиента; лента
/// их не разбирает. [output] — текстовый вывод вызова. Пока [approval] —
/// ожидающее одобрение, строка всегда раскрыта и тег статуса — «Awaiting
/// approval», каким бы ни был [status].
final class CodeLabToolCallRow extends CodeLabTranscriptRow {
  const CodeLabToolCallRow({
    required this.id,
    required this.status,
    required this.label,
    this.detail = '',
    this.secondary,
    this.output = const [],
    this.approval,
    this.subagent,
    this.childApprovals = const [],
    this.children = const [],
    this.awaitsRootDecision = false,
  });

  @override
  final String id;
  final CodeLabToolCallStatus status;
  final String label;
  final String detail;
  final String? secondary;
  final List<String> output;
  final CodeLabTranscriptApproval? approval;

  /// Вызов `agent` в компактном виде (D27); `null` у остальных вызовов и у
  /// стороннего агента без признака субагента (D28).
  final CodeLabSubagentCall? subagent;

  /// Одобрения потомков под строкой `agent` корневого уровня: ожидающие и
  /// решённые в порядке прихода (D27 п. 4, D43 п. 2). Блок рисуется под
  /// строкой и не раскрывает её; свой [approval] строки при этом пуст.
  final List<CodeLabTranscriptApproval> childApprovals;

  /// Вложенные строки потомков в теле раскрытой строки `agent` (D24, D47
  /// Т11): вызовы и тихие строки операций, глубже — тем же списком. Id строк
  /// стабильны и уникальны, по ним лента хранит раскрытие; у остальных строк
  /// пусто.
  final List<CodeLabTranscriptRow> children;

  /// Вложенная строка ждёт решения пользователя, а панель решения стоит в
  /// блоке под строкой корня (D27 п. 4, D47 Т9): строка показывает только
  /// ожидание и сама кнопок не несёт — один запрос, одна панель.
  final bool awaitsRootDecision;

  /// Потомок под этой строкой ждёт решения: строка не крутит индикатор
  /// работы, решение принимается в блоке под ней.
  bool get awaitsChildApproval =>
      childApprovals.any((a) => a is CodeLabTranscriptApprovalPending);

  /// Вызов ждёт решения пользователя.
  bool get awaitsApproval => approval is CodeLabTranscriptApprovalPending;

  /// Есть что показать под заголовком строки.
  bool get isExpandable =>
      approval != null ||
      secondary != null ||
      output.isNotEmpty ||
      children.isNotEmpty;
}

/// Данные компактной строки вызова `agent`: итог справа и строка прогресса.
///
/// Почему: завершённый субагент в ленте — одна строка, где статус передаёт
/// глиф, а не тег «Done», и справа короткий итог (D24, D27, артборд 30;
/// spec agent-workbench-ui «Завершённый субагент свёрнут»).
///
/// Для чего: готовые строки от kit; виджет их не считает и не разбирает.
/// [stats] — сокращённый итог («4 tool calls · 18.2k · 48s») или счётчик
/// работающего без токенов («5 tool calls», Q15); [progress] — последняя
/// строка прогресса, пока вызов идёт и дерева вызовов потомков нет (D27
/// п. 3); [tail] и [tailMore] — хвост работающего при наличии дерева.
///
/// Как использовать: передать в [CodeLabToolCallRow.subagent]; заголовок
/// «Subagent `type`: `description`» — в [CodeLabToolCallRow.label], отчёт — в
/// [CodeLabToolCallRow.output].
final class CodeLabSubagentCall {
  const CodeLabSubagentCall({
    this.stats,
    this.progress,
    this.tail = const [],
    this.tailMore = 0,
  });

  final String? stats;
  final String? progress;

  /// «Хвост» работающего `agent` — три последних вызова поддерева, которые
  /// показываются под свёрнутой строкой вместо [progress] (D25, D47 Т9).
  /// Операция со списком задач — [CodeLabTaskOpsRow] (тихая строка, D48 п. 3).
  /// Хвост строится независимо от статуса вызова; после завершения его скрывает
  /// сама строка (показывается только у работающего), итог берётся из [stats].
  final List<CodeLabTranscriptRow> tail;

  /// Сколько вызовов поддерева не вошло в [tail] («+N more tool calls»).
  final int tailMore;

  @override
  bool operator ==(Object other) =>
      other is CodeLabSubagentCall &&
      other.stats == stats &&
      other.progress == progress &&
      other.tailMore == tailMore &&
      _sameTail(other.tail, tail);

  @override
  int get hashCode =>
      Object.hash(stats, progress, tailMore, Object.hashAll(tail.map(_key)));

  /// Значимые для отображения поля строки хвоста: у строк нет собственного
  /// `==`, поэтому сравниваем по ключу из id, статуса, меток и вида строки.
  static Object _key(CodeLabTranscriptRow row) => switch (row) {
    CodeLabToolCallRow() => ('call', row.id, row.status, row.label, row.detail),
    CodeLabTaskOpsRow() => ('ops', row.id, row.text),
    _ => ('other', row.id),
  };

  static bool _sameTail(
    List<CodeLabTranscriptRow> a,
    List<CodeLabTranscriptRow> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (_key(a[i]) != _key(b[i])) return false;
    }
    return true;
  }
}

/// Тихая строка операций со списком задач: иконка списка и короткий текст.
///
/// Почему: создание и закрытие задач — служебные шаги, а не работа, которую
/// стоит показывать рамкой с тегом «Done» (D27 change
/// `add-subagents-and-tasks`, артборд 30; spec agent-workbench-ui «Тихие
/// строки операций со списком задач»).
///
/// Для чего: [text] целиком собирает kit (`TaskOpsItem`, «Tasks #1–#4 added to
/// the plan»); виджет его не разбирает. Неуспешный вызов сюда не попадает —
/// он остаётся обычным [CodeLabToolCallRow].
final class CodeLabTaskOpsRow extends CodeLabTranscriptRow {
  const CodeLabTaskOpsRow({required this.id, required this.text});

  @override
  final String id;
  final String text;
}

/// Тяжесть заметки в ленте (design D6).
enum CodeLabNoticeSeverity { error, warning, info }

/// Заметка ленты: сбой хода, отсоединение сессии, новая сессия, пустой ход.
///
/// [error] и [warning] рисуются InfoBar, [info] — нейтральной строкой.
/// [details] — технический текст под свёрнутой раскрывашкой Details,
/// [action] — кнопка под заметкой (Retry).
final class CodeLabNoticeRow extends CodeLabTranscriptRow {
  const CodeLabNoticeRow({
    required this.id,
    required this.severity,
    required this.body,
    this.title,
    this.details,
    this.action,
  });

  @override
  final String id;
  final CodeLabNoticeSeverity severity;
  final String? title;
  final String body;
  final String? details;
  final CodeLabTranscriptAction? action;
}

/// Действие под строкой ленты — например, Retry у заметки о сбое хода.
///
/// Почему: заметка о сбое должна давать повторить ход в один клик (design D4
/// change `add-connection-and-error-states`), а лента не знает, что значит
/// действие. Для чего: подпись и обработчик, которые строит хост. Как
/// использовать: передать в [CodeLabNoticeRow.action]; `null` у [onPressed]
/// рисует кнопку недоступной.
class CodeLabTranscriptAction {
  const CodeLabTranscriptAction({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
}

/// Одобрение вызова инструмента, встроенное в его строку: ожидающее
/// (полоса решения) или решённое (тег исхода).
sealed class CodeLabTranscriptApproval {
  const CodeLabTranscriptApproval();

  /// Id цели показа блока в ленте (`approvalId`); `null` — блок не
  /// адресуется (D49 Т7).
  String? get targetId;

  const factory CodeLabTranscriptApproval.pending({
    required CodeLabApprovalRisk risk,
    required List<CodeLabApprovalOption> options,
    required CodeLabApprovalOptionSelected onOptionSelected,
    String? reason,
    String? command,
    String? diffSummary,
    String? rawInput,
    bool enabled,
    String? approveOptionId,
    String? rejectOptionId,
    bool shortcutsEnabled,
    String? requesterLine,
    String? requesterHint,
    String? callTitle,
    String? targetId,
    String? sessionId,
  }) = CodeLabTranscriptApprovalPending;

  const factory CodeLabTranscriptApproval.resolved({
    required String label,
    CodeLabApprovalOutcome outcome,
    String? requesterLine,
  }) = CodeLabTranscriptApprovalResolved;
}

/// Исход решённого одобрения, по которому выбирается тон тега в строке
/// вызова.
///
/// Почему: раньше решённое одобрение всегда получало зелёную галочку, и
/// отменённый запрос выглядел как «✓ Cancelled».
///
/// Для чего: тег различает разрешённый, отклонённый и отменённый вызов;
/// [unknown] — исход без известного вида варианта, показывается нейтрально.
///
/// Как использовать: app переводит в него исход из модели клиентского ядра и
/// передаёт в [CodeLabTranscriptApproval.resolved].
enum CodeLabApprovalOutcome { allowed, rejected, cancelled, unknown }

/// Ожидающее одобрение. Заголовка нет: вид действия уже назван меткой
/// строки вызова (change `lighten-approval-block`, D4). [command] — команда
/// целиком, как она выполнится: строка вызова показывает её в шапке вместо
/// обрезанной детали (D5).
final class CodeLabTranscriptApprovalPending extends CodeLabTranscriptApproval {
  const CodeLabTranscriptApprovalPending({
    required this.risk,
    required this.options,
    required this.onOptionSelected,
    this.reason,
    this.command,
    this.diffSummary,
    this.rawInput,
    this.enabled = true,
    this.approveOptionId,
    this.rejectOptionId,
    this.shortcutsEnabled = true,
    this.requesterLine,
    this.requesterHint,
    this.callTitle,
    this.targetId,
    this.sessionId,
  });

  final CodeLabApprovalRisk risk;
  final List<CodeLabApprovalOption> options;
  final CodeLabApprovalOptionSelected onOptionSelected;
  final String? reason;
  final String? command;
  final String? diffSummary;
  final String? rawInput;
  final bool enabled;
  final String? approveOptionId;
  final String? rejectOptionId;
  final bool shortcutsEnabled;

  /// Готовая строка «review › explore wants to run», когда спрашивает
  /// субагент; путь строит kit (D27 п. 4, D43 п. 4), виджет его не разбирает.
  final String? requesterLine;

  /// Заголовок задачи спрашивающего: подсказка пути и строка под ним.
  final String? requesterHint;

  /// Заголовок вызова запроса («Write .codelab/config.yaml»): у блока потомка
  /// под строкой `agent` корня своей строки вызова нет, и без заголовка не
  /// видно, какой инструмент и какой путь человек разрешает (D43 п. 2).
  final String? callTitle;

  /// Id цели показа блока в ленте (`approvalId`): app ставит его любому
  /// ожидающему одобрению (в том числе одобрению запуска субагента), и по
  /// нему «Go to approval» панели Agents прокручивает ленту именно к этому
  /// блоку (`CodeLabTranscriptPanel.targetKey`, D49 Т7). `null` — блок не
  /// адресуется.
  @override
  final String? targetId;

  /// Сессия запроса: вместе с [targetId] даёт ключ полосы
  /// (`CodeLabApprovalPrompt.keyFor`); id запросов уникальны только в
  /// соединении (change `fix-approval-focus`, D4, п. 4). `null` — ключа нет.
  final String? sessionId;
}

/// Решённое одобрение: [label] — выбранный вариант или «Cancelled».
final class CodeLabTranscriptApprovalResolved
    extends CodeLabTranscriptApproval {
  const CodeLabTranscriptApprovalResolved({
    required this.label,
    this.outcome = CodeLabApprovalOutcome.unknown,
    this.requesterLine,
  });

  final String label;
  final CodeLabApprovalOutcome outcome;

  /// Строка пути спрашивавшего субагента для тега исхода под строкой корня.
  final String? requesterLine;

  /// Решённый тег исхода не адресуется: «Go to approval» ведёт только к
  /// ожидающему блоку.
  @override
  String? get targetId => null;
}
