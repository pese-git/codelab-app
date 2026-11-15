/// Строки панели Agents v1: проекция субагентов сессии (`SessionView.subagents`).
///
/// ВРЕМЕННАЯ ЗАГЛУШКА красных тестов 5b.1 (`[client]`): только публичный API
/// без логики, чтобы `test/session/session_subagents_test.dart` компилировался
/// и падал по существу. Реализация — задача 5b.2 (design.md change
/// `add-subagents-and-tasks`, D33, D49 Т2–Т6, D50; spec acp-client-kit
/// «Список субагентов сессии»).
library;

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';

import '../transcript/subagent_views.dart';

/// Состояние строки панели (D33): `running`, `awaitingApproval` — поверх
/// нетерминального, `completed`, `failed`, `cancelled` — по статусу вызова.
enum SubagentRowState {
  running,
  awaitingApproval,
  completed,
  failed,
  cancelled,
}

/// Строка панели Agents: один вызов `agent` с признаком `subagentCall`.
///
/// Почему: панель — навигация по уже показанным данным, и строки должен
/// считать kit, а не app (D33, `AGENTS.md` §8); поля — таблица D33.
///
/// Как использовать: читать из `SessionView.subagents`; хост только
/// отображает. Поля без данных — `null`/пусто, а не отказ (терпимый разбор).
final class SubagentRowView {
  const SubagentRowView({
    required this.toolCallId,
    required this.type,
    required this.title,
    required this.state,
    required this.depth,
    required this.path,
    this.subagentId,
    this.startedAt,
    this.summary,
    this.toolCalls,
    this.lastAction,
    this.taskIds = const [],
    this.approvalId,
  });

  /// Ключ строки — `toolCallId` вызова на проводе.
  final ToolCallId toolCallId;

  /// Id субагента; `null` — реплей отклонённого вызова (D36, Т15).
  final String? subagentId;

  /// Тип: `explore`, `review` и т. д.
  final String type;

  /// `rawInput.description`, а без него — `title` вызова как есть.
  final String title;

  final SubagentRowState state;

  /// 1 — вызов без родителя или с неизвестным родителем.
  final int depth;

  /// Id элементов транскрипта от строки верхнего уровня до этой строки
  /// (`TranscriptItem.id`, D49 Т2): по нему app раскрывает путь и
  /// прокручивает ленту.
  final List<String> path;

  /// Момент первого появления вызова по часам `ClientWorkspace` (D49 Т3);
  /// у терминальной строки может быть `null`.
  final DateTime? startedAt;

  /// Итог (D24): у терминальной строки; токены и длительность — только отсюда.
  final SubagentSummaryView? summary;

  /// Терминальная — `summary.toolCalls`; работающая — `subtreeCalls`;
  /// без дерева и без итога — `null`.
  final int? toolCalls;

  /// Работающая — `title` последнего вызова поддерева; `failed` — `failure`.
  final String? lastAction;

  /// Id пунктов плана: сначала `owner` = id субагента, затем `rawInput.task`,
  /// без повторов (D49 Т6).
  final List<String> taskIds;

  /// Ожидающее одобрение строки (D33, D50 п. 3); при нескольких — самое раннее.
  final ApprovalRequestId? approvalId;
}
