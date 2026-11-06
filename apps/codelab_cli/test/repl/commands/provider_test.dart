// `/provider add|list|remove` в REPL (задача 4.3 change
// `add-provider-setup-ui`; spec codelab-cli «Команды /provider и /settings в
// REPL и TUI», сценарии «/provider add во время хода», «Удалённый агент»;
// design.md D17, решение Q14).
//
// Ожидаемый API реализации (задача 4.7), см. отчёт:
//   lib/src/setup/setup_commands.dart — `SetupCommands`, `SetupCommandResult`;
//   `Repl(setup: SetupCommands?)`, `ReplContext.setup`;
//   lib/src/repl/commands/commands.dart — `replCommands` (= `mvpReplCommands`
//   + `/provider` + `/settings`; в TUI 4a остаётся `mvpReplCommands`).
//
// Порт `SetupCommands` — фейк (`test/support/setup_repl_harness.dart`).
// Мастер идёт на настоящем `ProviderSetupFlow` с фейковыми проверкой,
// ключами и конфигом. Ввод мастера идёт через подписку `Repl` на
// `Terminal.input`: `CountingTerminal` считает подписки.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile;
import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import '../../support/fake_terminal.dart';
import '../../support/setup_fakes.dart';
import '../../support/setup_repl_harness.dart';

