// PTY-e2e мастера провайдера и экрана `/settings` в `--ui tui` (задача 4.13
// change `add-provider-setup-ui`; spec codelab-cli «Команды /provider и
// /settings в REPL и TUI», сценарии «Мастер в TUI», «Экран настроек в TUI»,
// «Одобрение при открытом мастере»; codelab-tui «Кадр TUI»; design.md D17).
//
// Только Dart VM. Временные `CODELAB_HOME` и `HOME`, хранилище секретов —
// `secrets.backend: file` во временном доме (настоящие keychain и
// `~/.codelab` не читаются), ответы `/models` даёт фиктивный сервер на петле.
// Маркер утечки — `sk-test-leak-0123456789`: ни в экране PTY на каждом шаге,
// ни в `cli_history`, ни в журнале `--verbose` (он идёт в тот же PTY), ни в
// `config.yaml`.
//
// PTY не отвечает на запросы терминала, поэтому TUI идёт без synchronized
// output и kitty (как `tui_smoke_test.dart`). Экран перерисовывается целиком,
// и ожидания идут по тексту, который кадр хранит строкой.
@Timeout(Duration(seconds: 60))
library;

import 'dart:convert';
import 'dart:io';

import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import '../support/cli_process.dart';
import '../support/fake_models_server.dart';
import '../support/setup_fakes.dart' show leakMarker, snapshotOf;
import 'support/e2e_agent.dart' show scriptedOnly;
import 'support/pty_process.dart';

const _altScreen = '\x1b[?1049h';
const _down = '\x1b[B';
const _left = '\x1b[D';
const _ctrlD = '\x04';
const _esc = '\x1b';

