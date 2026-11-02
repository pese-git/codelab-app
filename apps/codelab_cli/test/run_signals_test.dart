// Сигналы во время `dispose` режима (spec codelab-cli «Встроенный агент в
// CLI», «Выход»; design.md change `add-embedded-agent-mode`, D6, «Выход
// CLI»; AGENTS.md §12): пока встроенный агент завершается, обработчики
// живы, а любой сигнал выходит сразу с кодом сигнала.

import 'dart:async';
import 'dart:io';

import 'package:codelab_acp_transports/codelab_acp_transports.dart'
    show AcpTransport;
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_embedded/codelab_embedded.dart' as embedded;
import 'package:codelab_embedded/testing.dart';
import 'package:test/test.dart';

import 'support/fake_cli_io.dart';

/// Агент, чей `dispose` висит, пока тест не отпустит его.
final class _HangingDispose implements embedded.EmbeddedAgent {
  _HangingDispose(this._inner);

  final embedded.EmbeddedAgent _inner;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  AcpTransport get clientTransport => _inner.clientTransport;

  @override
  Future<void> get closed => _inner.closed;

  @override
  Future<void> dispose() {
    if (!started.isCompleted) started.complete();
    return release.future;
  }

  Future<void> disposeInner() => _inner.dispose();
}

void main() {
  group('watchModeSignals', () {
    late StreamController<ProcessSignal> sigint;
    late StreamController<ProcessSignal> sigterm;
    late List<int> stops;
    late List<int> forced;
    late List<String> keys;
    late bool stopped;
    late StopSignals signals;

    StopSignals watch({bool withSigintKey = false}) => watchModeSignals(
      onStop: stops.add,
      isStopped: () => stopped,
      onSigint: withSigintKey ? () => keys.add('sigint') : null,
      seam: SignalSeam(
        sigint: sigint.stream,
        sigterm: sigterm.stream,
        forceExit: forced.add,
      ),
    );

    setUp(() {
      sigint = StreamController<ProcessSignal>();
      sigterm = StreamController<ProcessSignal>();
      stops = [];
      forced = [];
      keys = [];
      stopped = false;
    });
    tearDown(() => signals.cancel());

    test(
      'before the mode is over the first signal is a graceful stop',
      () async {
        signals = watch();

        sigterm.add(ProcessSignal.sigterm);
        await pumpEvents();

        expect(stops, [143]);
        expect(forced, isEmpty);
      },
    );

    test('after the mode is over (dispose runs) the FIRST signal exits at '
        'once with its own code', () async {
      signals = watch();
      stopped = true;

      sigterm.add(ProcessSignal.sigterm);
      await pumpEvents();

      expect(forced, [143]);
      expect(stops, isEmpty);
    });

    test('REPL: SIGINT is Ctrl+C while the REPL runs and exits at once '
        'with 130 during dispose', () async {
      signals = watch(withSigintKey: true);

      sigint.add(ProcessSignal.sigint);
      await pumpEvents();
      expect(keys, ['sigint']);
      expect(forced, isEmpty);

      stopped = true;
      sigint.add(ProcessSignal.sigint);
      await pumpEvents();
      expect(forced, [130]);
      expect(keys, ['sigint']);
    });

    test('cancel() removes both subscriptions', () async {
      signals = watch(withSigintKey: true);
      await signals.cancel();
      stopped = true;

      sigint.add(ProcessSignal.sigint);
      sigterm.add(ProcessSignal.sigterm);
      await pumpEvents();

      expect(forced, isEmpty);
    });
  });

  group('runCodelab -p with a hanging dispose of the embedded agent', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('codelab_sig_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<void> scenario(ProcessSignal signal, int code) async {
      final sigint = StreamController<ProcessSignal>();
      final sigterm = StreamController<ProcessSignal>();
      final forced = <int>[];
      final inner = scriptedEmbeddedAgentOpener(
        llm: {
          'model': {
            'provider': 'scripted',
            'modelId': 'scripted-1',
            'contextWindow': 32768,
          },
          'steps': [
            {
              'reply': [
                {'text': 'done'},
              ],
              'stopReason': 'stop',
            },
          ],
        },
        codelabHome: '${tmp.path}/home',
        logger: const CliEmbeddedLogger.silent(),
      );
      _HangingDispose? hanging;
      final io = FakeCliIo();
      final run = runCodelab(
        ['-a', 'embedded', '-p', 'hi', '-C', tmp.path],
        environment: {'CODELAB_HOME': '${tmp.path}/home'},
        io: io,
        embeddedOpener: ({required cwd, required hostProfile}) async =>
            hanging = _HangingDispose(
              await inner(cwd: cwd, hostProfile: hostProfile),
            ),
        signals: SignalSeam(
          sigint: sigint.stream,
          sigterm: sigterm.stream,
          forceExit: forced.add,
        ),
      );
      // Ход закончен, `dispose` агента начался и висит: вот момент сигнала.
      await Future.doWhile(() async {
        await pumpEvents();
        return hanging == null || !hanging!.started.isCompleted;
      });

      (signal == ProcessSignal.sigint ? sigint : sigterm).add(signal);
      await pumpEvents();

      expect(forced, [code]);
      hanging!.release.complete();
      expect(await run, 0, reason: io.stderrText);
      await hanging!.disposeInner();
    }

    test('SIGTERM during dispose exits at once with 143', () async {
      await scenario(ProcessSignal.sigterm, 143);
    });

    test('SIGINT during dispose exits at once with 130', () async {
      await scenario(ProcessSignal.sigint, 130);
    });
  });
}

/// Пропускает очередь событий: доставка сообщений контроллеров и микрозадачи.
Future<void> pumpEvents() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
