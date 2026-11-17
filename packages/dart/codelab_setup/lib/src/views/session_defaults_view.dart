/// Умолчания новой сессии для страницы «Agents & modes»: режим разрешений и
/// уровень рассуждения (client-agent-setup «Умолчания новой сессии в мосте»;
/// design.md change `add-settings-agents-modes`, D2, D4, D6; SETUP-8).
///
/// Тесты — `test/views/session_defaults_view_test.dart`.
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show ConfigLayer, ModeId, ReasoningEffort, ToolTier;

import '../access/settings_access.dart';
import '../config/agent_config_store.dart';
import '../config/config_source_view.dart';

/// Итоговый режим разрешений новых сессий.
///
/// Почему отдельный тип: клиент не разбирает слои, псевдонимы (`acceptEdits`,
/// `alwaysAsk`) и правила доверия сам (SETUP-8); он получает уже итог.
///
/// Как использовать: поле [SessionDefaultsView.mode]; значения строит
/// [sessionDefaultsOf].
final class ModeChoiceView {
  const ModeChoiceView({
    required this.id,
    required this.source,
    required this.narrowedByProject,
    required this.blocksWriteAndExec,
  });

  /// Основной id режима: `plan`, `ask`, `standard`, `accept-edits`, `bypass`
  /// (псевдонимы приведены к основному). `autopilot` сюда не попадает: он
  /// задаётся только флагом запуска агента, не конфигом.
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
/// Как использовать: поле [SessionDefaultsView.effort].
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
/// Как использовать: `sessionDefaultsOf(snapshot, access)`.
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
/// Итог берётся из разобранного `snapshot.loaded.config` (псевдонимы и
/// сочетание `ask`+`plan` уже разобраны ядром), источник — из
/// `snapshot.originOf`, сужение — из `loaded.warnings`; страница правила
/// доверия не повторяет (SETUP-8). Без итога загрузки действуют умолчания
/// профиля хоста: `standard` и `medium`.
///
/// Особый случай `ask`+`plan`: итог не совпадает ни с одним слоем, поэтому
/// снимок приписывает ему внешний источник (`env`). Режим при этом пришёл из
/// слоя ниже проекта, а писать можно только в `user`, так что источником
/// отдаётся слой `user` (D4), если `ask` задан в его листьях; иначе источник
/// остаётся как в снимке. Цель записи — по общему правилу.
SessionDefaultsView sessionDefaultsOf(
  AgentConfigSnapshot snapshot,
  EditableSettings access,
) {
  final config = snapshot.loaded.config;
  final permissions = config?.permissions;
  final blocks =
      permissions != null &&
      permissions.extraDeniedTiers.containsAll(const {
        ToolTier.write,
        ToolTier.exec,
      });
  final modeId = permissions?.mode?.value ?? 'standard';

  var modeSource = snapshot.originOf(_modeKey);
  final user = snapshot.layers[ConfigLayer.user];
  if (blocks && modeSource?.layer == null && user != null) {
    // Подмена только если `ask` действительно из слоя `user` (основной id или
    // псевдоним `alwaysAsk`: `configModeId` ядра не экспортируется, а
    // `ModeId.tryParse` его не знает); `ask` из окружения или `--config`
    // остаётся со своим источником.
    final raw = switch (user.values['permissions']) {
      final Map<String, Object?> p => p['mode'],
      _ => null,
    };
    if (raw is String &&
        (raw == 'alwaysAsk' || ModeId.tryParse(raw) == ModeId.ask)) {
      modeSource = ConfigSourceView(
        kind: ConfigSourceKind.user,
        label: user.path,
      );
    }
  }

  final narrowed = snapshot.loaded.warnings.any(
    (w) => w.event == _untrustedEvent && w.key == _modeKey,
  );

  final editableLayer = modeSource != null && modeSource.editable
      ? modeSource.layer
      : null;
  final target = editableLayer == ConfigLayer.projectLocal && access.cwd != null
      ? ConfigLayer.projectLocal
      : ConfigLayer.user;

  return SessionDefaultsView(
    mode: ModeChoiceView(
      id: modeId,
      source: modeSource,
      narrowedByProject: narrowed,
      blocksWriteAndExec: blocks,
    ),
    effort: EffortChoiceView(
      id: (config?.effort ?? ReasoningEffort.medium).name,
      source: snapshot.originOf('agent.effort'),
    ),
    suggestedTarget: target,
  );
}

const _modeKey = 'permissions.mode';
const _untrustedEvent = 'config.project.untrusted_key';
