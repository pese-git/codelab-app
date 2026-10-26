import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Какой агент стоит за e2e-тестами app.
enum E2eAgentKind { scripted, dart }

/// Тег тестов, которые проверяют поведение именно scripted-агента; в режиме
/// `dart` прогон идёт с `--exclude-tags scripted-only` (`dart_test.yaml`).
const scriptedOnly = 'scripted-only';

/// Агент e2e-тестов, выбранный `--dart-define=CODELAB_E2E_AGENT`.
///
/// Почему: одни и те же 8 тестов `integration_test/` проверяют app и против
/// scripted-агента из `codelab_acp_testing`, и против бинаря `codelab-agent`; код
/// `lib/` при этом не меняется (контракт e2e `09-09`; design.md change
/// `add-codelab-agent-binary`, D9).
///
/// Для чего: единственное место, где тест узнаёт команду запуска агента и
/// ожидания, которые у агентов различаются (метка сессии, модели, заголовок
/// одобрения, маркер сырых аргументов).
///
/// Как использовать: `final launch = await E2eAgent.current.launch(tempDir,
/// mode: …)`; [E2eLaunch.command] и [E2eLaunch.args] вводятся в поля
/// `transport-field-Command` и `transport-field-Args`. Режим без сценария
/// Dart-агента — [StateError]: такой тест помечается [scriptedOnly].
final class E2eAgent {
  E2eAgent._(this.kind);

  static final E2eAgent current = E2eAgent._(
    switch (const String.fromEnvironment(
      'CODELAB_E2E_AGENT',
      defaultValue: 'scripted',
    )) {
      'scripted' => E2eAgentKind.scripted,
      'dart' => E2eAgentKind.dart,
      final other => throw ArgumentError.value(other, 'CODELAB_E2E_AGENT'),
    },
  );

  final E2eAgentKind kind;

  bool get isScripted => kind == E2eAgentKind.scripted;

  /// scripted: пишет агента из `codelab_acp_testing` в [tempDir]; dart: ничего не
  /// пишет, сценарий — `integration_test/llm_scripts/<mode.wireName>.json`.
  Future<E2eLaunch> launch(
    Directory tempDir, {
    CodelabCompatibleStdioAgentMode mode =
        CodelabCompatibleStdioAgentMode.normal,
  }) async {
    switch (kind) {
      case E2eAgentKind.scripted:
        final agent = await writeCodelabCompatibleStdioAgent(
          tempDir,
          mode: mode,
        );
        const dart = String.fromEnvironment(
          'CODELAB_E2E_DART',
          defaultValue: 'dart',
        );
        return E2eLaunch._(
          command: _absolute(dart),
          args: '${_noSpaces(agent.path)} serve --stdio',
          sessionLabel: equals('Session codelab-test-session'),
          models: const [
            (value: 'gpt-5', name: 'GPT-5'),
            (value: 'gpt-4', name: 'GPT-4'),
          ],
          permissionTitle: 'Run test command',
          rawInputMarker: '/bin/bash',
        );
      case E2eAgentKind.dart:
        const bin = String.fromEnvironment('CODELAB_E2E_AGENT_BIN');
        if (bin.isEmpty) {
          throw StateError(
            'CODELAB_E2E_AGENT=dart needs CODELAB_E2E_AGENT_BIN '
            '(melos run test:e2e:app:dart-agent)',
          );
        }
        final script = File(
          'integration_test/llm_scripts/${mode.wireName}.json',
        ).absolute.path;
        return E2eLaunch._(
          command: _noSpaces(File(bin).absolute.path),
          args: [
            'serve',
            '--stdio',
            '--llm-script',
            _noSpaces(script),
            ..._dartFlags(mode),
          ].join(' '),
          sessionLabel: matches(RegExp(r'^Session \S+$')),
          models: const [
            (value: 'scripted/gpt-5', name: 'gpt-5'),
            (value: 'scripted/gpt-4', name: 'gpt-4'),
          ],
          // Заголовок `exec` — сама команда (ToolPresentation инструмента).
          permissionTitle: 'echo hello',
          rawInputMarker: 'timeout',
        );
    }
  }

  /// Флаги бинаря по таблице контракта: режим разрешений даёт тот же
  /// видимый результат, что у scripted-агента (вопрос на `exec`, запись без
  /// вопроса и так далее).
  static List<String> _dartFlags(CodelabCompatibleStdioAgentMode mode) =>
      switch (mode) {
        CodelabCompatibleStdioAgentMode.normal ||
        CodelabCompatibleStdioAgentMode.withPlan ||
        CodelabCompatibleStdioAgentMode.echoesCwd => const [],
        CodelabCompatibleStdioAgentMode.withConfigOptions => const [
          '--model',
          'gpt-5',
          '--model',
          'gpt-4',
        ],
        CodelabCompatibleStdioAgentMode.withPermissionRequest ||
        CodelabCompatibleStdioAgentMode.withQueuedPromptDrain ||
        CodelabCompatibleStdioAgentMode.withConcurrentSessions => const [
          '--permission-mode',
          'standard',
        ],
        CodelabCompatibleStdioAgentMode.withFsAccess => const [
          '--permission-mode',
          'accept-edits',
        ],
        CodelabCompatibleStdioAgentMode.withTerminalExecution => const [
          '--permission-mode',
          'bypass',
        ],
        final other => throw StateError(
          '${other.name} has no Dart agent scenario: tag the test '
          '$scriptedOnly',
        ),
      };

  /// Относительная команда разрешается от `apps/codelab_desktop`: спавн агента
  /// идёт из папки проекта, где относительный путь уже не найдётся. Голое
  /// имя (`dart`) ищется в `PATH` и остаётся как есть.
  static String _absolute(String command) =>
      command.contains('/') ? File(command).absolute.path : command;

  /// Поле `Args` делится по пробелам, путь с пробелом развалится на части.
  static String _noSpaces(String path) {
    if (path.contains(' ')) {
      throw StateError('e2e paths must not contain spaces: $path');
    }
    return path;
  }
}

/// Запуск агента и ожидания теста, которые зависят от агента.
final class E2eLaunch {
  E2eLaunch._({
    required this.command,
    required this.args,
    required this.sessionLabel,
    required this.models,
    required this.permissionTitle,
    required this.rawInputMarker,
  });

  /// Поле `transport-field-Command`.
  final String command;

  /// Поле `transport-field-Args`.
  final String args;

  /// Метка новой сессии в списке.
  final Matcher sessionLabel;

  /// Значения и подписи опции `model`, по умолчанию — первая.
  final List<({String value, String name})> models;

  /// Заголовок карточки одобрения для команды `echo hello`.
  final String permissionTitle;

  /// Текст, который есть только в сырых аргументах вызова (`rawInput`).
  final String rawInputMarker;

  /// Текстовые виджеты, совпавшие с [sessionLabel].
  Finder get sessionLabelFinder => find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        sessionLabel.matches(widget.data ?? widget.textSpan?.toPlainText(), {}),
    description: 'session label',
  );
}
