# terminal_spike

Спайк 1.1 change `add-integrated-terminal` (design.md D14, D15). Не часть
workspace: свой `pubspec.yaml` и `pubspec.lock`. Удаляется в задаче 3.9.

Из этого каталога:

```bash
fvm flutter pub get
fvm dart test test/pty_contract_test.dart   # контракт PTY (pty2) на Dart VM
fvm flutter test                     # то же + TerminalView в FluentApp, политика буфера
fvm dart run bin/core_probe.dart     # xterm2_core без Flutter: OSC-буфер, скорость
fvm dart run bin/throughput_probe.dart
fvm dart run bin/orphan_check.dart   # SIGKILL app -> shell и задание завершаются
fvm flutter build macos --release
fvm flutter run -d macos --profile   # ручная проверка (чек-лист — в design.md, «Итог спайка»)
```
