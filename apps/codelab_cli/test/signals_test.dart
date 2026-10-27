// Сигналы остановки CLI (tasks 4.9; spec codelab-cli «Сигналы CLI»;
// design.md change `add-codelab-cli`, D13).

import 'dart:async';
import 'dart:io';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

void main() {
  late StreamController<ProcessSignal> sigint;
  late StreamController<ProcessSignal> sigterm;
  late List<int> stops;
  late List<int> forced;
  late StopSignals signals;

  setUp(() {
    sigint = StreamController<ProcessSignal>();
    sigterm = StreamController<ProcessSignal>();
    stops = [];
    forced = [];
    signals = watchStopSignals(
      stops.add,
      sigint: sigint.stream,
      sigterm: sigterm.stream,
      forceExit: forced.add,
    );
  });
  tearDown(() => signals.cancel());

  test('the first SIGINT starts a graceful stop with 130', () async {
    sigint.add(ProcessSignal.sigint);
    await Future<void>.delayed(Duration.zero);

    expect(stops, [130]);
    expect(forced, isEmpty);
  });

  test('the first SIGTERM starts a graceful stop with 143', () async {
    sigterm.add(ProcessSignal.sigterm);
    await Future<void>.delayed(Duration.zero);

    expect(stops, [143]);
  });

  test('a second signal during the stop exits at once', () async {
    sigint.add(ProcessSignal.sigint);
    await Future<void>.delayed(Duration.zero);
    sigterm.add(ProcessSignal.sigterm);
    await Future<void>.delayed(Duration.zero);

    expect(stops, [130]);
    expect(forced, [143]);
  });

  test('no signal after cancel() is handled', () async {
    await signals.cancel();
    sigint.add(ProcessSignal.sigint);
    await Future<void>.delayed(Duration.zero);

    expect(stops, isEmpty);
  });
}
