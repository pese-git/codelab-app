import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_ui/codelab_ui.dart';

import 'agents_pane_data.dart';

/// Цель сочетания «Go to approval» (Cmd/Ctrl+Shift+A): ожидающее одобрение,
/// к которому нужно прокрутить ленту и поставить клавиатурный фокус.
///
/// Почему в application: какое одобрение «активное», решает модель клиентского
/// ядра (признак `focused` — самое раннее по `requestedAt` ожидающее одобрение
/// хода), а не виджет и не порядок списка (`fix-approval-focus`, D4, п. 1;
/// AGENTS.md §7, §10). Признак модели не означает клавиатурного фокуса.
///
/// Для чего: `CodeLabShellCubit.goToApproval` вызывает функцию в момент
/// нажатия и, если цель есть, просит ленту показать её с фокусом. Функция
/// ответа на запрос разрешения не формирует.
///
/// Как использовать: [view] — `SessionView` активной сессии, [rows] — строки её
/// ленты. Цели нет (`null`), если ожидающего одобрения нет, соединение не
/// `Connected` или сессия `detached`: ответить на такой запрос некому. Для
/// одобрения субагента цель — строка `agent` корня (`rowId`) с блоком под ней
/// (`targetId` — id запроса); `expand` пуст, строка не раскрывается.
AgentsShowTarget? goToApprovalTargetOf({
  required CodeLabConnectionStatus connectionStatus,
  required SessionView? view,
  required List<CodeLabTranscriptRow> rows,
}) {
  if (connectionStatus != CodeLabConnectionStatus.connected ||
      view == null ||
      view.status == SessionStatusView.detached) {
    return null;
  }
  for (final approval in view.pendingApprovals) {
    if (approval.focused) {
      return AgentsPaneData.approvalTargetById(approval.approvalId.value, rows);
    }
  }
  return null;
}
