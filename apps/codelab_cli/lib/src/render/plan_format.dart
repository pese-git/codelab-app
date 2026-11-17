import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';

import 'sanitize.dart';

/// Строка пункта плана для REPL и TUI.
///
/// Почему: план и список задач CodeLab приходят одним `plan`, а REPL, TUI и
/// блок над композером должны печатать пункт одинаково (spec codelab-cli
/// «Субагенты и список задач в REPL»; design.md change
/// `add-subagents-and-tasks`, D26).
///
/// Для чего: пункт с `taskId` — `#<id> [<status>] <subject>`, затем
/// ` (<метка владельца>)` и ` (blocked by #<id>, …)` для незавершённых
/// блокеров; пункт без `taskId` (план стороннего агента) — как прежде,
/// `[x]`, `[~]`, `[ ]` и текст. Текст из сессии очищается от управляющих
/// символов.
///
/// Как использовать: `planEntryText(entry)`; отступ строки добавляет вызывающий.
String planEntryText(PlanEntryView entry) {
  final subject = sanitizeTerminalText(entry.content);
  final id = entry.taskId;
  if (id == null) {
    return '${_mark(entry.status)} $subject';
  }
  final owner = entry.ownerLabel;
  return '#${sanitizeTerminalText(id)} [${_status(entry.status)}] $subject'
      '${owner == null ? '' : ' (${sanitizeTerminalText(owner)})'}'
      '${entry.openBlockers.isEmpty ? '' : ' (blocked by ${entry.openBlockers.map((b) => '#${sanitizeTerminalText(b)}').join(', ')})'}';
}

String _mark(PlanEntryStatus status) => switch (status) {
  PlanEntryStatus.completed => '[x]',
  PlanEntryStatus.inProgress => '[~]',
  PlanEntryStatus.pending => '[ ]',
};

String _status(PlanEntryStatus status) => switch (status) {
  PlanEntryStatus.completed => 'completed',
  PlanEntryStatus.inProgress => 'in_progress',
  PlanEntryStatus.pending => 'pending',
};