void main() async {
  final skip = await PtyProcess.unavailableReason();
  late Directory dir;
  late String home;
  late String project;

  test('kernel сборки CLI готовы', () async {
    await CliProcess.kernelOf(CliEntry.production);
    await CliProcess.kernelOf(CliEntry.scriptedEmbedded);
  }, timeout: const Timeout(Duration(seconds: 240)));

  setUp(() {
    dir = Directory(
      Directory.systemTemp
          .createTempSync('cli_tui_setup_')
          .resolveSymbolicLinksSync(),
    );
    home = '${dir.path}/codelab';
    project = '${dir.path}/project';
    Directory(home).createSync();
    Directory(project).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// Конфиг с готовым провайдером `gw`: первый запуск не срабатывает.
  void writeConfig(String baseUrl, {String extra = ''}) =>
      File('$home/config.yaml').writeAsStringSync('''
providers:
  gw:
    kind: openai-compatible
    base_url: $baseUrl
    models:
      m1:
        context_window: 8000
agent:
  default_model: gw/m1
secrets:
  backend: file
$extra''');

  String config() => File('$home/config.yaml').readAsStringSync();

  Future<PtyProcess> tui(
    List<String> args, {
    CliEntry entry = CliEntry.production,
    Map<String, String> environment = const {},
  }) async => PtyProcess.start(
    dartExecutable(),
    [await CliProcess.kernelOf(entry), '-C', project, '--ui', 'tui', ...args],
    columns: 120,
    rows: 40,
    environment: {
      'HOME': '${dir.path}/no-home',
      'CODELAB_HOME': home,
      'LANG': 'en_US.UTF-8',
      ...environment,
    },
  );

  void pick(PtyProcess p, int index) {
    for (var i = 0; i < index; i++) {
      p.write(_down);
    }
    p.write('\r');
  }

  void expectNoLeak(PtyProcess p, {String step = ''}) {
    expect(p.text, isNot(contains(leakMarker)), reason: 'экран PTY: $step');
  }

  test(
    'cli/tui-provider-wizard: «Мастер в TUI» — маска, Ctrl+R, ключ только в '
    'хранилище',
    () async {
      final server = await FakeModelsServer.start();
      writeConfig(server.baseUrl);

      final p = await tui(['--verbose']);
      await p.waitFor(_altScreen);
      p.write('/provider add\r');
      await p.waitFor('? API type');
      pick(p, 4); // Custom OpenAI-compatible endpoint
      await p.waitFor('? Base URL ›');
      p.write('${server.baseUrl}\r');
      await p.waitFor('? API key source');
      p.write('\r'); // Store in file as "codelab/local-<port>"
      await p.waitFor('? API key ›');

      p.write(leakMarker);
      await p.waitFor('*' * leakMarker.length);
      expectNoLeak(p, step: 'ввод ключа');
      var hiddenAt = 0;
      p.write('\x12'); // Ctrl+R показывает значение
      await p.waitFor(leakMarker);
      final beforeHide = p.text.length;
      p.write('\x12'); // и снова прячет
      // Ждём маску на экране вместо паузы: перерисовка пришла.
      await p.waitFor(
        '? API key › ${'*' * leakMarker.length}',
        from: beforeHide,
      );
      hiddenAt = p.text.length;
      p.write('\r');
      await p.waitFor('Checking ${server.origin}/v1/models');
      await p.waitFor('? Model (type to filter) ›');
      p.write('\r');
      await p.waitFor('? Save? [Y/n]');
      p.write('\r');
      await p.waitFor(
        'Saved provider "local-${server.port}". Restart codelab to use its '
        'models.',
      );

      p.write(_ctrlD);

      expect(await p.exitCode, 0, reason: p.text);
      // Значение видно только между двумя Ctrl+R: после второго — маска.
      expect(
        p.text.substring(hiddenAt),
        isNot(contains(leakMarker)),
        reason: 'после повторного Ctrl+R и до конца экрана только маска',
      );
      expect(
        config(),
        contains('api_key_secret: codelab/local-${server.port}'),
      );
      expect(config(), isNot(contains(leakMarker)));
      expect(File('$home/secrets.yaml').existsSync(), isTrue);
      final history = File('$home/cli_history');
      if (history.existsSync()) {
        expect(history.readAsStringSync(), isNot(contains(leakMarker)));
      }
      expect(server.requests.first.authorization, 'Bearer $leakMarker');
    },
    skip: skip,
    tags: scriptedOnly,
  );

  test(
    'cli/tui-provider-wizard-model: новая модель провайдера появляется в '
    'списке моделей без перезапуска',
    () async {
      final server = await FakeModelsServer.start();
      writeConfig(server.baseUrl);

      final p = await tui(const []);
      await p.waitFor(_altScreen);
      p.write('/provider add\r');
      await p.waitFor('? API type');
      pick(p, 4);
      await p.waitFor('? Base URL ›');
      p.write('${server.baseUrl}\r');
      await p.waitFor('? API key source');
      pick(p, 2); // No key
      await p.waitFor('? Model (type to filter) ›');
      p.write('\r');
      await p.waitFor('? Save? [Y/n]');
      p.write('\r');
      await p.waitFor(
        'Saved provider "local-${server.port}". Models are available in /model.',
      );

      // Агент перечитывает конфиг сам: ждём, пока `/config` (без пикера, в
      // транскрипт) назовёт новую модель среди значений опции `model`.
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      var shown = false;
      while (!shown && DateTime.now().isBefore(deadline)) {
        final from = p.text.length;
        p.write('/config\r');
        await Future<void>.delayed(const Duration(milliseconds: 500));
        shown = p.text.substring(from).contains('local-${server.port}/m1');
      }
      expect(shown, isTrue, reason: p.text);
      p.write(_ctrlD);

      expect(await p.exitCode, 0, reason: p.text);
    },
    skip: skip,
    tags: scriptedOnly,
  );

  test(
    'cli/tui-settings: «Экран настроек в TUI» — ключ реестра меняется, '
    'пометка о перезапуске',
    () async {
      final server = await FakeModelsServer.start();
      writeConfig(server.baseUrl, extra: 'permissions:\n  mode: standard\n');
      // Раздел и строка `permissions.mode` — по порядку реестра.
      final rows = settingFieldsOf(
        snapshotOf(
          user: {
            'providers': {
              'gw': {
                'kind': 'openai-compatible',
                'models': {
                  'm1': {'context_window': 8000},
                },
              },
            },
          },
        ),
      );
      final sections = <String>[];
      for (final row in rows) {
        if (!sections.contains(row.descriptor.section)) {
          sections.add(row.descriptor.section);
        }
      }
      final tabs = sections.indexOf('Permissions');
      final downs = [
        for (final r in rows)
          if (r.descriptor.section == 'Permissions') r.key,
      ].indexOf('permissions.mode');

      final p = await tui(const []);
      await p.waitFor(_altScreen);
      p.write('/settings\r');
      await p.waitFor('Settings · /settings');
      // Заголовок режется по ширине экрана (длинный временный путь).
      await p.waitFor('user $home/config');
      for (var i = 0; i < tabs; i++) {
        p.write('\t');
      }
      await p.waitFor('› Permissions');
      for (var i = 0; i < downs; i++) {
        p.write(_down);
      }
      await p.waitFor('› permissions.mode');
      p.write('\r'); // выбор ←→
      p.write(_left); // standard → ask
      p.write('\r');
      // Строка исхода переносится по ширине экрана: ждём её части.
      await p.waitFor('Updated permissions.mode in');
      await p.waitFor('(applies after restart)');

      p.write(_esc);
      // Одиночный Esc терминал отличает от начала последовательности по паузе.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      p.write(_ctrlD);
      expect(await p.exitCode, 0, reason: p.text);
      expect(config(), contains('mode: ask'));
      for (final absent in ['Display', 'Input', 'Updates']) {
        expect(p.text, isNot(contains(absent)));
      }
    },
    skip: skip,
    tags: scriptedOnly,
  );

  test(
    'cli/tui-wizard-approval: запрос разрешения при открытом мастере не '
    'отвечается его клавишами',
    () async {
      final server = await FakeModelsServer.start();
      writeConfig(server.baseUrl);
      // Модель медлит 5 с: мастер успевает открыться до запроса разрешения.
      final script = File('${dir.path}/script.json')
        ..writeAsStringSync(
          jsonEncode({
            'llm': {
              'model': {
                'provider': 'scripted',
                'modelId': 'scripted-1',
                'contextWindow': 32768,
              },
              'steps': [
                {
                  'delayMs': 5000,
                  'reply': [
                    {
                      'toolCall': {
                        'id': 'call_1',
                        'name': 'exec',
                        'arguments': {'command': 'echo hello', 'timeout': 30},
                      },
                    },
                  ],
                  'stopReason': 'toolUse',
                },
                {
                  'expect': {
                    'toolResult': {'toolCallId': 'call_1'},
                  },
                  'reply': [
                    {'text': 'approved'},
                  ],
                  'stopReason': 'stop',
                },
              ],
            },
          }),
        );

      final p = await tui(
        ['go'],
        entry: CliEntry.scriptedEmbedded,
        environment: {
          'CODELAB_E2E_LLM_SCRIPT': script.path,
          'CODELAB_E2E_PERMISSION_MODE': 'standard',
        },
      );
      await p.waitFor(_altScreen);
      p.write('/provider add\r');
      await p.waitFor('? API type');
      pick(p, 4);
      await p.waitFor('? Base URL ›');
      p.write('y'); // не ответ на запрос, а символ в поле адреса
      await p.waitFor('approval pending · esc to answer');
      expect(p.text, contains('? Base URL › y'));
      expect(
        p.text,
        isNot(contains('[y] allow once')),
        reason: 'зона одобрения скрыта, пока открыт мастер',
      );
      expect(p.text, isNot(contains('approved')));

      p.write(_esc); // закрывает мастер, ход не отменяется
      await p.waitFor('[y] allow once');
      p.write('y');
      await p.waitFor('approved');
      p.write(_ctrlD);

      expect(await p.exitCode, 0, reason: p.text);
      expect(config(), contains('gw:'));
      expect(
        File('$home/config.yaml').readAsStringSync(),
        isNot(contains('local-')),
        reason: 'мастер закрыт без записи',
      );
    },
    skip: skip,
    tags: scriptedOnly,
  );
}
