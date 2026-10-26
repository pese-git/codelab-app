import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' as acp;
import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Режимы и опции сессии для ACP (`agent-core-architecture` §13.6).
///
/// Почему отдельно: один и тот же снимок уходит в ответах `session/new`,
/// `session/load` и `session/set_config_option` и в `config_option_update`,
/// поэтому его сборка — одна функция, а не копии в обработчиках.
///
/// Как использовать: [sessionModes] и [sessionConfigOptions] строят
/// значения `modes` и `configOptions` по текущему состоянию сессии;
/// [parseModeId] и [parseEffort] разбирают значения клиента.

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

/// Устаревшие id режимов: принимаются на входе, наружу не уходят (§13.6).
const _modeSynonyms = {
  'architect': ModeId.plan,
  'debug': ModeId.standard,
  'acceptEdits': ModeId.acceptEdits,
  'code': ModeId.bypass,
};

/// Режим по id клиента или его синониму; `null` — значения нет в списке.
ModeId? parseModeId(String value) =>
    ModeId.values.where((mode) => mode.value == value).firstOrNull ??
    _modeSynonyms[value];

/// Уровень рассуждения по значению опции `effort`; `null` — значения нет.
ReasoningEffort? parseEffort(String value) =>
    ReasoningEffort.values.where((e) => e.name == value).firstOrNull;

/// Имена уровней в селекторе клиента (§13.6).
const _effortNames = {
  ReasoningEffort.low: 'Low',
  ReasoningEffort.medium: 'Medium',
  ReasoningEffort.high: 'High',
};

/// `configOptions` в порядке важности: `mode`, `model`, `effort` (§13.6).
///
/// `model` — модели каталога [catalog]; модель сессии вне каталога (её
/// задал хост) идёт первой, чтобы текущее значение было среди вариантов.
/// `effort` — только у модели с `supportsReasoning` (ACP-10).
List<acp.SessionConfigOption> sessionConfigOptions(
  AgentSession session,
  ModelCatalog catalog,
) {
  final model = session.model;
  final modelValue = '${model.provider}/${model.id}';
  final entries = catalog.models;
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
        if (!entries.any((entry) => entry.id.value == modelValue))
          acp.SessionConfigSelectOption(
            value: acp.SessionConfigValueId(modelValue),
            name: model.id,
          ),
        for (final entry in entries)
          acp.SessionConfigSelectOption(
            value: acp.SessionConfigValueId(entry.id.value),
            name: entry.name,
          ),
      ],
    ),
    if (model.supportsReasoning)
      acp.SessionConfigOption.select(
        id: const acp.SessionConfigId('effort'),
        name: 'Reasoning effort',
        category: 'thought_level',
        currentValue: acp.SessionConfigValueId(session.effort.name),
        options: [
          for (final MapEntry(key: effort, value: name) in _effortNames.entries)
            acp.SessionConfigSelectOption(
              value: acp.SessionConfigValueId(effort.name),
              name: name,
            ),
        ],
      ),
  ];
}
