/// Правило записи списков `skills.disabled` и `skills.extra_roots`
/// (design.md change `add-app-skills-page`, D5; `dart-agent-and-clients`
/// §12.4.6а, п. 5).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show
        ConfigEdit,
        ConfigLayer,
        ConfigSnapshot,
        SetValue,
        UnsetValue,
        isRelativeSkillRoot;

import '../config/agent_config_store.dart';
import '../config/project_trust.dart';

/// Ключ списка выключенных навыков.
const _disabledKey = 'skills.disabled';

/// Ключ дополнительных корней навыков.
const _rootsKey = 'skills.extra_roots';

/// Результат правила: план записи или отказ с причиной.
///
/// Почему sealed: страница обязана различить «можно записать» и «нельзя, и
/// вот почему» (подсказка неактивного переключателя), а не получить `null`.
sealed class SkillsListEditResult {
  const SkillsListEditResult();
}

/// Запись возможна: [edits] нужно передать `AgentConfigStore.apply(base,
/// edits)`.
///
/// Почему [base] — снимок целевого слоя: отпечаток и конфликт (SETUP-6)
/// проверяются по файлу, который меняется. Пустой [edits] — список уже такой,
/// писать не нужно (повторное нажатие не создаёт записи).
///
/// Как использовать: вызывающий (Cubit страницы) при непустом [edits]
/// вызывает `AgentConfigStore.apply(base, edits)` и по исходу
/// (`ConfigSaved`, `ConfigConflict`, `ConfigRejected`) обновляет страницу; при
/// пустом [edits] ничего не пишет и запись не показывает. План сам файл не
/// меняет.
final class SkillsListPlan extends SkillsListEditResult {
  const SkillsListPlan({
    required this.layer,
    required this.base,
    required this.edits,
  });

  /// Целевой слой: только `user` или `projectLocal` (SETUP-3).
  final ConfigLayer layer;

  /// Снимок слоя [layer] из `AgentConfigSnapshot.layers`.
  final ConfigSnapshot base;

  /// Одна `SetValue`, `UnsetValue` для пустого списка или ничего.
  final List<ConfigEdit> edits;

  @override
  String toString() => 'SkillsListPlan(${layer.name}, $edits)';
}

/// Запись невозможна по причине [refusal].
///
/// Почему значение, а не исключение: отказ — обычный исход действия
/// пользователя (список из недоступного слоя, недоверенный проект), а не
/// ошибка программиста.
///
/// Как использовать: вызывающий ничего не пишет и показывает подсказку по
/// [refusal] (`Set in <файл>; edit that file.` и т. п.); тот же отказ делает
/// переключатель неактивным (`SkillToggle`).
final class SkillsListRefused extends SkillsListEditResult {
  const SkillsListRefused(this.refusal);

  final SkillsListRefusal refusal;

  @override
  String toString() => 'SkillsListRefused($refusal)';
}

/// Причина отказа; из неё страница берёт подсказку неактивного элемента.
sealed class SkillsListRefusal {
  const SkillsListRefusal();
}

/// Список действует из слоя, который страница не пишет (`project`, файл
/// `--config`, переменная окружения): запись в нижний слой не подействовала
/// бы. Подсказка: `Set in <source>; edit that file.`
final class SkillsListNotEditable extends SkillsListRefusal {
  const SkillsListNotEditable(this.source);

  /// `ConfigSourceView.label`: путь файла или имя переменной.
  final String source;

  @override
  String toString() => 'SkillsListNotEditable($source)';
}

/// Имя выключено конфигурацией недоверенного проекта: включить его нельзя
/// (Q43). Подсказка: `Disabled by the project config (<source>).`
final class SkillsListDisabledByProject extends SkillsListRefusal {
  const SkillsListDisabledByProject(this.source);

  /// Путь файла проектного слоя.
  final String source;

  @override
  String toString() => 'SkillsListDisabledByProject($source)';
}

/// Согласие на относительный каталог в недоверенном проекте: загрузчик его не
/// прочитает. Подсказка: `Trust this project to read <entry>.`
final class SkillsListUntrustedProject extends SkillsListRefusal {
  const SkillsListUntrustedProject();

  @override
  String toString() => 'SkillsListUntrustedProject';
}

/// Файл слоя не прочитан (например, битый YAML) и вне снимка: писать в него
/// небезопасно. Подсказка: исправить файл (причину называет загрузчик в
/// `AgentConfigSnapshot.issues`).
final class SkillsListLayerUnreadable extends SkillsListRefusal {
  const SkillsListLayerUnreadable(this.layer);

  /// Слой без снимка.
  final ConfigLayer layer;

  @override
  String toString() => 'SkillsListLayerUnreadable(${layer.name})';
}

/// Состояние переключателя в виде: доступен или неактивен с причиной.
///
/// Почему отдельный тип: вид и запись должны опираться на одно правило
/// ([skillsListEdit]); переключатель — его результат без плана (D5, «Одна
/// реализация для вида и записи»).
final class SkillToggle {
  /// Переключатель доступен.
  const SkillToggle.available() : refusal = null;

  /// Переключатель неактивен по причине [refusal].
  const SkillToggle.refused(SkillsListRefusal this.refusal);

  /// Состояние по результату правила: план — доступен, отказ — с причиной.
  factory SkillToggle.of(SkillsListEditResult result) => switch (result) {
    SkillsListPlan() => const SkillToggle.available(),
    SkillsListRefused(:final refusal) => SkillToggle.refused(refusal),
  };

  /// `null` — переключатель доступен.
  final SkillsListRefusal? refusal;

