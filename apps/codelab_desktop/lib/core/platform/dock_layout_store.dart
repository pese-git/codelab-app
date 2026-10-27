import 'package:shared_preferences/shared_preferences.dart';

/// Сохранённая раскладка дока панелей инструментов.
///
/// Панели хранятся по имени (`ToolPane.name`), а не самим enum: хранилище —
/// инфраструктура и не зависит от `codelab_ui`; имя, которого больше нет,
/// при чтении пропускает `LayoutCubit`.
final class DockLayout {
  const DockLayout({
    required this.openPanes,
    required this.activePane,
    required this.width,
  });

  final List<String> openPanes;
  final String? activePane;
  final double width;
}

/// Хранилище раскладки дока между запусками.
///
/// Почему: набор открытых панелей и ширина дока — UI-состояние окна, которое
/// пользователь ожидает увидеть после перезапуска (`dart-agent-and-clients`
/// §12.3 A13, шаг 0; change `redesign-workbench-shell`, D5).
///
/// Для чего: порт `LayoutCubit`; реализация по умолчанию —
/// [SharedPreferencesDockLayoutStore].
///
/// Как использовать: [load] при старте (`null` — сохранённой раскладки нет),
/// [save] после каждого изменения дока.
abstract interface class DockLayoutStore {
  Future<DockLayout?> load();

  Future<void> save(DockLayout layout);
}

const _kOpenPanesKey = 'codelab.dock.open_panes';
const _kActivePaneKey = 'codelab.dock.active_pane';
const _kWidthKey = 'codelab.dock.width';

/// [DockLayoutStore] в `shared_preferences` под ключами `codelab.dock.*`, по
/// образцу `SharedPreferencesRecentProjectsStore`.
final class SharedPreferencesDockLayoutStore implements DockLayoutStore {
  const SharedPreferencesDockLayoutStore();

  @override
  Future<DockLayout?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final panes = prefs.getStringList(_kOpenPanesKey);
    final width = prefs.getDouble(_kWidthKey);
    if (panes == null && width == null) {
      return null;
    }
    return DockLayout(
      openPanes: panes ?? const [],
      activePane: prefs.getString(_kActivePaneKey),
      width: width ?? 0,
    );
  }

  @override
  Future<void> save(DockLayout layout) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kOpenPanesKey, layout.openPanes);
    final active = layout.activePane;
    if (active == null) {
      await prefs.remove(_kActivePaneKey);
    } else {
      await prefs.setString(_kActivePaneKey, active);
    }
    await prefs.setDouble(_kWidthKey, layout.width);
  }
}
