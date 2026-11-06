// Мастер провайдера как модальный экран ядра TUI (задача 4.10 change
// `add-provider-setup-ui`; codelab-cli «Команды /provider и /settings в REPL и
// TUI»; codelab-tui «Кадр TUI», сценарий «Маска ключа в кадре»; design.md
// D17, D21, D14).
//
// Ожидаемый API реализации (задача 4.14), см. отчёт:
//   tui_msg.dart — OpenWizardMsg(int id, ProviderSetupState state,
//     {String Function(ConfigTarget)? pathOf}); WizardStateMsg(int id,
//     ProviderSetupState state);
//   tui_cmd.dart — WizardEventCmd(ProviderSetupEvent event).
// Тексты шагов — из `wizardStepOf` (4.8a), своих текстов у оверлея нет:
// кадр содержит «? <заголовок>», варианты («  › » у выбранного), строки
// пояснений, поле «<приглашение><значение или маска>».

import 'dart:convert';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import '../../support/setup_fakes.dart' show leakMarker;
import '../../support/tui_overlay_fixtures.dart';

/// Единственная команда `WizardEventCmd` в [cmds] и её событие.
T eventOf<T extends ProviderSetupEvent>(List<TuiCmd> cmds) {
  final wizard = cmds.whereType<WizardEventCmd>().toList();
  expect(wizard, hasLength(1), reason: '$cmds');
  return wizard.single.event as T;
}

/// Открытый мастер на шаге ключа, выбран вариант «Store in file…», поле
/// открыто.
TuiModel keyField() {
  final model = openWizard(keyState());
  return reduce(model, key(Key.enter)).$1;
}

