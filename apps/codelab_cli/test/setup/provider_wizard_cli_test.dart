// Построчный мастер провайдера CLI на фейковом терминале (задачи 4.0, 4.1
// change `add-provider-setup-ui`; spec codelab-cli «Подкоманды codelab
// provider и codelab mcp», «Ключ мастера не утекает»; design.md D7, D8,
// D15; артборд `CliSetup`).
//
// Ожидаемый API реализации (задача 4.5), см. отчёт:
//   lib/src/setup/provider_wizard.dart —
//     Future<ProviderWizardResult> runProviderWizard({
//       required ProviderSetupFlow flow,
//       required Terminal terminal,
//       String? providerId,
//       String Function(ConfigTarget target)? pathOf,
//     });
//     sealed class ProviderWizardResult;
//     final class ProviderWizardSaved { String providerId; }
//     final class ProviderWizardCancelled;
//
// Мастер сам владеет `Terminal.input` (подписка, raw-режим, `restore`), ведёт
// автомат `ProviderSetupFlow` и печатает вопросы в `Terminal.output`; запись
// и строка `Saved provider …` — на вызывающем.
//
// Порты — фейки (`test/support/setup_fakes.dart`); синхронизация — ожидание
// текста в выводе (`eventually`), без таймеров теста.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codelab_cli/src/setup/prompt_line.dart';
import 'package:codelab_cli/src/setup/provider_wizard.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import '../support/cli_process.dart' show appDirectory;
import '../support/fake_terminal.dart';
import '../support/setup_fakes.dart';

