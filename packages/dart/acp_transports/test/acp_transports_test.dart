import 'package:acp_transports/acp_transports.dart';
import 'package:test/test.dart';

void main() {
  test('exports transport and protocol markers', () {
    expect(acpTransportsPackageName, 'acp_transports');
    expect(acpProtocolPackageName, 'acp_protocol');
  });
}