void main() {
  group('шаги CliSetup в кадре', () {
    test(
      'тип API: заголовок, пресеты, курсор; Down и Enter → PresetChosen',
      () {
        var model = openWizard(presetsState());
        final frame = frameOf(model);

        expect(frame, contains('? API type'));
        expect(frame, contains('  › OpenAI'));
        for (final preset in ProviderPresets.all) {
          expect(screenOf(model), contains(preset.label));
        }

        model = reduce(model, key(Key.down)).$1;
        expect(frameOf(model), contains('  › Anthropic'));

        final (_, cmds) = reduce(model, key(Key.enter));
        expect(eventOf<PresetChosen>(cmds).presetId, 'anthropic');
      },
    );

    test('адрес: поле с начальным значением; Enter → BaseUrlSubmitted', () {
      var model = openWizard(EnteringBaseUrl(draft));

      expect(
        frameOf(model),
        contains('? Base URL › https://api.anthropic.com'),
      );

      final (_, cmds) = reduce(model, key(Key.enter));
      expect(eventOf<BaseUrlSubmitted>(cmds).text, 'https://api.anthropic.com');

      model = reduce(model, text('/v1')).$1;
      expect(
        eventOf<BaseUrlSubmitted>(reduce(model, key(Key.enter)).$2).text,
        'https://api.anthropic.com/v1',
      );
    });

    test('ошибка шага — строка перед полем', () {
      final model = openWizard(
        EnteringBaseUrl(draft, error: 'Enter an http or https address.'),
      );

      expect(frameOf(model), contains('  Enter an http or https address.'));
    });

    test('источник ключа: Store…, переменная, No key', () {
      final frame = frameOf(openWizard(keyState()));

      expect(frame, contains('? API key source'));
      expect(frame, contains('  › Store in file as "codelab/anthropic"'));
      expect(
        frame,
        contains('    Read from environment variable (ANTHROPIC_API_KEY)'),
      );
      expect(frame, contains('    No key'));
    });

    test('бэкенд только для чтения: варианта «Store…» нет, причина есть', () {
      final model = openWizard(
        keyState(writable: false, hint: 'READONLY-HINT'),
      );

      expect(screenOf(model), contains('READONLY-HINT'));
      expect(screenOf(model), isNot(contains('Store in')));
    });

    test('«No key» → KeySubmitted(NoKey)', () {
      var model = openWizard(keyState());
      model = reduce(model, key(Key.down)).$1;
      model = reduce(model, key(Key.down)).$1;

      final (_, cmds) = reduce(model, key(Key.enter));

      expect(eventOf<KeySubmitted>(cmds).choice, isA<NoKey>());
    });

    test('проверка: строка прогресса; отказ — заголовок и варианты', () {
      var model = openWizard(
        Checking(draft, Uri.parse('https://api.anthropic.com/v1/models'), 1),
      );
      expect(
        screenOf(model),
        contains('Checking https://api.anthropic.com/v1/models'),
      );

      model = reduce(
        model,
        WizardStateMsg(
          1,
          CheckFailed(
            draft,
            const ProviderCheckFailure(
              kind: ProviderCheckFailureKind.unauthorized,
              statusCode: 401,
              message: 'x',
            ),
            Uri.parse('https://api.anthropic.com/v1/models'),
            Duration.zero,
            canSkip: false,
            canUseV1: false,
          ),
        ),
      ).$1;
      expect(frameOf(model), contains('failed: Key rejected (401)'));
      expect(frameOf(model), contains('  › Retry'));
      expect(
        eventOf<RetryCheck>(reduce(model, key(Key.enter)).$2),
        isA<RetryCheck>(),
      );
    });

    test('сводка и «? Save? [Y/n]»; Enter → ConfirmSave, n → Cancel', () {
      var model = openWizard(Reviewing(plan(), const []));
      final frame = frameOf(model);

      expect(frame, contains('Provider "anthropic"'));
      expect(frame, contains('  model  anthropic/claude-sonnet-5-5 (default)'));
      expect(frame, contains('  file   /h/config.yaml'));
      expect(frame, contains('? Save? [Y/n] '));
      expect(
        eventOf<ConfirmSave>(reduce(model, key(Key.enter)).$2),
        isA<ConfirmSave>(),
      );

      model = reduce(model, text('n')).$1;
      expect(eventOf<Cancel>(reduce(model, key(Key.enter)).$2), isA<Cancel>());
    });
  });

  group('чужой номер оверлея', () {
    test('WizardStateMsg с другим id не меняет модель', () {
      final model = openWizard(presetsState(), id: 1);

      final (next, cmds) = reduce(
        model,
        WizardStateMsg(2, EnteringBaseUrl(draft)),
      );

      expect(cmds, isEmpty);
      expect(frameOf(next), frameOf(model));
      expect((next.overlay as ProviderWizardOverlay).id, 1);
    });

    test('WizardStateMsg без открытого мастера игнорируется', () {
      final (next, cmds) = reduce(
        newModel(),
        WizardStateMsg(1, presetsState()),
      );

      expect(next.overlay, isNull);
      expect(cmds, isEmpty);
    });

    test('Done и Cancelled закрывают оверлей', () {
      for (final done in [
        const Cancelled(),
        Done(
          plan(),
          const ProviderCommitted(
            saved: ConfigSaved(
              fingerprint: 'f',
              warnings: [],
              restartRequiredKeys: [],
            ),
            keyReplaced: false,
          ),
        ),
      ]) {
        final model = openWizard(presetsState());

        expect(reduce(model, WizardStateMsg(1, done)).$1.overlay, isNull);
      }
    });
  });

  group('скрытое поле ключа (U-17, D14)', () {
    test('выбор «Store…» открывает поле «? API key › »', () {
      final model = keyField();

      expect(frameOf(model), contains('? API key › '));
    });

    test('маска «*» по числу рун, значения в кадре нет', () {
      final model = reduce(keyField(), text(leakMarker)).$1;

      expect(
        frameOf(model),
        contains('? API key › ${'*' * leakMarker.length}'),
      );
      expect(screenOf(model), isNot(contains(leakMarker)));
      expect(model.composer.text, isEmpty);
      expect(model.composer.history.join(), isNot(contains(leakMarker)));
    });

    test('Ctrl+R показывает значение, второй раз — снова маска', () {
      var model = reduce(keyField(), text(leakMarker)).$1;

      model = reduce(model, key(Key.ctrlR)).$1;
      expect(frameOf(model), contains('? API key › $leakMarker'));

      model = reduce(model, key(Key.ctrlR)).$1;
      expect(screenOf(model), isNot(contains(leakMarker)));
      expect(
        frameOf(model),
        contains('? API key › ${'*' * leakMarker.length}'),
      );
    });

    test('Ctrl+U очищает поле, Backspace стирает руну', () {
      var model = reduce(keyField(), text('abc')).$1;
      model = reduce(model, key(Key.backspace)).$1;
      expect(frameOf(model), contains('? API key › **'));

      model = reduce(model, key(Key.ctrlU)).$1;
      expect(frameOf(model).where((l) => l.contains('*')), isEmpty);
    });

    test('пустое значение: Reask — «Enter the API key.», события нет', () {
      final (model, cmds) = reduce(keyField(), key(Key.enter));

      expect(cmds.whereType<WizardEventCmd>(), isEmpty);
      expect(frameOf(model), contains('Enter the API key.'));
    });

    test('Enter → KeySubmitted(StoreSecret), буфер очищен в той же reduce', () {
      final model = reduce(keyField(), text(leakMarker)).$1;

      final (next, cmds) = reduce(model, key(Key.enter));

      final submitted = eventOf<KeySubmitted>(cmds);
      expect((submitted.choice as StoreSecret).value.reveal(), leakMarker);
      expect(screenOf(next), isNot(contains(leakMarker)));
      expect(frameOf(next).where((l) => l.contains('*')), isEmpty);
      expect(next.composer.history.join(), isNot(contains(leakMarker)));
    });

    test('Cancel (Esc) очищает буфер', () {
      final model = reduce(keyField(), text(leakMarker)).$1;

      final (next, cmds) = reduce(model, key(Key.escape));

      expect(eventOf<Cancel>(cmds), isA<Cancel>());
      expect(screenOf(next), isNot(contains(leakMarker)));
      expect(frameOf(next).where((l) => l.contains('*')), isEmpty);
    });

    test('закрытие оверлея (Cancelled) не оставляет значения', () {
      var model = reduce(keyField(), text(leakMarker)).$1;

      model = reduce(model, const WizardStateMsg(1, Cancelled())).$1;

      expect(model.overlay, isNull);
      expect(screenOf(model), isNot(contains(leakMarker)));
    });

    test('переход в Checking сбрасывает поле', () {
      var model = reduce(keyField(), text(leakMarker)).$1;

      model = reduce(
        model,
        WizardStateMsg(
          1,
          Checking(draft, Uri.parse('https://api.anthropic.com/v1/models'), 1),
        ),
      ).$1;

      expect(screenOf(model), isNot(contains(leakMarker)));
    });

    test('вставка (PasteMsg) идёт в поле, а не в композер', () {
      final (model, _) = reduce(keyField(), PasteMsg(leakMarker));

      expect(
        frameOf(model),
        contains('? API key › ${'*' * leakMarker.length}'),
      );
      expect(model.composer.text, isEmpty);
    });

    test('вставка в обычное поле (адрес) идёт в поле', () {
      final model = openWizard(EnteringBaseUrl(draft));

      final (next, _) = reduce(model, const PasteMsg('/v1'));

      expect(
        frameOf(next),
        contains('? Base URL › https://api.anthropic.com/v1'),
      );
    });

    test('многострочная вставка: keyRejectedLine без значения, поле пусто', () {
      final (model, cmds) = reduce(
        keyField(),
        PasteMsg('${leakMarker}A\n${leakMarker}B'),
      );

      expect(cmds, isEmpty);
      expect(frameOf(model), contains(keyRejectedLine));
      expect(screenOf(model), isNot(contains(leakMarker)));
      expect(model.composer.text, isEmpty);
    });

    test('значение длиннее maxKeyBytes отклоняется', () {
      final (model, _) = reduce(keyField(), PasteMsg('a' * (maxKeyBytes + 1)));

      expect(frameOf(model), contains(keyRejectedLine));
      expect(frameOf(model).where((l) => l.contains('***')), isEmpty);
    });

    test('перевод строки с клавиатуры (Ctrl+J) в поле ключа отклоняется', () {
      final model = reduce(keyField(), text('abc')).$1;

      final (next, _) = reduce(model, key(Key.ctrlJ));

      expect(frameOf(next), contains(keyRejectedLine));
    });
  });

  group('маркер не утекает никуда', () {
    test('ни в кадре, ни в истории композера, ни в статус-строке по шагам', () {
      var model = reduce(keyField(), text(leakMarker)).$1;
      model = reduce(model, key(Key.ctrlR)).$1;
      model = reduce(model, key(Key.ctrlR)).$1;
      expect(screenOf(model), isNot(contains(leakMarker)));
      expect(frameOf(model).last, isNot(contains(leakMarker)));

      final (submitted, _) = reduce(model, key(Key.enter));
      expect(screenOf(submitted), isNot(contains(leakMarker)));
      expect(submitted.composer.history, isEmpty);
      expect(
        submitted.notes.map((n) => n.text).join(),
        isNot(contains(leakMarker)),
      );
      expect(jsonEncode(frameOf(submitted)), isNot(contains(leakMarker)));
    });
  });

  group('запись блокирует Esc (D21)', () {
    test('Saving: Esc и Ctrl+C ничего не делают, оверлей остаётся', () {
      final model = openWizard(Saving(plan()));

      for (final k in [Key.escape, Key.ctrlC]) {
        final (next, cmds) = reduce(model, key(k));

        expect(cmds, isEmpty, reason: '$k');
        expect(next.overlay, isA<ProviderWizardOverlay>());
      }
      expect(screenOf(model), contains('Saving…'));
    });
  });

  group('выбор модели: фильтр и ручной ввод', () {
    TuiModel models() => openWizard(
      modelsState(['claude-sonnet-5-5', 'claude-sonnet-4-5', 'gpt-5']),
    );

    test('заголовок, все модели и пункт ручного ввода', () {
      final model = models();

      expect(frameOf(model), contains('? Model (type to filter) › '));
      for (final id in ['claude-sonnet-5-5', 'claude-sonnet-4-5', 'gpt-5']) {
        expect(screenOf(model), contains(id));
      }
      expect(screenOf(model), contains('Enter model id manually'));
    });

    test('ввод фильтрует по подстроке, Enter выбирает первую найденную', () {
      final model = reduce(models(), text('son')).$1;

      expect(screenOf(model), contains('claude-sonnet-5-5'));
      expect(screenOf(model), isNot(contains('gpt-5')));
      expect(screenOf(model), contains('Enter model id manually'));

      final (_, cmds) = reduce(model, key(Key.enter));
      expect(eventOf<ModelChosen>(cmds).modelId, 'claude-sonnet-5-5');
    });

    test('стрелка вниз выбирает следующую модель', () {
      final model = reduce(models(), key(Key.down)).$1;

      expect(
        eventOf<ModelChosen>(reduce(model, key(Key.enter)).$2).modelId,
        'claude-sonnet-4-5',
      );
    });

    test(
      '«Enter model id manually» открывает поле id → ModelEnteredManually',
      () {
        var model = reduce(models(), text('zzz')).$1;

        model = reduce(model, key(Key.enter)).$1;
        expect(frameOf(model), contains('? Model id › '));

        model = reduce(model, text('my-model')).$1;
        final (_, cmds) = reduce(model, key(Key.enter));
        expect(eventOf<ModelEnteredManually>(cmds).modelId, 'my-model');
      },
    );
  });
}
