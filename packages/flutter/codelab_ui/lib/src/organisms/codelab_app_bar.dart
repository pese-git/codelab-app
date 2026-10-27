import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';

/// App bar рабочего места: название, поиск палитры, переключатели панелей,
/// бейдж соединения.
///
/// Почему: прежняя шапка показывала путь к бинарю агента и кнопку Connect
/// при активном соединении; макет (артборд Main, A13 шаг 0) ставит сюда
/// вход в палитру, переключатели дока и компактный бейдж соединения
/// (change `redesign-workbench-shell`, D6).
///
/// Для чего: организм без логики; что открыть, что переключить и как
/// переподключиться, решает хост через колбэки.
///
/// Как использовать: [onSearch] открывает палитру — поле только выглядит как
/// ввод, второго поиска нет. [paneToggles] — переключатели доступных панелей;
/// нажатие вызывает [onPaneToggled]. [onMenu] показывает кнопку меню
/// сайдбара — хост передаёт её в узких классах раскладки. [onRetry] нужен,
/// пока соединение `lost` или `failed`; [onConnect] — пока его нет.
class CodeLabAppBar extends StatelessWidget {
  const CodeLabAppBar({
    required this.title,
    required this.connectionStatus,
    this.searchShortcutLabel = 'Ctrl+K',
    this.onSearch,
    this.paneToggles = const [],
    this.onPaneToggled,
    this.connectionTooltip,
    this.onRetry,
    this.onConnect,
    this.onMenu,
    super.key,
  });

  static const searchKey = ValueKey('app-bar-search');
  static const menuKey = ValueKey('app-bar-menu');
  static const connectionBadgeKey = ValueKey('connection-badge');
  static const connectionRetryKey = ValueKey('connection-badge-retry');
  static const connectionConnectKey = ValueKey('connection-badge-connect');

  /// Ключ переключателя панели (A13, шаг 8).
  static ValueKey<String> toggleKey(ToolPane pane) =>
      ValueKey('tool-toggle-${pane.name}');

  final String title;
  final CodeLabConnectionStatus connectionStatus;
  final String searchShortcutLabel;
  final VoidCallback? onSearch;
  final List<CodeLabPaneToggle> paneToggles;
  final ValueChanged<ToolPane>? onPaneToggled;

  /// Профиль и транспорт — в подсказке бейджа, а не в шапке.
  final String? connectionTooltip;
  final VoidCallback? onRetry;
  final VoidCallback? onConnect;
  final VoidCallback? onMenu;

  /// Ширина бара, ниже которой переключатели панелей теряют подписи.
  static const compactWidth = 1000.0;

  /// Ширина бара, ниже которой поиск — иконка, а бейдж — точка статуса.
  static const minimalWidth = 600.0;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return SizedBox(
      height: 40,
      // Бар подстраивается под свою ширину, а не под класс окна: в узком
      // окне и при открытом сайдбаре места меньше по разным причинам, а
      // переполнения не должно быть ни в одном случае (MOB-3).
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < compactWidth;
          final minimal = constraints.maxWidth < minimalWidth;
          return Row(
            children: [
              if (onMenu != null) ...[
                IconButton(
                  key: menuKey,
                  icon: const Icon(FluentIcons.global_nav_button, size: 16),
                  onPressed: onMenu,
                ),
                const SizedBox(width: 4),
              ],
              CodeLabText(
                title,
                role: minimal ? CodeLabTextRole.strong : CodeLabTextRole.title,
              ),
              const SizedBox(width: 12),
              if (minimal)
                Tooltip(
                  message: 'Search or run a command ($searchShortcutLabel)',
                  child: IconButton(
                    key: searchKey,
                    icon: const Icon(FluentIcons.search, size: 14),
                    onPressed: onSearch,
                  ),
                )
              else
                Expanded(
                  child: Align(
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: _SearchField(
                        shortcutLabel: compact ? null : searchShortcutLabel,
                        onPressed: onSearch,
                      ),
                    ),
                  ),
                ),
              if (minimal) const Spacer(),
              const SizedBox(width: 12),
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final toggle in paneToggles) ...[
                        _PaneToggleButton(
                          toggle: toggle,
                          showLabel: !compact,
                          onPaneToggled: onPaneToggled,
                        ),
                        const SizedBox(width: 4),
                      ],
                      if (paneToggles.isNotEmpty) const SizedBox(width: 8),
                      _ConnectionBadge(
                        status: connectionStatus,
                        tooltip: connectionTooltip,
                        onRetry: onRetry,
                        onConnect: onConnect,
                        dotOnly: minimal,
                        background:
                            theme.resources.cardBackgroundFillColorDefault,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PaneToggleButton extends StatelessWidget {
  const _PaneToggleButton({
    required this.toggle,
    required this.showLabel,
    required this.onPaneToggled,
  });

  final CodeLabPaneToggle toggle;
  final bool showLabel;
  final ValueChanged<ToolPane>? onPaneToggled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: toggle.pane.label,
      child: ToggleButton(
        key: CodeLabAppBar.toggleKey(toggle.pane),
        checked: toggle.selected,
        onChanged: onPaneToggled == null
            ? null
            : (_) => onPaneToggled!(toggle.pane),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(toggle.pane.icon, size: 14),
            if (showLabel) ...[
              const SizedBox(width: 6),
              Text(toggle.pane.label),
            ],
          ],
        ),
      ),
    );
  }
}

