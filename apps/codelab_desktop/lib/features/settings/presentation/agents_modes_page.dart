import 'package:fluent_ui/fluent_ui.dart';

/// Тело страницы «Agents & modes» для таблицы `settingsPageBuilders`.
///
/// ЗАГЛУШКА итерации 1, задача 1.1: ничего не рисует и нигде не
/// зарегистрирована (`defaultSettingsPages`, `settingsPageBuilders` — задача
/// 1.4). Ключи теста по D9: тело `settings-agents-modes`, `agents-modes-*`.
Widget buildAgentsModesPage(BuildContext context) => const AgentsModesPage();

/// Страница настроек «Agents & modes»; читает `AgentsModesCubit` из
/// `BlocProvider` (задача 1.4).
class AgentsModesPage extends StatelessWidget {
  const AgentsModesPage({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
