import 'package:acp_protocol/acp_protocol.dart' as acp;
import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Режимы и опции сессии для ACP (`agent-core-architecture` §13.6).
///
/// Почему отдельно: один и тот же снимок уходит в ответах `session/new`,
/// `session/load` и `session/set_config_option` и в `config_option_update`,
/// поэтому его сборка — одна функция, а не копии в обработчиках.
///
/// Как использовать: [sessionModes] и [sessionConfigOptions] строят
/// значения `modes` и `configOptions` по текущему состоянию сессии.

/// Режим сессии на проводе: id, имя и описание для клиента. Тексты видит
/// пользователь в селекторе клиента, поэтому они английские (§11.7).
typedef ModeInfo = ({ModeId id, String name, String description});

/// Режимы в порядке `availableModes` (§13.6, таблица режимов).
const modeInfos = <ModeInfo>[
  (
    id: ModeId.plan,
    name: 'Plan',
    description: 'Read and plan only, no changes',
  ),
  (
    id: ModeId.ask,
    name: 'Ask',
    description: 'Approve every call, including reads',
  ),
  (
    id: ModeId.standard,
    name: 'Standard',
    description: 'Reads without asking, edits and commands with approval',
  ),
  (
    id: ModeId.acceptEdits,
    name: 'Accept edits',
    description:
        'Reads and edits without asking, commands and network with approval',
  ),
  (
    id: ModeId.bypass,
    name: 'Bypass',
    description:
        'No approval except for critical commands, agent config edits and '
        'network access',
  ),
];

/// `modes` ответа: для клиентов, которые не знают `configOptions`.
acp.SessionModeState sessionModes(AgentSession session) => acp.SessionModeState(
  currentModeId: acp.SessionModeId(session.mode.value),
  availableModes: [
    for (final mode in modeInfos)
      acp.SessionMode(
        id: acp.SessionModeId(mode.id.value),
        name: mode.name,
        description: mode.description,
      ),
  ],
);

/// `configOptions` в порядке важности: `mode`, затем `model` (§13.6).
///
/// Список моделей — модель сессии: каталог моделей подключается в
/// итерации 3 (design.md, D3).
List<acp.SessionConfigOption> sessionConfigOptions(AgentSession session) {
  final model = session.model;
  final modelValue = '${model.provider}/${model.id}';
  return [
    acp.SessionConfigOption.select(
      id: const acp.SessionConfigId('mode'),
      name: 'Mode',
      category: 'mode',
      currentValue: acp.SessionConfigValueId(session.mode.value),
      options: [
        for (final mode in modeInfos)
          acp.SessionConfigSelectOption(
            value: acp.SessionConfigValueId(mode.id.value),
            name: mode.name,
          ),
      ],
    ),
    acp.SessionConfigOption.select(
      id: const acp.SessionConfigId('model'),
      name: 'Model',
      category: 'model',
      currentValue: acp.SessionConfigValueId(modelValue),
      options: [
        acp.SessionConfigSelectOption(
          value: acp.SessionConfigValueId(modelValue),
          name: model.id,
        ),
      ],
    ),
  ];
}