/// Переключатель панели дока в app bar: [selected] — панель открыта и
/// активна.
class CodeLabPaneToggle {
  const CodeLabPaneToggle({required this.pane, this.selected = false});

  final ToolPane pane;
  final bool selected;
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.shortcutLabel, required this.onPressed});

  /// `null` — подсказка сочетания не помещается и не показывается.
  final String? shortcutLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Button(
      key: CodeLabAppBar.searchKey,
      onPressed: onPressed,
      child: Row(
        children: [
          const Expanded(
            child: CodeLabText(
              'Search or run a command',
              role: CodeLabTextRole.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (shortcutLabel case final label?) ...[
            const SizedBox(width: 8),
            CodeLabText(label, role: CodeLabTextRole.caption),
          ],
          const SizedBox(width: 6),
          const Icon(FluentIcons.search, size: 12),
        ],
      ),
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({
    required this.status,
    required this.tooltip,
    required this.onRetry,
    required this.onConnect,
    required this.background,
    this.dotOnly = false,
  });

  final CodeLabConnectionStatus status;
  final String? tooltip;
  final VoidCallback? onRetry;
  final VoidCallback? onConnect;
  final Color background;

  /// Только точка статуса, подпись — в подсказке (узкий бар).
  final bool dotOnly;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (status) {
      CodeLabConnectionStatus.connected => (
        'Connected',
        CodeLabStatusTone.active,
      ),
      CodeLabConnectionStatus.connecting => (
        'Connecting…',
        CodeLabStatusTone.warning,
      ),
      CodeLabConnectionStatus.reconnecting => (
        'Reconnecting…',
        CodeLabStatusTone.warning,
      ),
      CodeLabConnectionStatus.lost => (
        'Connection lost',
        CodeLabStatusTone.danger,
      ),
      CodeLabConnectionStatus.failed => (
        'Connection failed',
        CodeLabStatusTone.danger,
      ),
      CodeLabConnectionStatus.idle || CodeLabConnectionStatus.disconnected => (
        'Disconnected',
        CodeLabStatusTone.idle,
      ),
    };
    final busy =
        status == CodeLabConnectionStatus.connecting ||
        status == CodeLabConnectionStatus.reconnecting;
    final canRetry =
        status == CodeLabConnectionStatus.lost ||
        status == CodeLabConnectionStatus.failed;
    final canConnect =
        status == CodeLabConnectionStatus.disconnected ||
        status == CodeLabConnectionStatus.idle;

    final badge = DecoratedBox(
      key: CodeLabAppBar.connectionBadgeKey,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotOnly)
              CodeLabStatusIndicator(label: '', tone: tone)
            else if (busy) ...[
              const SizedBox.square(
                dimension: 12,
                child: ProgressRing(strokeWidth: 2),
              ),
              const SizedBox(width: 6),
              CodeLabText(label, role: CodeLabTextRole.caption),
            ] else
              CodeLabStatusIndicator(label: label, tone: tone),
          ],
        ),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: [label, if (tooltip != null) tooltip].join(' — '),
          child: badge,
        ),
        if (canRetry && onRetry != null) ...[
          const SizedBox(width: 6),
          Button(
            key: CodeLabAppBar.connectionRetryKey,
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
        if (canConnect && onConnect != null) ...[
          const SizedBox(width: 6),
          FilledButton(
            key: CodeLabAppBar.connectionConnectKey,
            onPressed: onConnect,
            child: const Text('Connect'),
          ),
        ],
      ],
    );
  }
}
