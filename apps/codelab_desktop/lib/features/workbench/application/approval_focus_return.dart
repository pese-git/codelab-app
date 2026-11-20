/// Куда вернуть клавиатурный фокус после ухода полосы одобрения.
///
/// [composer] — в поле композера активной сессии, [workbench] — на рабочее
/// место, [none] — ничего не делать.
enum ApprovalFocusReturn { composer, workbench, none }

/// Выбор цели возврата фокуса после ухода полосы одобрения с фокусом.
///
/// Почему отдельной чистой функцией: правило безопасно проверять без дерева
/// виджетов, а в `build` и в обработчиках логики быть не должно (AGENTS.md
/// §12, `fix-approval-focus`, D5). Полоса не возвращает фокус сама: после её
/// ухода Flutter отдаёт его ближайшей области или никому, и пользователь
/// остаётся без места на клавиатуре.
///
/// Для чего: хост (`_CodeLabHomeState`) вызывает функцию в следующем кадре
/// после `onApprovalFocusReleased` и выполняет результат.
///
/// Как использовать: [focusTaken] — за время между уходом полосы и кадром
/// фокус перешёл на другой узел (пользователь кликнул в дерево Files, открыл
/// палитру): устаревший результат не должен отбирать фокус, тогда [none].
/// Иначе композер, если он есть ([hasComposer]) и включён ([composerEnabled]),
/// а при его отсутствии или выключенном состоянии — рабочее место.
ApprovalFocusReturn approvalFocusReturnOf({
  required bool hasComposer,
  required bool composerEnabled,
  required bool focusTaken,
}) {
  if (focusTaken) {
    return ApprovalFocusReturn.none;
  }
  return hasComposer && composerEnabled
      ? ApprovalFocusReturn.composer
      : ApprovalFocusReturn.workbench;
}
