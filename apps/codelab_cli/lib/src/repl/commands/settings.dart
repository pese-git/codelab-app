import 'package:codelab_setup/codelab_setup.dart';

import '../../setup/settings_access.dart';
import '../../setup/settings_rows.dart';
import '../../setup/settings_screen.dart';
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
    if (access is! EditableSettings) {
      if (args.isEmpty) {
        // Список (и экран TUI) для чужого агента — только чтение.
        context.showSettings(SettingsScreen(access: access));
      } else {
        context.say(readOnlyLineOf(access)!);
      }
      return;
    }
    final editable = access;
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
      context.showSettings(
        SettingsScreen(
          access: editable,
          scope: scope,
          store: store,
          snapshot: snapshot,
        ),
      );
      return;
    }
    final key = words.first;
    // Отказ по самому ключу нужен и до пикера значений (он для таких ключей
    // не открывается); остальные проверки записи — источник, замаскированное
    // значение, слой — только в `applySetting` (D17), своей копии здесь нет.
    if (settingKeyRefusal(key) case final refusal?) {
      context.say(refusal);
      return;
    }
    final descriptor = editableDescriptorOf(key)!;
    if (words.length == 1 && !reset) {
      final row = settingRowsOf(
        snapshot,
      ).where((r) => r.key == key).firstOrNull;
      _values(context, key, descriptor, row);
      return;
    }
    // Слой 3 (проектный `config.yaml`) не пишется (SETUP-3).
    final layer = local ? ConfigLayer.projectLocal : ConfigLayer.user;
    context.say(
      await applySetting(
        store,
        snapshot,
        key,
        raw: reset ? null : words.skip(1).join(' '),
        layer: layer,
        access: editable,
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
