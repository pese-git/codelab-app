import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../atomics/codelab_resize_handle.dart';

/// Класс раскладки рабочего места по ширине окна.
///
/// Почему: один и тот же каркас должен работать в широком окне десктопа, в
/// узком окне (D-21) и на планшете; решает только ширина окна, а не тип
/// устройства (`dart-agent-and-clients` §12.8.3, MOB-3).
///
/// Для чего: [CodeLabWorkbenchLayout] выбирает по классу, стоят ли сайдбар и
/// док колонками или выдвигаются поверх контента; app — показывать ли кнопку
/// меню сайдбара и сворачивать ли сайдбар в иконки.
///
/// Как использовать: `CodeLabLayoutClass.ofContext(context)` внутри дерева с
/// `MediaQuery`; [of] — для ширины, известной заранее (тесты, превью).
/// Класс [phone] пока раскладывается как [narrow]: отдельные экраны телефона —
/// этап 10.
enum CodeLabLayoutClass {
  /// Ширина окна меньше 641 px.
  phone,

  /// 641–899 px: сайдбар и док выдвигаются поверх ленты.
  narrow,

  /// 900–1279 px: сайдбар колонкой, док выдвигается поверх ленты.
  medium,

  /// От 1280 px: сайдбар и док колонками.
  wide;

  /// Нижняя граница [narrow] — порог режима `compact` у `NavigationView` WinUI.
  static const double narrowMinWidth = 641;

  /// Нижняя граница [medium] — порог D-21.
  static const double mediumMinWidth = 900;

  /// Нижняя граница [wide] — порог дока колонкой (A13, шаг 6b).
  static const double wideMinWidth = 1280;

  static CodeLabLayoutClass of(double windowWidth) {
    if (windowWidth >= wideMinWidth) {
      return wide;
    }
    if (windowWidth >= mediumMinWidth) {
      return medium;
    }
    if (windowWidth >= narrowMinWidth) {
      return narrow;
    }
    return phone;
  }

  static CodeLabLayoutClass ofContext(BuildContext context) =>
      of(MediaQuery.sizeOf(context).width);

  /// Сайдбар стоит колонкой рядом с панелью сессии.
  bool get sidebarAsColumn => this == wide || this == medium;

  /// Док стоит колонкой справа, а не выдвигается поверх ленты.
  bool get dockAsColumn => this == wide;
}

/// Каркас рабочего места: app bar, сайдбар сессий, панель сессии, док.
///
/// Почему: макет задаёт четыре зоны (`dart-agent-and-clients` §12.3 A13,
/// шаг 0), а их поведение по ширине — классы §12.8.3; прежние пороги 720/1100
/// и постоянная колонка инспектора с этим не совпадали (change
/// `redesign-workbench-shell`, D2).
///
/// Для чего: только раскладка зон по [CodeLabLayoutClass]; содержимое зон,
/// ширины и открытость выдвижных панелей передаёт хост.
///
/// Как использовать: хост передаёт виджеты зон и состояние из своего Cubit-а.
/// [dock] равен `null`, когда открытых панелей нет. В [CodeLabLayoutClass.wide]
/// док — колонка; в остальных классах он показывается поверх ленты, пока
/// [dockOverlayOpen]. Сайдбар в узких классах показывается поверх контента,
/// пока [sidebarOverlayOpen]. Клик мимо выдвинутой панели и Esc вызывают
/// [onSidebarOverlayDismiss] / [onDockOverlayDismiss]. Панель сессии остаётся
/// тем же элементом дерева при любом классе, поэтому лента и композер не
/// теряют прокрутку и черновик (MOB-3).
class CodeLabWorkbenchLayout extends StatelessWidget {
  const CodeLabWorkbenchLayout({
    required this.appBar,
    required this.sidebar,
    required this.sessionPane,
    this.dock,
    this.sidebarWidth = 280,
    this.compactSidebarWidth = 56,
    this.sidebarCollapsed = false,
    this.sidebarOverlayOpen = false,
    this.dockWidth = 360,
    this.dockOverlayOpen = false,
    this.gap = 12,
    this.padding = const EdgeInsets.all(16),
    this.onSidebarWidthChanged,
    this.onSidebarResizeEnd,
    this.onDockWidthChanged,
    this.onDockResizeEnd,
    this.onSidebarOverlayDismiss,
    this.onDockOverlayDismiss,
    super.key,
  });

  static const appBarKey = ValueKey('workbench-app-bar');
  static const sidebarKey = ValueKey('workbench-sidebar');
  static const sessionPaneKey = ValueKey('workbench-session-pane');
  static const dockKey = ValueKey('workbench-dock');

  /// Ключ ячейки панели сессии в строке зон: по нему элемент сохраняется при
  /// смене класса, даже когда соседние колонки появляются и исчезают.
  static const _sessionCellKey = ValueKey('workbench-session-cell');

  final Widget appBar;
  final Widget sidebar;
  final Widget sessionPane;
  final Widget? dock;

  final double sidebarWidth;

