// Web-smoke entry point: compiled with `dart compile js` and
// `dart compile wasm` by `melos run web-compile` to prove the core stays
// web-safe (no dart:io, dart:isolate, dart:ffi, Flutter).
import 'package:codelab_agent_core/codelab_agent_core.dart';

void main() {
  // ignore: avoid_print
  print(codelabAgentCorePackageName);
}
