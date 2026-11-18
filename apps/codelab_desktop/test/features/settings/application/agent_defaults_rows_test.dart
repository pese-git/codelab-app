// Таблица классификации и строки блока «Agent defaults» (задача 2.1 change
// `add-app-general-page`; spec app-settings «Умолчания агента на странице
// «General»: доступ и строки», сценарий «Новый ключ реестра без решения»;
// design.md D2, D5).
//
// Красные тесты: функции — заглушки итерации 2, реализация — задача 2.2.
//
// Почему тест обходит реестр, а не список ключей: ключ `scope: shared`,
// которого нет в таблице, должен ронять тест и называть себя, а не появляться
// на странице сам (D2).

import 'dart:convert';
import 'dart:io';

import 'package:codelab_desktop/features/settings/application/agent_defaults_rows.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ключи блока `general` в порядке реестра (D2): 4 бюджета, сжатие, 12 ключей
/// субагентов, уровень журнала.
const _generalKeys = [
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
];

/// Ключи с владельцем-страницей: на «General» их быть не должно (D2).
const _notGeneral = {
  'agent.default_model': SettingsPageOwner.providers,
  'providers.*.kind': SettingsPageOwner.providers,
  'providers.*.base_url': SettingsPageOwner.providers,
  'providers.*.api_key_env': SettingsPageOwner.providers,
  'providers.*.api_key_secret': SettingsPageOwner.providers,
  'providers.*.models.*.context_window': SettingsPageOwner.providers,
  'permissions.mode': SettingsPageOwner.agentsAndModes,
  'agent.effort': SettingsPageOwner.agentsAndModes,
  'mcp.servers': SettingsPageOwner.mcpServers,
  'permissions.deny': SettingsPageOwner.permissionsAndTools,
  'permissions.tools': SettingsPageOwner.permissionsAndTools,
  'trusted_projects': SettingsPageOwner.trustBoundary,
};

/// Типы, для которых у страницы есть редактор (D5).
const _editorTypes = {
  SettingType.bool,
  SettingType.enumeration,
  SettingType.int,
  SettingType.float,
  SettingType.duration,
};

List<SettingDescriptor> _shared() => [
  for (final d in SettingsRegistry.all)
    if (d.scope == SettingScope.shared) d,
];

List<SettingDescriptor> _general() => [
  for (final d in _shared())
    if (settingsPageOwnerOf(d.key) == SettingsPageOwner.general) d,
];

/// Строка реестра без значения, как её отдаёт `settingFieldsOf` для ключа,
/// который нигде не задан.
SettingFieldView _field(
  String key, {
  Object? value,
  ConfigSourceView? source,
}) => SettingFieldView(
  key: key,
  descriptor: SettingsRegistry.lookup(key)!,
  value: value,
  source: source,
);

/// Все ключи реестра без шаблонов `*` — вход функции группировки, как у
/// `settingFieldsOf` до отбора страницы.
List<SettingFieldView> _allFields() => [
  for (final d in _shared())
    if (!d.key.contains('*')) _field(d.key),
];

