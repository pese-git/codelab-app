import 'package:codelab_setup/codelab_setup.dart' show AgentExtensionsView;

/// Состояние страницы «Skills & extensions» (change `add-app-skills-page`,
/// D6).
///
/// Почему закрытая иерархия, а не набор флагов: «загрузка», «только для
/// чтения», «нет папки», «конфиг не читается» и «готово» взаимоисключающи;
/// флаги допустили бы невозможные сочетания (`AGENTS.md` §8).
///
/// Для чего: отображаемое состояние страницы. Тексты файлов (`AGENTS.md`, тела
/// навыков и шаблонов) сюда не попадают: вид моста их не несёт (SETUP-25).
///
/// Как использовать: страница делает `switch` по [SkillsSettingsState];
/// владелец — `SkillsSettingsCubit`.
sealed class SkillsSettingsState {
  const SkillsSettingsState();
}

/// Идёт первая загрузка.
final class SkillsSettingsLoading extends SkillsSettingsState {
  const SkillsSettingsLoading();
}

/// Агент не на этой машине или чужой: локальные файлы не читались (SETUP-2).
///
/// [notice] — основная строка InfoBar `skills-read-only`, [hint] — вторая
/// (как проверить на другом хосте); `null` — подсказки нет.
final class SkillsSettingsReadOnly extends SkillsSettingsState {
  const SkillsSettingsReadOnly({required this.notice, this.hint});

  final String notice;
  final String? hint;

  @override
  String toString() => 'SkillsSettingsReadOnly';
}

/// Папки нет: читать нечего (D2). [banner] — итог «Open .codelab folder»;
/// [codelabHome] — `CODELAB_HOME` профиля: каталог для этой кнопки и её
/// подсказки (хранится в состоянии, чтобы кнопка не зависела от более новой
/// загрузки, ревью итерации 4).
final class SkillsSettingsNoFolder extends SkillsSettingsState {
  const SkillsSettingsNoFolder({this.banner, this.codelabHome});

  final SkillsBanner? banner;
  final String? codelabHome;
}

/// Конфиг агента не читается: файлы не читались и не пишутся.
///
/// [problems] — проблемы загрузчика с путём ключа, по строке на проблему.
final class SkillsSettingsUnreadable extends SkillsSettingsState {
  const SkillsSettingsUnreadable({required this.problems});

  final List<String> problems;

  @override
  String toString() => 'SkillsSettingsUnreadable(${problems.length})';
}

/// Страница прочитана.
///
/// [view] — вид моста; [userConfigPath] — файл слоя `user` (подсказка
/// `skills-untrusted`); [folder] и [codelabHome] — папка и `CODELAB_HOME`, для
/// которых прочитан [view] (по ним работает «Open .codelab folder», пока идёт
/// более новая загрузка); [banner] — итог последнего действия; [saving] —
/// идёт запись (итерация 5, в итерации 4 всегда `false`).
final class SkillsSettingsReady extends SkillsSettingsState {
  const SkillsSettingsReady({
    required this.view,
    required this.userConfigPath,
    required this.folder,
    required this.codelabHome,
    this.banner,
    this.saving = false,
  });

  final AgentExtensionsView view;
  final String? userConfigPath;
  final String folder;
  final String? codelabHome;
  final SkillsBanner? banner;
  final bool saving;

  SkillsSettingsReady withBanner(SkillsBanner? banner) => SkillsSettingsReady(
    view: view,
    userConfigPath: userConfigPath,
    folder: folder,
    codelabHome: codelabHome,
    banner: banner,
    saving: saving,
  );

  @override
  String toString() => 'SkillsSettingsReady($view)';
}

/// Вид баннера страницы.
enum SkillsBannerKind { openFailed }

/// Баннер итога действия (ключ `skills-banner`).
final class SkillsBanner {
  const SkillsBanner(this.kind, this.text);

  final SkillsBannerKind kind;
  final String text;

  @override
  String toString() => 'SkillsBanner(${kind.name})';
}
