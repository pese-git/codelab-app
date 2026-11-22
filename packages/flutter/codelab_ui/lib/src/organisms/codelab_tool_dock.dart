import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../l10n/strings.dart';
import '../molecules/molecules.dart';

/// Действие вкладки дока: подпись и колбэк (например, `Pause`, `Clear`,
/// `Export…` у Protocol).
///
/// Почему описание, а не готовый виджет: узкому доку (360 px) не хватает
/// места для всех кнопок, и решать, какие из них уйдут в меню «⋯», может
/// только кит, который видит ширину (ручной смок change
/// `redesign-protocol-pane`, D12). Прокрутка строки действий отвергнута:
/// трекпад её находит, колесо мыши и клавиатура — нет.
///
/// Как использовать: [pinned] — действие всегда на виду (переключатель
/// режима, который должен быть заметен); остальные показываются в строке,
/// пока помещаются, а не поместившиеся — в меню «⋯» с теми же подписью и
/// доступностью. [checked] не `null` — переключатель (нажатое состояние
/// видно и передаётся скринридеру); [onPressed] `null` — действие
/// недоступно (в меню — отключённый пункт).
class CodeLabDockAction {
  const CodeLabDockAction({
    required this.label,
    this.onPressed,
    this.pinned = false,
    this.checked,
    this.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool pinned;
  final bool? checked;

  /// Ключ кнопки в строке (тесты хоста); в меню не используется.
  final Key? key;
}

/// Вкладка дока: панель и её содержимое.
///
/// [actions] — действия панели: док показывает их справа в строке вкладок,
/// только пока вкладка активна. Почему в доке, а не в теле панели: так
/// устроен макет, а поле нужно и будущим панелям Terminal и Diff (change
/// `redesign-protocol-pane`, D1, D12).
class CodeLabDockTab {
  const CodeLabDockTab({
    required this.pane,
    required this.content,
    this.actions,
  });

  final ToolPane pane;
  final Widget content;

  /// Действия активной вкладки; `null` или пусто — вид дока прежний.
  final List<CodeLabDockAction>? actions;
}

/// Док панелей инструментов справа от панели сессии.
///
/// Почему: бывшие колонки Inspector и Debug log и будущие Files, Terminal,
/// Diff должны жить в одном месте с вкладками, а не плодить колонки
/// (`dart-agent-and-clients` §12.3 A13, шаги 0 и 6; change
/// `redesign-workbench-shell`, D5).
///
/// Для чего: строка вкладок открытых панелей и содержимое активной; без
/// логики — какие панели открыты и какая активна, хранит хост.
///
/// Как использовать: хост передаёт [tabs] в порядке открытия и [active] из
/// своего состояния; [onSelected] делает вкладку активной, [onClosed]
/// закрывает панель. Без вкладок хост не показывает док вовсе. Содержимое
/// активной панели помечено ключом `tool-pane-<pane>` (A13, шаг 8).
class CodeLabToolDock extends StatefulWidget {
  const CodeLabToolDock({
    required this.tabs,
    required this.active,
    this.onSelected,
    this.onClosed,
    super.key,
  }) : assert(tabs.length > 0, 'the dock is shown only with open panes');

  /// Ключ содержимого панели (A13, шаг 8).
  static ValueKey<String> paneKey(ToolPane pane) =>
      ValueKey('tool-pane-${pane.name}');

  static ValueKey<String> tabKey(ToolPane pane) =>
      ValueKey('tool-tab-${pane.name}');

  static ValueKey<String> closeKey(ToolPane pane) =>
      ValueKey('tool-tab-close-${pane.name}');

  final List<CodeLabDockTab> tabs;
  final ToolPane active;
  final ValueChanged<ToolPane>? onSelected;
  final ValueChanged<ToolPane>? onClosed;

  /// Минимальная ширина зоны действий справа (закреплённое действие и «⋯»):
  /// вкладки получают остальное и прокручиваются, поэтому действия не
  /// вытесняют заголовок активной вкладки (ручной смок change `redesign-protocol-pane`, док 360 px).
  static const double minActionsWidth = 180;

  @override
  State<CodeLabToolDock> createState() => _CodeLabToolDockState();
}

class _CodeLabToolDockState extends State<CodeLabToolDock> {
  /// Ключ активной вкладки: по нему она прокручивается в видимую область.
  final _activeKey = GlobalKey();
  ToolPane? _revealed;

  List<CodeLabDockTab> get tabs => widget.tabs;
  ValueChanged<ToolPane>? get onSelected => widget.onSelected;
  ValueChanged<ToolPane>? get onClosed => widget.onClosed;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final active = widget.active;
    // Активная панель может пропасть из вкладок раньше, чем хост обновит
    // [active]; тогда показывается первая вкладка, а не пустой док.
    final shown = tabs.firstWhere(
      (tab) => tab.pane == active,
      orElse: () => tabs.first,
    );

    if (_revealed != shown.pane) {
      _revealed = shown.pane;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _activeKey.currentContext;
        if (mounted && context != null) {
          Scrollable.ensureVisible(context, alignment: 0);
        }
      });
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Вкладки идут слева и прокручиваются (не шире, чем ширина дока
          // минус [CodeLabToolDock.minActionsWidth]); действия активной
          // вкладки получают остаток и тоже прокручиваются. Активная вкладка
          // прокручивается в видимую область, поэтому её заголовок не
          // обрезается (док 360 px, русские подписи).
          LayoutBuilder(
            builder: (context, constraints) {
              final hasActions = shown.actions?.isNotEmpty ?? false;
              final tabsRow = SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                child: Row(
                  children: [
                    for (final tab in tabs)
                      tab.pane == shown.pane
                          ? KeyedSubtree(
                              key: _activeKey,
                              child: _DockTabButton(
                                pane: tab.pane,
                                selected: true,
                                onSelected: onSelected,
                                onClosed: onClosed,
                              ),
                            )
                          : _DockTabButton(
                              pane: tab.pane,
                              selected: false,
                              onSelected: onSelected,
                              onClosed: onClosed,
                            ),
                  ],
                ),
              );
              return Row(
                children: [
                  if (hasActions)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: math.max(
                          0,
                          constraints.maxWidth -
                              CodeLabToolDock.minActionsWidth,
                        ),
                      ),
                      child: tabsRow,
                    )
                  else
                    Expanded(child: tabsRow),
                  // Действия — только у активной вкладки (D1): закреплённые
                  // всегда на виду, остальные — в строке, пока помещаются,
                  // иначе в меню «⋯» (никакой прокрутки строки).
                  if (hasActions)
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _DockActions(actions: shown.actions!),
                      ),
                    ),
                ],
              );
            },
          ),
          Container(height: 1, color: theme.resources.cardStrokeColorDefault),
          Expanded(
            child: KeyedSubtree(
              key: CodeLabToolDock.paneKey(shown.pane),
              child: shown.content,
            ),
          ),
        ],
      ),
    );
  }
}

