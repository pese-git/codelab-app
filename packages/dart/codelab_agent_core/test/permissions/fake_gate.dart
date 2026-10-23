import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';

/// A [PermissionGate] that records requests and answers with [decide];
/// with [clock] and [wait] it answers after that time on the fake clock.
final class FakeGate implements PermissionGate {
  FakeGate([this.decide = _allow, this.clock, this.wait]);

  final PermissionDecision Function(PermissionRequest request) decide;
  final FakeClock? clock;
  final Duration? wait;
  final requests = <PermissionRequest>[];

  static PermissionDecision _allow(PermissionRequest _) =>
      PermissionDecision.allowOnce;

  @override
  Future<PermissionDecision> request(
    PermissionRequest req,
    CancelToken cancel,
  ) async {
    requests.add(req);
    if (clock case final clock?) {
      await clock.delay(wait ?? Duration.zero);
    }
    return decide(req);
  }
}

FakeGate gateAnswering(PermissionDecision decision) =>
    FakeGate((_) => decision);
