import 'package:acp_testing/acp_testing.dart';
import 'package:test/test.dart';

void main() {
  test('exports testing package boundaries', () {
    expect(acpTestingPackageName, 'acp_testing');
    expect(acpClientCorePackageName, 'acp_client_core');
    expect(acpProtocolPackageName, 'acp_protocol');
    expect(acpTransportsPackageName, 'acp_transports');
  });
}