class _DockTabButton extends StatelessWidget {
  const _DockTabButton({
    required this.pane,
    required this.selected,
    required this.onSelected,
    required this.onClosed,
  });

  final ToolPane pane;
  final bool selected;
  final ValueChanged<ToolPane>? onSelected;
  final ValueChanged<ToolPane>? onClosed;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: HoverButton(
        key: CodeLabToolDock.tabKey(pane),
        onPressed: onSelected == null ? null : () => onSelected!(pane),
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
                Icon(pane.icon, size: 12),
                const SizedBox(width: 6),
                CodeLabText(
                  toolPaneTitleOf(context, pane),
                  role: selected
                      ? CodeLabTextRole.strong
                      : CodeLabTextRole.body,
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: CodeLabToolDock.closeKey(pane),
                  icon: const Icon(FluentIcons.chrome_close, size: 8),
                  onPressed: onClosed == null ? null : () => onClosed!(pane),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Строка действий активной вкладки: закреплённые кнопки и командная строка
/// Fluent с динамическим переносом в «⋯» для остальных.
class _DockActions extends StatelessWidget {
  const _DockActions({required this.actions});

  final List<CodeLabDockAction> actions;

  static const _compact = ButtonStyle(
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final strings = codeLabStringsOf(context);
    final pinned = [
      for (final a in actions)
        if (a.pinned) a,
    ];
    final rest = [
      for (final a in actions)
        if (!a.pinned) a,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          for (final action in pinned) _pinned(action),
          if (rest.isNotEmpty)
            Flexible(
              child: CommandBar(
                overflowBehavior: CommandBarOverflowBehavior.dynamicOverflow,
                mainAxisAlignment: MainAxisAlignment.end,
                primaryItems: [
                  for (final action in rest)
                    CommandBarButton(
                      key: action.key,
                      label: Text(action.label),
                      onPressed: action.onPressed,
                    ),
                ],
                overflowItemBuilder: (onPressed) => CommandBarButton(
                  icon: const Icon(FluentIcons.more),
                  tooltip: strings.codeLabDockMoreActions,
                  onPressed: onPressed,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pinned(CodeLabDockAction action) {
    final checked = action.checked;
    if (checked == null) {
      return Button(
        key: action.key,
        style: _compact,
        onPressed: action.onPressed,
        child: Text(action.label),
      );
    }
    // Родной стиль `ToggleButton`: у нажатой кнопки акцентный фон; свой
    // `style` стёр бы его. Состояние читает и скринридер (`toggled`).
    return Semantics(
      toggled: checked,
      container: true,
      child: ToggleButton(
        key: action.key,
        checked: checked,
        onChanged: action.onPressed == null ? null : (_) => action.onPressed!(),
        child: Text(action.label),
      ),
    );
  }
}
