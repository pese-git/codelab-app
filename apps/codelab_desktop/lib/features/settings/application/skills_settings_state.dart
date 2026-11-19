import 'package:codelab_setup/codelab_setup.dart' show AgentExtensionsView;

import 'settings_notices.dart';
import 'skills_messages.dart';

export 'settings_notices.dart';
export 'skills_messages.dart';

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
/// [reason] — чей агент; InfoBar `skills-read-only` и подсказку строит
/// presentation по причине.
final class SkillsSettingsReadOnly extends SkillsSettingsState {
  const SkillsSettingsReadOnly({required this.reason});

  /// Причина «только чтение»: чей агент (D5, «Уточнение итерации 5»); текст
  /// InfoBar и подсказку строит presentation.
  final ReadOnlyReason reason;

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
/// [issues] — проблемы: фразы app и тексты загрузчика с путём ключа.
final class SkillsSettingsUnreadable extends SkillsSettingsState {
  const SkillsSettingsUnreadable({required this.issues});

  /// Проблемы закрытого типа: фраза app (переводится) или текст загрузчика как
  /// есть (D5, D6).
  final List<SettingsProblem> issues;

  @override
  String toString() => 'SkillsSettingsUnreadable(${issues.length})';
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

  /// То же состояние с признаком записи [saving]; баннер сбрасывается:
  /// запись начинается с чистого баннера, итог ляжет на свежее состояние
  /// (D14). Пока идёт запись, страница не принимает новых действий.
  SkillsSettingsReady withSaving({required bool saving}) => SkillsSettingsReady(
    view: view,
    userConfigPath: userConfigPath,
    folder: folder,
    codelabHome: codelabHome,
    saving: saving,
  );

  /// То же состояние с [saving] `false` и ПРЕЖНИМ баннером: запись завершена,
  /// включая перечитывание (D14).
  SkillsSettingsReady settled() => SkillsSettingsReady(
    view: view,
    userConfigPath: userConfigPath,
    folder: folder,
    codelabHome: codelabHome,
    banner: banner,
  );

  @override
  String toString() => 'SkillsSettingsReady($view)';
}

/// Вид баннера: [openFailed] — отказ открыть каталог; [saved], [conflict] и
/// [error] — исход записи `skills.*` (D9).
enum SkillsBannerKind { openFailed, saved, conflict, error }

/// Баннер итога действия (ключ `skills-banner`).
///
/// Хранит типизированное [message], а не текст: текст строит presentation
/// (`skillsMessageText`) на текущем языке (D5, «Уточнение итерации 5»).
final class SkillsBanner {
  const SkillsBanner(this.kind, {required this.message});

  final SkillsBannerKind kind;
  final SkillsMessage message;

  @override
  String toString() => 'SkillsBanner(${kind.name})';
}

/// Вид строки согласия на каталог навыков другого агента (Q3).
///
/// Почему: Cubit пишет его в событие `root_consent`, страница — в ключ и
/// подпись строки; правило «`~` в начале — домашний каталог» должно быть одним
/// (ревью итерации 5 change `add-app-skills-page`).
enum SkillsConsentKind {
  /// `~/.claude/skills`: каталог пользователя.
  home('home', 'home'),

  /// `.claude/skills`: относительный элемент, от папки проекта.
  project('project', 'project_relative');

  const SkillsConsentKind(this.key, this.rootKind);

  /// Суффикс ключей страницы `skills-consent-<key>`.
  final String key;

  /// Значение поля `root_kind` события `skills_settings.root_consent`.
  final String rootKind;
}

/// Вид строки согласия по элементу `skills.extra_roots` [entry].
SkillsConsentKind consentKindOf(String entry) =>
    entry.startsWith('~') ? SkillsConsentKind.home : SkillsConsentKind.project;