  /// Можно ли нажать: действие даст план записи (в том числе пустой, если
  /// список уже такой). Для неактивного — `false` и подсказка из [refusal].
  ///
  /// Как использовать: view-слой привязывает к нему `onChanged` (`null` при
  /// `false`) и показывает [refusal] подсказкой; саму запись строит
  /// [skillsListEdit] в момент нажатия по свежему снимку.
  bool get isAvailable => refusal == null;

  @override
  String toString() =>
      isAvailable ? 'SkillToggle(available)' : 'SkillToggle($refusal)';
}

/// Правка списка [key] (`skills.disabled` или `skills.extra_roots`): элемент
/// [element] должен оказаться в списке при [present] `true` или выйти из него
/// при `false` (D5).
///
/// Почему такое правило: списки при слиянии слоёв заменяются целиком, поэтому
/// правка меняет список того слоя, чьё значение сейчас действует
/// (`snapshot.origins`), а не дописывает слой ниже: иначе она молча не
/// подействовала бы. Нет источника — слой `user` (Q2, Q3). Источник не
/// `user`/`projectLocal` — отказ [SkillsListNotEditable].
///
/// Доверие проекта (`CoreConfig.projectRoot` против `trustedProjects`;
/// fail-closed): у недоверенного проекта `skills.disabled` объединяется с
/// нижними слоями (Q43) — выключить можно всегда, а имя, выключенное
/// проектным слоем, включить нельзя ([SkillsListDisabledByProject]).
/// `skills.extra_roots` никогда не пишется в `project` (SKL-2), а в
/// `projectLocal` — только у доверенного проекта; относительный элемент
/// недоверенного проекта выдать нельзя ([SkillsListUntrustedProject]), но
/// отозвать можно: это только сужает доступ (приоритет 1).
///
/// Как использовать: вызывающий передаёт `plan.base` и `plan.edits` в
/// `AgentConfigStore.apply`; пустой `edits` — запись не нужна. Ключ вне двух
/// поддерживаемых — `ArgumentError` (ошибка программиста). Без
/// `loaded.config` проект считается недоверенным (fail-closed).
SkillsListEditResult skillsListEdit(
  AgentConfigSnapshot snapshot,
  String key,
  String element, {
  required bool present,
}) {
  if (key != _disabledKey && key != _rootsKey) {
    throw ArgumentError.value(key, 'key', 'is not a skills list key');
  }
  // Нет итога загрузки (нечитаемый конфиг) — проект недоверенный: fail-closed.
  final trusted = projectTrustedIn(snapshot.loaded.config);

  // Проектные слои, выключающие навыки: у недоверенного проекта их списки
  // объединяются с нижними (Q43). Источник такого ключа снимок уже определил
  // по значениям без проектных слоёв (`AgentConfigSnapshot.origins`), здесь
  // проектные слои нужны только для отказа «включить нельзя».
  final projectDisables = [
    for (final layer in const [ConfigLayer.project, ConfigLayer.projectLocal])
      if (snapshot.layers[layer] case final projectLayer?)
        if (_listOf(projectLayer, key).isNotEmpty) projectLayer,
  ];

  var target = ConfigLayer.user;
  final origin = snapshot.origins[key];
  if (origin != null) {
    final layer = origin.layer;
    // `extra_roots` слоя `project` агент отбрасывает всегда (SKL-2): он не
    // источник и в него не пишется.
    final discarded = key == _rootsKey && layer == ConfigLayer.project;
    if (!discarded) {
      if (!origin.editable || layer == null) {
        return SkillsListRefused(SkillsListNotEditable(origin.label));
      }
      target = layer;
    }
  }
  // Слой `projectLocal` недоверенного проекта `extra_roots` не читает.
  if (key == _rootsKey && !trusted && target == ConfigLayer.projectLocal) {
    target = ConfigLayer.user;
  }

  // Q43: имя из `skills.disabled` недоверенного проекта включить нельзя.
  if (key == _disabledKey && !present && !trusted) {
    for (final projectLayer in projectDisables) {
      if (_listOf(projectLayer, key).contains(element)) {
        return SkillsListRefused(
          SkillsListDisabledByProject(projectLayer.path),
        );
      }
    }
  }
  // Выдача согласия на относительный каталог: загрузчик не читает его у
  // недоверенного проекта. Отзыв (`present: false`) разрешён.
  if (key == _rootsKey && present && !trusted && isRelativeSkillRoot(element)) {
    return const SkillsListRefused(SkillsListUntrustedProject());
  }

  final base = snapshot.layers[target];
  if (base == null) {
    // Слой с нечитаемым файлом вне снимка: писать нечего и небезопасно.
    return SkillsListRefused(SkillsListLayerUnreadable(target));
  }
  final current = _listOf(base, key);
  final next = [
    for (final e in current)
      if (e != element || present) e,
    if (present && !current.contains(element)) element,
  ];
  final unchanged =
      next.length == current.length &&
      [
        for (var i = 0; i < next.length; i++) next[i] == current[i],
      ].every((e) => e);
  return SkillsListPlan(
    layer: target,
    base: base,
    edits: unchanged
        ? const []
        : [next.isEmpty ? UnsetValue(key) : SetValue(key, next)],
  );
}

/// Сырой список слоя по ключу `skills.<имя>`; нет или не список — пусто.
List<String> _listOf(ConfigSnapshot layer, String key) {
  final skills = layer.values['skills'];
  final value = skills is Map ? skills[key.substring('skills.'.length)] : null;
  return value is List
      ? [
          for (final e in value)
            if (e is String) e,
        ]
      : const [];
}
