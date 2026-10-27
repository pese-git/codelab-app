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

/// Ответ агента простым текстом. Change `add-transcript-markdown` заменит
/// его блоками markdown, не трогая остальные строки.
final class CodeLabAgentTextRow extends CodeLabTranscriptRow {
  const CodeLabAgentTextRow({required this.id, required this.text});

  @override
  final String id;
  final String text;
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
  });

  @override
  final String id;
  final CodeLabToolCallStatus status;
  final String label;
  final String detail;
  final String? secondary;
  final List<String> output;
  final CodeLabTranscriptApproval? approval;

  /// Вызов ждёт решения пользователя.
  bool get awaitsApproval => approval is CodeLabTranscriptApprovalPending;

  /// Есть что показать под заголовком строки.
  bool get isExpandable =>
      approval != null || secondary != null || output.isNotEmpty;
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
