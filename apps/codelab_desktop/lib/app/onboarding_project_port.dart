import '../features/onboarding/application/onboarding_project_port.dart';
import '../features/workbench/application/shell_cubit.dart';

/// Адаптер порта `OnboardingProjectPort` поверх фасада рабочего места
/// (design.md change `add-onboarding-project-step`, D5).
///
/// Почему в `lib/app/`: application onboarding не должен зависеть от
/// application рабочего места, а правило «принятая папка» (диалог, бросок,
/// недавние, отказы) уже живёт в `SettingsCubit`; второй копии нет. Адаптер
/// только пробрасывает вызовы и их результат.
///
/// Для чего: выбор на шаге «Open a project» попадает в то же состояние, что
/// и выбор в рабочем месте (проект, недавние, снимок, диагностика
/// `Selected project: …`), но агента не стартует: пока показан onboarding,
/// `SettingsCubit` держит триггер (`projectStartHeld`), а снимает удержание
/// `CodeLabShellCubit.startOnLaunch()`.
///
/// Как использовать: `app_scope.dart` создаёт его над тем же
/// `CodeLabShellCubit`, что и рабочее место, и передаёт в `OnboardingCubit`.
final class ShellOnboardingProjectPort implements OnboardingProjectPort {
  ShellOnboardingProjectPort(this._shell);

  final CodeLabShellCubit _shell;

  @override
  Future<String?> pickFolder() => _shell.browseForProject();

  @override
  Future<String?> openDropped(List<String?> paths) =>
      _shell.openDroppedPaths(paths);

  @override
  Future<String?> openRecent(String path) => _shell.selectProject(path);

  @override
  String? get selectedProject {
    final selected = _shell.state.selectedProjectPath?.trim();
    return selected == null || selected.isEmpty ? null : selected;
  }
}
