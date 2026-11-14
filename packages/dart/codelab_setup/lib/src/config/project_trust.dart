/// Доверие проекта и значения «ниже недоверенного проекта» по итогу загрузки
/// (design.md change `add-app-skills-page`, D5, Q43).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart' show CoreConfig;

/// Ключи, которые недоверенный проект не заменяет, а объединяет с нижними
/// слоями (Q43: запреты пользователя проект не снимает).
///
/// Повторяет знание ядра (`codelab_agent_core/lib/src/config/trust.dart`,
/// объединение списков недоверенного проекта): при новом объединяемом ключе,
/// который пишет страница, набор пополняется или выносится в ядро.
const mergedByUntrustedProject = {'skills.disabled'};

/// Проект доверенный: корень проектных слоёв назван в `trusted_projects`.
///
/// Почему так: тот же расчёт, что у ядра (`resolveConfig`: `projectRoot` в
/// `trustedProjects`), без файловой системы — основной барель моста
/// web-безопасен. Нет итога загрузки или корня проектных слоёв — недоверенный
/// (fail-closed).
bool projectTrustedIn(CoreConfig? config) {
  final root = config?.projectRoot;
  if (config == null || root == null) {
    return false;
  }
  final canonical = root.replaceAll('\\', '/');
  return config.trustedProjects.any(
    (r) => r.replaceAll('\\', '/') == canonical,
  );
}

/// Значения листьев без проектных слоёв для недоверенного проекта; `null` —
/// проект доверенный, проектных слоёв нет или ядро не заполнило снимок.
///
/// Почему: у ключа из [mergedByUntrustedProject] итог загрузки — объединение,
/// и он часто совпадает со списком проектного слоя (user без ключа, project
/// `[p]` → итог `[p]`), а значит источник «по значению» ложно называл бы
/// проект или файл `--config`. Источник такого ключа определяется по этим
/// значениям (user, `--config`, окружение), а проектные слои при выборе
/// источника пропускаются.
Map<String, Object?>? valuesBelowUntrustedProject(CoreConfig? config) {
  if (config == null ||
      config.projectRoot == null ||
      projectTrustedIn(config)) {
    return null;
  }
  return config.withoutProjectValues;
}