Map<String, dynamic> _arb(String name) =>
    jsonDecode(File('lib/l10n/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  group('Таблица классификации (D2)', () {
    test('каждый ключ реестра scope: shared отнесён к странице', () {
      for (final d in _shared()) {
        expect(
          settingsPageOwnerOf(d.key),
          isNotNull,
          reason:
              'ключ ${d.key} реестра scope: shared без решения: добавьте его '
              'в таблицу agent_defaults_rows.dart (General или страница-'
              'владелец)',
        );
      }
    });

    test('на «General» ровно ключи бюджета, сжатия, субагентов и журнала', () {
      expect([for (final d in _general()) d.key], _generalKeys);
    });

    test('остальные ключи принадлежат страницам-владельцам', () {
      _notGeneral.forEach((key, owner) {
        expect(settingsPageOwnerOf(key), owner, reason: key);
      });
    });

    test('ключ вне реестра и не-shared ключ не имеют владельца', () {
      expect(settingsPageOwnerOf('no.such.key'), isNull);
      expect(settingsPageOwnerOf('providers.local.base_url'), isNull);
    });
  });

  group('Редакторы (D5)', () {
    test('у каждого ключа general тип из набора редакторов', () {
      final general = _general();
      expect(general, isNotEmpty);
      for (final d in general) {
        expect(
          _editorTypes,
          contains(d.type),
          reason: '${d.key}: нет редактора для типа ${d.type.name}',
        );
      }
    });

    test('у ключей-перечислений есть значения для выпадающего списка', () {
      expect(_general(), hasLength(_generalKeys.length));
      for (final d in _general()) {
        if (d.type == SettingType.enumeration) {
          expect(d.enumValues, isNotEmpty, reason: d.key);
        }
      }
    });
  });

  group('Подписи ARB (D2)', () {
    test('идентификаторы строятся по ключу реестра', () {
      expect(
        agentSettingLabelId('budget.max_steps'),
        'agentSettingLabel_budget_max_steps',
      );
      expect(
        agentSettingDescriptionId('budget.max_steps'),
        'agentSettingDescription_budget_max_steps',
      );
    });

    test('английские сообщения подписи и описания равны реестру', () {
      final en = _arb('app_en.arb');
      expect(_general(), hasLength(_generalKeys.length));
      for (final d in _general()) {
        expect(
          en[agentSettingLabelId(d.key)],
          d.label,
          reason: 'подпись ${d.key} в app_en.arb',
        );
        expect(
          en[agentSettingDescriptionId(d.key)],
          d.description,
          reason: 'описание ${d.key} в app_en.arb',
        );
      }
    });

    test('русские сообщения заданы для каждого ключа general', () {
      final ru = _arb('app_ru.arb');
      expect(_general(), hasLength(_generalKeys.length));
      for (final d in _general()) {
        for (final id in [
          agentSettingLabelId(d.key),
          agentSettingDescriptionId(d.key),
        ]) {
          expect(ru[id], isA<String>(), reason: '$id в app_ru.arb');
          expect(ru[id], isNotEmpty, reason: '$id в app_ru.arb');
        }
      }
    });
  });

  group('Группировка строк (D2)', () {
    test('Budget, Agent, Subagents, Logging; порядок реестра в группе', () {
      final groups = agentDefaultsGroupsOf(_allFields());

      expect(
        [for (final g in groups) g.section],
        ['Budget', 'Agent', 'Subagents', 'Logging'],
      );
      expect(
        [
          for (final g in groups) [for (final r in g.rows) r.field.key],
        ],
        [
          _generalKeys.sublist(0, 4),
          ['compaction.enabled'],
          _generalKeys.sublist(5, 17),
          ['logging.level'],
        ],
      );
    });

    test('ключей чужих страниц среди строк нет', () {
      final shown = {
        for (final g in agentDefaultsGroupsOf(_allFields()))
          for (final r in g.rows) r.field.key,
      };

      expect(shown, isNotEmpty);
      for (final key in ['permissions.mode', 'agent.effort', 'mcp.servers']) {
        expect(shown, isNot(contains(key)));
      }
      expect(shown, isNot(contains('trusted_projects')));
      expect(shown, isNot(contains('agent.default_model')));
    });

    test('группа без строк не создаётся', () {
      final groups = agentDefaultsGroupsOf([_field('logging.level')]);

      expect([for (final g in groups) g.section], ['Logging']);
    });

    test('строки чужих страниц одни дают пустой список', () {
      expect(agentDefaultsGroupsOf([_field('permissions.mode')]), isEmpty);
    });
  });

  group('Строка: отказ и перекрытие (D4, D6)', () {
    const user = ConfigSourceView(kind: ConfigSourceKind.user, label: 'u');
    const project = ConfigSourceView(
      kind: ConfigSourceKind.project,
      label: 'p',
    );
    const local = ConfigSourceView(
      kind: ConfigSourceKind.projectLocal,
      label: 'l',
    );
    const env = ConfigSourceView(
      kind: ConfigSourceKind.environment,
      label: 'env',
    );

    AgentDefaultsRow rowOf(SettingFieldView field) {
      final groups = agentDefaultsGroupsOf([field]);
      expect(groups, hasLength(1), reason: field.key);
      expect(groups.single.rows, hasLength(1), reason: field.key);
      return groups.single.rows.single;
    }

    test('источник user и default правятся без подписи перекрытия', () {
      final fromUser = rowOf(
        _field('budget.max_steps', value: 80, source: user),
      );
      final byDefault = rowOf(_field('budget.max_steps'));

      for (final row in [fromUser, byDefault]) {
        expect(row.refusal, isNull);
        expect(row.overriddenBy, isNull);
      }
    });

    test('источник project и local остаётся редактируемым и называет слой', () {
      final fromProject = rowOf(
        _field('budget.max_steps', value: 5, source: project),
      );
      final fromLocal = rowOf(
        _field('compaction.enabled', value: false, source: local),
      );

      expect(fromProject.refusal, isNull);
      expect(fromProject.overriddenBy, 'project');
      expect(fromLocal.refusal, isNull);
      expect(fromLocal.overriddenBy, 'local');
    });

    test('источник env отказывает ветвью моста', () {
      final row = rowOf(_field('budget.max_steps', value: 11, source: env));

      expect(row.refusal, isA<ExternalSourceSetting>());
      expect(row.overriddenBy, isNull);
    });
  });
}
