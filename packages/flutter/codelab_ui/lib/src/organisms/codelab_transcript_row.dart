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

  /// Вызов ждёт решения пользователя.
  bool get awaitsApproval => approval is CodeLabTranscriptApprovalPending;

  /// Есть что показать под заголовком строки.
  bool get isExpandable =>
      approval != null || secondary != null || output.isNotEmpty;
}

/// Данные компактной строки вызова `agent`: итог справа и строка прогресса.
///
/// Почему: завершённый субагент в ленте — одна строка, где статус передаёт
/// глиф, а не тег «Done», и справа короткий итог (D24, D27, артборд 30;
/// spec agent-workbench-ui «Завершённый субагент свёрнут»).
///
/// Для чего: готовые строки от kit; виджет их не считает и не разбирает.
/// [stats] — сокращённый итог («4 tool calls · 18.2k · 48s») или счётчик
/// работающего; [progress] — последняя строка прогресса, пока вызов идёт и
/// дерева вызовов потомков нет (D27 п. 3).
///
/// Как использовать: передать в [CodeLabToolCallRow.subagent]; заголовок
/// «Subagent `type`: `description`» — в [CodeLabToolCallRow.label], отчёт — в
/// [CodeLabToolCallRow.output].
final class CodeLabSubagentCall {
  const CodeLabSubagentCall({this.stats, this.progress});

  final String? stats;
  final String? progress;

  @override
  bool operator ==(Object other) =>
      other is CodeLabSubagentCall &&
      other.stats == stats &&
      other.progress == progress;

  @override
  int get hashCode => Object.hash(stats, progress);
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
  }) = CodeLabTranscriptApprovalPending;

  const factory CodeLabTranscriptApproval.resolved({
    required String label,
    CodeLabApprovalOutcome outcome,
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
}

/// Решённое одобрение: [label] — выбранный вариант или «Cancelled».
final class CodeLabTranscriptApprovalResolved
    extends CodeLabTranscriptApproval {
  const CodeLabTranscriptApprovalResolved({
    required this.label,
    this.outcome = CodeLabApprovalOutcome.unknown,
  });

  final String label;
  final CodeLabApprovalOutcome outcome;
}
