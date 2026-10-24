import 'dart:async';

import '../loop/agent_events.dart';

/// Доставка нового плана подписчикам сессии; ждётся до `ToolCallFinished`.
typedef PlanPublisher = FutureOr<void> Function(List<PlanEntry> entries);

/// План сессии (`agent-core-architecture` §6.4, `update_plan`; design.md,
/// D5).
///
/// Почему: план живёт дольше одного вызова инструмента — его показывает
/// клиент (ACP `plan`), а с этапа 3 он пишется в журнал. Инструменту нужен
/// сервис сессии, а не локальное состояние.
///
/// Для чего: хранит текущий план и публикует `PlanUpdated` через общую
/// очередь событий сессии, чтобы событие пришло между `ToolCallStarted` и
/// `ToolCallFinished` своего вызова.
///
/// Как использовать: сессия создаёт сервис, кладёт его в
/// `ToolServices.plan` и задаёт [publish] (эмит `PlanUpdated` в очередь
/// `Agent`). `update_plan` вызывает [replace] и ждёт его.
final class PlanService {
  PlanService({this.publish});

  /// `null` — план хранится, но никому не публикуется (тест без событий).
  PlanPublisher? publish;

  var _entries = const <PlanEntry>[];

  List<PlanEntry> get entries => _entries;

  /// Заменяет план целиком, как требует ACP `plan`.
  Future<void> replace(List<PlanEntry> entries) async {
    _entries = List.unmodifiable(entries);
    await publish?.call(_entries);
  }
}