void main() {
  late FakeTerminal terminal;
  late FakeProviderCheck check;
  late FakeProviderKeys keys;
  late FakeConfigStore config;
  late RecordingLogger logger;

  setUp(() {
    terminal = FakeTerminal();
    check = FakeProviderCheck();
    keys = FakeProviderKeys();
    config = FakeConfigStore(snapshotValue: snapshotOf());
    logger = RecordingLogger();
  });

  Future<ProviderWizardResult> start({String? providerId}) {
    final result = runProviderWizard(
      flow: buildWizardFlow(
        check: check,
        keys: keys,
        config: config,
        logger: logger,
      ),
      terminal: terminal,
      providerId: providerId,
      pathOf: (_) => '/h/config.yaml',
    );
    return result;
  }

  Future<void> see(String text) => eventually(
    () => terminal.text.contains(text),
    reason: 'no "$text" in:\n${terminal.text}',
  );

  /// Выбирает пункт списка с номером [index] стрелками и Enter.
  void pick(int index) {
    for (var i = 0; i < index; i++) {
      terminal.press(keyDown);
    }
    terminal.press(keyEnter);
  }

  // Индексы пресетов в `ProviderPresets.all`.
  const anthropic = 1;
  const customOpenai = 4;

  group('артборд CliSetup с реальным бэкендом', () {
    test('вопросы и тексты шагов до сохранения; запись как у ядра', () async {
      final result = start();

      await see('? API type');
      for (final label in const [
        'OpenAI',
        'Anthropic',
        'OpenRouter',
        'Ollama (local, no key)',
        'Custom OpenAI-compatible endpoint',
        'Custom Anthropic-compatible endpoint',
      ]) {
        expect(terminal.text, contains(label));
      }
      expect(terminal.rawEnabled, isTrue);

      pick(anthropic);
      await see('? Base URL ›');
      await see('https://api.anthropic.com');
      terminal.press(keyEnter);

      await see('? API key source');
      expect(terminal.text, contains('Store in file as "codelab/anthropic"'));
      expect(
        terminal.text,
        contains('Read from environment variable (ANTHROPIC_API_KEY)'),
      );
      expect(terminal.text, contains('No key'));
      terminal.press(keyEnter);

      await see('? API key ›');
      terminal.type(leakMarker);
      terminal.press(keyEnter);

      await eventually(() => check.calls.isNotEmpty);
      await see('Checking https://api.anthropic.com/v1/models');
      expect(check.calls.single.kind, 'anthropic');
      expect(check.calls.single.key, leakMarker);
      check.respond(modelsOk(['claude-sonnet-5-5', 'claude-sonnet-4-5']));

      await see('ok, 2 models');
      await see('? Model (type to filter) ›');
      expect(terminal.text, contains('claude-sonnet-5-5'));
      expect(terminal.text, contains('claude-sonnet-4-5'));
      expect(terminal.text, contains('Enter model id manually'));
      terminal.press(keyEnter);

      await see('? Save? [Y/n]');
      expect(terminal.text, contains('Provider "anthropic"'));
      expect(terminal.text, contains('secret "codelab/anthropic" (file)'));
      expect(terminal.text, contains('anthropic/claude-sonnet-5-5'));
      expect(terminal.text, contains('/h/config.yaml'));
      terminal.press(keyEnter);

      final saved = await result;
      expect(saved, isA<ProviderWizardSaved>());
      expect((saved as ProviderWizardSaved).providerId, 'anthropic');
      expect(keys.written, {'codelab/anthropic': leakMarker});
      final edits = config.applied.single.edits;
      expect(config.applied.single.base.target, const ConfigTarget.user());
      expect(
        edits,
        containsAll(<ConfigEdit>[
          const SetValue('providers.anthropic.kind', 'anthropic'),
          const SetValue(
            'providers.anthropic.api_key_secret',
            'codelab/anthropic',
          ),
          const SetValue('agent.default_model', 'anthropic/claude-sonnet-5-5'),
        ]),
      );
      expect(terminal.rawEnabled, isFalse, reason: 'терминал восстановлен');
      expect(terminal.restoreCount, greaterThanOrEqualTo(1));
    });

    test(
      'Enter и y на «? Save? [Y/n]» сохраняют, n — выход без записи',
      () async {
        final result = start();
        await see('? API type');
        pick(customOpenai);
        await see('? Base URL ›');
        terminal.type('https://gw.example/v1');
        terminal.press(keyEnter);
        await see('? API key source');
        pick(2); // No key
        await eventually(() => check.calls.isNotEmpty);
        check.respond(modelsOk(['m1']));
        await see('? Model (type to filter) ›');
        terminal.press(keyEnter);
        await see('? Save? [Y/n]');

        terminal.type('n');
        terminal.press(keyEnter);

        expect(await result, isA<ProviderWizardCancelled>());
        expect(config.applied, isEmpty);
        expect(keys.written, isEmpty);
      },
    );

    test('позиционный id применяется на «Review» как ReviewEdited', () async {
      final result = start(providerId: 'gw');
      await see('? API type');
      pick(customOpenai);
      await see('? Base URL ›');
      terminal.type('https://gw.example/v1');
      terminal.press(keyEnter);
      await see('? API key source');
      pick(2);
      await eventually(() => check.calls.isNotEmpty);
      check.respond(modelsOk(['m1']));
      await see('? Model (type to filter) ›');
      terminal.press(keyEnter);
      await see('? Save? [Y/n]');
      expect(terminal.text, contains('Provider "gw"'));
      terminal.press(keyEnter);

      final saved = await result as ProviderWizardSaved;
      expect(saved.providerId, 'gw');
      expect(
        config.applied.single.edits,
        contains(const SetValue('providers.gw.kind', 'openai-compatible')),
      );
    });

    test('бэкенд только для чтения: варианта «Store…» нет, причина D3 '
        'печатается', () async {
      keys = FakeProviderKeys(
        backend: const SecretBackendInfo(
          id: 'env',
          writable: false,
          unavailableReason: 'no OS store',
        ),
        readOnlyHint: 'Secret store env is read-only. READONLY-HINT',
      );
      final result = start();
      await see('? API type');
      pick(customOpenai);
      await see('? Base URL ›');
      terminal.type('https://gw.example/v1');
      terminal.press(keyEnter);

      await see('? API key source');
      expect(terminal.text, contains('READONLY-HINT'));
      expect(terminal.text, isNot(contains('Store in')));
      expect(terminal.text, contains('No key'));

      terminal.press(keyCtrlC);
      expect(await result, isA<ProviderWizardCancelled>());
    });
  });

  group('скрытый ввод ключа (U-17)', () {
    /// Доводит мастер до `? API key ›` на Custom OpenAI-compatible.
    late Future<ProviderWizardResult> running;
    Future<void> toKeyField() async {
      running = start();
      await see('? API type');
      pick(customOpenai);
      await see('? Base URL ›');
      terminal.type('https://gw.example/v1');
      terminal.press(keyEnter);
      await see('? API key source');
      terminal.press(keyEnter); // Store in file as "codelab/gw-example"
      await see('? API key ›');
    }

    test('эхо — «*» по числу рун, значение не печатается', () async {
      await toKeyField();

      terminal.type(leakMarker);
      await see('*' * leakMarker.length);
      expect(terminal.text, isNot(contains(leakMarker)));
      expect(terminal.errorText, isNot(contains(leakMarker)));

      terminal.press(keyCtrlC);
      await running;
      expect(terminal.text, isNot(contains(leakMarker)));
    });

    test('руны, а не байты: «*» по числу символов', () async {
      await toKeyField();

      terminal.type('ключ🙂');
      await see('****');

      terminal.press(keyCtrlC);
      await running;
      expect(terminal.text, isNot(contains('ключ')));
    });

    test('Ctrl+R показывает значение и снова прячет его', () async {
      await toKeyField();
      terminal.type(leakMarker);
      await see('*' * leakMarker.length);

      var mark = terminal.text.length;
      terminal.press(keyCtrlR);
      await eventually(
        () => terminal.text.substring(mark).contains(leakMarker),
      );

      mark = terminal.text.length;
      terminal.press(keyCtrlR);
      await eventually(
        () => terminal.text.substring(mark).contains('*' * leakMarker.length),
      );
      expect(terminal.text.substring(mark), isNot(contains(leakMarker)));

      terminal.press(keyCtrlC);
      await running;
    });

    test(
      'Ctrl+U очищает поле: проверка получает только новое значение',
      () async {
        await toKeyField();
        terminal.type('wrong-value');
        await see('*' * 'wrong-value'.length);

        terminal.press(keyCtrlU);
        terminal.type(leakMarker);
        terminal.press(keyEnter);

        await eventually(() => check.calls.isNotEmpty);
        expect(check.calls.single.key, leakMarker);
        expect(terminal.text, isNot(contains('wrong-value')));
        expect(terminal.text, isNot(contains(leakMarker)));

        terminal.press(keyCtrlC);
        await running;
      },
    );

    test('пустой ключ — «Enter the API key.», поле остаётся', () async {
      await toKeyField();

      terminal.press(keyEnter);

      await see('Enter the API key.');
      expect(check.calls, isEmpty);

      terminal.press(keyCtrlC);
      await running;
    });
  });

  group('Ctrl+C (байт 0x03) → Cancel, без записи', () {
    Future<void> expectCancelled(Future<ProviderWizardResult> result) async {
      expect(await result, isA<ProviderWizardCancelled>());
      expect(config.applied, isEmpty);
      expect(keys.written, isEmpty);
      expect(terminal.rawEnabled, isFalse);
      expect(terminal.restoreCount, greaterThanOrEqualTo(1));
    }

    test('на выборе типа API', () async {
      final result = start();
      await see('? API type');

      terminal.press(keyCtrlC);

      await expectCancelled(result);
    });

    test('на адресе', () async {
      final result = start();
      await see('? API type');
      pick(customOpenai);
      await see('? Base URL ›');

      terminal.press(keyCtrlC);

      await expectCancelled(result);
    });

    test('на скрытом поле ключа, значение не записано', () async {
      final result = start();
      await see('? API type');
      pick(customOpenai);
      await see('? Base URL ›');
      terminal.type('https://gw.example/v1');
      terminal.press(keyEnter);
      await see('? API key source');
      terminal.press(keyEnter);
      await see('? API key ›');
      terminal.type(leakMarker);

      terminal.press(keyCtrlC);

      await expectCancelled(result);
      expect(terminal.text, isNot(contains(leakMarker)));
    });

    test('во время проверки /models', () async {
      final result = start();
      await see('? API type');
      pick(customOpenai);
      await see('? Base URL ›');
      terminal.type('https://gw.example/v1');
      terminal.press(keyEnter);
      await see('? API key source');
      pick(2);
      await eventually(() => check.calls.isNotEmpty);

      terminal.press(keyCtrlC);

      await expectCancelled(result);
    });
  });

  group('ревью 4a: вывод и ввод мастера', () {
    /// Доводит мастер до проверки на Custom OpenAI-compatible без ключа.
    Future<void> toCheck({String url = 'https://gw.example/v1'}) async {
      await see('? API type');
      pick(customOpenai);
      await see('? Base URL ›');
      terminal.type(url);
      terminal.press(keyEnter);
      await see('? API key source');
      pick(2);
      await eventually(() => check.calls.isNotEmpty);
    }

    test('управляющие последовательности из id модели не доходят до '
        'терминала', () async {
      final result = start();
      await toCheck();

      check.respond(modelsOk(['m\x1b]52;c;AAAA\x07']));

      await see('ok, 1 models');
      expect(terminal.text, isNot(contains('\x1b]')));
      expect(terminal.text, isNot(contains('\x07')));
      terminal.press(keyCtrlC);
      await result;
    });

    test('404: «Model list not found (404)»', () async {
      final result = start();
      await toCheck();

      check.respond(
        const CheckFailure(
          ProviderCheckFailure(
            kind: ProviderCheckFailureKind.notFound,
            statusCode: 404,
            message: 'nf',
          ),
        ),
      );

      await see('Model list not found (404)');
      terminal.press(keyCtrlC);
      await result;
    });

    test('окно контекста проверяет автомат: неверное значение — тот же шаг '
        'снова', () async {
      final result = start();
      await toCheck();
      check.respond(const CheckOk([RemoteModel('m1')]));
      await see('? Model (type to filter) ›');
      terminal.press(keyEnter);
      await see('? Context window for m1 (tokens) ›');

      terminal.press(keyCtrlU);
      terminal.type('abc');
      terminal.press(keyEnter);

      await eventually(
        () => '? Context window for m1'.allMatches(terminal.text).length >= 2,
        reason: terminal.text,
      );
      expect(terminal.text, isNot(contains('Enter a whole number')));
      terminal.press(keyCtrlC);
      await result;
    });

    test('сводка без query и userinfo адреса', () async {
      final result = start();
      await toCheck(url: 'https://gw.example/v1?token=$leakMarker');
      check.respond(modelsOk(['m1']));
      await see('? Model (type to filter) ›');
      terminal.press(keyEnter);
      await see('? Save? [Y/n]');

      // Поле адреса показывает набранное человеком; сводка и проверка — нет.
      final afterTyping = terminal.text.substring(
        terminal.text.indexOf('Checking'),
      );
      expect(afterTyping, contains('Provider "gw-example"'));
      expect(afterTyping, isNot(contains(leakMarker)));
      expect(afterTyping, isNot(contains('token=')));
      terminal.press(keyCtrlC);
      await result;
    });

    test('вставка нескольких строк в поле ключа отклоняется без цитирования '
        'и спрашивается снова (D14)', () async {
      final result = start();
      await see('? API type');
      pick(customOpenai);
      await see('? Base URL ›');
      terminal.type('https://gw.example/v1');
      terminal.press(keyEnter);
      await see('? API key source');
      terminal.press(keyEnter);
      await see('? API key ›');

      terminal.press(utf8.encode('${leakMarker}A\r${leakMarker}B\r'));
      await see(keyRejectedLine);

      expect(terminal.text, isNot(contains(leakMarker)));
      expect(check.calls, isEmpty);
      terminal.type(leakMarker);
      terminal.press(keyEnter);
      await eventually(() => check.calls.isNotEmpty);
      expect(check.calls.single.key, leakMarker);
      terminal.press(keyCtrlC);
      await result;
    });

    test('Ctrl+R у длинного ключа стирает все перенесённые строки', () async {
      final result = start();
      await see('? API type');
      pick(customOpenai);
      await see('? Base URL ›');
      terminal.type('https://gw.example/v1');
      terminal.press(keyEnter);
      await see('? API key source');
      terminal.press(keyEnter);
      await see('? API key ›');
      terminal.type('a' * 200);
      await see('*' * 200);

      terminal.press(keyCtrlR);
      await eventually(() => terminal.text.contains('a' * 200));
      final mark = terminal.text.length;
      terminal.press(keyCtrlR);
      await eventually(() => terminal.text.length > mark);

      // Префикс 12 + 200 символов при ширине 80 — три экранные строки.
      expect(terminal.text.substring(mark), startsWith('\x1b[2A\r\x1b[J'));
      terminal.press(keyCtrlC);
      await result;
    });

    test('конец ввода во время записи не бросает запись', () async {
      config.applyGate = Completer<void>();
      final result = start();
      await toCheck();
      check.respond(modelsOk(['m1']));
      await see('? Model (type to filter) ›');
      terminal.press(keyEnter);
      await see('? Save? [Y/n]');
      terminal.press(keyEnter);
      await eventually(() => config.applied.isNotEmpty);

      await terminal.closeInput();
      await pumpEventQueue();
      var done = false;
      unawaited(result.whenComplete(() => done = true));
      await pumpEventQueue();
      expect(done, isFalse, reason: 'мастер ждёт итога записи');

      config.applyGate!.complete();
      expect(await result, isA<ProviderWizardSaved>());
    });
  });

  group('адрес http://127.0.0.1 без подтверждения (задача 4.0, D7, D8)', () {
    test('локальный адрес не спрашивает подтверждение небезопасного '
        'http://', () async {
      final result = start();
      await see('? API type');
      pick(customOpenai);
      await see('? Base URL ›');

      terminal.type('http://127.0.0.1:18765/v1');
      terminal.press(keyEnter);

      // Подтверждение стоило бы шага: сразу идёт выбор источника ключа.
      await see('? API key source');
      expect(terminal.text, isNot(contains('unencrypted')));

      terminal.press(keyCtrlC);
      await result;
    });

    test('в monorepo одно определение isLocalHost — в kit', () {
      final root = Directory(appDirectory).parent.parent;
      final definition = RegExp(r'bool\s+isLocalHost\s*\(');
      // Рабочий код пакетов и приложений: `lib/` каждого.
      final libs = <Directory>[
        for (final app in Directory('${root.path}/apps').listSync())
          if (app is Directory) Directory('${app.path}/lib'),
        for (final area in Directory('${root.path}/packages').listSync())
          if (area is Directory)
            for (final package in area.listSync())
              if (package is Directory) Directory('${package.path}/lib'),
      ];
      final found = <String>[];
      for (final lib in libs.where((d) => d.existsSync())) {
        for (final entity in lib.listSync(recursive: true)) {
          if (entity is File &&
              entity.path.endsWith('.dart') &&
              definition.hasMatch(entity.readAsStringSync())) {
            found.add(entity.path.substring(root.path.length + 1));
          }
        }
      }

      expect(found, [
        'packages/dart/codelab_client_core/lib/src/connection/'
            'profile_draft.dart',
      ]);
    });
  });
}
