import 'terminal_owner.dart';
import 'terminal_tab.dart';

/// Состояние панели терминала для показанного владельца (D3).
///
/// Почему: панель показывает вкладки только активной сессии, а остальные
/// владельцы остаются в реестре Cubit (D5).
///
/// Для чего: [owner] `null` — активной сессии нет, панель показывает
/// подсказку без «New terminal» (Q17); [disclosureShown] — предупреждение
/// закрыто за жизнь Cubit (Q7).
final class TerminalTabsState {
  const TerminalTabsState({
    this.owner,
    this.tabs = const [],
    this.activeTabId,
    this.disclosureShown = false,
  });

  final TerminalOwner? owner;
  final List<TerminalTab> tabs;
  final String? activeTabId;
  final bool disclosureShown;

  bool get hasSession => owner != null;

  @override
  bool operator ==(Object other) =>
      other is TerminalTabsState &&
      other.owner == owner &&
      _sameTabs(other.tabs, tabs) &&
      other.activeTabId == activeTabId &&
      other.disclosureShown == disclosureShown;

  @override
  int get hashCode =>
      Object.hash(owner, Object.hashAll(tabs), activeTabId, disclosureShown);
}

// Свой `listEquals`: `package:flutter/` в application запрещён сторожем (D11).
bool _sameTabs(List<TerminalTab> a, List<TerminalTab> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
