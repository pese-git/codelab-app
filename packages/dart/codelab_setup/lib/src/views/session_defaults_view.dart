/// Умолчания новой сессии для страницы «Agents & modes»: режим разрешений и
/// уровень рассуждения (client-agent-setup «Умолчания новой сессии в мосте»;
/// design.md change `add-settings-agents-modes`, D2, D4, D6; SETUP-8).
///
/// ЗАГЛУШКА итерации 1, задача 1.2: сигнатуры и поля стабильны (на них
/// опирается desktop), логики нет — `sessionDefaultsOf` бросает
/// [UnimplementedError]. Красные тесты — `test/views/session_defaults_view_test.dart`.
library;

import 'package:codelab_agent_core/codelab_agent_core.dart' show ConfigLayer;

import '../access/settings_access.dart';
import '../config/agent_config_store.dart';
import '../config/config_source_view.dart';

/// Итоговый режим разрешений новых сессий.
///
/// Почему отдельный тип: клиент не разбирает слои, псевдонимы (`acceptEdits`,
/// `alwaysAsk`) и правила доверия сам (SETUP-8); он получает уже итог.
///
/// Как использовать: поле [SessionDefaultsView.mode]; значения строит
/// [sessionDefaultsOf]. Заглушка итерации 1, задача 1.2.
final class ModeChoiceView {
  const ModeChoiceView({
    required this.id,
    required this.source,
    required this.narrowedByProject,
    required this.blocksWriteAndExec,
  });

  /// Основной id режима: `plan`, `ask`, `standard`, `accept-edits`, `bypass`
  /// (псевдонимы приведены к основному).
  final String id;

  /// Источник значения; `null` — листа нет, действует умолчание профиля хоста
  /// (`standard`), в сообщениях клиента — `default`.
  final ConfigSourceView? source;

  /// Недоверенный проект пытался сделать режим мягче и был сужен
  /// (предупреждение `config.project.untrusted_key` с ключом
  /// `permissions.mode`).
  final bool narrowedByProject;

  /// Сочетание `ask` и `plan`: итог `ask` с запретом `write` и `exec`.
  final bool blocksWriteAndExec;
}

/// Итоговый уровень рассуждения новых сессий (`agent.effort`).
///
/// Как использовать: поле [SessionDefaultsView.effort]. Заглушка итерации 1,
/// задача 1.2.
final class EffortChoiceView {
  const EffortChoiceView({required this.id, required this.source});

  /// `low`, `medium` или `high`.
  final String id;

  /// Источник; `null` — листа нет, действует умолчание `medium` (`default`).
  final ConfigSourceView? source;
}

/// Умолчания новой сессии: режим, effort и предлагаемая цель записи.
///
/// Почему: правила чтения итога и источника не должны повторяться в app и,
/// позже, в TUI (D6). Отдельного автомата нет: запись — одна `SetValue` в
/// `AgentConfigStore.apply`.
///
/// Как использовать: `sessionDefaultsOf(snapshot, access)`. Заглушка
/// итерации 1, задача 1.2.
final class SessionDefaultsView {
  const SessionDefaultsView({
    required this.mode,
    required this.effort,
    required this.suggestedTarget,
  });

  final ModeChoiceView mode;
  final EffortChoiceView effort;

  /// Слой источника `permissions.mode`, если он редактируемый и доступен
  /// [EditableSettings] (`projectLocal` — только при известной папке), иначе
  /// [ConfigLayer.user] (D4).
  final ConfigLayer suggestedTarget;
}

/// Строит умолчания новой сессии по снимку конфига и доступу (D6).
///
/// Итог берётся из разобранного `snapshot.loaded.config`, источник — из
/// `snapshot.originOf`, сужение — из `loaded.warnings`. Заглушка итерации 1,
/// задача 1.2: бросает [UnimplementedError].
SessionDefaultsView sessionDefaultsOf(
  AgentConfigSnapshot snapshot,
  EditableSettings access,
) => throw UnimplementedError('sessionDefaultsOf: задача 1.2');
