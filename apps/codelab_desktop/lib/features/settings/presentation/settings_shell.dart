import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../../app/navigation/settings_page.dart';
import '../application/settings_search_index.dart';

/// Тела страниц настроек.
///
/// Почему таблица, а не `switch` в оболочке: следующие страницы добавляются
/// записью в таблицу и в `SettingsPages.available`, а оболочка, навигация и
/// порядок не меняются (design.md change `add-app-settings-shell`, D3).
///
/// Как использовать: каждая страница из `SettingsPages.available` ДОЛЖНА
/// иметь запись (проверяет тест). В итерации 1 таблица пуста: страница
/// «Connection» появится в итерации 2.
final Map<SettingsPage, WidgetBuilder> settingsPageBuilders = Map.unmodifiable(
  const <SettingsPage, WidgetBuilder>{},
);

/// Ширина окна, меньше которой навигация настроек уходит наверх.
///
/// Порог взят из макета (`@media (max-width:760px)` артбордов `Connection` и
/// `General`) и относится только к экрану настроек (D3).
const settingsNarrowBreakpoint = 760.0;

/// Экран настроек: навигация по страницам и тело выбранной.
///
/// Почему: все страницы живут в одном `NavigationView` с поиском и двумя
/// группами (`dart-agent-and-clients` §12.4.9; spec app-settings «Навигация
/// настроек»).
///
/// Для чего: только отображение. Какая страница выбрана и как вернуться,
/// решает `NavigationCubit`; здесь — запрос поиска (временное состояние поля),
/// раскладка по ширине окна и привязка Esc к [onBack].
///
/// Как использовать: `CodeLabAppWidget` создаёт его по `SettingsDestination`
/// и передаёт [pages], [selected] и колбэки. [builders] подменяют тесты.
/// Видимые страницы берутся из [pages] в порядке `SettingsPage.values`;
/// страница без построителя показывает пустое тело, а не падает.
class SettingsShell extends StatefulWidget {
  const SettingsShell({
    required this.pages,
    required this.selected,
    required this.onSelected,
    required this.onBack,
    this.pendingApprovalSessions = 0,
    this.onBackToApproval,
    this.builders,
    super.key,
  });

  final SettingsPages pages;
  final SettingsPage selected;
  final ValueChanged<SettingsPage> onSelected;
  final VoidCallback onBack;

  /// Сколько сессий ждёт ответа на запрос разрешения; `0` — InfoBar нет.
  /// Число приходит из состояния рабочего места, своего источника у оболочки
  /// нет (design.md change `add-app-settings-shell`, D2).
  final int pendingApprovalSessions;

  /// Нажатие «Back to session» в InfoBar; сам ответ на запрос даётся только
  /// на рабочем месте, где виден контекст tool call.
  final VoidCallback? onBackToApproval;

  /// Таблица тел; `null` — [settingsPageBuilders].
  final Map<SettingsPage, WidgetBuilder>? builders;

  @override
  State<SettingsShell> createState() => _SettingsShellState();
}

class _SettingsShellState extends State<SettingsShell> {
  var _query = '';
  final _focusNode = FocusNode(debugLabel: 'SettingsShell');
  final _scopeNode = FocusScopeNode(debugLabel: 'SettingsShellScope');

  @override
  void initState() {
    super.initState();
    // `autofocus` не отбирает фокус у узла рабочего места, который уже
    // держит его: Esc и Cmd/Ctrl+N попали бы в рабочее место (D2). Явный
    // запрос после кадра переносит фокус сюда. Возврат фокуса при закрытии
    // экрана делает не оболочка, а `_CodeLabHome` (`codelab_app_widget.dart`):
    // у оболочки своя `FocusScope`, и сама она ничего не восстанавливает.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scopeNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final builders = widget.builders ?? settingsPageBuilders;
    final narrow = MediaQuery.sizeOf(context).width < settingsNarrowBreakpoint;
    final matches = SettingsSearchIndex.search(widget.pages.visible, _query);
    final body = builders[widget.selected];

    // Собственная область фокуса: Tab и Shift+Tab ходят только по настройкам
    // и не попадают в скрытое рабочее место (H1 ревью итерации 1; D2).
    // Esc возвращает на рабочее место. Открытый поверх страницы ContentDialog
    // живёт в маршруте Navigator вне этого поддерева и закрывается сам.
    return FocusScope(
      node: _scopeNode,
      child: FocusTraversalGroup(
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): widget.onBack,
          },
          child: Focus(
            focusNode: _focusNode,
            child: CodeLabSettingsNavigation(
              mode: narrow
                  ? CodeLabSettingsNavMode.top
                  : CodeLabSettingsNavMode.left,
              items: [
                for (final page in matches)
                  CodeLabSettingsNavItem(
                    id: page.slug,
                    title: page.title,
                    icon: _iconOf(page),
                    group: page.group.title,
                  ),
              ],
              selectedId: widget.selected.slug,
              onSelected: (id) {
                final page = SettingsPage.fromSlug(id);
                if (page != null) {
                  widget.onSelected(page);
                }
              },
              onQueryChanged: (query) => setState(() => _query = query),
              onBack: widget.onBack,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(40, 28, 40, 40),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.pendingApprovalSessions > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: InfoBar(
                              key: const ValueKey('settings-pending-approval'),
                              title: const Text(
                                'Agent is waiting for your approval',
                              ),
                              severity: InfoBarSeverity.warning,
                              action: Button(
                                onPressed: widget.onBackToApproval,
                                child: const Text('Back to session'),
                              ),
                            ),
                          ),
                        if (body != null) body(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static IconData _iconOf(SettingsPage page) => switch (page) {
    SettingsPage.connection => FluentIcons.plug_connected,
    SettingsPage.providers => FluentIcons.cloud,
    SettingsPage.mcpServers => FluentIcons.server,
    SettingsPage.agentsAndModes => FluentIcons.robot,
    SettingsPage.permissionsAndTools => FluentIcons.shield,
    SettingsPage.redaction => FluentIcons.hide3,
    SettingsPage.skillsAndExtensions => FluentIcons.puzzle,
    SettingsPage.codeAndWeb => FluentIcons.code,
    SettingsPage.general => FluentIcons.settings,
    SettingsPage.appearance => FluentIcons.color,
    SettingsPage.keyboard => FluentIcons.keyboard_classic,
  };
}
