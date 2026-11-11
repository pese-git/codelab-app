import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

/// Данные одной вкладки терминала для [CodeLabTerminalPane].
///
/// Почему: что показывать и в каком статусе вкладка, решает app (маппер
/// статуса), а не кит (`add-integrated-terminal`, D3).
///
/// Для чего: готовые строки и тон тега статуса; никакой логики.
///
/// Как использовать: app строит по одному объекту на вкладку из состояния
/// Cubit; [id] попадает в ключи `terminal-tab-<id>` и колбэки.
class CodeLabTerminalTab {
  const CodeLabTerminalTab({
    required this.id,
    required this.title,
    required this.statusLabel,
    this.statusTone = CodeLabTone.neutral,
  });

  final String id;
  final String title;

  /// Подпись тега статуса («Running», «Exited 3», …).
  final String statusLabel;
  final CodeLabTone statusTone;
}

/// Панель Terminal дока инструментов: вкладки, «+», предупреждение и слот
/// для виджета терминала.
///
/// Почему: панель должна жить в ките рядом с остальными организмами дока, но
/// кит не зависит от пакета рендера терминала и не знает про процессы
/// (`codelab_ui/AGENTS.md` §1–§2; `add-integrated-terminal`, D3).
///
/// Для чего: строка вкладок (заголовок, тег статуса, крестик), кнопка новой
/// вкладки, пустое состояние, место под предупреждение (`InfoBar`) и слот
/// [content] с терминалом активной вкладки.
///
/// Как использовать: хост передаёт [tabs] и [activeTabId] из состояния.
/// [hasSession] == false — только подсказка «Open a session to use the
/// terminal» без «New terminal» и без `terminal-new-tab` (Q17). [tabs] пусто
/// при [hasSession] — пустое состояние с «New terminal». [disclosure] —
/// текст предупреждения, `null` скрывает его; [onDisclosureClosed] зовётся
/// по крестику. Ключи — статические, как у `CodeLabToolDock.paneKey`.
class CodeLabTerminalPane extends StatelessWidget {
  const CodeLabTerminalPane({
    required this.tabs,
    required this.activeTabId,
    required this.hasSession,
    required this.content,
    this.disclosure,
    this.onSelected,
    this.onClosed,
    this.onNewTab,
    this.onDisclosureClosed,
    super.key,
  });

  static ValueKey<String> tabKey(String id) => ValueKey('terminal-tab-$id');

  static ValueKey<String> closeKey(String id) =>
      ValueKey('terminal-tab-close-$id');

  static const ValueKey<String> newTabKey = ValueKey('terminal-new-tab');

  static const ValueKey<String> disclosureKey = ValueKey('terminal-disclosure');

  final List<CodeLabTerminalTab> tabs;
  final String? activeTabId;
  final bool hasSession;

  /// Виджет терминала активной вкладки; строит app.
  final Widget content;
  final String? disclosure;
  final ValueChanged<String>? onSelected;
  final ValueChanged<String>? onClosed;
  final VoidCallback? onNewTab;
  final VoidCallback? onDisclosureClosed;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final text = disclosure;
    final Widget body;
    if (!hasSession) {
      body = const _Empty(
        child: CodeLabText(
          'Open a session to use the terminal',
          role: CodeLabTextRole.body,
        ),
      );
    } else if (tabs.isEmpty) {
      body = _Empty(
        child: Button(onPressed: onNewTab, child: const Text('New terminal')),
      );
    } else {
      body = content;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasSession)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final tab in tabs)
                          _TabButton(
                            tab: tab,
                            selected: tab.id == activeTabId,
                            onSelected: onSelected,
                            onClosed: onClosed,
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  key: newTabKey,
                  icon: const Icon(FluentIcons.add, size: 12),
                  onPressed: onNewTab,
                ),
              ],
            ),
          ),
        if (hasSession)
          Container(height: 1, color: theme.resources.cardStrokeColorDefault),
        if (text != null)
          InfoBar(
            key: disclosureKey,
            title: Text(text),
            severity: InfoBarSeverity.info,
            onClose: onDisclosureClosed,
          ),
        Expanded(child: body),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(child: child);
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.selected,
    required this.onSelected,
    required this.onClosed,
  });

  final CodeLabTerminalTab tab;
  final bool selected;
  final ValueChanged<String>? onSelected;
  final ValueChanged<String>? onClosed;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: HoverButton(
        key: CodeLabTerminalPane.tabKey(tab.id),
        onPressed: onSelected == null ? null : () => onSelected!(tab.id),
        builder: (context, states) => DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? theme.resources.subtleFillColorSecondary
                : states.isHovered
                ? theme.resources.subtleFillColorTertiary
                : null,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            border: selected
                ? Border(bottom: BorderSide(color: theme.accentColor, width: 2))
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CodeLabText(
                  tab.title,
                  role: selected
                      ? CodeLabTextRole.strong
                      : CodeLabTextRole.body,
                ),
                const SizedBox(width: 6),
                CodeLabBadge(label: tab.statusLabel, tone: tab.statusTone),
                const SizedBox(width: 4),
                IconButton(
                  key: CodeLabTerminalPane.closeKey(tab.id),
                  icon: const Icon(FluentIcons.chrome_close, size: 8),
                  onPressed: onClosed == null ? null : () => onClosed!(tab.id),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
