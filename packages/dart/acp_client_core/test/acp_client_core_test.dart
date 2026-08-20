import 'package:acp_client_core/acp_client_core.dart';
import 'package:test/test.dart';

void main() {
  test('exports core package boundaries', () {
    expect(acpClientCorePackageName, 'acp_client_core');
    expect(acpProtocolPackageName, 'acp_protocol');
    expect(acpTransportsPackageName, 'acp_transports');
  });
}
