import 'package:codelab_setup/codelab_setup.dart';

import '../../setup/settings_access.dart';
import '../../setup/settings_rows.dart';
import '../picker_spec.dart';
import '../repl_command.dart';

/// `/settings [<key> [<value> | --reset]] [--local]` — настройки агента.
///
/// Почему: U-19, решение Q6 — в REPL настройки идут по реестру
/// `SettingsRegistry` (`scope: shared`), а запись — через тот же
/// `AgentConfigStore`, что у мастера (SETUP-6: конфликт без автоповтора).
///
/// Для чего: без аргументов — список `key value source`; `<key>` — выбор
/// значения или подсказка формата; `<key> <value>` — запись в слой `user`
/// (с `--local` — `projectLocal` текущей папки); `<key> --reset` — удаление
/// ключа из этого слоя. Слой 3 (проектный `config.yaml`) не пишется никогда
/// (SETUP-3); ключ из `--config` или окружения не правится (Q15). Для
/// удалённого и стороннего агента печатается строка только для чтения.
final class SettingsCommand implements ReplCommand {
  const SettingsCommand();

  @override
  String get name => 'settings';

  @override
  String get usage => '/settings [<key> [<value> | --reset]] [--local]';

  @override
  String get description => 'show or change agent settings';

  @override
  Future<void> run(ReplContext context, List<String> args) async {
    final setup = context.setup;
    if (setup == null) {
      context.say('Settings are not available here.');
      return;
    }
    final access = settingsAccessOf(
      context.profile,
      cwd: context.cwd,
      codelabHome: setup.codelabHome,
    );
    if (readOnlyLineOf(access) case final line?) {
      context.say(line);
      return;
    }
    final editable = access as EditableSettings;
    final local = args.contains('--local');
    final reset = args.contains('--reset');
    final words = [
      for (final a in args)
        if (!a.startsWith('--')) a,
    ];
    if (local && projectLocalTargetOf(editable) == null) {
      context.say(noProjectLocalLine);
      return;
    }
    final scope = settingsScopeOf(context.profile, editable, cwd: context.cwd);
    final store = await setup.configStore(scope);
    final snapshot = await store.snapshot(cwd: scope.cwd);
    if (words.isEmpty) {
      _list(context, snapshot);
      return;
    }
    final key = words.first;
    final descriptor = editableDescriptorOf(key);
    if (descriptor == null) {
      context.say('Unknown setting $key. Run /settings to list them.');
      return;
    }
    if (isTrustBoundary(key)) {
      context.say(trustBoundaryLine);
      return;
    }
    if (isSecretKey(descriptor)) {
      context.say('Use codelab secret set <name>');
      return;
    }
    final row = settingRowsOf(snapshot).where((r) => r.key == key).firstOrNull;
    if (words.length == 1 && !reset) {
      _values(context, key, descriptor, row);
      return;
    }
    if (isExternalSource(row)) {
      context.say(
        '$key is set by ${row!.sourceName}; it cannot be changed here.',
      );
      return;
    }
    // Слой 3 (проектный `config.yaml`) не пишется (SETUP-3).
    final layer = local ? ConfigLayer.projectLocal : ConfigLayer.user;
    final base = snapshot.layers[layer];
    if (base == null) {
      context.say(
        'Cannot read the ${local ? 'local' : 'user'} config file; run '
        '"codelab config check".',
      );
      return;
    }
    final ConfigEdit edit;
    if (reset) {
      if (base.get(key) == null) {
        context.say('$key is not set in ${base.path}');
        return;
      }
      edit = UnsetValue(key);
    } else {
      try {
        edit = SetValue(
          key,
          SettingsRegistry.parseCliValue(descriptor, words.skip(1).join(' ')),
        );
      } on ConfigValueException catch (error) {
        // Значение в текст не попадает: оно могло быть секретом (CFG-10).
        context.say('$key: expected ${error.expected}');
        return;
      }
    }
    final outcome = await store.apply(base, [edit]);
    switch (outcome) {
      case ConfigSaved(:final restartRequiredKeys):
        final restart = restartRequiredKeys.contains(key)
            ? ' (applies after restart)'
            : '';
        context.say(
          reset
              ? 'Removed $key from ${base.path}$restart'
              : 'Updated $key in ${base.path}$restart',
        );
      case ConfigConflict():
        context.say('The config file changed; run the command again.');
      case ConfigRejected(:final issues):
        context.say('codelab: $key: ${issues.first.message}');
      case ConfigInlineSecret(:final suggestedSecretName):
        context.say('Use codelab secret set $suggestedSecretName');
    }
  }

  void _list(ReplContext context, AgentConfigSnapshot snapshot) {
    final rows = settingRowsOf(snapshot);
    context.pick(
      PickerSpec(
        title: 'Settings (key, value, source):',
        items: [
          for (final row in rows)
            PickerItem(
              label: '${row.key}  ${row.displayValue}  ${row.sourceName}',
              line: '/settings ${row.key}',
            ),
        ],
      ),
    );
  }

  void _values(
    ReplContext context,
    String key,
    SettingDescriptor descriptor,
    SettingFieldView? row,
  ) {
    final values = switch (descriptor.type) {
      SettingType.enumeration => descriptor.enumValues ?? const <String>[],
      SettingType.bool => const ['true', 'false'],
      _ => null,
    };
    if (values == null) {
      final expected = expectedFormatOf(descriptor);
      context.say(
        expected == null
            ? 'Set it with: /settings $key <value>'
            : '$key expects $expected. Set it with: /settings $key <value>',
      );
      return;
    }
    final current = row?.effectiveValue?.toString();
    context.pick(
      PickerSpec(
        title: '${descriptor.label} ($key):',
        items: [
          for (final value in values)
            PickerItem(label: value, line: '/settings $key $value'),
        ],
        current: current == null || !values.contains(current)
            ? null
            : values.indexOf(current),
      ),
    );
  }
}
