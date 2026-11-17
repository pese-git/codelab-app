// `TuiModel.overlay` — закрытая иерархия оверлеев (задача 4.9 change
// `add-provider-setup-ui`; spec codelab-tui «Кадр TUI», «Команды и пикеры
// TUI»; design.md D17, «Сверка с кодом (подготовка итерации 4b)»).
//
// Ожидаемый API реализации (задача 4.14), см. отчёт:
//   lib/src/tui/core/tui_overlay.dart —
//     sealed class TuiOverlay;
//     final class PickerOverlay { PickerSpec spec; }
//     final class ProviderWizardOverlay { int id; }
//     final class SettingsOverlay { int id; }
//   TuiModel.overlay: TuiOverlay?;
//   tui_msg.dart — OpenWizardMsg(int id, ProviderSetupState state,
//     {String Function(ConfigTarget)? pathOf}),
//     OpenSettingsMsg(int id, {required SettingsAccess access,
//     AgentConfigSnapshot? snapshot});
//   replCommands экспортируется барелем (список команд TUI после 4.15).
//
// Ядро тестируется без `dart_tui` и `dart:io` (TUI-5).

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import '../../support/setup_fakes.dart' show snapshotOf;
import '../../support/tui_overlay_fixtures.dart';

const _spec = PickerSpec(
  title: 'Model (model):',
  items: [
    PickerItem(label: 'm1  Model 1', line: '/model m1'),
    PickerItem(label: 'm2  Model 2', line: '/model m2'),
  ],
);

TuiModel _settings(TuiModel model) => reduce(
  model,
  OpenSettingsMsg(
    7,
    access: const EditableSettings(
      ConfigPaths(codelabHome: '/h', projectDir: '/work'),
    ),
    snapshot: snapshotOf(),
  ),
).$1;

void main() {
  group('TuiOverlay — закрытая иерархия', () {
    test('нет оверлея → null', () {
      expect(newModel().overlay, isNull);
    });

    test('OpenPickerMsg → PickerOverlay с тем же PickerSpec', () {
      final (model, _) = reduce(newModel(), const OpenPickerMsg(_spec));

      expect(
        model.overlay,
        isA<PickerOverlay>().having((o) => o.spec, 'spec', _spec),
      );
    });

    test('OpenWizardMsg → ProviderWizardOverlay с номером', () {
      final model = openWizard(presetsState(), id: 3);

      expect(
        model.overlay,
        isA<ProviderWizardOverlay>().having((o) => o.id, 'id', 3),
      );
    });

    test('OpenSettingsMsg → SettingsOverlay с номером', () {
      expect(
        _settings(newModel()).overlay,
        isA<SettingsOverlay>().having((o) => o.id, 'id', 7),
      );
    });

    test('все три вида разбираются исчерпывающим switch', () {
      String name(TuiOverlay overlay) => switch (overlay) {
        PickerOverlay() => 'picker',
        ProviderWizardOverlay() => 'wizard',
        SettingsOverlay() => 'settings',
      };

      expect(
        name(reduce(newModel(), const OpenPickerMsg(_spec)).$1.overlay!),
        'picker',
      );
      expect(name(openWizard(presetsState()).overlay!), 'wizard');
      expect(name(_settings(newModel()).overlay!), 'settings');
    });

    test('пустой пикер не открывается, PickerClosedMsg закрывает', () {
      final (empty, _) = reduce(
        newModel(),
        const OpenPickerMsg(PickerSpec(items: [])),
      );
      expect(empty.overlay, isNull);

      final (opened, _) = reduce(newModel(), const OpenPickerMsg(_spec));
      expect(reduce(opened, const PickerClosedMsg()).$1.overlay, isNull);
    });

    test('PickerChosenMsg по-прежнему запускает команду пункта', () {
      final (opened, _) = reduce(newModel(), const OpenPickerMsg(_spec));

      final (model, cmds) = reduce(opened, const PickerChosenMsg(1));

      expect(model.overlay, isNull);
      expect(cmds, [const RunCommandCmd('/model m2')]);
    });
  });

  group('клавиши: пикер у адаптера, мастер и настройки — в reduce', () {
    test('при PickerOverlay KeyMsg идёт в композер, как раньше', () {
      final (opened, _) = reduce(newModel(), const OpenPickerMsg(_spec));

      final (model, cmds) = reduce(opened, text('x'));

      expect(model.composer.text, 'x');
      expect(cmds, isEmpty);
    });

    test('при ProviderWizardOverlay композер и Enter не получают клавиш', () {
      var model = newModel();
      model = reduce(model, text('hello')).$1;
      model = openWizard(presetsState(), model: model);

      final (next, cmds) = reduce(model, key(Key.enter));

      expect(cmds.whereType<SubmitCmd>(), isEmpty);
      expect(next.composer.text, 'hello');
    });

    test('при SettingsOverlay композер и Enter не получают клавиш', () {
      var model = newModel();
      model = reduce(model, text('hello')).$1;
      model = _settings(model);

      final (next, cmds) = reduce(model, key(Key.enter));

      expect(cmds.whereType<SubmitCmd>(), isEmpty);
      expect(next.composer.text, 'hello');
    });

    test('вставка при оверлее мастера не уходит в композер', () {
      final model = openWizard(presetsState());

      final (next, _) = reduce(model, const PasteMsg('pasted'));

      expect(next.composer.text, isEmpty);
    });
  });

  group('кадр', () {
    test('строка подсказок скрыта при любом оверлее', () {
      final base = frameOf(newModel());
      expect(base, contains('Enter send · Shift+Enter new line'));

      final (picker, _) = reduce(newModel(), const OpenPickerMsg(_spec));
      for (final model in [
        picker,
        openWizard(presetsState()),
        _settings(newModel()),
      ]) {
        expect(
          frameOf(model),
          isNot(contains('Enter send · Shift+Enter new line')),
          reason: '${model.overlay.runtimeType}',
        );
      }
    });

    test('модальный экран заменяет композер, статус-строка — последняя', () {
      for (final model in [openWizard(presetsState()), _settings(newModel())]) {
        final frame = frameOf(model);

        expect(frame, hasLength(30));
        expect(frame.last, 'default');
        expect(
          frame.where((l) => l.startsWith('> ')),
          isEmpty,
          reason: 'композера нет',
        );
      }
    });

    test('каждая строка кадра не шире терминала', () {
      final model = openWizard(presetsState(), model: newModel(columns: 40));

      for (final line in frameOf(model)) {
        expect(displayWidth(line), lessThanOrEqualTo(40), reason: line);
      }
    });
  });
}
