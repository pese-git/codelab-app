import 'package:codelab_setup/codelab_setup.dart';

/// Страница, которой принадлежит ключ реестра `scope: shared` (design.md
/// change `add-app-general-page`, D2).
///
/// Почему: раскладка ключей по страницам — решение экрана app, а не моста
/// (CLI показывает все строки `/settings`). Явная таблица с тестом полноты
/// заставляет решить судьбу нового ключа, а не даёт ему молча появиться на
/// «General» или пропасть.
///
/// Для чего: `general` — блок «Agent defaults»; остальные владельцы только
/// исключают ключ со «General» (у них своя страница или правка запрещена).
enum SettingsPageOwner {
  general,
  providers,
  agentsAndModes,
  mcpServers,
  permissionsAndTools,
  trustBoundary,
}

/// Строка блока «Agent defaults»: строка реестра, отказ в правке и перекрытие.
///
/// Для чего: чистые данные для страницы; решение «можно ли править» берётся
/// из моста (`settingEditRefusalOf`, D6), а не принимается в виджете.
final class AgentDefaultsRow {
  const AgentDefaultsRow({
    required this.field,
    this.refusal,
    this.overriddenByKind,
  });

  /// Строка реестра: ключ, значение, источник, дескриптор.
  final SettingFieldView field;

  /// Причина, по которой редактора нет; `null` — строка редактируется.
  final SettingEditRefusal? refusal;

  /// Вид проектного слоя (`project` или `projectLocal`), из которого пришло
  /// значение; иначе `null`. Подпись `This project overrides it ({source})`
  /// строит страница одной функцией по `ConfigSourceKind` (D7, решение
  /// пользователя 2026-11-19 В1).
  final ConfigSourceKind? overriddenByKind;
}

/// Группа строк одного раздела реестра.
final class AgentDefaultsGroup {
  const AgentDefaultsGroup({required this.section, required this.rows});

  /// Раздел реестра: `Budget`, `Agent`, `Subagents` или `Logging`.
  final String section;
  final List<AgentDefaultsRow> rows;
}

/// Ключи блока «Agent defaults» (D2): бюджет хода, сжатие контекста, все 12
/// ключей субагентов и уровень журнала.
///
/// Почему перечислены поимённо, а не `subagents.*`: новый ключ раздела
/// `subagents` не должен молча появиться на странице; без строки в таблице
/// его ловит тест полноты.
const _generalKeys = {
  'budget.max_steps',
  'budget.max_tokens',
  'budget.max_cost',
  'budget.max_duration',
  'compaction.enabled',
  'subagents.enabled',
  'subagents.max_depth',
  'subagents.max_concurrent',
  'subagents.max_per_turn',
  'subagents.max_steps',
  'subagents.max_tokens',
  'subagents.max_cost',
  'subagents.max_duration',
  'subagents.report_max_bytes',
  'subagents.progress_interval',
  'subagents.heartbeat_interval',
  'subagents.cancel_grace',
  'logging.level',
};

/// Ключи, у которых есть своя страница или правка запрещена (D2).
const _otherOwners = <String, SettingsPageOwner>{
  'agent.default_model': SettingsPageOwner.providers,
  'permissions.mode': SettingsPageOwner.agentsAndModes,
  'agent.effort': SettingsPageOwner.agentsAndModes,
  'mcp.servers': SettingsPageOwner.mcpServers,
  'permissions.deny': SettingsPageOwner.permissionsAndTools,
  'permissions.tools': SettingsPageOwner.permissionsAndTools,
  'trusted_projects': SettingsPageOwner.trustBoundary,
};

/// Порядок разделов реестра на странице (D2).
const _sectionOrder = ['Budget', 'Agent', 'Subagents', 'Logging'];

/// Владелец ключа реестра по шаблону дескриптора (`providers.*.base_url`,
/// а не `providers.local.base_url`); `null` — ключа нет в таблице.
///
/// Для чего: единая таблица классификации D2. Тест полноты обходит
/// `SettingsRegistry.all` и падает на ключе `scope: shared`, у которого здесь
/// `null`, поэтому новый ключ реестра не появится на «General» без решения.
/// Ключи `providers.*` относятся к «Providers» по префиксу: у них один
/// владелец и мастера с порядком «секрет → конфиг» (SETUP-24).
SettingsPageOwner? settingsPageOwnerOf(String descriptorKey) {
  if (_generalKeys.contains(descriptorKey)) {
    return SettingsPageOwner.general;
  }
  if (descriptorKey.startsWith('providers.*.')) {
    return SettingsPageOwner.providers;
  }
  return _otherOwners[descriptorKey];
}

/// Строит группы блока «Agent defaults» из строк `settingFieldsOf`.
///
/// Для чего: оставляет только ключи владельца `general`, группирует по
/// разделу реестра в порядке Budget, Agent, Subagents, Logging (раздел
/// неизвестного порядка идёт после них), внутри группы сохраняет порядок
/// входа (порядок реестра, как у `/settings`). Пустые группы не создаются.
/// Отказ в правке и перекрытие проектным слоем берутся из правила моста
/// `settingEditRefusalOf` (D6), а не решаются в виджете.
List<AgentDefaultsGroup> agentDefaultsGroupsOf(
  Iterable<SettingFieldView> fields,
) {
  final bySection = <String, List<AgentDefaultsRow>>{};
  for (final field in fields) {
    if (settingsPageOwnerOf(field.descriptor.key) !=
        SettingsPageOwner.general) {
      continue;
    }
    bySection
        .putIfAbsent(field.descriptor.section, () => [])
        .add(
          AgentDefaultsRow(
            field: field,
            refusal: settingEditRefusalOf(field),
            overriddenByKind: switch (field.source?.kind) {
              final kind &&
                  (ConfigSourceKind.project || ConfigSourceKind.projectLocal) =>
                kind,
              _ => null,
            },
          ),
        );
  }
  final sections = [
    ..._sectionOrder.where(bySection.containsKey),
    ...bySection.keys.where((s) => !_sectionOrder.contains(s)),
  ];
  return [
    for (final section in sections)
      AgentDefaultsGroup(section: section, rows: bySection[section]!),
  ];
}
