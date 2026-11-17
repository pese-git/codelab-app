import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/codelab_text.dart';

/// Где располагается навигация настроек относительно страницы.
///
/// Решает хост по ширине окна: порог 760 px взят из макета (design.md change
/// `add-app-settings-shell`, D3), а сам виджет окно не измеряет.
enum CodeLabSettingsNavMode {
  /// Панель слева.
  left,

  /// Полоса сверху.
  top,
}

/// Пункт навигации настроек.
///
/// [id] — стабильный идентификатор страницы; из него складывается ключ теста
/// `settings-nav-<id>` ([CodeLabSettingsNavigation.itemKey]). [group] —
/// подпись группы, под которой стоит пункт.
class CodeLabSettingsNavItem {
  const CodeLabSettingsNavItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.group,
  });

  /// Идентификатор страницы (kebab-case); хост получает его в `onSelected`.
  final String id;

  /// Подпись пункта.
  final String title;

  /// Значок пункта.
  final IconData icon;

  /// Подпись группы; заголовок рисуется при смене группы между соседями.
  final String group;
}

/// Навигация экрана настроек: поиск «Find a setting», группы пунктов, кнопка
/// «Back» и страница справа или снизу.
///
/// Почему: все страницы настроек живут в одном Fluent `NavigationView`
/// (`dart-agent-and-clients` §12.4.9; design.md change
/// `add-app-settings-shell`, D3, D16). `NavigationView` держит выбранный пункт
/// индексом и сам рисует заголовки групп, поэтому отдельная вёрстка
/// расходилась бы с остальным Fluent UI.
///
/// Для чего: только вёрстка и ввод. Какие страницы видны, как их фильтрует
/// поиск и что показывает страница, решает хост: он передаёт уже отобранные
/// [items] по порядку групп и тело [child]. Заголовок группы рисуется при
/// смене [CodeLabSettingsNavItem.group] между соседними пунктами, поэтому
/// пустая группа заголовка не получает. Строка запроса — временное состояние
/// поля и живёт в виджете; хост узнаёт о нём через [onQueryChanged].
///
/// Как использовать: `CodeLabSettingsNavigation(items:, selectedId:,
/// onSelected:, onQueryChanged:, onBack:, mode:, child:)`. Пустой [items] при
/// непустом запросе показывает строку `No settings match "<query>"`.
class CodeLabSettingsNavigation extends StatefulWidget {
  const CodeLabSettingsNavigation({
    required this.items,
    required this.selectedId,
    required this.onSelected,
    required this.onQueryChanged,
    required this.onBack,
    required this.child,
    this.mode = CodeLabSettingsNavMode.left,
    super.key,
  });

  /// Ключ поля поиска.
  static const searchKey = ValueKey<String>('settings-search');

  /// Ключ кнопки «Back».
  static const backKey = ValueKey<String>('settings-back');

  /// Ключ пункта страницы [id]: `settings-nav-<id>`.
  static Key itemKey(String id) => ValueKey<String>('settings-nav-$id');

  /// Пункты в порядке показа; соседние пункты одной группы идут подряд.
  final List<CodeLabSettingsNavItem> items;

  /// Идентификатор выбранной страницы; если её нет в [items] (отфильтрована
  /// поиском), выбранного пункта нет.
  final String selectedId;

  final ValueChanged<String> onSelected;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onBack;
  final CodeLabSettingsNavMode mode;

  /// Тело выбранной страницы.
  final Widget child;

  @override
  State<CodeLabSettingsNavigation> createState() =>
      _CodeLabSettingsNavigationState();
}

class _CodeLabSettingsNavigationState extends State<CodeLabSettingsNavigation> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final selected = items.indexWhere((item) => item.id == widget.selectedId);
    final selectedIndex = selected < 0 ? null : selected;
    final query = _controller.text;

    final paneItems = <NavigationPaneItem>[];
    String? group;
    for (final item in items) {
      if (item.group != group) {
        group = item.group;
        paneItems.add(_label(context, item.group, strong: true));
      }
      paneItems.add(
        PaneItem(
          key: CodeLabSettingsNavigation.itemKey(item.id),
          icon: Icon(item.icon),
          // Обычный `Text`: `PaneItem` берёт из него подсказку и стиль
          // выбранного пункта, обёртка `CodeLabText` их бы подменила.
          title: Text(item.title),
          // Тело страницы рисует `paneBodyBuilder`: оно одно на все пункты.
          body: const SizedBox.shrink(),
        ),
      );
    }

    if (items.isEmpty && query.isNotEmpty) {
      // Пустой результат поиска: строка вместо пунктов, а не пустая панель.
      paneItems.add(_label(context, 'No settings match "$query"'));
    }

    return NavigationView(
      titleBar: TitleBar(
        backButton: PaneBackButton(
          key: CodeLabSettingsNavigation.backKey,
          onPressed: widget.onBack,
        ),
        title: const CodeLabText('Settings'),
      ),
      pane: NavigationPane(
        displayMode: widget.mode == CodeLabSettingsNavMode.left
            ? PaneDisplayMode.expanded
            : PaneDisplayMode.top,
        toggleable: false,
        selected: selectedIndex,
        onChanged: (index) => widget.onSelected(items[index].id),
        autoSuggestBox: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          child: TextBox(
            key: CodeLabSettingsNavigation.searchKey,
            controller: _controller,
            placeholder: 'Find a setting',
            onChanged: (value) {
              setState(() {});
              widget.onQueryChanged(value);
            },
          ),
        ),
        items: paneItems,
      ),
      // `NavigationView` отдаёт телу страницы свободные по высоте ограничения
      // (`0 <= h <= H`: страница лежит в `AnimatedSwitcher`-стеке, который
      // центрирует детей). Прокручиваемая страница тогда сжимается до высоты
      // содержимого и оказывается по центру области, а не у верхнего края
      // (D24, задача 3.16). Растягиваем тело на всю область сами.
      paneBodyBuilder: (item, body) => LayoutBuilder(
        builder: (context, constraints) => ConstrainedBox(
          constraints: BoxConstraints.tightFor(
            width: constraints.hasBoundedWidth ? constraints.maxWidth : null,
            height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }

  /// Подпись между пунктами: заголовок группы или строка «нет совпадений».
  ///
  /// Почему не `PaneItemHeader`: в `fluent_ui` 4.16 раскрытая панель рисует
  /// его пустым (`NavigationPane._buildItem` отдаёт `SizedBox`), и заголовки
  /// групп пропадали. `PaneItemWidgetAdapter` не получает индекса, поэтому не
  /// сдвигает индексы выбранного пункта.
  PaneItemWidgetAdapter _label(
    BuildContext context,
    String text, {
    bool strong = false,
  }) {
    return PaneItemWidgetAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
        child: CodeLabText(
          text,
          role: strong ? CodeLabTextRole.strong : CodeLabTextRole.body,
        ),
      ),
    );
  }
}
