import 'settings_page.dart';

/// Экран приложения, который показывает `CodeLabAppWidget`.
///
/// Почему закрытая иерархия: переход между экранами — состояние приложения, а
/// не маршрут `Navigator` (`dart-agent-and-clients` §12.3 A13, DSK-24;
/// design.md change `add-app-settings-shell`, D1). `sealed` позволяет
/// следующему change (`add-app-navigation-shell`) добавить ветки без правки
/// существующих.
///
/// Как использовать: читать из `NavigationCubit.state`, менять только его
/// методами.
sealed class AppDestination {
  const AppDestination();
}

/// Рабочее место: сайдбар, сессия, док. Остаётся смонтированным и под
/// экраном настроек (D2).
final class WorkbenchDestination extends AppDestination {
  const WorkbenchDestination();

  @override
  bool operator ==(Object other) => other is WorkbenchDestination;

  @override
  int get hashCode => (WorkbenchDestination).hashCode;
}

/// Экран настроек на странице [page].
///
/// [returnTo] — сессия, активная в момент ухода; экран настроек её не
/// меняет, а возврат показывает её же (spec app-settings «Переход в настройки
/// и обратно»).
///
/// Как использовать: создаёт только `NavigationCubit` (`openSettings`,
/// `selectSettingsPage`); UI читает [page] для выбора пункта навигации.
/// Равенство по [page] и [returnTo] позволяет Cubit-у не выпускать
/// одинаковые состояния.
final class SettingsDestination extends AppDestination {
  const SettingsDestination(this.page, {this.returnTo});

  final SettingsPage page;
  final String? returnTo;

  @override
  bool operator ==(Object other) =>
      other is SettingsDestination &&
      other.page == page &&
      other.returnTo == returnTo;

  @override
  int get hashCode => Object.hash(page, returnTo);
}
