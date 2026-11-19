import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_ui/codelab_ui.dart';

import 'agents_pane_data.dart';

/// Цель сочетания «Go to approval» (Cmd/Ctrl+Shift+A): ожидающее одобрение,
/// к которому нужно прокрутить ленту и поставить фокус.
///
/// ЗАГЛУШКА задачи 2.3 change `fix-approval-focus` (D4, п. 1): сигнатура есть,
/// поведения нет — функция всегда возвращает `null`. Реализацию добавляет
/// задача 2.4: самое раннее ожидающее одобрение активной сессии (признак
/// `focused` модели), для субагента — строка `agent` корня; без соединения
/// `Connected` и у `detached`-сессии цели нет.
AgentsShowTarget? goToApprovalTargetOf({
  required CodeLabConnectionStatus connectionStatus,
  required SessionView? view,
  required List<CodeLabTranscriptRow> rows,
}) => null;
