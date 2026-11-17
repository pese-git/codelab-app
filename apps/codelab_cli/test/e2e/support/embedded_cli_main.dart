// Тестовая точка входа CLI для e2e с `CODELAB_E2E_AGENT=embedded` (design.md
// change `add-embedded-agent-mode`, D8, D10; testing-quality «Встроенный
// режим в e2e и conformance»).
//
// Почему отдельная точка входа: `bin/codelab.dart` открывает встроенного
// агента настоящим `localEmbeddedAgentOpener` — с конфигом, ключом и сетью, а
// e2e нужен детерминированный сценарий модели. `package:codelab_embedded/
// testing.dart` рабочий код не импортирует (правило сторожа), поэтому
// открыватель со сценарием подставляется здесь, в тестах, через шов
// `runCodelab(embeddedOpener:)`. Остальное — тот же `runCodelab`, что у
// рабочего бинаря.
//
// Как использовать: kernel этого файла запускает `CliProcess.kernel()` в
// варианте `embedded`; тест задаёт окружение (см. `E2eCliLaunch.environment`):
// * `CODELAB_E2E_LLM_SCRIPT` — путь к файлу `test/e2e/llm_scripts/<режим>.json`
//   (обязательно);
// * `CODELAB_E2E_PERMISSION_MODE` — режим разрешений сессии (необязательно);
// * `CODELAB_E2E_MODELS` — модели каталога `provider/model` через запятую;
// * `CODELAB_E2E_SESSIONS_DIR` — журнал сессий, иначе `$CODELAB_HOME/sessions`.
import 'dart:convert';
import 'dart:io';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_embedded/testing.dart';

Future<void> main(List<String> args) async {
  final environment = Platform.environment;
  final scriptPath = environment['CODELAB_E2E_LLM_SCRIPT'];
  if (scriptPath == null) {
    stderr.writeln('embedded_cli_main: CODELAB_E2E_LLM_SCRIPT is not set');
    exit(2);
  }
  final script =
      jsonDecode(File(scriptPath).readAsStringSync()) as Map<String, Object?>;
  final home = environment['CODELAB_HOME'];
  if (home == null) {
    stderr.writeln('embedded_cli_main: CODELAB_HOME is not set');
    exit(2);
  }
  final models = environment['CODELAB_E2E_MODELS'];
  final opener = scriptedEmbeddedAgentOpener(
    llm: Map<String, Object?>.from(script['llm']! as Map),
    codelabHome: home,
    logger: const CliEmbeddedLogger.silent(),
    permissionMode: environment['CODELAB_E2E_PERMISSION_MODE'],
    sessionsDir: environment['CODELAB_E2E_SESSIONS_DIR'] ?? '$home/sessions',
    models: models == null ? const [] : models.split(','),
  );
  // `exit`, а не `exitCode`: подписки на stdin и сигналы держали бы процесс
  // живым после завершения клиента (как в `bin/codelab.dart`).
  exit(
    await runCodelab(args, environment: environment, embeddedOpener: opener),
  );
}