void main() {
  late SetupReplHarness repl;
  var opened = false;

  Future<void> open({
    ConnectionProfile profile = editableProfile,
    bool hasTerminal = true,
  }) async {
    repl = SetupReplHarness(profile: profile, hasTerminal: hasTerminal);
    opened = true;
    await repl.start();
  }

  tearDown(() async {
    if (opened) {
      await repl.dispose();
    }
    opened = false;
  });

  /// Доводит мастер Custom OpenAI-compatible без ключа до `? Save? [Y/n]`.
  Future<void> toReview() async {
    repl.line('/provider add');
    await repl.waitAny('? API type');
    for (var i = 0; i < 4; i++) {
      repl.press(keyDown);
    }
    repl.press(keyEnter);
    await repl.waitAny('? Base URL ›');
    repl.type('https://gw.example/v1');
    repl.press(keyEnter);
    await repl.waitAny('? API key source');
    repl.press(keyDown);
    repl.press(keyDown);
    repl.press(keyEnter);
    await eventually(() => repl.check.calls.isNotEmpty);
    repl.check.respond(modelsOk(['m1']));
    await repl.waitAny('? Model (type to filter) ›');
    repl.press(keyEnter);
    await repl.waitAny('? Save? [Y/n]');
  }

  test('/provider и /settings есть в списке команд REPL, а в списке TUI '
      '(mvpReplCommands) их нет (D17)', () {
    expect(
      replCommands.map((c) => c.name),
      containsAll(['provider', 'settings']),
    );
    expect(
      replCommands.map((c) => c.name),
      containsAll(mvpReplCommands.map((c) => c.name)),
    );
    expect(mvpReplCommands.map((c) => c.name), isNot(contains('provider')));
    expect(mvpReplCommands.map((c) => c.name), isNot(contains('settings')));
  });

  group('list и remove печатают результат порта', () {
    setUp(() => open());

    test('/provider list', () async {
      repl.setup.listResult = const SetupCommandResult(
        exitCode: 0,
        stdout: ['Secrets: file', 'gw  openai-compatible  user'],
        stderr: ['note: from stderr'],
      );

      repl.line('/provider list');

      await repl.waitText('gw  openai-compatible  user');
      expect(repl.lastOutput, contains('Secrets: file'));
      expect(repl.lastOutput, contains('note: from stderr'));
      expect(repl.setup.listCalls, ['/work']);
    });

    test('/provider remove <id> идёт без --local по слою user', () async {
      repl.line('/provider remove gw');

      await repl.waitText('Removed providers.gw from /h/config.yaml');
      expect(repl.setup.removeCalls, [(id: 'gw', cwd: '/work', local: false)]);
    });

    test('/provider remove <id> --local', () async {
      repl.line('/provider remove gw --local');

      await repl.waitText('Removed providers.gw from /h/config.yaml');
      expect(repl.setup.removeCalls, [(id: 'gw', cwd: '/work', local: true)]);
    });

    test('ошибка порта печатается как есть, REPL жив', () async {
      repl.setup.removeResult = const SetupCommandResult(
        exitCode: 1,
        stderr: ['codelab: provider remove failed: unknown provider'],
      );

      repl.line('/provider remove nope');

      await repl.waitText('codelab: provider remove failed: unknown provider');
      expect(repl.exited, isFalse);
    });
  });

  group(
    'чьи настройки: resolveSettingsAccess профиля подключения (SETUP-2)',
    () {
      test('WebSocket-профиль: add и remove — строка только для чтения, порт '
          'не вызван', () async {
        await open(profile: remoteProfile);

        repl.line('/provider add');
        await repl.waitText(remoteReadOnlyText);
        repl.line('/provider remove gw');
        await repl.waitText(remoteReadOnlyText);

        expect(repl.setup.flowRequests, 0);
        expect(repl.setup.removeCalls, isEmpty);
        expect(repl.output, isNot(contains('? API type')));
        expect(repl.store.applied, isEmpty);
      });

      test('чужой stdio-агент: «managed by <имя>», порт не вызван', () async {
        await open(profile: foreignProfile);

        repl.line('/provider add');
        await repl.waitText('Provider settings are managed by agent.');
        repl.line('/provider remove gw');
        await repl.waitText('Provider settings are managed by agent.');

        expect(repl.setup.flowRequests, 0);
        expect(repl.setup.removeCalls, isEmpty);
      });
    },
  );

  group('/provider add: мастер в REPL', () {
    setUp(() => open());

    test('ввод идёт через подписку Repl: второй подписки на Terminal.input '
        'нет', () async {
      await toReview();

      expect(repl.counting.listens, 1);
      expect(repl.setup.flowRequests, 1);
      repl.press(keyEnter);
      await repl.waitAny('Saved provider');
      expect(repl.counting.listens, 1);
    });

    test('запись и строка успеха; клавиши мастера не попадают в строку '
        'ввода REPL', () async {
      await toReview();
      repl.press(keyEnter);

      await repl.waitAny(
        'Saved provider "gw-example". Models are available in /model.',
      );
      expect(repl.store.applied.single.base.target, const ConfigTarget.user());
      expect(
        repl.store.applied.single.edits,
        contains(
          const SetValue('providers.gw-example.kind', 'openai-compatible'),
        ),
      );
      expect(
        repl.sentMethods,
        isNot(contains(sessionPromptMethod)),
        reason: 'ввод мастера не стал промптом агенту',
      );
      expect(repl.exited, isFalse);
    });

    test('значение ключа в выводе REPL — только маска', () async {
      repl.line('/provider add');
      await repl.waitAny('? API type');
      for (var i = 0; i < 4; i++) {
        repl.press(keyDown);
      }
      repl.press(keyEnter);
      await repl.waitAny('? Base URL ›');
      repl.type('https://gw.example/v1');
      repl.press(keyEnter);
      await repl.waitAny('? API key source');
      repl.press(keyEnter); // Store in file
      await repl.waitAny('? API key ›');

      repl.type(leakMarker);

      await repl.waitAny('*' * leakMarker.length);
      expect(repl.output, isNot(contains(leakMarker)));
      repl.press(keyCtrlC);
      await repl.waitAny('Provider setup cancelled.');
      expect(repl.output, isNot(contains(leakMarker)));
    });

    test('Ctrl+C закрывает только мастер: «Provider setup cancelled.», '
        'REPL жив, выход двойным Ctrl+C мастером не засчитан', () async {
      repl.line('/provider add');
      await repl.waitAny('? API type');

      repl.press(keyCtrlC);

      await repl.waitAny('Provider setup cancelled.');
      expect(repl.exited, isFalse);
      expect(repl.store.applied, isEmpty);

      // Первый Ctrl+C уже «потрачен» на мастер, поэтому следующий — первый
      // для REPL, а не второй из пары выхода.
      repl.press(keyCtrlC);
      await repl.waitAny(pressCtrlCAgain);
      await pumpEventQueue();
      expect(repl.exited, isFalse);

      repl.line('/provider list');
      await repl.waitText('Secrets: file');
    });

    test('Esc закрывает только мастер', () async {
      repl.line('/provider add');
      await repl.waitAny('? API type');

      repl.press(keyEsc);

      await repl.waitAny('Provider setup cancelled.');
      expect(repl.exited, isFalse);
      expect(repl.store.applied, isEmpty);
    });

    test('в состоянии Saving Ctrl+C и Esc игнорируются', () async {
      await toReview();
      repl.store.applyGate = Completer<void>();

      repl.press(keyEnter);
      await eventually(() => repl.store.applied.isNotEmpty);
      repl.press(keyCtrlC);
      repl.press(const [0x1b, 0x1b]);
      await pumpEventQueue();

      repl.store.applyGate!.complete();
      await repl.waitAny('Saved provider "gw-example".');
      expect(repl.output, isNot(contains('Provider setup cancelled.')));
      expect(repl.store.applied, hasLength(1));
      expect(repl.exited, isFalse);
    });

    test('мастер не оставляет терминал в особом режиме: после записи REPL '
        'принимает команды', () async {
      await toReview();
      repl.press(keyEnter);
      await repl.waitAny('Saved provider');

      repl.line('/provider list');

      await repl.waitText('Secrets: file');
    });
  });

  group('/provider add отказывается, когда мастер невозможен (Q14)', () {
    test('во время хода: строка отказа, мастер не открыт, ход идёт', () async {
      await open();
      repl.line('hello');
      final prompt = await repl.agent.next(sessionPromptMethod);

      repl.line('/provider add');

      await repl.waitText(
        'Finish or cancel the current turn first (Ctrl+C), then run '
        '/provider add.',
      );
      expect(repl.setup.flowRequests, 0);
      expect(repl.output, isNot(contains('? API type')));
      expect(repl.exited, isFalse);

      repl.agent
        ..chunk('s1', 'done')
        ..respond(prompt, {'stopReason': 'end_turn'});
    });

    test('без терминала (построчный ввод): строка про флаги', () async {
      await open(hasTerminal: false);

      repl.terminal.type('/provider add\n');

      await eventually(
        () => repl.output.contains(
          '/provider add needs a terminal; run "codelab provider add" with '
          'flags instead.',
        ),
        reason: repl.output,
      );
      expect(repl.setup.flowRequests, 0);
      await repl.terminal.closeInput();
    });
  });
}