  /// Ширина свёрнутого сайдбара (только иконки), когда [sidebarCollapsed].
  final double compactSidebarWidth;
  final bool sidebarCollapsed;
  final bool sidebarOverlayOpen;
  final double dockWidth;
  final bool dockOverlayOpen;
  final double gap;
  final EdgeInsetsGeometry padding;

  /// Сдвиг ширины сайдбара при перетаскивании его границы; `null` — граница
  /// не перетаскивается.
  final ValueChanged<double>? onSidebarWidthChanged;
  final VoidCallback? onSidebarResizeEnd;

  /// Сдвиг ширины дока; знак уже развёрнут: положительный — док шире, хотя
  /// граница на его левом крае.
  final ValueChanged<double>? onDockWidthChanged;
  final VoidCallback? onDockResizeEnd;
  final VoidCallback? onSidebarOverlayDismiss;
  final VoidCallback? onDockOverlayDismiss;

  @override
  Widget build(BuildContext context) {
    final layoutClass = CodeLabLayoutClass.ofContext(context);
    final dock = this.dock;
    final collapsed = sidebarCollapsed && layoutClass.sidebarAsColumn;

    return ColoredBox(
      color: FluentTheme.of(context).micaBackgroundColor,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Slot(slotKey: appBarKey, label: 'App bar', child: appBar),
            SizedBox(height: gap),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  fit: StackFit.expand,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (layoutClass.sidebarAsColumn) ...[
                          SizedBox(
                            key: const ValueKey('workbench-sidebar-column'),
                            width: collapsed
                                ? compactSidebarWidth
                                : sidebarWidth,
                            child: _Slot(
                              slotKey: sidebarKey,
                              label: 'Sessions sidebar',
                              child: sidebar,
                            ),
                          ),
                          _divider(
                            key: const ValueKey('workbench-sidebar-divider'),
                            onWidthChanged: collapsed
                                ? null
                                : onSidebarWidthChanged,
                            onResizeEnd: onSidebarResizeEnd,
                          ),
                        ],
                        Expanded(
                          key: _sessionCellKey,
                          child: _Slot(
                            slotKey: sessionPaneKey,
                            label: 'Session pane',
                            child: sessionPane,
                          ),
                        ),
                        if (layoutClass.dockAsColumn && dock != null) ...[
                          _divider(
                            key: const ValueKey('workbench-dock-divider'),
                            onWidthChanged: onDockWidthChanged == null
                                ? null
                                : (dx) => onDockWidthChanged!(-dx),
                            onResizeEnd: onDockResizeEnd,
                          ),
                          SizedBox(
                            key: const ValueKey('workbench-dock-column'),
                            width: dockWidth,
                            child: _Slot(
                              slotKey: dockKey,
                              label: 'Tool dock',
                              child: dock,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (!layoutClass.sidebarAsColumn && sidebarOverlayOpen)
                      _Overlay(
                        alignment: AlignmentDirectional.centerStart,
                        width: sidebarWidth.clamp(
                          0,
                          constraints.maxWidth * 0.9,
                        ),
                        onDismiss: onSidebarOverlayDismiss,
                        child: _Slot(
                          slotKey: sidebarKey,
                          label: 'Sessions sidebar',
                          child: sidebar,
                        ),
                      ),
                    if (!layoutClass.dockAsColumn &&
                        dock != null &&
                        dockOverlayOpen)
                      _Overlay(
                        alignment: AlignmentDirectional.centerEnd,
                        width: dockWidth.clamp(0, constraints.maxWidth * 0.9),
                        onDismiss: onDockOverlayDismiss,
                        child: _Slot(
                          slotKey: dockKey,
                          label: 'Tool dock',
                          child: dock,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider({
    required Key key,
    required ValueChanged<double>? onWidthChanged,
    required VoidCallback? onResizeEnd,
  }) {
    if (onWidthChanged == null) {
      return SizedBox(key: key, width: gap);
    }
    return CodeLabResizeHandle(
      key: key,
      width: gap,
      onDelta: onWidthChanged,
      onDragEnd: onResizeEnd,
    );
  }
}

/// Выдвижная панель поверх контента с затемнением: клик мимо и Esc
/// закрывают её через [onDismiss].
class _Overlay extends StatelessWidget {
  const _Overlay({
    required this.alignment,
    required this.width,
    required this.onDismiss,
    required this.child,
  });

  final AlignmentGeometry alignment;
  final double width;
  final VoidCallback? onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return CallbackShortcuts(
      bindings: {
        if (onDismiss != null)
          const SingleActivator(LogicalKeyboardKey.escape): onDismiss!,
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              key: const ValueKey('workbench-overlay-scrim'),
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              child: ColoredBox(color: Colors.black.withAlpha(40)),
            ),
            Align(
              alignment: alignment,
              child: SizedBox(
                width: width,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.resources.solidBackgroundFillColorBase,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 16,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.slotKey,
    required this.label,
    required this.child,
  });

  final Key slotKey;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: slotKey,
      child: Semantics(container: true, label: label, child: child),
    );
  }
}
