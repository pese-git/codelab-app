// Фокус под модальным экраном и одобрения (задача 4.11 change
// `add-provider-setup-ui`; codelab-cli «Esc в мастере TUI не отменяет ход»,
// «Одобрение при открытом мастере»; codelab-tui «Одобрение в TUI», сценарий
// «Запрос при открытом мастере»; design.md D17, D21).
//
// API — как в `provider_wizard_overlay_test.dart` и `tui_overlay_test.dart`.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import '../../support/setup_fakes.dart' show snapshotOf;
import '../../support/tui_overlay_fixtures.dart';

const _pending = 'approval pending · esc to answer';

/// Мастер на шаге адреса (есть поле) при идущем ходе с запросом разрешения.
TuiModel _wizardWithApproval() =>
    openWizard(EnteringBaseUrl(draft), model: withApproval(newModel()));

TuiModel _settingsWithApproval() => reduce(
  withApproval(newModel()),
  OpenSettingsMsg(
    4,
    access: const EditableSettings(
      ConfigPaths(codelabHome: '/h', projectDir: '/work'),
    ),
    snapshot: snapshotOf(),
  ),
).$1;

void main() {
  group('мастер открыт, идёт ход', () {
    test('Enter не отправляет промпт и не отвечает на запрос', () {
      var model = _wizardWithApproval();
      model = model.copyWith(composer: model.composer.insert('hello'));

      final (next, cmds) = reduce(model, key(Key.enter));

      expect(cmds.whereType<SubmitCmd>(), isEmpty);
      expect(cmds.whereType<RespondCmd>(), isEmpty);
      expect(next.composer.text, 'hello');
    });

    test('y, n, a и N попадают в поле мастера и не отвечают на запрос', () {
      var model = _wizardWithApproval();
      final all = <TuiCmd>[];

      for (final char in ['y', 'n', 'a', 'N']) {
        final (next, cmds) = reduce(model, text(char));
        model = next;
        all.addAll(cmds);
      }

      expect(all.whereType<RespondCmd>(), isEmpty);
      expect(
        frameOf(model),
        contains('? Base URL › https://api.anthropic.comynaN'),
      );
    });

    test('Esc закрывает мастер (Cancel), а не отменяет ход', () {
      final (_, cmds) = reduce(_wizardWithApproval(), key(Key.escape));

      expect(cmds.whereType<CancelTurnCmd>(), isEmpty);
      expect(cmds.whereType<WizardEventCmd>().single.event, isA<Cancel>());
    });

    test('Ctrl+C закрывает мастер, а не отменяет ход и не выходит', () {
      final (_, cmds) = reduce(_wizardWithApproval(), key(Key.ctrlC));

      expect(cmds.whereType<CancelTurnCmd>(), isEmpty);
      expect(cmds.whereType<QuitCmd>(), isEmpty);
      expect(cmds.whereType<WizardEventCmd>().single.event, isA<Cancel>());
    });

    test(
      'Esc при пустой очереди, но идущем ходе без запроса — тоже Cancel',
      () {
        final running = reduce(
          newModel(),
          SessionViewMsg(
            const SessionView(revision: 1, status: SessionStatusView.running),
            at: t0,
          ),
        ).$1;
        final model = openWizard(presetsState(), model: running);

        final (_, cmds) = reduce(model, key(Key.escape));

        expect(cmds.whereType<CancelTurnCmd>(), isEmpty);
        expect(cmds.whereType<WizardEventCmd>(), hasLength(1));
      },
    );
  });

  group('строка статуса', () {
    test('ожидающее одобрение показано в последней строке кадра', () {
      final frame = frameOf(_wizardWithApproval());

      expect(frame.last, contains(_pending));
    });

    test('зона одобрения при открытом мастере не показана', () {
      final screen = screenOf(_wizardWithApproval());

      expect(screen, isNot(contains('[y] allow once')));
      expect(screen, isNot(contains('make test')));
    });

    test('без запроса строка не говорит об одобрении', () {
      expect(
        frameOf(openWizard(presetsState())).last,
        isNot(contains(_pending)),
      );
    });

    test('после закрытия мастера — зона одобрения с контекстом вызова', () {
      var model = _wizardWithApproval();

      model = reduce(model, const WizardStateMsg(1, Cancelled())).$1;

      final frame = frameOf(model);
      expect(model.overlay, isNull);
      expect(
        frame,
        contains(predicate<String>((l) => l.contains('make test'))),
      );
      expect(frame.any((l) => l.contains('[y] allow once')), isTrue);
      expect(frame.last, isNot(contains(_pending)));
    });

    test('после закрытия y отвечает allow_once', () {
      var model = _wizardWithApproval();
      model = reduce(model, text('y')).$1;
      model = reduce(model, const WizardStateMsg(1, Cancelled())).$1;

      final (_, cmds) = reduce(model, text('y'));

      expect(cmds, [
        const RespondCmd(
          ApprovalRequestId('a1'),
          PermissionOptionId('allow-once'),
        ),
      ]);
    });
  });

  group('экран настроек и одобрения', () {
    test('Esc закрывает экран и не отменяет ход', () {
      final (model, cmds) = reduce(_settingsWithApproval(), key(Key.escape));

      expect(model.overlay, isNull);
      expect(cmds.whereType<CancelTurnCmd>(), isEmpty);
    });

    test('y и n не отвечают на запрос', () {
      var model = _settingsWithApproval();
      final all = <TuiCmd>[];
      for (final char in ['y', 'n']) {
        final (next, cmds) = reduce(model, text(char));
        model = next;
        all.addAll(cmds);
      }

      expect(all.whereType<RespondCmd>(), isEmpty);
    });

    test('статус-строка показывает ожидающее одобрение', () {
      expect(frameOf(_settingsWithApproval()).last, contains(_pending));
    });
  });

  group('пикер не меняет поведения одобрения', () {
    test('при PickerOverlay y по-прежнему отвечает (клавиши — у адаптера)', () {
      final model = reduce(
        withApproval(newModel()),
        const OpenPickerMsg(
          PickerSpec(
            items: [PickerItem(label: 'x', line: '/x')],
          ),
        ),
      ).$1;

      final (_, cmds) = reduce(model, text('y'));

      expect(cmds.whereType<RespondCmd>(), hasLength(1));
    });
  });
}
